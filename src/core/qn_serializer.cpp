#include "qn_serializer.hpp"
#include "qn_bit_buffer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/ref.hpp>

using namespace godot;

const double QNSerializer::POS_LO = -512.0;
const double QNSerializer::POS_HI = 512.0;

void QNSerializer::_bind_methods() {
	ClassDB::bind_static_method("QNSerializer", D_METHOD("encode_state_seq", "seq", "pos", "rot", "ts_msec", "custom_id"), &QNSerializer::encode_state_seq);
	ClassDB::bind_static_method("QNSerializer", D_METHOD("decode_state_seq", "b"), &QNSerializer::decode_state_seq);
	
	ClassDB::bind_static_method("QNSerializer", D_METHOD("encode_snapback", "seq", "pos", "rot", "ts_msec", "reason"), &QNSerializer::encode_snapback);
	
	ClassDB::bind_static_method("QNSerializer", D_METHOD("encode_state_history", "history"), &QNSerializer::encode_state_history);
	ClassDB::bind_static_method("QNSerializer", D_METHOD("decode_state_history", "b"), &QNSerializer::decode_state_history);
	
	BIND_CONSTANT(TYPE_PEER_LEFT);
	BIND_CONSTANT(TYPE_STATE);
	BIND_CONSTANT(TYPE_SNAPBACK);
	BIND_CONSTANT(TYPE_SLEEP);
	BIND_CONSTANT(TYPE_INPUT_SNAPSHOT);
	BIND_CONSTANT(TYPE_INPUT);
}

PackedByteArray QNSerializer::encode_state_seq(int seq, const Vector3 &pos, const Vector3 &rot, int ts_msec, int custom_id) {
	Ref<QNBitBuffer> buf;
	buf.instantiate();
	
	buf->write_bits(seq & 0xFFFF, 16);
	buf->write_float(pos.x, POS_LO, POS_HI, 16);
	buf->write_float(pos.y, POS_LO, POS_HI, 16);
	buf->write_float(pos.z, POS_LO, POS_HI, 16);
	buf->write_quaternion(Quaternion::from_euler(rot));
	buf->write_bits(ts_msec & 0xFFFFFFFF, 32);
	buf->write_bits(custom_id & 0xFF, 8);
	
	return buf->get_buffer();
}

Dictionary QNSerializer::decode_state_seq(const PackedByteArray &b) {
	if (b.size() < 17) {
		return Dictionary();
	}
	
	Ref<QNBitBuffer> buf;
	buf.instantiate();
	buf->set_buffer(b);
	
	Dictionary d;
	d["seq"] = (int)buf->read_bits(16);
	double x = buf->read_float(POS_LO, POS_HI, 16);
	double y = buf->read_float(POS_LO, POS_HI, 16);
	double z = buf->read_float(POS_LO, POS_HI, 16);
	d["pos"] = Vector3(x, y, z);
	d["rot"] = buf->read_quaternion().get_euler();
	d["ts"] = (int)buf->read_bits(32);
	d["custom_id"] = (int)buf->read_bits(8);
	
	return d;
}

PackedByteArray QNSerializer::encode_snapback(int seq, const Vector3 &pos, const Vector3 &rot, int ts_msec, int reason) {
	return encode_state_seq(seq, pos, rot, ts_msec, reason);
}

PackedByteArray QNSerializer::encode_state_history(const Array &history) {
	Ref<QNBitBuffer> buf;
	buf.instantiate();
	
	int count = UtilityFunctions::mini(history.size(), 255);
	buf->write_bits(count, 8);
	
	for (int i = 0; i < count; i++) {
		Dictionary st = history[i];
		int seq = st.get("seq", 0);
		Vector3 pos = st.get("pos", Vector3());
		Vector3 rot = st.get("rot", Vector3());
		int ts = st.get("ts", 0);
		int custom_id = st.get("custom_id", 0);
		
		buf->write_bits(seq & 0xFFFF, 16);
		buf->write_float(pos.x, POS_LO, POS_HI, 16);
		buf->write_float(pos.y, POS_LO, POS_HI, 16);
		buf->write_float(pos.z, POS_LO, POS_HI, 16);
		buf->write_quaternion(Quaternion::from_euler(rot));
		buf->write_bits(ts & 0xFFFFFFFF, 32);
		buf->write_bits(custom_id & 0xFF, 8);
	}
	
	return buf->get_buffer();
}

Array QNSerializer::decode_state_history(const PackedByteArray &b) {
	if (b.size() < 1) {
		return Array();
	}
	
	Ref<QNBitBuffer> buf;
	buf.instantiate();
	buf->set_buffer(b);
	
	int count = buf->read_bits(8);
	Array history;
	
	for (int i = 0; i < count; i++) {
		if ((buf->get_position() + 133) / 8 > b.size()) {
			break;
		}
		
		Dictionary d;
		d["seq"] = (int)buf->read_bits(16);
		double x = buf->read_float(POS_LO, POS_HI, 16);
		double y = buf->read_float(POS_LO, POS_HI, 16);
		double z = buf->read_float(POS_LO, POS_HI, 16);
		d["pos"] = Vector3(x, y, z);
		d["rot"] = buf->read_quaternion().get_euler();
		d["ts"] = (int)buf->read_bits(32);
		d["custom_id"] = (int)buf->read_bits(8);
		
		history.append(d);
	}
	
	return history;
}
