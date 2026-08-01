## @file qn_serializer.gd
## @path res://addons/quantic_net/src/domain/qn_serializer.gd
##
## @description
## Serializer binário quantizado de estado (19 bytes): posição 3x16bit,
## rotação 3x16bit (ângulos), seq 16bit, timestamp 32bit, custom_id 8bit.
## Camada: Domain (regra pura — não conhece ENet, MultiplayerPeer nem SceneTree).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)


const QNBitBuffer = preload("res://addons/quantic_net/src/domain/qn_bit_buffer.gd")

const TYPE_STATE := 1
const TYPE_SNAPBACK := 2
const TYPE_PEER_LEFT := 3

const POS_LO := -64.0
const POS_HI := 64.0

static func encode_state_seq(seq: int, pos: Vector3, rot: Vector3, ts_msec: int, custom_id: int) -> PackedByteArray:
	var buf = QNBitBuffer.new()
	buf.write_bits(seq & 0xFFFF, 16)
	buf.write_float(pos.x, POS_LO, POS_HI, 16)
	buf.write_float(pos.y, POS_LO, POS_HI, 16)
	buf.write_float(pos.z, POS_LO, POS_HI, 16)
	buf.write_quaternion(Quaternion.from_euler(rot))
	buf.write_bits(ts_msec & 0xFFFFFFFF, 32)
	buf.write_bits(custom_id & 0xFF, 8)
	return buf.get_buffer()

static func decode_state_seq(b: PackedByteArray) -> Dictionary:
	if b.size() < 17:
		return {}
	var buf = QNBitBuffer.new(b)
	return {
		"seq": buf.read_bits(16),
		"pos": Vector3(
			buf.read_float(POS_LO, POS_HI, 16),
			buf.read_float(POS_LO, POS_HI, 16),
			buf.read_float(POS_LO, POS_HI, 16)),
		"rot": buf.read_quaternion().get_euler(),
		"ts": buf.read_bits(32),
		"custom_id": buf.read_bits(8),
	}

static func encode_snapback(seq: int, pos: Vector3, rot: Vector3, ts_msec: int, reason: int) -> PackedByteArray:
	return encode_state_seq(seq, pos, rot, ts_msec, reason)

static func encode_state_history(history: Array) -> PackedByteArray:
	var buf = QNBitBuffer.new()
	var count = mini(history.size(), 255)
	buf.write_bits(count, 8)
	
	for i in range(count):
		var st = history[i]
		var seq = st.get("seq", 0)
		var pos = st.get("pos", Vector3.ZERO)
		var rot = st.get("rot", Vector3.ZERO)
		var ts = st.get("ts", 0)
		var custom_id = st.get("custom_id", 0)
		
		buf.write_bits(seq & 0xFFFF, 16)
		buf.write_float(pos.x, POS_LO, POS_HI, 16)
		buf.write_float(pos.y, POS_LO, POS_HI, 16)
		buf.write_float(pos.z, POS_LO, POS_HI, 16)
		buf.write_quaternion(Quaternion.from_euler(rot))
		buf.write_bits(ts & 0xFFFFFFFF, 32)
		buf.write_bits(custom_id & 0xFF, 8)
		
	return buf.get_buffer()

static func decode_state_history(b: PackedByteArray) -> Array:
	if b.size() < 1:
		return []
	var buf = QNBitBuffer.new(b)
	var count = buf.read_bits(8)
	var history := []
	
	for i in range(count):
		if (buf.get_position() + 133) / 8 > b.size():
			break
			
		var d = {}
		d["seq"] = buf.read_bits(16)
		d["pos"] = Vector3(
			buf.read_float(POS_LO, POS_HI, 16),
			buf.read_float(POS_LO, POS_HI, 16),
			buf.read_float(POS_LO, POS_HI, 16)
		)
		d["rot"] = buf.read_quaternion().get_euler()
		d["ts"] = buf.read_bits(32)
		d["custom_id"] = buf.read_bits(8)
		history.append(d)
		
	return history
