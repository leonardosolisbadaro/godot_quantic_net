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



const TYPE_STATE := 1
const TYPE_SNAPBACK := 2
const TYPE_PEER_LEFT := 3

const POS_LO := -64.0
const POS_HI := 64.0
const TAU_F := TAU

static func quantize_scalar(v: float, lo: float, hi: float) -> int:
	return clampi(roundi((v - lo) / (hi - lo) * 65535.0), 0, 65535)

static func dequantize_scalar(q: int, lo: float, hi: float) -> float:
	return lo + float(q) / 65535.0 * (hi - lo)

static func quantize_angle(a: float) -> int:
	return roundi(fposmod(a, TAU_F) / TAU_F * 65535.0) & 0xFFFF

static func dequantize_angle(q: int) -> float:
	return float(q) / 65535.0 * TAU_F

static func encode_state_seq(seq: int, pos: Vector3, rot: Vector3, ts_msec: int, custom_id: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(19)
	b.encode_u16(0, seq & 0xFFFF)
	b.encode_u16(2, quantize_scalar(pos.x, POS_LO, POS_HI))
	b.encode_u16(4, quantize_scalar(pos.y, POS_LO, POS_HI))
	b.encode_u16(6, quantize_scalar(pos.z, POS_LO, POS_HI))
	b.encode_u16(8, quantize_angle(rot.x))
	b.encode_u16(10, quantize_angle(rot.y))
	b.encode_u16(12, quantize_angle(rot.z))
	b.encode_u32(14, ts_msec & 0xFFFFFFFF)
	b.encode_u8(18, custom_id & 0xFF)
	return b

static func decode_state_seq(b: PackedByteArray) -> Dictionary:
	if b.size() < 19:
		return {}
	return {
		"seq": b.decode_u16(0),
		"pos": Vector3(
			dequantize_scalar(b.decode_u16(2), POS_LO, POS_HI),
			dequantize_scalar(b.decode_u16(4), POS_LO, POS_HI),
			dequantize_scalar(b.decode_u16(6), POS_LO, POS_HI)),
		"rot": Vector3(
			dequantize_angle(b.decode_u16(8)),
			dequantize_angle(b.decode_u16(10)),
			dequantize_angle(b.decode_u16(12))),
		"ts": b.decode_u32(14),
		"custom_id": b.decode_u8(18),
	}

static func encode_snapback(seq: int, pos: Vector3, rot: Vector3, ts_msec: int, reason: int) -> PackedByteArray:
	return encode_state_seq(seq, pos, rot, ts_msec, reason)
