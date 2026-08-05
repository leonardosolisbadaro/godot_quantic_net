#include "qn_input_buffer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

QNInputBuffer::QNInputBuffer() {
}

QNInputBuffer::~QNInputBuffer() {
}

void QNInputBuffer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("record", "seq", "move", "rot_delta", "dt", "sent_ts"), &QNInputBuffer::record, DEFVAL(0));
	ClassDB::bind_method(D_METHOD("get_sent_ts", "seq"), &QNInputBuffer::get_sent_ts);
	ClassDB::bind_method(D_METHOD("drain_after", "confirmed_seq"), &QNInputBuffer::drain_after);
	ClassDB::bind_method(D_METHOD("size"), &QNInputBuffer::size);
}

void QNInputBuffer::record(int seq, const Vector2 &move, double rot_delta, double dt, int sent_ts) {
	Dictionary d;
	d["seq"] = seq;
	d["move"] = move;
	d["rot_delta"] = rot_delta;
	d["dt"] = dt;
	d["sent_ts"] = sent_ts;
	
	pending.push_back(d);
	
	if (pending.size() > MAX_PENDING) {
		pending.pop_front();
	}
}

int QNInputBuffer::get_sent_ts(int seq) {
	for (int i = 0; i < pending.size(); i++) {
		Dictionary e = pending[i];
		if ((int)e["seq"] == seq) {
			return e.get("sent_ts", 0);
		}
	}
	return 0;
}

Array QNInputBuffer::drain_after(int confirmed_seq) {
	Array replay;
	Array keep;
	
	for (int i = 0; i < pending.size(); i++) {
		Dictionary e = pending[i];
		int e_seq = e["seq"];
		
		int diff = (confirmed_seq - e_seq) & 0xFFFF;
		if (diff < 32768) {
			continue; // Descarta os confirmados ou antigos
		}
			
		replay.push_back(e);
		keep.push_back(e);
	}
		
	pending = keep;
	return replay;
}

int QNInputBuffer::size() const {
	return pending.size();
}
