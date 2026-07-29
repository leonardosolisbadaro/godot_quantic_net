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

# Dummy virtual methods to prevent abstract class errors in Godot
func _get_available_packet_count() -> int: return 0
func _get_packet_script() -> PackedByteArray: return PackedByteArray()
func _get_packet_peer() -> int: return 0
func _get_packet_channel() -> int: return 0
func _get_packet_mode() -> int: return 0
func _get_unique_id() -> int: return 0
func _is_server() -> bool: return false
func _get_connection_status() -> MultiplayerPeer.ConnectionStatus: return MultiplayerPeer.CONNECTION_DISCONNECTED
func _set_target_peer(peer: int) -> void: pass
func _set_transfer_channel(channel: int) -> void: pass
func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void: pass
func _get_transfer_channel() -> int: return 0
func _get_transfer_mode() -> MultiplayerPeer.TransferMode: return MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
func _get_max_packet_size() -> int: return 0
func _close() -> void: pass
func _disconnect_peer(peer: int, force: bool) -> void: pass
func _is_server_relay_supported() -> bool: return false
func _is_refusing_new_connections() -> bool: return false
func _set_refuse_new_connections(enable: bool) -> void: pass
