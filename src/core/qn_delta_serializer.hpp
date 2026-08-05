#ifndef QN_DELTA_SERIALIZER_H
#define QN_DELTA_SERIALIZER_H

#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/classes/ref.hpp>
#include "qn_bit_buffer.hpp"

namespace godot {

class QNDeltaSerializer : public Object {
	GDCLASS(QNDeltaSerializer, Object)

protected:
	static void _bind_methods();

public:
	static const double POS_LO;
	static const double POS_HI;
	static const int POS_BITS = 16;

	static void encode_state(const Ref<QNBitBuffer> &buf, const Dictionary &base, const Dictionary &current);
	static Dictionary decode_state(const Ref<QNBitBuffer> &buf, const Dictionary &base);
};

} // namespace godot

#endif // QN_DELTA_SERIALIZER_H
