#include "qn_delta_serializer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/quaternion.hpp>

using namespace godot;

const double QNDeltaSerializer::POS_LO = -64.0;
const double QNDeltaSerializer::POS_HI = 64.0;

void QNDeltaSerializer::_bind_methods() {
}

void QNDeltaSerializer::encode_state(const Ref<QNBitBuffer> &buf, const QNEntityState *base, const QNEntityState &current) {
	if (buf.is_null()) {
		return;
	}

	buf->write_bits(current.seq & 0xFFFF, 16);
	buf->write_bits(current.ts & 0xFFFFFFFF, 32);
	
	if (base == nullptr || !base->has_state) {
		// I-Frame (Absolute)
		buf->write_bool(true);
		buf->write_float(current.pos.x, POS_LO, POS_HI, POS_BITS);
		buf->write_float(current.pos.y, POS_LO, POS_HI, POS_BITS);
		buf->write_float(current.pos.z, POS_LO, POS_HI, POS_BITS);
		
		buf->write_bool(true);
		buf->write_quaternion(Quaternion::from_euler(current.rot));
		
		buf->write_bool(true);
		buf->write_bits(current.custom_id & 0xFF, 8);
	} else {
		// P-Frame (Delta)
		if (current.pos.distance_squared_to(base->pos) > 0.0001) {
			buf->write_bool(true);
			buf->write_float(current.pos.x, POS_LO, POS_HI, POS_BITS);
			buf->write_float(current.pos.y, POS_LO, POS_HI, POS_BITS);
			buf->write_float(current.pos.z, POS_LO, POS_HI, POS_BITS);
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

QNEntityState QNDeltaSerializer::decode_state(const Ref<QNBitBuffer> &buf, const QNEntityState *base) {
	QNEntityState d;
	if (buf.is_null()) {
		return d;
	}
	
	d.has_state = true;
	d.seq = (int)buf->read_bits(16);
	d.ts = (int)buf->read_bits(32);
	
	if (buf->read_bool()) {
		double x = buf->read_float(POS_LO, POS_HI, POS_BITS);
		double y = buf->read_float(POS_LO, POS_HI, POS_BITS);
		double z = buf->read_float(POS_LO, POS_HI, POS_BITS);
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
		
	return d;
}
