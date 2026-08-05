#ifndef QN_LOSS_TRACKER_H
#define QN_LOSS_TRACKER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <deque>

namespace godot {

class QNLossTracker : public RefCounted {
	GDCLASS(QNLossTracker, RefCounted)

private:
	static const int WINDOW = 128;
	int last_seq;
	int received;
	int lost;
	std::deque<bool> recent;

	void _record(bool ok);

protected:
	static void _bind_methods();

public:
	QNLossTracker();
	~QNLossTracker();

	void on_packet(int seq);
	double loss_pct();
};

} // namespace godot

#endif // QN_LOSS_TRACKER_H
