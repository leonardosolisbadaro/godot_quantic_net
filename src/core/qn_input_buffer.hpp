#ifndef QN_INPUT_BUFFER_H
#define QN_INPUT_BUFFER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class QNInputBuffer : public RefCounted {
	GDCLASS(QNInputBuffer, RefCounted)

private:
	static const int MAX_PENDING = 256;
	Array pending;

protected:
	static void _bind_methods();

public:
	QNInputBuffer();
	~QNInputBuffer();

	void record(int seq, const Vector2 &move, double rot_delta, double dt, int sent_ts = 0);
	int get_sent_ts(int seq);
	Array drain_after(int confirmed_seq);
	int size() const;
};

} // namespace godot

#endif // QN_INPUT_BUFFER_H
