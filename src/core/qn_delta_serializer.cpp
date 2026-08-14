#include "qn_delta_serializer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/quaternion.hpp>

using namespace godot;

const double QNDeltaSerializer::POS_LO = -512.0;
const double QNDeltaSerializer::POS_HI = 512.0;

void QNDeltaSerializer::_bind_methods() {
	ClassDB::bind_static_method("QNDeltaSerializer", D_METHOD("encode_state", "buf", "base", "current", "pos_lo", "pos_hi"), &QNDeltaSerializer::encode_state_dict, DEFVAL(POS_LO), DEFVAL(POS_HI));
	ClassDB::bind_static_method("QNDeltaSerializer", D_METHOD("decode_state", "buf", "base", "pos_lo", "pos_hi"), &QNDeltaSerializer::decode_state_dict, DEFVAL(POS_LO), DEFVAL(POS_HI));
}

void QNDeltaSerializer::encode_state(const Ref<QNBitBuffer> &buf, const QNEntityState *base, const QNEntityState &current, double pos_lo, double pos_hi) {
	if (buf.is_null()) {
		return;
	}

	buf->write_bits(current.seq & 0xFFFF, 16);
	buf->write_bits(current.ts & 0xFFFFFFFF, 32);
	
	if (base == nullptr || !base->has_state) {
		// I-Frame (Absolute)
		buf->write_bool(true);
		buf->write_float(current.pos.x, pos_lo, pos_hi, POS_BITS);
		buf->write_float(current.pos.y, pos_lo, pos_hi, POS_BITS);
		buf->write_float(current.pos.z, pos_lo, pos_hi, POS_BITS);
		
		buf->write_bool(true);
		buf->write_quaternion(Quaternion::from_euler(current.rot));
		
		buf->write_bool(true);
		buf->write_bits(current.custom_id & 0xFF, 8);
	} else {
		// P-Frame (Delta)
		if (current.pos.distance_squared_to(base->pos) > 0.0001) {
			buf->write_bool(true);
			buf->write_float(current.pos.x, pos_lo, pos_hi, POS_BITS);
			buf->write_float(current.pos.y, pos_lo, pos_hi, POS_BITS);
			buf->write_float(current.pos.z, pos_lo, pos_hi, POS_BITS);
		} else {
			buf->write_bool(false);
		}
			
		if (current.rot.distance_squared_to(base->rot) > 0.0001) {
			buf->write_bool(true);
			buf->write_quaternion(Quaternion::from_euler(current.rot));
		} else {
			buf->write_bool(false);
		}
			
		if (current.custom_id != base->custom_id) {
			buf->write_bool(true);
			buf->write_bits(current.custom_id & 0xFF, 8);
		} else {
			buf->write_bool(false);
		}
	}
}

QNEntityState QNDeltaSerializer::decode_state(const Ref<QNBitBuffer> &buf, const QNEntityState *base, double pos_lo, double pos_hi) {
	QNEntityState d;
	if (buf.is_null() || buf->has_read_error()) {
		return d;
	}
	
	d.seq = (int)buf->read_bits(16);
	d.ts = (int)buf->read_bits(32);
	
	if (buf->read_bool()) {
		double x = buf->read_float(pos_lo, pos_hi, POS_BITS);
		double y = buf->read_float(pos_lo, pos_hi, POS_BITS);
		double z = buf->read_float(pos_lo, pos_hi, POS_BITS);
		d.pos = Vector3(x, y, z);
	} else {
		d.pos = base ? base->pos : Vector3();
	}
		
	if (buf->read_bool()) {
		d.rot = buf->read_quaternion().get_euler();
	} else {
		d.rot = base ? base->rot : Vector3();
	}
		
	if (buf->read_bool()) {
		d.custom_id = (int)buf->read_bits(8);
	} else {
		d.custom_id = base ? base->custom_id : 0;
	}
	
	if (buf->has_read_error()) {
		d.has_state = false;
	} else {
		d.has_state = true;
	}
		
	return d;
}

void QNDeltaSerializer::encode_state_dict(const Ref<QNBitBuffer> &buf, const Dictionary &base_dict, const Dictionary &current_dict, double pos_lo, double pos_hi) {
	QNEntityState base_st;
	QNEntityState *p_base = nullptr;
	if (!base_dict.is_empty()) {
		base_st.has_state = base_dict.get("has_state", true);
		base_st.seq = base_dict.get("seq", 0);
		base_st.ts = base_dict.get("ts", 0);
		base_st.pos = base_dict.get("pos", Vector3());
		base_st.rot = base_dict.get("rot", Vector3());
		base_st.custom_id = base_dict.get("custom_id", 0);
		p_base = &base_st;
	}

	QNEntityState curr_st;
	curr_st.has_state = true;
	curr_st.seq = current_dict.get("seq", 0);
	curr_st.ts = current_dict.get("ts", 0);
	curr_st.pos = current_dict.get("pos", Vector3());
	curr_st.rot = current_dict.get("rot", Vector3());
	curr_st.custom_id = current_dict.get("custom_id", 0);

	encode_state(buf, p_base, curr_st, pos_lo, pos_hi);
}

Dictionary QNDeltaSerializer::decode_state_dict(const Ref<QNBitBuffer> &buf, const Dictionary &base_dict, double pos_lo, double pos_hi) {
	QNEntityState base_st;
	QNEntityState *p_base = nullptr;
	if (!base_dict.is_empty()) {
		base_st.has_state = base_dict.get("has_state", true);
		base_st.seq = base_dict.get("seq", 0);
		base_st.ts = base_dict.get("ts", 0);
		base_st.pos = base_dict.get("pos", Vector3());
		base_st.rot = base_dict.get("rot", Vector3());
		base_st.custom_id = base_dict.get("custom_id", 0);
		p_base = &base_st;
	}

	QNEntityState res = decode_state(buf, p_base, pos_lo, pos_hi);
	if (!res.has_state) {
		Dictionary empty_dict;
		empty_dict["has_state"] = false;
		return empty_dict;
	}
	return res.to_dict();
}
