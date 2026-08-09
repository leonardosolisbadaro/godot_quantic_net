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
	Dictionary entry;
	entry["ts"] = timestamp;
	entry["entities"] = world_snapshot; // This is a reference in GDScript, but we assume it's copied or read-only

	_history.push_front(entry);
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
	// Se o centro está atrás do raio, ignoramos a não ser que a origem esteja dentro da esfera (tca < 0)
	// Como isso é para tiros, se a origem está dentro, é hit direto.
	double d2 = L.dot(L) - tca * tca;
	double radius2 = radius * radius;
	if (d2 > radius2) {
		return false; // Raio passa fora da esfera
	}
	double thc = std::sqrt(radius2 - d2);
	double t0 = tca - thc;
	double t1 = tca + thc;

	if (t0 < 0 && t1 < 0) {
		return false; // Esfera completamente atrás
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

Dictionary QNWorldHistoryBuffer::_get_interpolated_state(int timestamp) const {
	if (_history.size() == 0) {
		return Dictionary();
	}
	
	if (timestamp < 0) {
		Dictionary first = _history[0];
		return first["entities"]; // Present
	}

	Dictionary state_before;
	Dictionary state_after;
	bool found = false;

	for (int i = 0; i < _history.size(); ++i) {
		Dictionary hist = _history[i];
		int hist_ts = hist["ts"];

		if (hist_ts == timestamp) {
			return hist["entities"];
		} else if (hist_ts < timestamp) {
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
		return Dictionary();
	}

	int ts_b = state_before["ts"];
	int ts_a = state_after["ts"];

	double factor = 0.0;
	if (ts_a != ts_b) {
		factor = (double)(timestamp - ts_b) / (double)(ts_a - ts_b);
		if (factor < 0.0) factor = 0.0;
		if (factor > 1.0) factor = 1.0;
	}

	Dictionary entities_b = state_before["entities"];
	Dictionary entities_a = state_after["entities"];
	Dictionary interpolated;
	Array keys = entities_b.keys();

	for (int i = 0; i < keys.size(); i++) {
		int entity_id = keys[i];
		Dictionary ent_b = entities_b[entity_id];
		Vector3 pos_b = ent_b.get("pos", Vector3());
		
		Dictionary interp_ent = ent_b.duplicate();

		if (entities_a.has(entity_id)) {
			Dictionary ent_a = entities_a[entity_id];
			Vector3 pos_a = ent_a.get("pos", Vector3());
			interp_ent["pos"] = pos_b.lerp(pos_a, factor);
		}
		interpolated[entity_id] = interp_ent;
	}
	
	return interpolated;
}

Dictionary QNWorldHistoryBuffer::query_raycast(const Vector3 &origin, const Vector3 &direction, double max_dist, int timestamp) const {
	Dictionary result;
	Dictionary entities = _get_interpolated_state(timestamp);
	if (entities.is_empty()) return result;

	Vector3 dir_norm = direction.normalized();
	Array keys = entities.keys();
	
	int hit_entity = 0;
	double min_dist = max_dist > 0 ? max_dist : std::numeric_limits<double>::max();
	Vector3 hit_pos;

	for (int i = 0; i < keys.size(); i++) {
		int entity_id = keys[i];
		Dictionary ent = entities[entity_id];
		Vector3 pos = ent.get("pos", Vector3());
		
		int type = ent.get("hitbox_type", 0);
		bool hit = false;
		
		if (type == 1) { // AABB
			Vector3 extents = ent.get("hitbox_extents", Vector3(1,1,1));
			hit = _ray_intersects_aabb(origin, dir_norm, pos, extents);
		} else { // SPHERE
			double radius = ent.get("hitbox_extents", Vector3(1,1,1)).operator Vector3()[0];
			hit = _ray_intersects_sphere(origin, dir_norm, pos, radius);
		}

		if (hit) {
			double dist = origin.distance_to(pos);
			if (dist <= min_dist) {
				min_dist = dist;
				hit_entity = entity_id;
				hit_pos = pos;
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
	Dictionary entities = _get_interpolated_state(timestamp);
	if (entities.is_empty()) return results;

	Vector3 box_min = center - extents;
	Vector3 box_max = center + extents;
	Array keys = entities.keys();

	for (int i = 0; i < keys.size(); i++) {
		int entity_id = keys[i];
		Dictionary ent = entities[entity_id];
		Vector3 pos = ent.get("pos", Vector3());

		// Point in AABB for simplicity
		if (pos.x >= box_min.x && pos.x <= box_max.x &&
			pos.y >= box_min.y && pos.y <= box_max.y &&
			pos.z >= box_min.z && pos.z <= box_max.z) {
			results.push_back(entity_id);
		}
	}
	return results;
}

Array QNWorldHistoryBuffer::query_sphere(const Vector3 &center, double radius, int timestamp) const {
	Array results;
	Dictionary entities = _get_interpolated_state(timestamp);
	if (entities.is_empty()) return results;

	Array keys = entities.keys();

	for (int i = 0; i < keys.size(); i++) {
		int entity_id = keys[i];
		Dictionary ent = entities[entity_id];
		Vector3 pos = ent.get("pos", Vector3());

		if (center.distance_squared_to(pos) <= radius * radius) {
			results.push_back(entity_id);
		}
	}
	return results;
}
