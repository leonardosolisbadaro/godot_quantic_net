## @file qn_client_session.gd
## @path res://addons/quantic_net/src/use_cases/qn_client_session.gd
##
## @description
## Sessao preditiva do cliente: envio de estado com rate-limit (20Hz),
## registro de seq+sent_ts, echo autoritativo alimentando clock-sync NTP
## de 3 argumentos, drain/replay no snapback, interp/loss por peer remoto.
## Camada: Use Cases (orquestracao de dominio; zero acoplamento de engine,
## transporte injetado via Callable, relogio por parametro — mesmo padrao
## do QNHostSession).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

## Contrapartida do QNHostSession no lado cliente. Nao conhece ENet,
## MultiplayerPeer, Node3D ou Input: o jogo consumidor faz a predicao local
## e chama submit_state(); esta classe cuida de TUDO que e' protocolo —
## ritmo de envio, sequenciamento, timestamps, reconciliacao e buffers.

## Eco autoritativo do proprio estado (alimenta clock-sync e confirma inputs).
signal pong_received(rtt_ms: float, offset_ms: float)
## Estado de peer remoto recebido e empilhado no buffer de interpolacao.
signal remote_state_received(owner: int, pos: Vector3, rot: Vector3, custom_id: int)
## Correcao autoritativa: o jogo deve aplicar pos/rot e REAPlicar replay_inputs
## (lista de {seq, move, rot_delta, dt} posteriores ao seq confirmado).
signal snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)

const CH_STATE := 1
const SEND_INTERVAL := 0.05  # 20 Hz (regime MMO; o COMPETITIVE e' Marco D do roadmap)
const TRANSFER_UNRELIABLE := 2  # MultiplayerPeer.TRANSFER_MODE_UNRELIABLE (int, sem enum na camada)

const QNSerializer = preload("res://addons/quantic_net/src/domain/qn_serializer.gd")

var _serializer  # QNSerializer (static)
var _clock       # QNClockSync
var _input_buf   # QNInputBuffer
var _interp := {}   # owner -> QNInterpBuffer
var _trackers := {} # owner -> QNLossTracker
var _state_history := []
var _world_history := [] # {seq: int, states: Dictionary}
var _last_server_seq := 0

## Estado local espelhado (o jogo escreve via submit_state; o snapback reescreve).
var local_pos := Vector3.ZERO
var local_rot := Vector3.ZERO

var _send_accum := 0.0
var _send_seq := 0
var _my_id := 0

## Callable de saida: send_callable(to_peer, data, channel, mode) -> void.
var send_callable: Callable

func _init(p_send_callable: Callable) -> void:
	send_callable = p_send_callable
	_serializer = QNSerializer
	_clock = preload("res://addons/quantic_net/src/domain/qn_clock_sync.gd").new()
	_input_buf = preload("res://addons/quantic_net/src/domain/qn_input_buffer.gd").new()

func set_local_id(id: int) -> void:
	_my_id = id

func is_clock_synced() -> bool:
	return _clock.is_synced()

func clock_rtt() -> float:
	return _clock.rtt_ms

func clock_offset() -> float:
	return _clock.offset_ms

func server_time(now: int) -> int:
	return int(now + _clock.offset_ms) if _clock.is_synced() else now

## O jogo chama a cada frame com sua posicao PREDITA localmente.
## dt: delta do frame (seg). now: Time.get_ticks_msec() local.
## So envia quando o acumulado atinge SEND_INTERVAL (rate-limit interno).
## Retorna true quando um pacote foi de fato emitido.
func submit_state(pos: Vector3, rot: Vector3, custom_id: int, dt: float, now: int) -> bool:
	local_pos = pos
	local_rot = rot
	_send_accum += dt
	if _my_id <= 1 or _send_accum < SEND_INTERVAL:
		return false
	_send_accum = 0.0
	_send_seq = (_send_seq + 1) & 0xFFFF
	_input_buf.record(_send_seq, Vector2.ZERO, 0.0, dt, now)
	var state_dict = {"seq": _send_seq, "pos": pos, "rot": rot, "ts": now, "custom_id": custom_id}
	_state_history.push_front(state_dict)
	if _state_history.size() > 3:
		_state_history.pop_back()
	var raw: PackedByteArray = _serializer.encode_state_history(_state_history)
	var pkt := PackedByteArray([_serializer.TYPE_STATE])
	var ack_bytes := PackedByteArray()
	ack_bytes.resize(2)
	ack_bytes.encode_u16(0, _last_server_seq)
	pkt.append_array(ack_bytes)
	pkt.append_array(raw)
	send_callable.call(1, pkt, CH_STATE, TRANSFER_UNRELIABLE)
	return true

## O jogo registra cada input de predicao (chamado junto da aplicacao local).
## sent_ts: o mesmo `now` usado no submit_state correspondente.
func record_input(seq: int, move: Vector2, rot_delta: float, dt: float, sent_ts: int) -> void:
	_input_buf.record(seq, move, rot_delta, dt, sent_ts)

func pending_inputs() -> int:
	return _input_buf.size()

## Ponto de entrada de pacotes vindos do fio (pos-codec, via NetHook).
## Formato relay do servidor: [type][owner u32][payload 19B].
## now: timestamp local de recebimento (relogio injetado).
func handle_packet(data: PackedByteArray, now: int) -> void:
	if data.size() < 2:
		return
	var ptype: int = data.decode_u8(0)
	if ptype == _serializer.TYPE_SNAPBACK:
		_handle_snapback(data.slice(1))
		return
	
	if ptype == 4: # TYPE_SNAPSHOT
		_handle_snapshot(data.slice(1), now)
		return
		
	if ptype != _serializer.TYPE_STATE or data.size() < 5:
		return
	var owner: int = data.decode_u32(1)
	var d: Dictionary = _serializer.decode_state_seq(data.slice(5))
	if d.is_empty():
		return
	if not _trackers.has(owner):
		_trackers[owner] = preload("res://addons/quantic_net/src/domain/qn_loss_tracker.gd").new()
		_interp[owner] = preload("res://addons/quantic_net/src/domain/qn_interp_buffer.gd").new()
	_trackers[owner].on_packet(d["seq"])
	if owner == _my_id:
		# Echo do proprio estado: clock-sync NTP de 3 argumentos.
		# client_sent = sent_ts registrado por seq; server_time = ts recarimbado.
		var sent_ts: int = _input_buf.get_sent_ts(d["seq"])
		_clock.on_pong(sent_ts, d["ts"], now)
		_input_buf.drain_after(d["seq"])
		pong_received.emit(_clock.rtt_ms, _clock.offset_ms)
		return
	_interp[owner].push(d["ts"], d["pos"], d["rot"])
	remote_state_received.emit(owner, d["pos"], d["rot"], d["custom_id"])

## Estado interpolado de um peer remoto; {} se desconhecido/sem snapshots.
func remote_state(owner: int, now: int) -> Dictionary:
	if not _interp.has(owner):
		return {}
	return _interp[owner].sample(server_time(now))

## Perda percentual recente de um peer (janela do tracker).
func loss_of(owner: int) -> float:
	return _trackers[owner].loss_pct() if _trackers.has(owner) else 0.0

func _handle_snapback(body: PackedByteArray) -> void:
	var d: Dictionary = _serializer.decode_state_seq(body)
	if d.is_empty():
		return
	local_pos = d["pos"]
	local_rot = d["rot"]
	var replay: Array = _input_buf.drain_after(d["seq"])
	snapback_received.emit(d["seq"], d["pos"], d["rot"], d["custom_id"], replay)

func _handle_snapshot(body: PackedByteArray, now: int) -> void:
	var buf = preload("res://addons/quantic_net/src/domain/qn_bit_buffer.gd").new(body)
	var server_seq = buf.read_bits(16)
	var ack = buf.read_bits(16)
	var num_entities = buf.read_bits(8)
	
	var base_states = {}
	for hist in _world_history:
		if hist.seq == ack:
			base_states = hist.states
			break
			
	var parsed_states = {}
	for i in range(num_entities):
		var entity_id = buf.read_bits(32)
		var base = base_states.get(entity_id, {})
		var st = preload("res://addons/quantic_net/src/domain/qn_delta_serializer.gd").decode_state(buf, base)
		parsed_states[entity_id] = st
		
		# Process state just like TYPE_STATE
		var owner = entity_id
		var d = st
		
		if not _trackers.has(owner):
			_trackers[owner] = preload("res://addons/quantic_net/src/domain/qn_loss_tracker.gd").new()
			_interp[owner] = preload("res://addons/quantic_net/src/domain/qn_interp_buffer.gd").new()
		_trackers[owner].on_packet(d["seq"])
		
		if owner == _my_id:
			var sent_ts: int = _input_buf.get_sent_ts(d["seq"])
			_clock.on_pong(sent_ts, d["ts"], now)
			_input_buf.drain_after(d["seq"])
			pong_received.emit(_clock.rtt_ms, _clock.offset_ms)
		else:
			_interp[owner].push(d["ts"], d["pos"], d["rot"])
			remote_state_received.emit(owner, d["pos"], d["rot"], d.get("custom_id", 0))
			
	_world_history.push_front({"seq": server_seq, "states": parsed_states})
	if _world_history.size() > 60:
		_world_history.pop_back()
		
	_last_server_seq = server_seq

