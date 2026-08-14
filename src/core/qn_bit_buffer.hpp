#ifndef QN_BIT_BUFFER_H
#define QN_BIT_BUFFER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/quaternion.hpp>

namespace godot {

class QNBitBuffer : public RefCounted {
	GDCLASS(QNBitBuffer, RefCounted)

private:
	PackedByteArray _buffer;
	int _bit_position;
	bool _read_overflow;

protected:
	static void _bind_methods();

public:
	QNBitBuffer();
	~QNBitBuffer();

	void set_buffer(const PackedByteArray &buf);
	PackedByteArray get_buffer() const;
	
	void seek(int pos);
	int get_position() const;
	bool has_read_error() const;

	void write_bool(bool b);
	bool read_bool();

	void write_bits(uint64_t value, int num_bits);
	uint64_t read_bits(int num_bits);

	void write_float(double val, double min_val, double max_val, int precision_bits);
	double read_float(double min_val, double max_val, int precision_bits);

	void write_quaternion(const Quaternion &q);
	Quaternion read_quaternion();
};

} // namespace godot

#endif // QN_BIT_BUFFER_H
