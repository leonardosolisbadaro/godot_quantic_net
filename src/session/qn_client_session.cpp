#include "qn_client_session.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include "core/qn_serializer.hpp"
#include "core/qn_delta_serializer.hpp"
#include <algorithm>

using namespace godot;

QNClientSession::QNClientSession() {
	_clock.instantiate();
	_input_buf.instantiate();
	_loss_tracker.instantiate();
	
	_read_buf.instantiate();
	_write_buf.instantiate();
}

QNClientSession::~QNClientSession() {
}

void QNClientSession::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init", "send_callable"), &QNClientSession::init);
	ClassDB::bind_method(D_METHOD("set_local_id", "id"), &QNClientSession::set_local_id);
	
	ClassDB::bind_method(D_METHOD("is_clock_synced"), &QNClientSession::is_clock_synced);
	ClassDB::bind_method(D_METHOD("clock_rtt"), &QNClientSession::clock_rtt);
	ClassDB::bind_method(D_METHOD("clock_offset"), &QNClientSession::clock_offset);
	ClassDB::bind_method(D_METHOD("server_time", "now"), &QNClientSession::server_time);
	
	ClassDB::bind_method(D_METHOD("submit_state", "pos", "rot", "custom_id", "dt", "now"), &QNClientSession::submit_state);
	ClassDB::bind_method(D_METHOD("record_input", "seq", "move", "rot_delta", "dt", "sent_ts"), &QNClientSession::record_input);
	ClassDB::bind_method(D_METHOD("pending_inputs"), &QNClientSession::pending_inputs);
	
	ClassDB::bind_method(D_METHOD("handle_packet", "data", "now"), &QNClientSession::handle_packet);
	ClassDB::bind_method(D_METHOD("remote_state", "owner", "now"), &QNClientSession::remote_state);
	ClassDB::bind_method(D_METHOD("loss_of", "owner"), &QNClientSession::loss_of);
	ClassDB::bind_method(D_METHOD("cleanup_entity", "owner"), &QNClientSession::cleanup_entity);
	
	ClassDB::bind_method(D_METHOD("set_local_pos", "p_pos"), &QNClientSession::set_local_pos);
	ClassDB::bind_method(D_METHOD("get_local_pos"), &QNClientSession::get_local_pos);
	ClassDB::bind_method(D_METHOD("set_local_rot", "p_rot"), &QNClientSession::set_local_rot);
	ClassDB::bind_method(D_METHOD("get_local_rot"), &QNClientSession::get_local_rot);

	ClassDB::bind_method(D_METHOD("get_registry"), &QNClientSession::get_registry);
	ClassDB::bind_method(D_METHOD("get_registry_keys"), &QNClientSession::get_registry_keys);
	
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "local_pos"), "set_local_pos", "get_local_pos");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "local_rot"), "set_local_rot", "get_local_rot");
	
	ADD_SIGNAL(MethodInfo("remote_state_received", PropertyInfo(Variant::INT, "owner"), PropertyInfo(Variant::VECTOR3, "pos"), PropertyInfo(Variant::VECTOR3, "rot"), PropertyInfo(Variant::INT, "custom_id")));
	ADD_SIGNAL(MethodInfo("snapback_received", PropertyInfo(Variant::INT, "seq"), PropertyInfo(Variant::VECTOR3, "pos"), PropertyInfo(Variant::VECTOR3, "rot"), PropertyInfo(Variant::INT, "custom_id"), PropertyInfo(Variant::ARRAY, "replay")));
	ADD_SIGNAL(MethodInfo("pong_received", PropertyInfo(Variant::FLOAT, "rtt"), PropertyInfo(Variant::FLOAT, "offset")));
}

void QNClientSession::init(Callable p_send_callable) {
	send_callable = p_send_callable;
}

void QNClientSession::set_local_id(int id) {
	_my_id = id;
}

bool QNClientSession::is_clock_synced() {
	return _clock->is_synced();
}

double QNClientSession::clock_rtt() {
	return _clock->rtt_ms;
}

double QNClientSession::clock_offset() {
	return _clock->offset_ms;
}

int QNClientSession::server_time(int now) {
	return _clock->is_synced() ? (int)(now + _clock->offset_ms) : now;
}

bool QNClientSession::submit_state(const Vector3 &pos, const Vector3 &rot, int custom_id, double dt, int now) {
	local_pos = pos;
	local_rot = rot;
	_send_accum += dt;
	
	if (_my_id <= 1 || _send_accum < SEND_INTERVAL) {
		return false;
	}
	
	_send_accum = 0.0;
	_send_seq = (_send_seq + 1) & 0xFFFF;
	_input_buf->record(_send_seq, Vector2(), 0.0, dt, now);
	
	QNClientInputState input_state;
	input_state.seq = _send_seq;
	input_state.pos = pos;
	input_state.rot = rot;
	input_state.ts = server_time(now);
	input_state.custom_id = custom_id;
	input_state.ack = _last_server_seq;
	
	_state_history.push_front(input_state);
	if (_state_history.size() > 60) {
		_state_history.pop_back();
	}
	
	_write_buf->seek(0);
	_write_buf->write_bits(1, 8); // MsgType::STATE
	_write_buf->write_bits(_send_seq, 16);
	_write_buf->write_bits(_last_server_seq, 16);
	_write_buf->write_bits(pending_inputs(), 8);
	
	int count = std::min((int)_state_history.size(), 3);
	_write_buf->write_bits(count, 8);
	
	for (int i = 0; i < count; i++) {
		const QNClientInputState &h = _state_history[i];
		_write_buf->write_bits(h.seq & 0xFFFF, 16);
		_write_buf->write_float(h.pos.x, -64.0, 64.0, 16);
		_write_buf->write_float(h.pos.y, 0.0, 10.0, 16);
		_write_buf->write_float(h.pos.z, -64.0, 64.0, 16);
		_write_buf->write_quaternion(Quaternion::from_euler(h.rot));
		_write_buf->write_bits(h.ts & 0xFFFFFFFF, 32);
		_write_buf->write_bits(h.custom_id & 0xFF, 5);
	}
	
	PackedByteArray pkt = _write_buf->get_buffer();
	
	if (send_callable.is_valid()) {
		send_callable.call(1, pkt, CH_STATE, TRANSFER_UNRELIABLE);
	}
	
	return true;
}

void QNClientSession::record_input(int seq, const Vector2 &move, double rot_delta, double dt, int sent_ts) {
	_input_buf->record(seq, move, rot_delta, dt, sent_ts);
}

int QNClientSession::pending_inputs() {
	return _input_buf->size();
}

void QNClientSession::handle_packet(const PackedByteArray &data, int now) {
	if (data.size() < 2) return;
	
	int ptype = data.decode_u8(0);
	if (ptype == QNSerializer::TYPE_SNAPBACK) {
		_handle_snapback(data.slice(1));
		return;
	}
	
	if (ptype == 4) { // TYPE_SNAPSHOT
		_handle_snapshot(data.slice(1), now);
		return;
	}
	
	if (ptype != QNSerializer::TYPE_STATE || data.size() < 5) return;
	
	int owner = data.decode_u32(1);
	Dictionary d = QNSerializer::decode_state_seq(data.slice(5));
	if (d.is_empty()) return;
	
	if (!_interp.has(owner)) {
		Ref<QNInterpBuffer> ib; ib.instantiate();
		_interp[owner] = ib;
		_active_interps.push_back(owner);
	}
	
	if (owner == _my_id) {
		int sent_ts = _input_buf->get_sent_ts(d["seq"]);
		_clock->on_pong(sent_ts, d["ts"], now);
		_input_buf->drain_after(d["seq"]);
		
		double current_jitter = _clock->jitter_ms;
		for (int i = 0; i < _active_interps.size(); i++) {
			int owner_id = _active_interps[i];
			if (_interp.has(owner_id)) {
				Ref<QNInterpBuffer> ib = _interp[owner_id];
				if (ib.is_valid()) ib->update_jitter(current_jitter);
			}
		}
		
		emit_signal("pong_received", _clock->rtt_ms, _clock->offset_ms);
		return;
	}
	
	Ref<QNInterpBuffer> owner_interp = _interp[owner];
	owner_interp->push(d["ts"], d["pos"], d["rot"]);
	emit_signal("remote_state_received", owner, d["pos"], d["rot"], d.get("custom_id", 0));
}

Dictionary QNClientSession::remote_state(int owner, int now) {
	if (!_interp.has(owner)) return Dictionary();
	Ref<QNInterpBuffer> owner_interp = _interp[owner];
	return owner_interp->sample(server_time(now));
}

double QNClientSession::loss_of(int owner) {
	return _loss_tracker->loss_pct();
}

void QNClientSession::cleanup_entity(int owner) {
	if (_interp.has(owner)) {
		_interp.erase(owner);
		
		auto it = std::find(_active_interps.begin(), _active_interps.end(), owner);
		if (it != _active_interps.end()) {
			_active_interps.erase(it);
		}
	}
}

void QNClientSession::_handle_snapback(const PackedByteArray &body) {
	Dictionary d = QNSerializer::decode_state_seq(body);
	if (d.is_empty()) return;
	
	local_pos = d["pos"];
	local_rot = d["rot"];
	Array replay = _input_buf->drain_after(d["seq"]);
	emit_signal("snapback_received", d["seq"], d["pos"], d["rot"], d.get("custom_id", 0), replay);
}

void QNClientSession::_handle_snapshot(const PackedByteArray &body, int now) {
	_read_buf->set_buffer(body);
	
	int server_seq = _read_buf->read_bits(16);
	_loss_tracker->on_packet(server_seq);
	
	int diff = server_seq - _last_server_seq;
	if (diff < -32768) diff += 65536;
	else if (diff > 32768) diff -= 65536;
	
	if (_last_server_seq != 0 && diff <= 0) {
		return;
	}
	
	int client_seq_ack = _read_buf->read_bits(16);
	int server_now = _read_buf->read_bits(32);
	int num_entities = _read_buf->read_bits(8);
	
	int base_server_seq = -1;
	for (int i = 0; i < _state_history.size(); i++) {
		if (_state_history[i].seq == client_seq_ack) {
			base_server_seq = _state_history[i].ack;
			break;
		}
	}
	if (base_server_seq == -1) {
		base_server_seq = _last_server_seq;
	}
	
	std::unordered_map<int, QNEntityState> parsed_states;
	if (_world_history.size() > 0) {
		parsed_states = _world_history[0].states;
	}
	
	for (int i = 0; i < num_entities; i++) {
		if ((_read_buf->get_position() + 32) / 8 > body.size()) break;
		
		int entity_id = _read_buf->read_bits(32);
		
		const QNEntityState* base_state = nullptr;
		if (server_seq == _last_server_seq + 1 && base_server_seq == _last_server_seq) {
			// Fast path
			if (_world_history.size() > 0) {
				const auto &old_states = _world_history[0].states;
				if (old_states.find(entity_id) != old_states.end()) {
					base_state = &old_states.at(entity_id);
				}
			}
		} else {
			for (int j = 0; j < _world_history.size(); j++) {
				if (_world_history[j].seq == base_server_seq) {
					const auto &old_states = _world_history[j].states;
					if (old_states.find(entity_id) != old_states.end()) {
						base_state = &old_states.at(entity_id);
					}
					break;
				}
			}
		}
		
		QNEntityState st = QNDeltaSerializer::decode_state(_read_buf, base_state);
		parsed_states[entity_id] = st;
		
		int owner = entity_id;
		
		if (!_interp.has(owner)) {
			Ref<QNInterpBuffer> ib; ib.instantiate();
			_interp[owner] = ib;
			_active_interps.push_back(owner);
		}
		
		if (owner == _my_id) {
			int sent_ts = _input_buf->get_sent_ts(st.seq);
			_clock->on_pong(sent_ts, server_now, now);
			_input_buf->drain_after(st.seq);
			
			double current_jitter = _clock->jitter_ms;
			for (int j = 0; j < _active_interps.size(); j++) {
				int owner_id = _active_interps[j];
				if (_interp.has(owner_id)) {
					Ref<QNInterpBuffer> ib = _interp[owner_id];
					if (ib.is_valid()) ib->update_jitter(current_jitter);
				}
			}
			
			emit_signal("pong_received", _clock->rtt_ms, _clock->offset_ms);
		} else {
			Ref<QNInterpBuffer> owner_interp = _interp[owner];
			owner_interp->push(st.ts, st.pos, st.rot);
			emit_signal("remote_state_received", owner, st.pos, st.rot, st.custom_id);
		}
	}
	
	QNWorldSnapshot world_snapshot;
	world_snapshot.seq = server_seq;
	world_snapshot.states = parsed_states;
	
	_world_history.push_front(world_snapshot);
	if (_world_history.size() > 60) {
		_world_history.pop_back();
	}
	
	_last_server_seq = server_seq;
}

Dictionary QNClientSession::get_registry() const { return _interp; }
Array QNClientSession::get_registry_keys() const { return _interp.keys(); }
