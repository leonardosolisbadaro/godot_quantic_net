#ifndef QN_CLOCK_SYNC_H
#define QN_CLOCK_SYNC_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <deque>

namespace godot {

class QNClockSync : public RefCounted {
	GDCLASS(QNClockSync, RefCounted)

private:
	static const int SAMPLE_WINDOW = 10;
	static constexpr double EMA_ALPHA = 0.2;

	std::deque<double> _samples;
	bool _initialized;

protected:
	static void _bind_methods();

public:
	double offset_ms;
	double rtt_ms;
	double jitter_ms;

	QNClockSync();
	~QNClockSync();

	void on_pong(int client_sent_time, int server_time, int client_now);
	int server_time();
	bool is_synced();

	double get_offset_ms() const { return offset_ms; }
	double get_rtt_ms() const { return rtt_ms; }
	double get_jitter_ms() const { return jitter_ms; }
};

} // namespace godot

#endif // QN_CLOCK_SYNC_H
