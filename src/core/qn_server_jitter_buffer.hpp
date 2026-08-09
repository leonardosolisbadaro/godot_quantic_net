#ifndef QN_SERVER_JITTER_BUFFER_H
#define QN_SERVER_JITTER_BUFFER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class QNServerJitterBuffer : public RefCounted {
	GDCLASS(QNServerJitterBuffer, RefCounted)

private:
	static const int MAX_PENDING = 512;
	Array pending;
	int tick_rate_ms;
	int target_delay_ms;
	bool initialized;
	int base_seq;
	int base_time;

protected:
	static void _bind_methods();

public:
	QNServerJitterBuffer();
	~QNServerJitterBuffer();

	void setup(int p_tick_rate_ms);
	void set_target_delay(int ms);
	void push(int seq, int input_mask, const Vector2 &look_dir, int server_receive_time);
	Dictionary pop(int current_server_time);
};

} // namespace godot

#endif // QN_SERVER_JITTER_BUFFER_H
