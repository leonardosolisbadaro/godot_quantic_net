## @file qn_host_session.gd
## @path res://addons/quantic_net/src/use_cases/qn_host_session.gd
##
## @description
## Orquestração da sessão do servidor autoritativo. Processa autenticação,
## validação de movimento, propagação e registro de entidades.
##
## @created 2026-07-30
## @updated 2026-08-01
##
## @since 0.1.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends RefCounted

signal snapback_requested(peer_id: int, pkt: PackedByteArray)
signal peer_rejected(peer_id: int, reason: String, strikes: int)
signal broadcast_ready(states: Array)
signal packet_ready(peer_id: int, data: PackedByteArray)

const SNAPBACK_REASON_CLAMP = 1
const SNAPBACK_REASON_REJECT = 2

var _registry := {}
const QNSerializer = preload("res://addons/quantic_net/src/domain/qn_serializer.gd")
const QNDeltaSerializer = preload("res://addons/quantic_net/src/domain/qn_delta_serializer.gd")
const QNBitBuffer = preload("res://addons/quantic_net/src/domain/qn_bit_buffer.gd")
const QNNetProfile = preload("res://addons/quantic_net/src/domain/qn_net_profile.gd")
const QNPriorityAccumulator = preload("res://addons/quantic_net/src/domain/qn_priority_accumulator.gd")

var _server_seq: int = 0
var _world_history := []
var _accumulator = QNPriorityAccumulator.new()

var _stats: Dictionary = {
	"entities_total": 0,
	"entities_sent_this_tick": 0,
	"bytes_saved_by_hybrid_ticking": 0,
	"ticks_since_log": 0
}

var validator: RefCounted:
	set(v):
		if validator and validator.has_signal("peer_rejected"):
			validator.peer_rejected.disconnect(_on_validator_peer_rejected)
		validator = v
		if validator and validator.has_signal("peer_rejected"):
			validator.peer_rejected.connect(_on_validator_peer_rejected)

func _on_validator_peer_rejected(id: int, reason: String, strikes: int) -> void:
	peer_rejected.emit(id, reason, strikes)

func register_entity(entity_id: int, is_peer: bool, has_initial_state: bool, profile: RefCounted = null) -> void:
	if profile == null:
		profile = QNNetProfile.preset_standard()
		
	_registry[entity_id] = {
		"id": entity_id,
		"pos": Vector3.ZERO,
		"rot": Vector3.ZERO,
		"seq": 0,
		"ts": 0,
		"ack": 0,
		"profile": profile,
		"has_state": has_initial_state,
		"last_broadcast_ts": 0,
		"is_peer": is_peer
	}

func on_peer_authenticated(peer_id: int, profile: RefCounted = null) -> void:
	register_entity(peer_id, true, false, profile)

func unregister_entity(entity_id: int) -> void:
	if _registry.has(entity_id):
		_registry.erase(entity_id)
	_accumulator.cleanup_entity(entity_id)

func change_entity_profile(entity_id: int, new_profile: RefCounted) -> void:
	if _registry.has(entity_id):
		_registry[entity_id].profile = new_profile
		_registry[entity_id].last_broadcast_ts = 0

func on_peer_disconnected(peer_id: int) -> void:
	if _registry.has(peer_id):
		_registry.erase(peer_id)
	_accumulator._cleanup_peer(peer_id)
	if validator and validator.has_method("peer_left"):
		validator.peer_left(peer_id)

func on_client_snapshot(peer_id: int, data: PackedByteArray, now: int) -> void:
	if not _registry.has(peer_id) or not validator or data.size() < 2:
		return
	
	var client_ack = data.decode_u16(0)
	_registry[peer_id].ack = client_ack
		
	var history = QNSerializer.decode_state_history(data.slice(2))
	if history.is_empty():
		return
	
	for i in range(history.size() - 1, -1, -1):
		var state = history[i]
		var pos: Vector3 = state.get("pos", Vector3.ZERO)
		var rot: Vector3 = state.get("rot", Vector3.ZERO)
		var seq: int = state.get("seq", 0)
		var client_ts: int = state.get("ts", 0)
		
		var last_seq = _registry[peer_id].seq
		var diff = seq - last_seq
		if diff < -32768: diff += 65536
		elif diff > 32768: diff -= 65536
		
		if last_seq != 0 and diff <= 0:
			continue
			
		var result: Dictionary = validator.validate(peer_id, pos, rot, client_ts)
		var action: String = result.get("action", "")
		
		if action == "accept":
			_registry[peer_id].pos = result.pos
			_registry[peer_id].rot = result.rot
			_registry[peer_id].seq = seq
			_registry[peer_id].ts = client_ts
			_registry[peer_id].has_state = true
		elif action == "clamp":
			_registry[peer_id].pos = result.pos
			_registry[peer_id].rot = result.rot
			_registry[peer_id].seq = seq
			_registry[peer_id].ts = client_ts
			_registry[peer_id].has_state = true
			var snap = QNSerializer.encode_snapback(seq, result.pos, result.rot, client_ts, SNAPBACK_REASON_CLAMP)
			snapback_requested.emit(peer_id, snap)
			break
		elif action == "reject":
			var snap = QNSerializer.encode_snapback(seq, result.pos, result.rot, client_ts, SNAPBACK_REASON_REJECT)
			snapback_requested.emit(peer_id, snap)
			break

func tick_broadcast(now: int) -> void:
	_server_seq = (_server_seq + 1) & 0xFFFF
	var world_snapshot := {}
	for id in _registry:
		var st = _registry[id]
		if st.has_state:
			world_snapshot[id] = {"id": id, "seq": st.seq, "pos": st.pos, "rot": st.rot, "custom_id": 0, "ts": st.ts}
			
	_world_history.push_front({"seq": _server_seq, "states": world_snapshot})
	if _world_history.size() > 60:
		_world_history.pop_back()
		
	var current_states := {}
	for id in _registry:
		var st = _registry[id]
		if not st.has_state:
			continue
			
		var profile = st.profile
		var tick_rate_hz: float = profile.tick_rate_hz if profile else 20.0
		var should_broadcast := false
		
		if tick_rate_hz > 0.0:
			var interval_ms: int = int(1000.0 / tick_rate_hz)
			if now - st.last_broadcast_ts >= interval_ms:
				should_broadcast = true
		else:
			if st.last_broadcast_ts == 0:
				should_broadcast = true
				
		if should_broadcast:
			current_states[id] = world_snapshot[id]
			
	for id in _registry:
		var st = _registry[id]
		if not st.get("is_peer", false):
			continue
			
		var ack = st.get("ack", 0)
		var base_states = {}
		for hist in _world_history:
			if hist.seq == ack:
				base_states = hist.states
				break
				
		var profiles = {}
		for cid in current_states:
			profiles[cid] = _registry[cid].profile if _registry.has(cid) else null
			
		# Filtra entidades por MTU e Priority
		var selected_states = _accumulator.select_entities(id, current_states, profiles, st.pos, 1200, 19)
		
		# Atualiza last_broadcast_ts APENAS para os que foram efetivamente selecionados
		for selected_id in selected_states:
			if _registry.has(selected_id):
				_registry[selected_id].last_broadcast_ts = now
				
		_stats["entities_total"] = _registry.size()
		_stats["entities_sent_this_tick"] = selected_states.size()
		var omitted_entities = _registry.size() - selected_states.size()
		_stats["bytes_saved_by_hybrid_ticking"] += omitted_entities * 19 # Aprox. 19 bytes por estado omitido
		_stats["ticks_since_log"] += 1
		if _stats["ticks_since_log"] >= 600: # Log a cada 10s (a 60Hz)
			print("[QNHostSession] Bandwidth Stats (Peer %d): %d entities sent out of %d. Savings so far: %d bytes" % [id, selected_states.size(), _registry.size(), _stats["bytes_saved_by_hybrid_ticking"]])
			_stats["ticks_since_log"] = 0
				
		var buf = QNBitBuffer.new()
		buf.write_bits(_server_seq, 16)
		buf.write_bits(ack, 16)
		buf.write_bits(now & 0xFFFFFFFF, 32)
		buf.write_bits(selected_states.size(), 8)
		
		for entity_id in selected_states:
			buf.write_bits(entity_id, 32)
			var base = base_states.get(entity_id, {})
			
			# Lógica Stateless de AoI:
			# Verifica se no momento do 'ack', a entidade estava DENTRO da visão do cliente.
			# Se estava FORA da visão, significa que o cliente NUNCA a recebeu naquele pacote.
			# Portanto, a base dele é VAZIA, e devemos enviar um I-Frame!
			if not base.is_empty():
				var peer_base = base_states.get(id, {})
				if not peer_base.is_empty():
					var cull_radius = 50.0
					if profiles.has(entity_id):
						cull_radius = profiles[entity_id].spatial_culling_radius
					
					var old_dist = peer_base.pos.distance_to(base.pos)
					if old_dist > cull_radius:
						base = {} # Culled at ACK time -> Força I-Frame!
			
			QNDeltaSerializer.encode_state(buf, base, current_states[entity_id])
			
		packet_ready.emit(id, buf.get_buffer())


func get_registry() -> Dictionary:
	return _registry
