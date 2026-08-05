#ifndef QN_INTERP_BUFFER_H
#define QN_INTERP_BUFFER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

class QNInterpBuffer : public RefCounted {
	GDCLASS(QNInterpBuffer, RefCounted)

private:
	static const int BASE_DELAY_MS = 60;
	static const int MAX_DELAY_MS = 250;
	static const int MAX_SNAPSHOTS = 20;
	static const int EXTRAPOLATION_LIMIT_MS = 250;
	static constexpr double ERROR_BLEND_SPEED = 5.0;

	Array snaps;
	Dictionary _cached_state;
	Dictionary _empty_state;

	int _last_sample_now;
	Vector3 _last_sample_pos;
	Vector3 _last_sample_rot;
	bool _was_extrapolating;
	Vector3 _error_pos;
	Vector3 _error_rot;

	double _target_delay_ms;
	double _current_delay_ms;
	int render_delay_ms;

	static Vector3 _lerp_angle_vec(const Vector3 &a, const Vector3 &b, double t);

protected:
	static void _bind_methods();

public:
	QNInterpBuffer();
	~QNInterpBuffer();

	void update_jitter(double jitter_ms);
	void push(int ts, const Vector3 &pos, const Vector3 &rot);
	Dictionary sample(int now);
};

} // namespace godot

#endif // QN_INTERP_BUFFER_H
