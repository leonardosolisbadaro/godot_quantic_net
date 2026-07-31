## @file qn_delta_serializer.gd
## @path res://addons/quantic_net/src/domain/qn_delta_serializer.gd
##
## @description
## Delta Compression para estados de entidades (P-Frames).
## Se a base for vazia, grava I-Frame (Absoluto).
## Se houver base, grava flag de mudança (1 bit) + valor (se mudou).
##
## @created 2026-07-31
## @updated 2026-07-31

extends RefCounted

const QNBitBuffer = preload("res://addons/quantic_net/src/domain/qn_bit_buffer.gd")

const POS_LO := -64.0
const POS_HI := 64.0
const POS_BITS := 16

static func encode_state(buf: QNBitBuffer, base: Dictionary, current: Dictionary) -> void:
	buf.write_bits(current.get("seq", 0) & 0xFFFF, 16)
	buf.write_bits(current.get("ts", 0) & 0xFFFFFFFF, 32)
	
	if base.is_empty():
		# I-Frame (Absolute)
		buf.write_bool(true)
		var pos = current.get("pos", Vector3.ZERO)
		buf.write_float(pos.x, POS_LO, POS_HI, POS_BITS)
		buf.write_float(pos.y, POS_LO, POS_HI, POS_BITS)
		buf.write_float(pos.z, POS_LO, POS_HI, POS_BITS)
		
		buf.write_bool(true)
		var rot = current.get("rot", Vector3.ZERO)
		buf.write_quaternion(Quaternion.from_euler(rot))
		
		buf.write_bool(true)
		buf.write_bits(current.get("custom_id", 0) & 0xFF, 8)
	else:
		# P-Frame (Delta)
		var c_pos = current.get("pos", Vector3.ZERO)
		var b_pos = base.get("pos", Vector3.ZERO)
		if c_pos.distance_squared_to(b_pos) > 0.0001:
			buf.write_bool(true)
			buf.write_float(c_pos.x, POS_LO, POS_HI, POS_BITS)
			buf.write_float(c_pos.y, POS_LO, POS_HI, POS_BITS)
			buf.write_float(c_pos.z, POS_LO, POS_HI, POS_BITS)
		else:
			buf.write_bool(false)
			
		var c_rot = current.get("rot", Vector3.ZERO)
		var b_rot = base.get("rot", Vector3.ZERO)
		if c_rot.distance_squared_to(b_rot) > 0.0001:
			buf.write_bool(true)
			buf.write_quaternion(Quaternion.from_euler(c_rot))
		else:
			buf.write_bool(false)
			
		var c_cid = current.get("custom_id", 0)
		var b_cid = base.get("custom_id", 0)
		if c_cid != b_cid:
			buf.write_bool(true)
			buf.write_bits(c_cid & 0xFF, 8)
		else:
			buf.write_bool(false)

static func decode_state(buf: QNBitBuffer, base: Dictionary) -> Dictionary:
	var d = {}
	d["seq"] = buf.read_bits(16)
	d["ts"] = buf.read_bits(32)
	
	if buf.read_bool():
		d["pos"] = Vector3(
			buf.read_float(POS_LO, POS_HI, POS_BITS),
			buf.read_float(POS_LO, POS_HI, POS_BITS),
			buf.read_float(POS_LO, POS_HI, POS_BITS)
		)
	else:
		d["pos"] = base.get("pos", Vector3.ZERO)
		
	if buf.read_bool():
		d["rot"] = buf.read_quaternion().get_euler()
	else:
		d["rot"] = base.get("rot", Vector3.ZERO)
		
	if buf.read_bool():
		d["custom_id"] = buf.read_bits(8)
	else:
		d["custom_id"] = base.get("custom_id", 0)
		
	return d
