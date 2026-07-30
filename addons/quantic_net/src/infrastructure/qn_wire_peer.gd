## @file qn_wire_peer.gd
## @path res://addons/quantic_net/src/infrastructure/qn_wire_peer.gd
##
## @description
## Peer de rede proprietário sobre ENetConnection: codec versionado
## (magic+ZSTD condicional+XOR), mapa de canais virtuais e Netem.
## Camada: Infrastructure
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends MultiplayerPeerExtension

const MAGIC := 0xC0B0
const WIRE_VER := 1

const FLAG_COMPRESS := 1
const FLAG_OBFUSCATE := 2
const FLAG_BROADCAST := 4

const CH_CONTROL := 0
const CH_STATE := 1
const CH_RELIABLE := 2

const CH_MAP := {CH_CONTROL: 0, CH_STATE: 3, CH_RELIABLE: 1}

var enet: ENetConnection
var obfuscate := false

var netem_enabled := false
var netem_loss_pct := 0.0
var netem_latency_ms := 0
var netem_jitter_ms := 0
var netem_dup_pct := 0.0

var _netem_queue: Array[Dictionary] = []
var _in_queue: Array[Dictionary] = []
var _peer_map: Dictionary = {}
var _next_id: int = 2
var _is_server_flag := false
var _client_id := 2
var _status: int = MultiplayerPeer.CONNECTION_DISCONNECTED

func _init(p_enet: ENetConnection = null, p_is_server: bool = false) -> void:
	_is_server_flag = p_is_server
	if p_enet:
		enet = p_enet
		_status = MultiplayerPeer.CONNECTION_CONNECTED if _is_server_flag else MultiplayerPeer.CONNECTION_CONNECTING

func _encode(vchannel: int, payload: PackedByteArray) -> PackedByteArray:
	var flags := 0
	var body: PackedByteArray = payload
	
	if body.size() > 16:
		var comp = body.compress(FileAccess.COMPRESSION_DEFLATE)
		if comp.size() < body.size():
			body = comp
			flags |= FLAG_COMPRESS
			
	if obfuscate:
		flags |= FLAG_OBFUSCATE
		for i in range(body.size()):
			body[i] ^= 0x5A
	
	var w := PackedByteArray()
	w.resize(5)
	w.encode_u16(0, MAGIC)
	w.encode_u8(2, WIRE_VER)
	w.encode_u8(3, vchannel)
	w.encode_u8(4, flags)
	w.append_array(body)
	return w

func _decode(wire: PackedByteArray) -> PackedByteArray:
	if wire.size() < 5:
		return PackedByteArray()
		
	var magic = wire.decode_u16(0)
	if magic != MAGIC:
		return PackedByteArray()
		
	var version = wire.decode_u8(2)
	if version != WIRE_VER:
		return PackedByteArray()
		
	var flags = wire.decode_u8(4)
	var payload = wire.slice(5)
	
	if flags & FLAG_OBFUSCATE:
		for i in range(payload.size()):
			payload[i] ^= 0x5A
			
	if flags & FLAG_COMPRESS:
		var decomp = payload.decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE)
		if decomp.is_empty():
			decomp = payload.decompress_dynamic(65536, FileAccess.COMPRESSION_DEFLATE)
		
		if not decomp.is_empty():
			payload = decomp
		else:
			return PackedByteArray()
	return payload

func _queue_netem(vchannel: int, payload: PackedByteArray, current_ts: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not netem_enabled:
		result.append({"channel": vchannel, "payload": payload, "release_ts": current_ts})
		return result
		
	var should_drop = false
	if vchannel != CH_CONTROL and netem_loss_pct > 0.0:
		should_drop = (randf() < netem_loss_pct)
		
	if should_drop:
		return result
		
	var copies = 1
	if vchannel != CH_CONTROL and netem_dup_pct > 0.0:
		if randf() < netem_dup_pct:
			copies = 2
			
	for i in range(copies):
		var delay = netem_latency_ms
		if netem_jitter_ms > 0:
			var jitter = int(randfn(0.0, float(netem_jitter_ms)))
			delay += jitter
			if delay < 0:
				delay = 0
				
		var pkt = {
			"channel": vchannel,
			"payload": payload,
			"release_ts": current_ts + delay,
			"target": _target_peer
		}
		result.append(pkt)
		_netem_queue.append(pkt)
		
	return result

func _drain_netem(current_ts: int) -> Array[Dictionary]:
	var ready: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	
	for pkt in _netem_queue:
		if pkt.release_ts <= current_ts:
			ready.append(pkt)
		else:
			remaining.append(pkt)
			
	ready.sort_custom(func(a, b): return a.release_ts < b.release_ts)
	
	for pkt in ready:
		_send_packet(pkt.payload, pkt.target, pkt.channel)
		
	_netem_queue = remaining
	return ready


var _target_peer := 0
var _transfer_channel := 0
var _transfer_mode := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
var _refusing_connections := false
var _current_packet_peer := 0
var _current_packet_channel := 0

func _set_target_peer(peer: int) -> void:
	_target_peer = peer

func _set_transfer_channel(channel: int) -> void:
	_transfer_channel = channel

func _set_transfer_mode(mode: int) -> void:
	_transfer_mode = mode

func _get_transfer_channel() -> int:
	return _transfer_channel

func _get_transfer_mode() -> int:
	return _transfer_mode

func _is_refusing_new_connections() -> bool:
	return _refusing_connections

func _set_refuse_new_connections(enable: bool) -> void:
	_refusing_connections = enable

func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	var current_ts = Time.get_ticks_msec()
	var encoded = _encode(_transfer_channel, p_buffer)
	print("WIRE_PEER SEND (", _transfer_channel, "): ", p_buffer.hex_encode())
	var queued = _queue_netem(_transfer_channel, encoded, current_ts)
	
	if not netem_enabled:
		_send_packet(encoded, _target_peer, _transfer_channel)
		
	return OK

func _send_packet(payload: PackedByteArray, target: int, channel: int) -> void:
	if enet == null: return
	var flag = ENetPacketPeer.FLAG_RELIABLE if _transfer_mode == MultiplayerPeer.TRANSFER_MODE_RELIABLE else ENetPacketPeer.FLAG_UNSEQUENCED
	if target == 0:
		enet.broadcast(channel, payload, flag)
	else:
		for ep in _peer_map:
			if _peer_map[ep] == target:
				ep.send(channel, payload, flag)
				break

func _get_available_packet_count() -> int: return _in_queue.size()

func _get_packet_script() -> PackedByteArray: 
	if _in_queue.size() > 0:
		var pkt = _in_queue.pop_front()
		_current_packet_peer = pkt.peer
		_current_packet_channel = pkt.channel
		return pkt.data
	return PackedByteArray()
	
func _get_packet_peer() -> int:
	if _in_queue.size() > 0:
		return _in_queue[0].peer
	return _current_packet_peer
func _get_packet_channel() -> int:
	if _in_queue.size() > 0:
		return _in_queue[0].channel
	return _current_packet_channel
func _get_packet_mode() -> int: return MultiplayerPeer.TRANSFER_MODE_RELIABLE
func _get_unique_id() -> int: return 1 if _is_server_flag else _client_id
func _is_server() -> bool: return _is_server_flag
func _get_connection_status() -> int: return _status
func _close() -> void: pass
func _disconnect_peer(peer: int, force: bool) -> void: pass
func _is_server_relay_supported() -> bool: return false
func _get_max_packet_size() -> int: return 1048576
func _poll() -> void:
	if enet == null: return
	var event = enet.service(0)
	while event.size() > 0 and event[0] != ENetConnection.EVENT_NONE:
		var type = event[0]
		if type == ENetConnection.EVENT_ERROR: break
		var ep = event[1] as ENetPacketPeer
		if type == ENetConnection.EVENT_CONNECT:
			if _is_server_flag:
				var id = _next_id
				_next_id += 1
				_peer_map[ep] = id
				peer_connected.emit(id)
			else:
				_peer_map[ep] = 1
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				peer_connected.emit(1)
		elif type == ENetConnection.EVENT_DISCONNECT:
			if _peer_map.has(ep):
				peer_disconnected.emit(_peer_map[ep])
				_peer_map.erase(ep)
			if not _is_server_flag:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		elif type == ENetConnection.EVENT_RECEIVE:
			if _peer_map.has(ep):
				var data = ep.get_packet()
				var decoded = _decode(data)
				print("SERVER RECEIVED DATA: ", decoded.hex_encode())
				if decoded.size() > 0:
					_in_queue.append({"peer": _peer_map[ep], "data": decoded, "channel": event[2]})
		event = enet.service(0)
	
	if netem_enabled:
		_drain_netem(Time.get_ticks_msec())
