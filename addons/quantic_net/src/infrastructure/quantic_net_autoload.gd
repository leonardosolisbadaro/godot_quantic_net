## @file quantic_net_autoload.gd
## @path res://addons/quantic_net/src/infrastructure/quantic_net_autoload.gd
##
## @description
## Autoload principal (casca) do QuanticNet.
## Expõe a API pública do plugin (host, join, submit_state) 
## para integração plug and play com a Godot Engine.
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends Node

# Sinais públicos (API)
signal connection_state_changed(new_state: int)
signal connection_failed_reason(error: int)

signal peer_joined(id: int)
signal peer_left(id: int)
signal state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)
signal pong_received(rtt: float, offset: float)
signal snapback_received(seq: int, pos: Vector3, rot: Vector3, reason: int, replay_inputs: Array)

enum ConnectionState {DISCONNECTED, CONNECTING, AUTHENTICATING, CONNECTED, FAILED}

const QNDTLSBootstrap = preload("res://addons/quantic_net/src/infrastructure/qn_dtls_bootstrap.gd")
const QNWirePeer = preload("res://addons/quantic_net/src/infrastructure/qn_wire_peer.gd")
const QNNetHook = preload("res://addons/quantic_net/src/infrastructure/qn_net_hook.gd")
const QNHostSession = preload("res://addons/quantic_net/src/use_cases/qn_host_session.gd")
const QNClientSession = preload("res://addons/quantic_net/src/use_cases/qn_client_session.gd")
const QNSerializer = preload("res://addons/quantic_net/src/domain/qn_serializer.gd")

const CH_STATE := 1
const SERVER_PEER_ID := 1
const TRANSFER_UNRELIABLE := 1 # MultiplayerPeer.TRANSFER_MODE_UNRELIABLE

var _state: int = ConnectionState.DISCONNECTED
var _enet: ENetConnection = null
var _hook: Object = null # QNNetHook
var _wire: Object = null # QNWirePeer
var _host_session: RefCounted = null # QNHostSession
var _client_session: RefCounted = null # QNClientSession
var _secret: String = ""
var _is_server: bool = false

func get_state() -> int:
	return _state

func is_server() -> bool:
	return _is_server

func get_unique_id() -> int:
	if _is_server: return 1
	if _hook != null and _hook.base != null:
		return _hook.base.get_unique_id()
	return 0

func _set_state(s: int) -> void:
	if _state != s:
		_state = s
		connection_state_changed.emit(s)

func host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32) -> int:
	_is_server = true
	_secret = secret
	var err_out := [OK]
	_enet = QNDTLSBootstrap.host(port, bind_ip, max_peers, err_out)
	if _enet == null:
		_set_state(ConnectionState.FAILED)
		connection_failed_reason.emit(err_out[0])
		return err_out[0]
		
	_wire = QNWirePeer.new(_enet, true)
	_hook = QNNetHook.new()
	_hook.base.multiplayer_peer = _wire
	_hook.base.server_relay = true
	
	_host_session = QNHostSession.new()
	_host_session.validator = preload("res://addons/quantic_net/src/domain/qn_server_validator.gd").new()
	_host_session.snapback_requested.connect(_on_host_snapback_requested)
	_host_session.broadcast_ready.connect(_on_host_broadcast_ready)
	_host_session.peer_rejected.connect(func(id: int, r: String, s: int) -> void:
		print("[SERVER] Peer %d rejected. Reason: %s. Strikes: %d" % [id, r, s])
		if s >= 5:
			_hook.base.disconnect_peer(id)
	)
		
	_hook.custom_packet.connect(_on_custom_packet)
	_hook.base.auth_timeout = 3.0
	_hook.base.allow_object_decoding = false
	_hook.base.auth_callback = Callable(self, "_on_auth_callback")
	_hook.peer_connected.connect(func(id: int) -> void:
		if _is_server:
			print("HOOK PEER CONNECTED: ", id)
			peer_joined.emit(id))
	_hook.peer_disconnected.connect(func(id: int) -> void:
		if _is_server:
			if _host_session.has_method("on_peer_disconnected"):
				_host_session.on_peer_disconnected(id)
			
			var pkt := PackedByteArray([QNSerializer.TYPE_PEER_LEFT])
			var id_bytes := PackedByteArray()
			id_bytes.resize(4)
			id_bytes.encode_u32(0, id)
			pkt.append_array(id_bytes)
			_hook.send_custom(0, pkt, CH_STATE, MultiplayerPeer.TRANSFER_MODE_RELIABLE)
			
		peer_left.emit(id))
		
	get_tree().set_multiplayer(_hook, self.get_path())
	_set_state(ConnectionState.CONNECTED)
	return OK

func join(ip: String, port: int, secret: String, netem: bool = false) -> int:
	_is_server = false
	_secret = secret
	_set_state(ConnectionState.CONNECTING)
	var err_out := [OK]
	_enet = QNDTLSBootstrap.join(ip, port, QNDTLSBootstrap.CERT_HOSTNAME, err_out)
	if _enet == null:
		_set_state(ConnectionState.FAILED)
		connection_failed_reason.emit(err_out[0])
		return err_out[0]
		
	_wire = QNWirePeer.new(_enet)
	if netem:
		_wire.netem_enabled = true
		
	_hook = QNNetHook.new()
	_hook.base.multiplayer_peer = _wire
	
	_client_session = QNClientSession.new(Callable(self, "_on_client_submit_packet"))
	_client_session.pong_received.connect(func(rtt: float, off: float) -> void: pong_received.emit(rtt, off))
	_client_session.remote_state_received.connect(func(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
		state_received.emit(owner, pos, rot, custom))
	_client_session.snapback_received.connect(func(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
		snapback_received.emit(seq, pos, rot, reason, replay))
		
	_hook.base.auth_callback = _on_client_auth_callback
	
	_hook.custom_packet.connect(_on_custom_packet)
	_hook.connected_to_server.connect(func() -> void:
		var my_id: int = _hook.base.get_unique_id()
		_client_session.set_local_id(my_id)
		_set_state(ConnectionState.CONNECTED)
		peer_joined.emit(my_id))
	_hook.peer_connected.connect(func(id: int) -> void:
		if id != SERVER_PEER_ID:
			peer_joined.emit(id))
	_hook.peer_disconnected.connect(func(id: int) -> void:
		peer_left.emit(id)
		if id == SERVER_PEER_ID:
			_set_state(ConnectionState.DISCONNECTED))
			
	get_tree().set_multiplayer(_hook, self.get_path())
	return OK

func _physics_process(delta: float) -> void:
	if _hook == null:
		return
	if _is_server and _state == ConnectionState.CONNECTED:
		_host_session.tick_broadcast(Time.get_ticks_msec())
	elif not _is_server:
		var peers = _enet.get_peers()
		if peers.size() > 0:
			var s = peers[0].get_state()
			if s == ENetPacketPeer.STATE_CONNECTED and _state == ConnectionState.CONNECTING:
				_set_state(ConnectionState.AUTHENTICATING)
				var err = _hook.base.send_auth(SERVER_PEER_ID, _secret.to_utf8_buffer())
				print("CLIENT SEND AUTH RESULT: ", err)
				# _hook.base.complete_auth(SERVER_PEER_ID)
				# Wait for the server to reply with the assigned ID in _on_client_auth_callback

func _on_auth_callback(id: int, data: PackedByteArray) -> void:
	if _is_server:
		_on_server_auth_callback(id, data)
	else:
		_on_client_auth_callback(id, data)

func _on_server_auth_callback(id: int, data: PackedByteArray) -> void:
	print("SERVER AUTH CALLBACK TRIGGERED: ", id)
	if data == _secret.to_utf8_buffer():
		print("SERVER AUTH SECRET MATCH!")
		_host_session.on_peer_authenticated(id)
		var b = PackedByteArray()
		b.resize(4)
		b.encode_u32(0, id)
		_hook.base.send_auth(id, b)
		_hook.base.complete_auth(id)
	else:
		_hook.base.disconnect_peer(id)

func _on_client_auth_callback(id: int, data: PackedByteArray) -> void:
	print("CLIENT AUTH CALLBACK TRIGGERED: ", id)
	if data.size() >= 4:
		var assigned_id = data.decode_u32(0)
		_wire.set_client_id(assigned_id)
		print("CLIENT ASSIGNED ID: ", assigned_id)
	_hook.base.complete_auth(id)

func _on_custom_packet(peer_id: int, data: PackedByteArray, _channel: int = 1) -> void:
	if _is_server:
		if data.size() >= 20 and data[0] == QNSerializer.TYPE_STATE:
			_host_session.on_client_snapshot(peer_id, data.slice(1), Time.get_ticks_msec())
	else:
		if data.size() >= 1:
			if data[0] == QNSerializer.TYPE_PEER_LEFT and data.size() >= 5:
				var left_id = data.decode_u32(1)
				peer_left.emit(left_id)
			else:
				_client_session.handle_packet(data, Time.get_ticks_msec())

func _on_host_snapback_requested(peer_id: int, pkt: PackedByteArray) -> void:
	var body := PackedByteArray([QNSerializer.TYPE_SNAPBACK])
	body.append_array(pkt)
	_hook.send_custom(peer_id, body, CH_STATE, TRANSFER_UNRELIABLE)

func _on_host_broadcast_ready(states: Array) -> void:
	var now = Time.get_ticks_msec()
	for s in states:
		var raw = QNSerializer.encode_state_seq(s.seq, s.pos, s.rot, now, 0)
		var pkt := PackedByteArray([QNSerializer.TYPE_STATE])
		var id_bytes := PackedByteArray()
		id_bytes.resize(4)
		id_bytes.encode_u32(0, s.id)
		pkt.append_array(id_bytes)
		pkt.append_array(raw)
		_hook.send_custom(0, pkt, CH_STATE, TRANSFER_UNRELIABLE)

func _on_client_submit_packet(to: int, data: PackedByteArray, ch: int, mode: int) -> void:
	_hook.send_custom(to, data, ch, mode)

func submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void:
	if not _is_server and _client_session:
		_client_session.submit_state(pos, rot, custom, dt, Time.get_ticks_msec())

func remote_state(owner_id: int) -> Dictionary:
	if not _is_server and _client_session:
		return _client_session.remote_state(owner_id, Time.get_ticks_msec())
	return {}

func loss_of(owner_id: int) -> float:
	if not _is_server and _client_session:
		return _client_session.loss_of(owner_id)
	return 0.0

func is_clock_synced() -> bool:
	if not _is_server and _client_session:
		return _client_session.is_clock_synced()
	return false

func get_registry() -> Dictionary:
	if _is_server and _host_session:
		return _host_session.get_registry()
	return {}

func kick(peer_id: int) -> void:
	if _is_server and _hook:
		_hook.base.disconnect_peer(peer_id)

func toggle_netem() -> void:
	if _wire:
		_wire.netem_enabled = not _wire.netem_enabled

func _exit_tree() -> void:
	if get_tree().has_method("get_multiplayer") and get_tree().get_multiplayer(self.get_path()) == _hook:
		get_tree().set_multiplayer(SceneMultiplayer.new(), self.get_path())
	if _wire and _wire.has_method("close"):
		_wire.close()
