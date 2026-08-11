#ifndef QN_SERIALIZER_H
#define QN_SERIALIZER_H

#include <godot_cpp/core/object.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

class QNSerializer : public Object {
	GDCLASS(QNSerializer, Object)

protected:
	static void _bind_methods();

public:
	// --- CONNECTION / TOPOLOGY (0 - 9) ---
	static constexpr int TYPE_PEER_LEFT = 1;

	// --- PHYSICS & STATE SYNC (10 - 19) ---
	static constexpr int TYPE_STATE = 10;
	static constexpr int TYPE_SNAPBACK = 11;
	static constexpr int TYPE_SLEEP = 12;
	static constexpr int TYPE_INPUT_SNAPSHOT = 13;

	// --- INTERNAL COMMANDS (20 - 31) ---
	static constexpr int TYPE_INPUT = 20;

	static const double POS_LO;
	static const double POS_HI;

	static PackedByteArray encode_state_seq(int seq, const Vector3 &pos, const Vector3 &rot, int ts_msec, int custom_id);
	static Dictionary decode_state_seq(const PackedByteArray &b);

	static PackedByteArray encode_snapback(int seq, const Vector3 &pos, const Vector3 &rot, int ts_msec, int reason);

	static PackedByteArray encode_state_history(const Array &history);
	static Array decode_state_history(const PackedByteArray &b);
};

} // namespace godot

#endif // QN_SERIALIZER_H
