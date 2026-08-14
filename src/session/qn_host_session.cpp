#include "qn_host_session.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include "core/qn_serializer.hpp"
#include "core/qn_delta_serializer.hpp"

using namespace godot;

QNHostSession::QNHostSession() {
	_server_seq = 0;
	
	_accumulator.instantiate();
	_grid.instantiate();
	_rewind_buffer.instantiate();
	
	_read_buf.instantiate();
	_write_buf.instantiate();
	
	_stats["entities_total"] = 0;
	_stats["entities_sent_this_tick"] = 0;
	_stats["bytes_saved_by_hybrid_ticking"] = 0;
	_stats["ticks_since_log"] = 0;
}

QNHostSession::~QNHostSession() {
}

void QNHostSession::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_validator", "validator"), &QNHostSession::set_validator);
	ClassDB::bind_method(D_METHOD("get_validator"), &QNHostSession::get_validator);
	ClassDB::bind_method(D_METHOD("set_dormancy_threshold", "ticks"), &QNHostSession::set_dormancy_threshold);
	ClassDB::bind_method(D_METHOD("set_default_cull_radius", "r"), &QNHostSession::set_default_cull_radius);
	ClassDB::bind_method(D_METHOD("get_default_cull_radius"), &QNHostSession::get_default_cull_radius);
	ClassDB::bind_method(D_METHOD("set_default_entity_aura", "r"), &QNHostSession::set_default_entity_aura);
	ClassDB::bind_method(D_METHOD("get_default_entity_aura"), &QNHostSession::get_default_entity_aura);
	ClassDB::bind_method(D_METHOD("register_entity", "entity_id", "is_peer", "has_initial_state", "profile"), &QNHostSession::register_entity, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("on_peer_authenticated", "peer_id", "profile"), &QNHostSession::on_peer_authenticated, DEFVAL(Variant()));
	ClassDB::bind_method(D_METHOD("unregister_entity", "entity_id"), &QNHostSession::unregister_entity);
	ClassDB::bind_method(D_METHOD("change_entity_profile", "entity_id", "new_profile"), &QNHostSession::change_entity_profile);
	ClassDB::bind_method(D_METHOD("update_entity_state", "entity_id", "pos", "rot", "custom_id", "ts"), &QNHostSession::update_entity_state);
	ClassDB::bind_method(D_METHOD("on_peer_disconnected", "peer_id"), &QNHostSession::on_peer_disconnected);
	ClassDB::bind_method(D_METHOD("on_client_snapshot", "peer_id", "data", "now"), &QNHostSession::on_client_snapshot);
	ClassDB::bind_method(D_METHOD("tick_broadcast", "now"), &QNHostSession::tick_broadcast);
	
	ClassDB::bind_method(D_METHOD("add_region", "region_id", "center", "extents"), &QNHostSession::add_region);
	ClassDB::bind_method(D_METHOD("remove_region", "region_id"), &QNHostSession::remove_region);
	ClassDB::bind_method(D_METHOD("clear_regions"), &QNHostSession::clear_regions);
	
	ClassDB::bind_method(D_METHOD("query_raycast", "origin", "direction", "max_dist", "timestamp"), &QNHostSession::query_raycast);
	ClassDB::bind_method(D_METHOD("query_box", "center", "extents", "timestamp"), &QNHostSession::query_box);
	ClassDB::bind_method(D_METHOD("query_sphere", "center", "radius", "timestamp"), &QNHostSession::query_sphere);

	ClassDB::bind_method(D_METHOD("get_registry"), &QNHostSession::get_registry);
	ClassDB::bind_method(D_METHOD("get_registry_keys"), &QNHostSession::get_registry_keys);
	ClassDB::bind_method(D_METHOD("get_entity_position", "entity_id"), &QNHostSession::get_entity_position);
	ClassDB::bind_method(D_METHOD("get_grid"), &QNHostSession::get_grid);
	
	ClassDB::bind_method(D_METHOD("set_sync_adjacent_grids", "sync"), &QNHostSession::set_sync_adjacent_grids);
	ClassDB::bind_method(D_METHOD("get_sync_adjacent_grids"), &QNHostSession::get_sync_adjacent_grids);
	ClassDB::bind_method(D_METHOD("_on_validator_peer_rejected", "id", "reason", "strikes"), &QNHostSession::_on_validator_peer_rejected);

	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "validator"), "set_validator", "get_validator");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "sync_adjacent_grids"), "set_sync_adjacent_grids", "get_sync_adjacent_grids");

		ADD_SIGNAL(MethodInfo("snapback_requested", PropertyInfo(Variant::INT, "peer_id"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "pkt")));
	ADD_SIGNAL(MethodInfo("packet_ready", PropertyInfo(Variant::INT, "peer_id"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "data")));
	ADD_SIGNAL(MethodInfo("peer_rejected", PropertyInfo(Variant::INT, "peer_id"), PropertyInfo(Variant::STRING, "reason"), PropertyInfo(Variant::INT, "strikes")));
}

void QNHostSession::set_dormancy_threshold(int ticks) {
	_dormancy_threshold_ticks = ticks;
}

void QNHostSession::set_validator(const Ref<RefCounted> &v) {
	if (validator.is_valid() && validator->has_signal("peer_rejected")) {
		validator->disconnect("peer_rejected", Callable(this, "_on_validator_peer_rejected"));
	}
	validator = v;
	if (validator.is_valid() && validator->has_signal("peer_rejected")) {
		validator->connect("peer_rejected", Callable(this, "_on_validator_peer_rejected"));
	}
}

Ref<RefCounted> QNHostSession::get_validator() const {
	return validator;
}

void QNHostSession::_on_validator_peer_rejected(int id, String reason, int strikes) {
	emit_signal("peer_rejected", id, reason, strikes);
}

void QNHostSession::add_region(int region_id, const Vector3 &center, const Vector3 &extents) {
	RegionData rd;
	rd.aabb = AABB(center - extents, extents * 2.0);
	_regions[region_id] = rd;
}

void QNHostSession::remove_region(int region_id) {
	_regions.erase(region_id);
}

void QNHostSession::clear_regions() {
	_regions.clear();
}

void QNHostSession::register_entity(int entity_id, bool is_peer, bool has_initial_state, Ref<QNEntityProfile> profile) {
	if (_registry.find(entity_id) == _registry.end()) {
		_active_entities.push_back(entity_id);
		_dormancy_ticks[entity_id] = 0;
	}
	QNEntityState st;
	st.is_peer = is_peer;
	st.has_state = has_initial_state;
	st.seq = _server_seq;
	st.client_seq = 0;
	st.ack = 0;
	st.last_broadcast_ts = 0;
	_registry[entity_id] = st;
	
	if (profile.is_valid()) {
		_profiles[entity_id] = profile;
	} else {
		Ref<QNEntityProfile> def_profile;
		def_profile.instantiate();
		_profiles[entity_id] = def_profile;
	}
}

void QNHostSession::on_peer_authenticated(int peer_id, Ref<QNEntityProfile> profile) {
	register_entity(peer_id, true, false, profile);
}

void QNHostSession::unregister_entity(int entity_id) {
	_registry.erase(entity_id);
	_profiles.erase(entity_id);
	_dormancy_ticks.erase(entity_id);
	_peer_known_entities.erase(entity_id);
	for (auto &pair : _peer_known_entities) {
		pair.second.erase(entity_id);
	}
	
	auto it = std::find(_active_entities.begin(), _active_entities.end(), entity_id);
	if (it != _active_entities.end()) {
		_active_entities.erase(it);
	}
}

void QNHostSession::change_entity_profile(int entity_id, Ref<QNEntityProfile> new_profile) {
	if (_registry.find(entity_id) != _registry.end()) {
		if (new_profile.is_valid()) {
			_profiles[entity_id] = new_profile;
		} else {
			_profiles.erase(entity_id);
		}
	}
}

void QNHostSession::update_entity_state(int entity_id, const Vector3 &pos, const Vector3 &rot, int custom_id, int ts) {
	if (_registry.find(entity_id) != _registry.end()) {
		QNEntityState &st = _registry[entity_id];
		st.has_state = true;
		st.pos = pos;
		st.rot = rot;
		st.ts = ts;
		st.custom_id = custom_id;
		st.seq = _server_seq;

		_grid->update_entity(entity_id, pos);
	}
}

void QNHostSession::on_peer_disconnected(int peer_id) {
	unregister_entity(peer_id);
}

void QNHostSession::on_client_snapshot(int peer_id, const PackedByteArray &data, int now) {
	if (_registry.find(peer_id) == _registry.end() || validator.is_null() || data.size() < 3) return;

	_read_buf->set_buffer(data);

	int client_seq = _read_buf->read_bits(16);
	int ack = _read_buf->read_bits(16);
	int pending = _read_buf->read_bits(8);
	
	QNEntityState &st = _registry[peer_id];
	st.client_seq = client_seq;
	st.ack = ack;
	
	int count = _read_buf->read_bits(8);
	if (count == 0) return;
	
	Vector3 last_pos;
	Vector3 last_rot;
	int last_pkt_seq = 0;
	int last_ts = 0;
	int last_custom_id = 0;
	
	for (int i = 0; i < count; i++) {
		if ((_read_buf->get_position() + 133) / 8 > data.size()) break;
		
		last_pkt_seq = (int)_read_buf->read_bits(16);
		double x = _read_buf->read_float(-512.0, 512.0, 16);
		double y = _read_buf->read_float(-512.0, 512.0, 16);
		double z = _read_buf->read_float(-512.0, 512.0, 16);
		last_pos = Vector3(x, y, z);
		last_rot = _read_buf->read_quaternion().get_euler();
		last_ts = (int)_read_buf->read_bits(32);
		last_custom_id = (int)_read_buf->read_bits(8);
	}
	
	int peer_last_seq = st.seq;
	int diff = last_pkt_seq - peer_last_seq;
	if (diff < -32768) diff += 65536;
	else if (diff > 32768) diff -= 65536;
	
	if (peer_last_seq != 0 && diff <= 0) {
		return; // Older packet
	}
	
	Dictionary result = validator->call("validate", peer_id, last_pos, last_rot, last_ts);
	String action = result.get("action", "");
	
	if (action == "accept") {
		st.pos = result["pos"];
		st.rot = result["rot"];
		st.seq = last_pkt_seq;
		st.ts = now;
		st.custom_id = last_custom_id;
		st.has_state = true;
		_grid->update_entity(peer_id, st.pos);
	} else if (action == "clamp") {
		st.pos = result["pos"];
		st.rot = result["rot"];
		st.seq = last_pkt_seq;
		st.ts = now;
		st.custom_id = last_custom_id;
		st.has_state = true;
		_grid->update_entity(peer_id, st.pos);
		
		PackedByteArray snap = QNSerializer::encode_snapback(last_pkt_seq, result["pos"], result["rot"], last_ts, SNAPBACK_REASON_CLAMP);
		emit_signal("snapback_requested", peer_id, snap);
	} else if (action == "reject") {
		PackedByteArray snap = QNSerializer::encode_snapback(last_pkt_seq, result["pos"], result["rot"], last_ts, SNAPBACK_REASON_REJECT);
		emit_signal("snapback_requested", peer_id, snap);
	}
}

void QNHostSession::tick_broadcast(int now) {
	_server_seq++;
	_grid->clear();
	
	for (int i = 0; i < _active_entities.size(); i++) {
		int id = _active_entities[i];
		QNEntityState &st = _registry[id];
		if (!st.has_state) continue;
		_grid->insert_entity(id, st.pos);
	}
	
	QNWorldSnapshot world_snapshot;
	world_snapshot.seq = _server_seq;
	
	std::vector<int> fell_asleep_this_tick;
	std::vector<int> sleeping_entities;
	
	for (int i = 0; i < _active_entities.size(); i++) {
		int id = _active_entities[i];
		QNEntityState &st = _registry[id];
		if (!st.has_state) continue;
		
		if (_world_history.size() > 0) {
			const QNWorldSnapshot &prev = _world_history.front();
			if (prev.states.find(id) != prev.states.end()) {
				const QNEntityState &p_st = prev.states.at(id);
				if (p_st.pos.is_equal_approx(st.pos) && p_st.rot.is_equal_approx(st.rot)) {
					_dormancy_ticks[id]++;
				} else {
					_dormancy_ticks[id] = 0;
				}
			}
		}
		
		if (_dormancy_ticks[id] >= _dormancy_threshold_ticks) {
			if (_dormancy_ticks[id] == _dormancy_threshold_ticks) {
				fell_asleep_this_tick.push_back(id);
				_dormancy_ticks[id]++;
			}
			sleeping_entities.push_back(id);
		}
	}
	
	for (int i = 0; i < _active_entities.size(); i++) {
		int id = _active_entities[i];
		QNEntityState &st = _registry[id];
		if (!st.has_state) continue;
		
		QNEntityState ws = st;
		ws.ts = now;
		
		st.custom_id = 0;
		
		if (_profiles.find(id) != _profiles.end()) {
			Ref<QNEntityProfile> profile = _profiles[id];
			if (profile.is_valid()) {
				ws.type = profile->get_hitbox_type();
				ws.extents = profile->get_hitbox_extents();
			}
		} else {
			ws.type = 0;
			ws.extents = Vector3(1.0, 1.0, 1.0);
		}
		
		world_snapshot.states[id] = ws;
	}
	
	_world_history.push_front(world_snapshot);
	if (_world_history.size() > 60) {
		_world_history.pop_back();
	}
	
	std::unordered_map<int, QNEntityState> current_states;
	
	for (int i = 0; i < _active_entities.size(); i++) {
		int id = _active_entities[i];
		QNEntityState &st = _registry[id];
		if (!st.has_state) continue;
		
		bool is_sleeping = (std::find(sleeping_entities.begin(), sleeping_entities.end(), id) != sleeping_entities.end());
		
		double tick_rate_hz = 20.0;
		if (is_sleeping) {
			tick_rate_hz = 1.0; // Heartbeat periódico para entidades dormentes (1 Hz = 95% economia de banda e resiliência UDP)
		} else if (_profiles.find(id) != _profiles.end()) {
			Ref<QNEntityProfile> profile = _profiles[id];
			if (profile.is_valid()) tick_rate_hz = profile->get_tick_rate_hz();
		}
		
		bool should_broadcast = false;
		if (tick_rate_hz > 0.0) {
			int interval_ms = (int)(1000.0 / tick_rate_hz);
			if (now - st.last_broadcast_ts >= interval_ms) {
				should_broadcast = true;
			}
		} else {
			if (st.last_broadcast_ts == 0) {
				should_broadcast = true;
			}
		}
		
		if (should_broadcast) {
			QNEntityState st_copy = st;
			st_copy.seq = _server_seq;
			current_states[id] = st_copy;
			st.last_broadcast_ts = now;
		} else {
			if (world_snapshot.states.find(id) != world_snapshot.states.end()) {
				current_states[id] = world_snapshot.states[id];
			}
		}
	}
	
	std::vector<int> candidates;
	candidates.reserve(128);
	std::vector<int> selected_states;
	selected_states.reserve(128);

	for (int i = 0; i < _active_entities.size(); i++) {
		int id = _active_entities[i];
		QNEntityState &st = _registry[id];
		if (!st.is_peer) continue;
		
		const QNWorldSnapshot* base_snapshot = nullptr;
		for (int k = 0; k < _world_history.size(); k++) {
			if (_world_history[k].seq == st.ack) {
				base_snapshot = &_world_history[k];
				break;
			}
		}
		
		candidates.clear();
		selected_states.clear();

		double observer_vision = _default_cull_radius; // Alcance de visão/percepção do observador

		if (_sync_adjacent_grids) {
			_grid->get_entities_in_radius_internal(st.pos, observer_vision, candidates);
		} else {
			PackedInt32Array chunk_ents = _grid->get_entities_in_chunk(st.pos);
			for (int j = 0; j < chunk_ents.size(); j++) {
				candidates.push_back(chunk_ents[j]);
			}
		}
		
		auto it = candidates.begin();
		while (it != candidates.end()) {
			int cid = *it;
			
			if (current_states.find(cid) != current_states.end()) {
				double cid_aura = _default_entity_aura;
				if (_profiles.find(cid) != _profiles.end()) {
					Ref<QNEntityProfile> cid_profile = _profiles[cid];
					if (cid_profile.is_valid()) cid_aura = cid_profile->get_spatial_culling_radius();
				}

				Vector3 cid_pos = current_states[cid].pos;

				// O Server verifica se o observador está dentro da Aura de Presença da Entidade Candidata (e dentro do alcance de visão)
				double effective_radius = Math::min(observer_vision, cid_aura);

				if (_sync_adjacent_grids && cid_pos.distance_to(st.pos) > effective_radius) {
					it = candidates.erase(it);
				} else {
					_peer_known_entities[id].insert(cid);
					++it;
				}
			} else {
				it = candidates.erase(it);
			}
		}
		
		// Detecta entidades que saíram do escopo de visão/presença deste observador (AoI Exit)
		std::vector<int> left_scope_entities;
		for (int known_cid : _peer_known_entities[id]) {
			if (known_cid != id && std::find(candidates.begin(), candidates.end(), known_cid) == candidates.end()) {
				if (_registry.find(known_cid) != _registry.end() && _registry[known_cid].has_state) {
					double known_aura = _default_entity_aura;
					if (_profiles.find(known_cid) != _profiles.end()) {
						Ref<QNEntityProfile> kp = _profiles[known_cid];
						if (kp.is_valid()) known_aura = kp->get_spatial_culling_radius();
					}
					double eff_r = Math::min(observer_vision, known_aura);
					Vector3 kpos = _registry[known_cid].pos;
					if (kpos.distance_to(st.pos) <= eff_r) {
						// A entidade ainda está dentro do alcance efetivo (dormindo), mantemos no escopo
						continue;
					}
				}
				left_scope_entities.push_back(known_cid);
			}
		}
		for (int left_id : left_scope_entities) {
			_peer_known_entities[id].erase(left_id);

			PackedByteArray left_pkt;
			left_pkt.resize(5);
			left_pkt.encode_u8(0, QNSerializer::TYPE_PEER_LEFT);
			left_pkt.encode_u32(1, left_id);
			emit_signal("packet_ready", id, left_pkt);
		}

		if (current_states.find(id) != current_states.end()) {
			if (std::find(candidates.begin(), candidates.end(), id) == candidates.end()) {
				candidates.push_back(id);
			}
		}
		
		_accumulator->select_entities_fast(id, candidates, _registry, current_states, _profiles, st.pos, 1200, 19, selected_states);
		
		for (int j = 0; j < selected_states.size(); j++) {
			int selected_id = selected_states[j];
			if (_registry.find(selected_id) != _registry.end()) {
				_registry[selected_id].last_broadcast_ts = now;
			}
		}
		
		for (int asleep_id : fell_asleep_this_tick) {
			if (_registry.find(asleep_id) == _registry.end()) continue;

			double asleep_aura = _default_entity_aura;
			if (_profiles.find(asleep_id) != _profiles.end()) {
				Ref<QNEntityProfile> asleep_profile = _profiles[asleep_id];
				if (asleep_profile.is_valid()) {
					asleep_aura = asleep_profile->get_spatial_culling_radius();
				}
			}

			double effective_radius = Math::min(observer_vision, asleep_aura);
			Vector3 asleep_pos = _registry[asleep_id].pos;
			if (asleep_pos.distance_to(st.pos) <= effective_radius) {
				PackedByteArray sleep_pkt;
				sleep_pkt.resize(5);
				sleep_pkt.encode_u8(0, QNSerializer::TYPE_SLEEP);
				sleep_pkt.encode_u32(1, asleep_id);
				emit_signal("packet_ready", id, sleep_pkt);
			}
		}
		
		_write_buf->seek(0);
		_write_buf->write_bits(QNSerializer::TYPE_INPUT_SNAPSHOT, 8);
		_write_buf->write_bits(_server_seq, 16);
		_write_buf->write_bits(st.client_seq, 16);
		_write_buf->write_bits(now & 0xFFFFFFFF, 32);
		_write_buf->write_bits(selected_states.size(), 8);
		
		for (int j = 0; j < selected_states.size(); j++) {
			int entity_id = selected_states[j];
			_write_buf->write_bits(entity_id, 32);
			
			const QNEntityState* base = nullptr;
			if (base_snapshot && base_snapshot->states.find(entity_id) != base_snapshot->states.end()) {
				base = &base_snapshot->states.at(entity_id);
			}
			
			const QNEntityState &c_state = current_states[entity_id];
			QNDeltaSerializer::encode_state(_write_buf, base, c_state);
		}
		
		emit_signal("packet_ready", id, _write_buf->get_buffer());
	}
	
	// Gravação nativa no buffer de histórico temporal (Zero alocações de Dictionary)
	_rewind_buffer->push_state_native(now, current_states, _active_entities);
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
	Dictionary gd_registry;
	for (int id : _active_entities) {
		if (_registry.find(id) != _registry.end()) {
			Dictionary d = _registry[id].to_dict();
			d["id"] = id;
			if (_profiles.find(id) != _profiles.end()) {
				d["profile"] = _profiles[id];
			}
			gd_registry[id] = d;
		}
	}
	return gd_registry;
}

Array QNHostSession::get_registry_keys() const {
	Array keys;
	for (int id : _active_entities) {
		keys.push_back(id);
	}
	return keys;
}

Vector3 QNHostSession::get_entity_position(int entity_id) const {
	if (_registry.find(entity_id) != _registry.end()) {
		return _registry.at(entity_id).pos;
	}
	return Vector3();
}

Ref<QNSpatialGrid> QNHostSession::get_grid() const {
	return _grid;
}

void QNHostSession::set_sync_adjacent_grids(bool p_sync) {
	_sync_adjacent_grids = p_sync;
}

bool QNHostSession::get_sync_adjacent_grids() const {
	return _sync_adjacent_grids;
}

void QNHostSession::set_default_cull_radius(double r) {
	_default_cull_radius = r;
}

double QNHostSession::get_default_cull_radius() const {
	return _default_cull_radius;
}

void QNHostSession::set_default_entity_aura(double r) {
	_default_entity_aura = r;
}

double QNHostSession::get_default_entity_aura() const {
	return _default_entity_aura;
}


