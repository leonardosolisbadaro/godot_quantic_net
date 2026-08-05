#include "qn_bit_buffer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

QNBitBuffer::QNBitBuffer() {
	_bit_position = 0;
	_buffer.resize(32); // Pre-allocate some capacity to avoid frequent reallocations
}

QNBitBuffer::~QNBitBuffer() {
}

void QNBitBuffer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_buffer", "buf"), &QNBitBuffer::set_buffer);
	ClassDB::bind_method(D_METHOD("get_buffer"), &QNBitBuffer::get_buffer);
	ClassDB::bind_method(D_METHOD("seek", "pos"), &QNBitBuffer::seek);
	ClassDB::bind_method(D_METHOD("get_position"), &QNBitBuffer::get_position);
	
	ClassDB::bind_method(D_METHOD("write_bool", "b"), &QNBitBuffer::write_bool);
	ClassDB::bind_method(D_METHOD("read_bool"), &QNBitBuffer::read_bool);
	
	ClassDB::bind_method(D_METHOD("write_bits", "value", "num_bits"), &QNBitBuffer::write_bits);
	ClassDB::bind_method(D_METHOD("read_bits", "num_bits"), &QNBitBuffer::read_bits);
	
	ClassDB::bind_method(D_METHOD("write_float", "val", "min_val", "max_val", "precision_bits"), &QNBitBuffer::write_float);
	ClassDB::bind_method(D_METHOD("read_float", "min_val", "max_val", "precision_bits"), &QNBitBuffer::read_float);
	
	ClassDB::bind_method(D_METHOD("write_quaternion", "q"), &QNBitBuffer::write_quaternion);
	ClassDB::bind_method(D_METHOD("read_quaternion"), &QNBitBuffer::read_quaternion);
}

void QNBitBuffer::set_buffer(const PackedByteArray &buf) {
	_buffer = buf;
	_bit_position = 0;
}

PackedByteArray QNBitBuffer::get_buffer() const {
	int byte_count = (_bit_position + 7) / 8;
	return _buffer.slice(0, byte_count);
}

void QNBitBuffer::seek(int pos) {
	_bit_position = pos;
}

int QNBitBuffer::get_position() const {
	return _bit_position;
}

void QNBitBuffer::write_bool(bool b) {
	write_bits(b ? 1 : 0, 1);
}

bool QNBitBuffer::read_bool() {
	return read_bits(1) != 0;
}

void QNBitBuffer::write_bits(uint64_t value, int num_bits) {
	int byte_idx = _bit_position / 8;
	int bit_offset = _bit_position % 8;
	
	int required_bytes = (_bit_position + num_bits + 7) / 8;
	if (_buffer.size() < required_bytes) {
		_buffer.resize(required_bytes * 2);
	}
	
	uint64_t mask = (1ULL << num_bits) - 1;
	uint64_t val = value & mask;
	
	int bits_written = 0;
	uint8_t *ptr = _buffer.ptrw();
	
	while (bits_written < num_bits) {
		int bits_this_byte = 8 - bit_offset;
		int bits_to_write = UtilityFunctions::mini(bits_this_byte, num_bits - bits_written);
		
		uint64_t chunk_mask = (1ULL << bits_to_write) - 1;
		uint64_t chunk = (val >> bits_written) & chunk_mask;
		
		ptr[byte_idx] = ptr[byte_idx] & ~(chunk_mask << bit_offset);
		ptr[byte_idx] = ptr[byte_idx] | (chunk << bit_offset);
		
		bits_written += bits_to_write;
		_bit_position += bits_to_write;
		byte_idx += 1;
		bit_offset = 0;
	}
}

uint64_t QNBitBuffer::read_bits(int num_bits) {
	int byte_idx = _bit_position / 8;
	int bit_offset = _bit_position % 8;
	
	uint64_t val = 0;
	int bits_read = 0;
	
	const uint8_t *ptr = _buffer.ptr();
	int size = _buffer.size();
	
	while (bits_read < num_bits) {
		if (byte_idx >= size) {
			break;
		}
		
		int bits_this_byte = 8 - bit_offset;
		int bits_to_read = UtilityFunctions::mini(bits_this_byte, num_bits - bits_read);
		
		uint64_t chunk_mask = (1ULL << bits_to_read) - 1;
		uint64_t chunk = (ptr[byte_idx] >> bit_offset) & chunk_mask;
		
		val = val | (chunk << bits_read);
		
		bits_read += bits_to_read;
		_bit_position += bits_to_read;
		byte_idx += 1;
		bit_offset = 0;
	}
	
	return val;
}

void QNBitBuffer::write_float(double val, double min_val, double max_val, int precision_bits) {
	uint64_t max_int = (1ULL << precision_bits) - 1;
	double ratio = UtilityFunctions::clamp((val - min_val) / (max_val - min_val), 0.0, 1.0);
	uint64_t int_val = (uint64_t)UtilityFunctions::round(ratio * (double)max_int);
	write_bits(int_val, precision_bits);
}

double QNBitBuffer::read_float(double min_val, double max_val, int precision_bits) {
	uint64_t max_int = (1ULL << precision_bits) - 1;
	uint64_t int_val = read_bits(precision_bits);
	double ratio = (double)int_val / (double)max_int;
	return min_val + ratio * (max_val - min_val);
}

void QNBitBuffer::write_quaternion(const Quaternion &q) {
	int max_idx = 0;
	double max_val = Math::abs(q.x);
	if (Math::abs(q.y) > max_val) { max_idx = 1; max_val = Math::abs(q.y); }
	if (Math::abs(q.z) > max_val) { max_idx = 2; max_val = Math::abs(q.z); }
	if (Math::abs(q.w) > max_val) { max_idx = 3; max_val = Math::abs(q.w); }
	
	double sign_val = 1.0;
	switch (max_idx) {
		case 0: sign_val = Math::sign(q.x); break;
		case 1: sign_val = Math::sign(q.y); break;
		case 2: sign_val = Math::sign(q.z); break;
		case 3: sign_val = Math::sign(q.w); break;
	}
	if (sign_val == 0.0) sign_val = 1.0;
	
	Quaternion q_norm(q.x * sign_val, q.y * sign_val, q.z * sign_val, q.w * sign_val);
	
	write_bits(max_idx, 2);
	
	double min_comp = -0.707107;
	double max_comp = 0.707107;
	int precision = 10;
	
	switch (max_idx) {
		case 0:
			write_float(q_norm.y, min_comp, max_comp, precision);
			write_float(q_norm.z, min_comp, max_comp, precision);
			write_float(q_norm.w, min_comp, max_comp, precision);
			break;
		case 1:
			write_float(q_norm.x, min_comp, max_comp, precision);
			write_float(q_norm.z, min_comp, max_comp, precision);
			write_float(q_norm.w, min_comp, max_comp, precision);
			break;
		case 2:
			write_float(q_norm.x, min_comp, max_comp, precision);
			write_float(q_norm.y, min_comp, max_comp, precision);
			write_float(q_norm.w, min_comp, max_comp, precision);
			break;
		case 3:
			write_float(q_norm.x, min_comp, max_comp, precision);
			write_float(q_norm.y, min_comp, max_comp, precision);
			write_float(q_norm.z, min_comp, max_comp, precision);
			break;
	}
}

Quaternion QNBitBuffer::read_quaternion() {
	int max_idx = read_bits(2);
	double min_comp = -0.707107;
	double max_comp = 0.707107;
	int precision = 10;
	
	double a = read_float(min_comp, max_comp, precision);
	double b = read_float(min_comp, max_comp, precision);
	double c = read_float(min_comp, max_comp, precision);
	
	double missing_sq = Math::max(0.0, 1.0 - a*a - b*b - c*c);
	double missing = Math::sqrt(missing_sq);
	
	Quaternion q;
	switch (max_idx) {
		case 0: q = Quaternion(missing, a, b, c); break;
		case 1: q = Quaternion(a, missing, b, c); break;
		case 2: q = Quaternion(a, b, missing, c); break;
		case 3: q = Quaternion(a, b, c, missing); break;
	}
	
	return q.normalized();
}
