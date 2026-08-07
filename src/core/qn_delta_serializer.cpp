#include "qn_delta_serializer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/quaternion.hpp>

using namespace godot;

const double QNDeltaSerializer::POS_LO = -64.0;
const double QNDeltaSerializer::POS_HI = 64.0;

void QNDeltaSerializer::_bind_methods() {
	ClassDB::bind_static_method("QNDeltaSerializer", D_METHOD("encode_state", "buf", "base", "current"), &QNDeltaSerializer::encode_state);
	ClassDB::bind_static_method("QNDeltaSerializer", D_METHOD("decode_state", "buf", "base"), &QNDeltaSerializer::decode_state);
}

void QNDeltaSerializer::encode_state(const Ref<QNBitBuffer> &buf, const Dictionary &base, const Dictionary &current) {
	if (buf.is_null()) {
		return;
	}

	buf->write_bits((int)current.get("seq", 0) & 0xFFFF, 16);
	buf->write_bits((int)current.get("ts", 0) & 0xFFFFFFFF, 32);
	
	if (base.is_empty()) {
		// I-Frame (Absolute)
		buf->write_bool(true);
		Vector3 pos = current.get("pos", Vector3());
		buf->write_float(pos.x, POS_LO, POS_HI, POS_BITS);
		buf->write_float(pos.y, POS_LO, POS_HI, POS_BITS);
		buf->write_float(pos.z, POS_LO, POS_HI, POS_BITS);
		
		buf->write_bool(true);
		Vector3 rot = current.get("rot", Vector3());
		buf->write_quaternion(Quaternion::from_euler(rot));
		
		buf->write_bool(true);
		buf->write_bits((int)current.get("custom_id", 0) & 0xFF, 8);
	} else {
		// P-Frame (Delta)
		Vector3 c_pos = current.get("pos", Vector3());
		Vector3 b_pos = base.get("pos", Vector3());
		if (c_pos.distance_squared_to(b_pos) > 0.0001) {
			buf->write_bool(true);
			buf->write_float(c_pos.x, POS_LO, POS_HI, POS_BITS);
			buf->write_float(c_pos.y, POS_LO, POS_HI, POS_BITS);
			buf->write_float(c_pos.z, POS_LO, POS_HI, POS_BITS);
		} else {
			buf->write_bool(false);
		}
			
		Vector3 c_rot = current.get("rot", Vector3());
		Vector3 b_rot = base.get("rot", Vector3());
		if (c_rot.distance_squared_to(b_rot) > 0.0001) {
			buf->write_bool(true);
			buf->write_quaternion(Quaternion::from_euler(c_rot));
		} else {
			buf->write_bool(false);
		}
			
		int c_cid = current.get("custom_id", 0);
		int b_cid = base.get("custom_id", 0);
		if (c_cid != b_cid) {
			buf->write_bool(true);
			buf->write_bits(c_cid & 0xFF, 8);
		} else {
			buf->write_bool(false);
		}
	}
}

Dictionary QNDeltaSerializer::decode_state(const Ref<QNBitBuffer> &buf, const Dictionary &base) {
	Dictionary d;
	if (buf.is_null()) {
		return d;
	}

	d["seq"] = (int)buf->read_bits(16);
	d["ts"] = (int)buf->read_bits(32);
	
	if (buf->read_bool()) {
		double x = buf->read_float(POS_LO, POS_HI, POS_BITS);
		double y = buf->read_float(POS_LO, POS_HI, POS_BITS);
		double z = buf->read_float(POS_LO, POS_HI, POS_BITS);
		d["pos"] = Vector3(x, y, z);
	} else {
		d["pos"] = base.get("pos", Vector3());
	}
		
	if (buf->read_bool()) {
		d["rot"] = buf->read_quaternion().get_euler();
	} else {
		d["rot"] = base.get("rot", Vector3());
	}
		
	if (buf->read_bool()) {
		d["custom_id"] = (int)buf->read_bits(8);
	} else {
		d["custom_id"] = base.get("custom_id", 0);
	}
		
	return d;
}
