#include "qn_clock_sync.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/time.hpp>

using namespace godot;

QNClockSync::QNClockSync() {
	offset_ms = 0.0;
	rtt_ms = 0.0;
	jitter_ms = 0.0;
	_initialized = false;
}

QNClockSync::~QNClockSync() {
}

void QNClockSync::_bind_methods() {
	ClassDB::bind_method(D_METHOD("on_pong", "client_sent_time", "server_time", "client_now"), &QNClockSync::on_pong);
	ClassDB::bind_method(D_METHOD("server_time"), &QNClockSync::server_time);
	ClassDB::bind_method(D_METHOD("is_synced"), &QNClockSync::is_synced);
	
	ClassDB::bind_method(D_METHOD("get_offset_ms"), &QNClockSync::get_offset_ms);
	ClassDB::bind_method(D_METHOD("get_rtt_ms"), &QNClockSync::get_rtt_ms);
	ClassDB::bind_method(D_METHOD("get_jitter_ms"), &QNClockSync::get_jitter_ms);
	
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "offset_ms"), "", "get_offset_ms");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "rtt_ms"), "", "get_rtt_ms");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "jitter_ms"), "", "get_jitter_ms");
}

void QNClockSync::on_pong(int client_sent_time, int server_time_val, int client_now) {
	if (client_sent_time <= 0) return;
	int rtt = client_now - client_sent_time;
	if (rtt < 0 || rtt > 5000) {
		return;
	}
	
	double sample = (double)server_time_val - ((double)client_sent_time + (double)rtt / 2.0);
	_samples.push_back(sample);
	
	if (_samples.size() > SAMPLE_WINDOW) {
		_samples.pop_front();
	}
	
	double best = _samples[0];
	for (double s : _samples) {
		best = UtilityFunctions::min(best, s);
	}
	
	if (!_initialized) {
		offset_ms = best;
		rtt_ms = (double)rtt;
		jitter_ms = 0.0;
		_initialized = true;
	} else {
		double current_jitter = Math::abs((double)rtt - rtt_ms);
		jitter_ms = UtilityFunctions::lerp(jitter_ms, current_jitter, EMA_ALPHA);
		offset_ms = UtilityFunctions::lerp(offset_ms, best, EMA_ALPHA);
		rtt_ms = UtilityFunctions::lerp(rtt_ms, (double)rtt, EMA_ALPHA);
	}
}

int QNClockSync::server_time() {
	return (int)(Time::get_singleton()->get_ticks_msec() + offset_ms);
}

bool QNClockSync::is_synced() {
	return _initialized;
}
