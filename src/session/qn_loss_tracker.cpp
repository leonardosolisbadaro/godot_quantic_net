#include "qn_loss_tracker.hpp"
#include <godot_cpp/core/class_db.hpp>

using namespace godot;

QNLossTracker::QNLossTracker() {
	last_seq = -1;
	received = 0;
	lost = 0;
}

QNLossTracker::~QNLossTracker() {
}

void QNLossTracker::_bind_methods() {
	ClassDB::bind_method(D_METHOD("on_packet", "seq"), &QNLossTracker::on_packet);
	ClassDB::bind_method(D_METHOD("loss_pct"), &QNLossTracker::loss_pct);
	
	ClassDB::bind_method(D_METHOD("get_received"), &QNLossTracker::get_received);
	ClassDB::bind_method(D_METHOD("get_lost"), &QNLossTracker::get_lost);
	
	ADD_PROPERTY(PropertyInfo(Variant::INT, "received"), "", "get_received");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "lost"), "", "get_lost");
}

void QNLossTracker::on_packet(int seq) {
	if (last_seq == -1) {
		last_seq = seq;
		_record(true);
		received += 1;
		return;
	}
	
	int gap = (seq - last_seq) & 0xFFFF;
	if (gap == 0 || gap > 32768) {
		return;
	}
	
	for (int i = 1; i < gap; i++) {
		_record(false);
		lost += 1;
	}
	
	_record(true);
	received += 1;
	last_seq = seq;
}

void QNLossTracker::_record(bool ok) {
	recent.push_back(ok);
	if (recent.size() > WINDOW) {
		recent.pop_front();
	}
}

double QNLossTracker::loss_pct() {
	if (recent.empty()) {
		return 0.0;
	}
	int count_false = 0;
	for (bool b : recent) {
		if (!b) count_false++;
	}
	return 100.0 * (double)count_false / (double)recent.size();
}
