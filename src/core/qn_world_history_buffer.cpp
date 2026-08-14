#include "qn_world_history_buffer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <limits>

using namespace godot;

QNWorldHistoryBuffer::QNWorldHistoryBuffer() {
	_max_history_ticks = 90; // 1.5s at 60Hz
}

QNWorldHistoryBuffer::~QNWorldHistoryBuffer() {
}

void QNWorldHistoryBuffer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_max_history_ticks", "max_ticks"), &QNWorldHistoryBuffer::set_max_history_ticks);
	ClassDB::bind_method(D_METHOD("get_max_history_ticks"), &QNWorldHistoryBuffer::get_max_history_ticks);

	ClassDB::bind_method(D_METHOD("push_state", "timestamp", "world_snapshot"), &QNWorldHistoryBuffer::push_state);
	ClassDB::bind_method(D_METHOD("clear"), &QNWorldHistoryBuffer::clear);
	ClassDB::bind_method(D_METHOD("query_raycast", "origin", "direction", "max_dist", "timestamp"), &QNWorldHistoryBuffer::query_raycast);
	ClassDB::bind_method(D_METHOD("query_box", "center", "extents", "timestamp"), &QNWorldHistoryBuffer::query_box);
	ClassDB::bind_method(D_METHOD("query_sphere", "center", "radius", "timestamp"), &QNWorldHistoryBuffer::query_sphere);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_history_ticks"), "set_max_history_ticks", "get_max_history_ticks");
}

void QNWorldHistoryBuffer::set_max_history_ticks(int max_ticks) {
	if (max_ticks > 0) {
		_max_history_ticks = max_ticks;
	}
}

int QNWorldHistoryBuffer::get_max_history_ticks() const {
	return _max_history_ticks;
}

void QNWorldHistoryBuffer::push_state(int timestamp, const Dictionary &world_snapshot) {
	QNWorldSnapshot snap;
	snap.ts = timestamp;
	Array keys = world_snapshot.keys();
	for (int i = 0; i < keys.size(); i++) {
		int id = keys[i];
		Dictionary ent = world_snapshot[id];
		QNEntitySnapshot es;
		es.pos = ent.get("pos", Vector3());
		es.extents = ent.get("hitbox_extents", Vector3(1.0, 1.0, 1.0));
		es.type = ent.get("hitbox_type", 0);
		snap.entities[id] = es;
	}
	_history.push_front(snap);
	if (_history.size() > _max_history_ticks) {
		_history.pop_back();
	}
}

void QNWorldHistoryBuffer::push_state_internal(int timestamp, const Dictionary &world_snapshot, const std::vector<int> &active_entities) {
	QNWorldSnapshot snap;
	snap.ts = timestamp;
	for (int i = 0; i < active_entities.size(); i++) {
		int id = active_entities[i];
		if (!world_snapshot.has(id)) continue;
		Dictionary ent = world_snapshot[id];
		QNEntitySnapshot es;
		es.pos = ent.get("pos", Vector3());
		es.type = ent.get("hitbox_type", 0);
		es.extents = ent.get("hitbox_extents", Vector3(1,1,1));
		snap.entities[id] = es;
	}

	_history.push_front(snap);
	if (_history.size() > _max_history_ticks) {
		_history.pop_back();
	}
}

void QNWorldHistoryBuffer::push_state_native(int timestamp, const std::unordered_map<int, QNEntityState> &current_states, const std::vector<int> &active_entities) {
	QNWorldSnapshot snap;
	snap.ts = timestamp;
	for (int i = 0; i < active_entities.size(); i++) {
		int id = active_entities[i];
		auto it = current_states.find(id);
		if (it == current_states.end()) continue;
		const QNEntityState &st = it->second;
		QNEntitySnapshot es;
		es.pos = st.pos;
		es.type = st.type;
		es.extents = st.extents;
		snap.entities[id] = es;
	}

	_history.push_front(snap);
	if (_history.size() > _max_history_ticks) {
		_history.pop_back();
	}
}

void QNWorldHistoryBuffer::clear() {
	_history.clear();
}

bool QNWorldHistoryBuffer::_ray_intersects_sphere(const Vector3 &origin, const Vector3 &dir, const Vector3 &center, double radius) const {
	Vector3 L = center - origin;
	double tca = L.dot(dir);
	double d2 = L.dot(L) - tca * tca;
	double radius2 = radius * radius;
	if (d2 > radius2) {
		return false;
	}
	double thc = std::sqrt(radius2 - d2);
	double t0 = tca - thc;
	double t1 = tca + thc;

	if (t0 < 0 && t1 < 0) {
		return false;
	}
	return true;
}

bool QNWorldHistoryBuffer::_ray_intersects_aabb(const Vector3 &origin, const Vector3 &dir, const Vector3 &center, const Vector3 &extents) const {
	Vector3 box_min = center - extents;
	Vector3 box_max = center + extents;

	double tmin = -std::numeric_limits<double>::max();
	double tmax = std::numeric_limits<double>::max();

	for (int i = 0; i < 3; ++i) {
		double origin_i = origin[i];
		double dir_i = dir[i];
		double min_i = box_min[i];
		double max_i = box_max[i];

		if (std::abs(dir_i) < 1e-6) {
			if (origin_i < min_i || origin_i > max_i) return false;
		} else {
			double t1 = (min_i - origin_i) / dir_i;
			double t2 = (max_i - origin_i) / dir_i;

			if (t1 > t2) std::swap(t1, t2);

			if (t1 > tmin) tmin = t1;
			if (t2 < tmax) tmax = t2;

			if (tmin > tmax) return false;
			if (tmax < 0) return false;
		}
	}
	return true;
}

std::map<int, QNWorldHistoryBuffer::QNEntitySnapshot> QNWorldHistoryBuffer::_get_interpolated_state(int timestamp) const {
	std::map<int, QNEntitySnapshot> result;
	if (_history.size() == 0) {
		return result;
	}
	
	if (timestamp < 0) {
		return _history[0].entities;
	}

	QNWorldSnapshot state_before;
	QNWorldSnapshot state_after;
	bool found = false;

	for (size_t i = 0; i < _history.size(); ++i) {
		const QNWorldSnapshot &hist = _history[i];
		
		if (hist.ts == timestamp) {
			return hist.entities;
		} else if (hist.ts < timestamp) {
			state_before = hist;
			if (i > 0) {
				state_after = _history[i - 1];
			} else {
				state_after = hist;
			}
			found = true;
			break;
		}
	}

	if (!found) {
		return result;
	}

	double factor = 0.0;
	if (state_after.ts != state_before.ts) {
		factor = (double)(timestamp - state_before.ts) / (double)(state_after.ts - state_before.ts);
		if (factor < 0.0) factor = 0.0;
		if (factor > 1.0) factor = 1.0;
	}

	for (auto const& [entity_id, ent_b] : state_before.entities) {
		QNEntitySnapshot interp_ent = ent_b;
		
		auto it_a = state_after.entities.find(entity_id);
		if (it_a != state_after.entities.end()) {
			interp_ent.pos = ent_b.pos.lerp(it_a->second.pos, factor);
		}
		result[entity_id] = interp_ent;
	}
	
	return result;
}

Dictionary QNWorldHistoryBuffer::query_raycast(const Vector3 &origin, const Vector3 &direction, double max_dist, int timestamp) const {
	Dictionary result;
	std::map<int, QNEntitySnapshot> entities = _get_interpolated_state(timestamp);
	if (entities.empty()) return result;

	Vector3 dir_norm = direction.normalized();
	
	int hit_entity = 0;
	double min_dist = max_dist > 0 ? max_dist : std::numeric_limits<double>::max();
	Vector3 hit_pos;

	for (auto const& [entity_id, ent] : entities) {
		bool hit = false;
		if (ent.type == 1) { // AABB
			hit = _ray_intersects_aabb(origin, dir_norm, ent.pos, ent.extents);
		} else { // SPHERE
			hit = _ray_intersects_sphere(origin, dir_norm, ent.pos, ent.extents[0]);
		}

		if (hit) {
			double dist = origin.distance_to(ent.pos);
			if (dist <= min_dist) {
				min_dist = dist;
				hit_entity = entity_id;
				hit_pos = ent.pos;
			}
		}
	}

	if (hit_entity != 0) {
		result["entity_id"] = hit_entity;
		result["hit_point"] = hit_pos;
	}
	
	return result;
}

Array QNWorldHistoryBuffer::query_box(const Vector3 &center, const Vector3 &extents, int timestamp) const {
	Array results;
	std::map<int, QNEntitySnapshot> entities = _get_interpolated_state(timestamp);
	if (entities.empty()) return results;

	Vector3 box_min = center - extents;
	Vector3 box_max = center + extents;

	for (auto const& [entity_id, ent] : entities) {
		if (ent.pos.x >= box_min.x && ent.pos.x <= box_max.x &&
			ent.pos.y >= box_min.y && ent.pos.y <= box_max.y &&
			ent.pos.z >= box_min.z && ent.pos.z <= box_max.z) {
			results.push_back(entity_id);
		}
	}
	
	return results;
}

Array QNWorldHistoryBuffer::query_sphere(const Vector3 &center, double radius, int timestamp) const {
	Array results;
	std::map<int, QNEntitySnapshot> entities = _get_interpolated_state(timestamp);
	if (entities.empty()) return results;

	for (auto const& [entity_id, ent] : entities) {
		if (center.distance_squared_to(ent.pos) <= radius * radius) {
			results.push_back(entity_id);
		}
	}
	
	return results;
}
