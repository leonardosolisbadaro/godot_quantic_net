## @file qn_wire_peer.gd
## @path res://addons/quantic_net/src/adapters/qn_wire_peer.gd
##
## @description
## Peer de rede proprietário sobre ENetConnection: codec versionado
## (magic+ZSTD condicional+XOR), mapa de canais virtuais e Netem.
## Camada: Adapters
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

func _init(p_enet: ENetConnection = null) -> void:
	if p_enet:
		enet = p_enet

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
			"release_ts": current_ts + delay
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
	
	_netem_queue = remaining
	return ready


var _target_peer := 0
var _transfer_channel := 0
var _transfer_mode := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
var _refusing_connections := false

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
	# Primeiro encodamos
	var encoded = _encode(_transfer_channel, p_buffer)
	# Depois passamos no Netem
	var queued = _queue_netem(_transfer_channel, encoded, current_ts)
	
	# Aqui, em teoria, se o release_ts <= current_ts, enviamos imediatamente pro ENet.
	# Como é um wrapper, a lógica real de envio dependerá do ENetConnection que encapsularemos mais tarde.
	return OK

func _get_available_packet_count() -> int: return 0
func _get_packet_script() -> PackedByteArray: return PackedByteArray()
func _get_packet_peer() -> int: return 0
func _get_packet_channel() -> int: return 0
func _get_packet_mode() -> int: return 0
func _get_unique_id() -> int: return 0
func _is_server() -> bool: return false
func _get_connection_status() -> int: return MultiplayerPeer.CONNECTION_DISCONNECTED
func _close() -> void: pass
func _disconnect_peer(peer: int, force: bool) -> void: pass
func _is_server_relay_supported() -> bool: return false
func _get_max_packet_size() -> int: return 0
func _poll() -> void: pass
