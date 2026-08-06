#include "qn_host_session.hpp"
#include "../core/qn_clock_sync.hpp"
#include "../core/qn_input_buffer.hpp"
#include "qn_loss_tracker.hpp"
#include "../core/qn_priority_accumulator.hpp"
#include "../core/qn_serializer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include "core/qn_serializer.hpp"
#include "core/qn_delta_serializer.hpp"
#include "core/qn_bit_buffer.hpp"

using namespace godot;

QNHostSession::QNHostSession() {
	_server_seq = 0;
	_accumulator.instantiate();
	_grid.instantiate();
	_rewind_buffer.instantiate();
	_stats["entities_total"] = 0;
	_stats["entities_sent_this_tick"] = 0;
	_stats["bytes_saved_by_hybrid_ticking"] = 0;
	_stats["ticks_since_log"] = 0;
}

QNHostSession::~QNHostSession() {
}

void QNHostSession::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_validator", "v"), &QNHostSession::set_validator);
	ClassDB::bind_method(D_METHOD("get_validator"), &QNHostSession::get_validator);
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "validator"), "set_validator", "get_validator");
	
	ClassDB::bind_method(D_METHOD("_on_validator_peer_rejected", "id", "reason", "strikes"), &QNHostSession::_on_validator_peer_rejected);
	ClassDB::bind_method(D_METHOD("register_entity", "entity_id", "is_peer", "has_initial_state", "profile"), &QNHostSession::register_entity, DEFVAL(nullptr));
	ClassDB::bind_method(D_METHOD("on_peer_authenticated", "peer_id", "profile"), &QNHostSession::on_peer_authenticated, DEFVAL(nullptr));
	ClassDB::bind_method(D_METHOD("unregister_entity", "entity_id"), &QNHostSession::unregister_entity);
	ClassDB::bind_method(D_METHOD("change_entity_profile", "entity_id", "new_profile"), &QNHostSession::change_entity_profile);
	ClassDB::bind_method(D_METHOD("update_entity_state", "entity_id", "pos", "rot", "custom_id", "ts"), &QNHostSession::update_entity_state);
	ClassDB::bind_method(D_METHOD("on_peer_disconnected", "peer_id"), &QNHostSession::on_peer_disconnected);
	
	ClassDB::bind_method(D_METHOD("query_raycast", "origin", "direction", "max_dist", "timestamp"), &QNHostSession::query_raycast, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("query_box", "center", "extents", "timestamp"), &QNHostSession::query_box, DEFVAL(-1));
	ClassDB::bind_method(D_METHOD("query_sphere", "center", "radius", "timestamp"), &QNHostSession::query_sphere, DEFVAL(-1));

	ClassDB::bind_method(D_METHOD("on_client_snapshot", "peer_id", "data", "now"), &QNHostSession::on_client_snapshot);
	ClassDB::bind_method(D_METHOD("tick_broadcast", "now"), &QNHostSession::tick_broadcast);
	ClassDB::bind_method(D_METHOD("get_registry"), &QNHostSession::get_registry);
	
	ADD_SIGNAL(MethodInfo("snapback_requested", PropertyInfo(Variant::INT, "peer_id"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "pkt")));
	ADD_SIGNAL(MethodInfo("peer_rejected", PropertyInfo(Variant::INT, "peer_id"), PropertyInfo(Variant::STRING, "reason"), PropertyInfo(Variant::INT, "strikes")));
	ADD_SIGNAL(MethodInfo("broadcast_ready", PropertyInfo(Variant::ARRAY, "states")));
	ADD_SIGNAL(MethodInfo("packet_ready", PropertyInfo(Variant::INT, "peer_id"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "data")));
}

void QNHostSession::set_validator(const Ref<RefCounted> &v) {
	if (validator.is_valid() && validator->has_signal("peer_rejected")) {
		validator->disconnect("peer_rejected", callable_mp(this, &QNHostSession::_on_validator_peer_rejected));
	}
	validator = v;
	if (validator.is_valid() && validator->has_signal("peer_rejected")) {
		validator->connect("peer_rejected", callable_mp(this, &QNHostSession::_on_validator_peer_rejected));
	}
}

Ref<RefCounted> QNHostSession::get_validator() const {
	return validator;
}

void QNHostSession::_on_validator_peer_rejected(int id, String reason, int strikes) {
	emit_signal("peer_rejected", id, reason, strikes);
}

void QNHostSession::register_entity(int entity_id, bool is_peer, bool has_initial_state, Ref<QNEntityProfile> profile) {
	if (profile.is_null()) {
		profile = QNEntityProfile::preset_standard();
	}
	
	Dictionary st;
	st["id"] = entity_id;
	st["pos"] = Vector3();
	st["rot"] = Vector3();
	st["seq"] = 0;
	st["ts"] = 0;
	st["ack"] = 0;
	st["profile"] = profile;
	st["has_state"] = has_initial_state;
	st["last_broadcast_ts"] = 0;
	st["is_peer"] = is_peer;
	
	_registry[entity_id] = st;
}

void QNHostSession::on_peer_authenticated(int peer_id, Ref<QNEntityProfile> profile) {
	register_entity(peer_id, true, false, profile);
}

void QNHostSession::unregister_entity(int entity_id) {
	if (_registry.has(entity_id)) {
		_registry.erase(entity_id);
	}
	_accumulator->cleanup_entity(entity_id);
	_grid->remove_entity(entity_id);
}

void QNHostSession::change_entity_profile(int entity_id, Ref<QNEntityProfile> new_profile) {
	if (_registry.has(entity_id)) {
		Dictionary st = _registry[entity_id];
		st["profile"] = new_profile;
		st["last_broadcast_ts"] = 0;
		_registry[entity_id] = st;
	}
}

void QNHostSession::update_entity_state(int entity_id, const Vector3 &pos, const Vector3 &rot, int custom_id, int ts) {
	if (_registry.has(entity_id)) {
		Dictionary st = _registry[entity_id];
		st["pos"] = pos;
		st["rot"] = rot;
		st["custom_id"] = custom_id;
		st["ts"] = ts;
		_registry[entity_id] = st;
		_grid->update_entity(entity_id, pos);
	}
}

void QNHostSession::on_peer_disconnected(int peer_id) {
	if (_registry.has(peer_id)) {
		_registry.erase(peer_id);
	}
	_accumulator->_cleanup_peer(peer_id);
	_grid->remove_entity(peer_id);
	if (validator.is_valid() && validator->has_method("peer_left")) {
		validator->call("peer_left", peer_id);
	}
}

void QNHostSession::on_client_snapshot(int peer_id, const PackedByteArray &data, int now) {
	if (!_registry.has(peer_id) || validator.is_null() || data.size() < 2) {
		return;
	}
	
	int client_ack = data.decode_u16(0);
	Dictionary peer_st = _registry[peer_id];
	peer_st["ack"] = client_ack;
	_registry[peer_id] = peer_st;
	
	Array history = QNSerializer::decode_state_history(data.slice(2));
	if (history.is_empty()) return;
	
	for (int i = history.size() - 1; i >= 0; i--) {
		Dictionary state = history[i];
		Vector3 pos = state.get("pos", Vector3());
		Vector3 rot = state.get("rot", Vector3());
		int seq = state.get("seq", 0);
		int client_ts = state.get("ts", 0);
		int custom_id = state.get("custom_id", 0);
		
		int last_seq = peer_st["seq"];
		int diff = seq - last_seq;
		if (diff < -32768) diff += 65536;
		else if (diff > 32768) diff -= 65536;
		
		if (last_seq != 0 && diff <= 0) {
			continue;
		}
		
		Dictionary result = validator->call("validate", peer_id, pos, rot, client_ts);
		String action = result.get("action", "");
		
		if (action == "accept") {
			peer_st["pos"] = result["pos"];
			peer_st["rot"] = result["rot"];
			peer_st["seq"] = seq;
			peer_st["ts"] = now;
			peer_st["custom_id"] = custom_id;
			peer_st["has_state"] = true;
			_registry[peer_id] = peer_st;
			_grid->update_entity(peer_id, peer_st["pos"]);
		} else if (action == "clamp") {
			peer_st["pos"] = result["pos"];
			peer_st["rot"] = result["rot"];
			peer_st["seq"] = seq;
			peer_st["ts"] = now;
			peer_st["custom_id"] = custom_id;
			peer_st["has_state"] = true;
			_registry[peer_id] = peer_st;
			_grid->update_entity(peer_id, peer_st["pos"]);
			
			PackedByteArray snap = QNSerializer::encode_snapback(seq, result["pos"], result["rot"], client_ts, SNAPBACK_REASON_CLAMP);
			emit_signal("snapback_requested", peer_id, snap);
			break;
		} else if (action == "reject") {
			PackedByteArray snap = QNSerializer::encode_snapback(seq, result["pos"], result["rot"], client_ts, SNAPBACK_REASON_REJECT);
			emit_signal("snapback_requested", peer_id, snap);
			break;
		}
	}
}

void QNHostSession::tick_broadcast(int now) {
	_server_seq = (_server_seq + 1) & 0xFFFF;
	Dictionary world_snapshot;
	
	Array keys = _registry.keys();
	for (int i = 0; i < keys.size(); i++) {
		int id = keys[i];
		Dictionary st = _registry[id];
		if ((bool)st["has_state"]) {
			Dictionary ws;
			ws["id"] = id;
			ws["seq"] = st["seq"];
			ws["pos"] = st["pos"];
			ws["rot"] = st["rot"];
			ws["custom_id"] = st.get("custom_id", 0);
			ws["ts"] = now;
			
			Ref<QNEntityProfile> profile = st.get("profile", Variant());
			if (profile.is_valid()) {
				ws["hitbox_type"] = profile->get_hitbox_type();
				ws["hitbox_extents"] = profile->get_hitbox_extents();
			} else {
				ws["hitbox_type"] = 0; // Sphere
				ws["hitbox_extents"] = Vector3(1.0, 1.0, 1.0);
			}
			
			world_snapshot[id] = ws;
		}
	}
	
	Dictionary hist_entry;
	hist_entry["seq"] = _server_seq;
	hist_entry["states"] = world_snapshot;
	_world_history.push_front(hist_entry);
	if (_world_history.size() > 60) {
		_world_history.pop_back();
	}
	
	Dictionary current_states;
	for (int i = 0; i < keys.size(); i++) {
		int id = keys[i];
		Dictionary st = _registry[id];
		if (!(bool)st["has_state"]) continue;
		
		Ref<QNEntityProfile> profile = st.get("profile", Variant());
		double tick_rate_hz = profile.is_valid() ? profile->get_tick_rate_hz() : 20.0;
		bool should_broadcast = false;
		
		int last_broadcast_ts = st["last_broadcast_ts"];
		if (tick_rate_hz > 0.0) {
			int interval_ms = (int)(1000.0 / tick_rate_hz);
			if (now - last_broadcast_ts >= interval_ms) {
				should_broadcast = true;
			}
		} else {
			if (last_broadcast_ts == 0) {
				should_broadcast = true;
			}
		}
		
		if (should_broadcast) {
			current_states[id] = world_snapshot[id];
		}
	}
	
	for (int i = 0; i < keys.size(); i++) {
		int id = keys[i];
		Dictionary st = _registry[id];
		if (!(bool)st.get("is_peer", false)) continue;
		
		int ack = st.get("ack", 0);
		Dictionary base_states;
		for (const Dictionary &hist : _world_history) {
			if ((int)hist["seq"] == ack) {
				base_states = hist["states"];
				break;
			}
		}
		
		Dictionary peer_current_states;
		Dictionary profiles;
		
		// Use spatial grid to cull entities beyond the peer's dynamic culling radius (AoI)
		Ref<QNEntityProfile> my_profile = st.get("profile", Variant());
		double cull_rad = my_profile.is_valid() ? my_profile->get_spatial_culling_radius() : 250.0;
		PackedInt32Array nearby = _grid->get_entities_in_radius(st["pos"], cull_rad);
		for (int j = 0; j < nearby.size(); j++) {
			int cid = nearby[j];
			if (current_states.has(cid)) {
				peer_current_states[cid] = current_states[cid];
				profiles[cid] = ((Dictionary)_registry[cid]).get("profile", Variant());
			}
		}
		
		// Ensure peer itself is included
		if (current_states.has(id)) {
			peer_current_states[id] = current_states[id];
			profiles[id] = ((Dictionary)_registry[id]).get("profile", Variant());
		}
		
		Dictionary selected_states = _accumulator->select_entities(id, peer_current_states, profiles, st["pos"], 1200, 19);
		
		Array sel_keys = selected_states.keys();
		for (int j = 0; j < sel_keys.size(); j++) {
			int selected_id = sel_keys[j];
			if (_registry.has(selected_id)) {
				Dictionary sel_st = _registry[selected_id];
				sel_st["last_broadcast_ts"] = now;
				_registry[selected_id] = sel_st;
			}
		}
		
		_stats["entities_total"] = _registry.size();
		_stats["entities_sent_this_tick"] = selected_states.size();
		int omitted_entities = _registry.size() - selected_states.size();
		_stats["bytes_saved_by_hybrid_ticking"] = (int)_stats["bytes_saved_by_hybrid_ticking"] + (omitted_entities * 19);
		_stats["ticks_since_log"] = (int)_stats["ticks_since_log"] + 1;
		
		if ((int)_stats["ticks_since_log"] >= 600) {
			UtilityFunctions::print(String("[QNHostSession] Bandwidth Stats (Peer ") + String::num_int64(id) + "): " + String::num_int64(selected_states.size()) + " entities sent out of " + String::num_int64(_registry.size()) + ". Savings so far: " + String::num_int64(_stats["bytes_saved_by_hybrid_ticking"]) + " bytes");
			_stats["ticks_since_log"] = 0;
		}
		
		Ref<QNBitBuffer> buf; buf.instantiate();
		buf->write_bits(_server_seq, 16);
		buf->write_bits(ack, 16);
		buf->write_bits(now & 0xFFFFFFFF, 32);
		buf->write_bits(selected_states.size(), 8);
		
		for (int j = 0; j < sel_keys.size(); j++) {
			int entity_id = sel_keys[j];
			buf->write_bits(entity_id, 32);
			Dictionary base = base_states.get(entity_id, Dictionary());
			
			if (!base.is_empty()) {
				Dictionary peer_base = base_states.get(id, Dictionary());
				if (!peer_base.is_empty()) {
					double cull_radius = 50.0;
					if (profiles.has(entity_id)) {
						Ref<QNEntityProfile> p = profiles[entity_id];
						if (p.is_valid()) cull_radius = p->get_spatial_culling_radius();
					}
					
					Vector3 pb_pos = peer_base["pos"];
					Vector3 b_pos = base["pos"];
					double old_dist = pb_pos.distance_to(b_pos);
					if (old_dist > cull_radius) {
						base = Dictionary();
					}
				}
			}
			
			QNDeltaSerializer::encode_state(buf, base, selected_states[entity_id]);
		}
		
		emit_signal("packet_ready", id, buf->get_buffer());
	}
	
	_rewind_buffer->push_state(now, current_states);
}

Dictionary QNHostSession::query_raycast(const Vector3 &origin, const Vector3 &direction, double max_dist, int timestamp) const {
	return _rewind_buffer->query_raycast(origin, direction, max_dist, timestamp);
}

Array QNHostSession::query_box(const Vector3 &center, const Vector3 &extents, int timestamp) const {
	return _rewind_buffer->query_box(center, extents, timestamp);
}

Array QNHostSession::query_sphere(const Vector3 &center, double radius, int timestamp) const {
	return _rewind_buffer->query_sphere(center, radius, timestamp);
}

Dictionary QNHostSession::get_registry() {
	return _registry;
}
