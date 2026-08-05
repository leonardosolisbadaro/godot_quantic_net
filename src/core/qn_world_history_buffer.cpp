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
	ClassDB::bind_method(D_METHOD("raycast_past", "origin", "direction", "timestamp"), &QNWorldHistoryBuffer::raycast_past);

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

Dictionary QNWorldHistoryBuffer::raycast_past(const Vector3 &origin, const Vector3 &direction, int timestamp) const {
	Dictionary result;

	if (_history.empty()) {
		return result;
	}

	Vector3 dir_norm = direction.normalized();

	// Encontrar o estado exato ou interpolar
	Dictionary state_before;
	Dictionary state_after;
	bool found = false;

	for (size_t i = 0; i < _history.size(); ++i) {
		Dictionary hist = _history[i];
		int hist_ts = hist["ts"];

		if (hist_ts == timestamp) {
			state_before = hist;
			state_after = hist;
			found = true;
			break;
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
		// O timestamp pedido está fora do nosso histórico gravado (provavelmente velho demais)
		return result;
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

	Array keys = entities_b.keys();
	
	int hit_entity = 0;
	double min_dist = std::numeric_limits<double>::max();
	Vector3 hit_pos;

	for (int i = 0; i < keys.size(); i++) {
		int entity_id = keys[i];
		Dictionary ent_b = entities_b[entity_id];
		
		Vector3 pos_b = ent_b.get("pos", Vector3());
		double radius = ent_b.get("radius", 1.0); // Assume 1.0 como default cull/hit radius

		Vector3 pos_interp = pos_b;
		
		if (entities_a.has(entity_id)) {
			Dictionary ent_a = entities_a[entity_id];
			Vector3 pos_a = ent_a.get("pos", Vector3());
			pos_interp = pos_b.lerp(pos_a, factor);
		}

		if (_ray_intersects_sphere(origin, dir_norm, pos_interp, radius)) {
			double dist = origin.distance_to(pos_interp);
			if (dist < min_dist) {
				min_dist = dist;
				hit_entity = entity_id;
				hit_pos = pos_interp;
			}
		}
	}

	if (hit_entity != 0) {
		result["entity_id"] = hit_entity;
		result["hit_point"] = hit_pos;
	}

	return result;
}
