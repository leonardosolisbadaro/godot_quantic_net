#ifndef QN_CLIENT_SESSION_H
#define QN_CLIENT_SESSION_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <deque>

#include "core/qn_clock_sync.hpp"
#include "core/qn_input_buffer.hpp"
#include "core/qn_interp_buffer.hpp"
#include "session/qn_loss_tracker.hpp"

namespace godot {

class QNClientSession : public RefCounted {
	GDCLASS(QNClientSession, RefCounted)

private:
	static const int CH_STATE = 1;
	static constexpr double SEND_INTERVAL = 0.05;
	static const int TRANSFER_UNRELIABLE = 2;

	Ref<QNClockSync> _clock;
	Ref<QNInputBuffer> _input_buf;
	Dictionary _interp; // owner -> Ref<QNInterpBuffer>
	Ref<QNLossTracker> _loss_tracker;
	
	std::deque<Dictionary> _state_history;
	std::deque<Dictionary> _world_history;
	int _last_server_seq = 0;
	
	double _send_accum = 0.0;
	int _send_seq = 0;
	int _my_id = 0;

	Callable send_callable;

	void _handle_snapback(const PackedByteArray &body);
	void _handle_snapshot(const PackedByteArray &body, int now);

protected:
	static void _bind_methods();

public:
	Vector3 local_pos;
	Vector3 local_rot;

	void set_local_pos(const Vector3 &p_pos) { local_pos = p_pos; }
	Vector3 get_local_pos() const { return local_pos; }
	void set_local_rot(const Vector3 &p_rot) { local_rot = p_rot; }
	Vector3 get_local_rot() const { return local_rot; }

	QNClientSession();
	~QNClientSession();

	void init(Callable p_send_callable);
	void set_local_id(int id);
	
	bool is_clock_synced();
	double clock_rtt();
	double clock_offset();
	int server_time(int now);

	bool submit_state(const Vector3 &pos, const Vector3 &rot, int custom_id, double dt, int now);
	void record_input(int seq, const Vector2 &move, double rot_delta, double dt, int sent_ts);
	int pending_inputs();

	void handle_packet(const PackedByteArray &data, int now);
	Dictionary remote_state(int owner, int now);
	double loss_of(int owner);
	void cleanup_entity(int owner);
};

} // namespace godot

#endif // QN_CLIENT_SESSION_H
