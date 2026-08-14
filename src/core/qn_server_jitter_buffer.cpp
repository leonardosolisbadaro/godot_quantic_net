#include "qn_server_jitter_buffer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

QNServerJitterBuffer::QNServerJitterBuffer() {
	tick_rate_ms = 50;
	target_delay_ms = 0;
	initialized = false;
	base_seq = 0;
	base_time = 0;
}

QNServerJitterBuffer::~QNServerJitterBuffer() {
}

void QNServerJitterBuffer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("setup", "tick_rate_ms"), &QNServerJitterBuffer::setup);
	ClassDB::bind_method(D_METHOD("set_target_delay", "ms"), &QNServerJitterBuffer::set_target_delay);
	ClassDB::bind_method(D_METHOD("push", "seq", "input_mask", "look_dir", "server_receive_time"), &QNServerJitterBuffer::push);
	ClassDB::bind_method(D_METHOD("pop", "current_server_time"), &QNServerJitterBuffer::pop);
	ClassDB::bind_method(D_METHOD("pop_ready_inputs", "current_server_time"), &QNServerJitterBuffer::pop_ready_inputs);
}

void QNServerJitterBuffer::setup(int p_tick_rate_ms) {
	tick_rate_ms = p_tick_rate_ms;
}

void QNServerJitterBuffer::set_target_delay(int ms) {
	target_delay_ms = ms;
}

void QNServerJitterBuffer::push(int seq, int input_mask, const Vector2 &look_dir, int server_receive_time) {
	Dictionary d;
	d["seq"] = seq;
	d["input_mask"] = input_mask;
	d["look_dir"] = look_dir;
	d["receive_time"] = server_receive_time;

	if (!initialized) {
		base_seq = seq;
		base_time = server_receive_time;
		initialized = true;
	} else {
		// Reset if we drifted too far or stalled (handle uint16 wrap-around)
		int diff = (seq - base_seq) & 0xFFFF;
		if (diff > 32768) diff -= 65536;
		
		if (diff > 100) {
			// Big forward gap / reconnect / stall, re-sync base
			base_seq = seq;
			base_time = server_receive_time;
		} else if (diff < -100) {
			// Extremely stale packet from past, discard to prevent corrupting base_time
			return;
		}
	}
	
	// Sort insertion by sequence
	bool inserted = false;
	for (int i = 0; i < pending.size(); i++) {
		Dictionary e = pending[i];
		int e_seq = e["seq"];
		int diff = (seq - e_seq) & 0xFFFF;
		if (diff > 32768) diff -= 65536;
		
		if (diff < 0) { // seq is older than e_seq
			pending.insert(pending.begin() + i, d);
			inserted = true;
			break;
		} else if (diff == 0) {
			// duplicate packet, ignore
			return;
		}
	}
	
	if (!inserted) {
		pending.push_back(d);
	}
	
	if (pending.size() > MAX_PENDING) {
		pending.pop_front(); // drop oldest if full
	}
}

Dictionary QNServerJitterBuffer::pop(int current_server_time) {
	if (pending.size() == 0) {
		return Dictionary();
	}
	
	Dictionary oldest = pending[0];
	int seq = oldest["seq"];
	
	int diff = (seq - base_seq) & 0xFFFF;
	if (diff > 32768) diff -= 65536;
	
	int playout_time = base_time + target_delay_ms + (diff * tick_rate_ms);
	
	if (current_server_time >= playout_time) {
		pending.pop_front();
		return oldest;
	}
	
	return Dictionary();
}

Array QNServerJitterBuffer::pop_ready_inputs(int current_server_time) {
	Array ready_list;
	while (!pending.empty()) {
		Dictionary oldest = pending[0];
		int seq = oldest["seq"];
		
		int diff = (seq - base_seq) & 0xFFFF;
		if (diff > 32768) diff -= 65536;
		
		int playout_time = base_time + target_delay_ms + (diff * tick_rate_ms);
		if (current_server_time >= playout_time) {
			pending.pop_front();
			ready_list.push_back(oldest);
		} else {
			break;
		}
	}
	return ready_list;
}
