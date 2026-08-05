#include "qn_priority_accumulator.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/array.hpp>
#include "qn_entity_profile.hpp"
#include <vector>
#include <algorithm>

using namespace godot;

QNPriorityAccumulator::QNPriorityAccumulator() {
}

QNPriorityAccumulator::~QNPriorityAccumulator() {
}

void QNPriorityAccumulator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("cleanup_entity", "entity_id"), &QNPriorityAccumulator::cleanup_entity);
	ClassDB::bind_method(D_METHOD("_cleanup_peer", "peer_id"), &QNPriorityAccumulator::_cleanup_peer);
	ClassDB::bind_method(D_METHOD("select_entities", "peer_id", "candidates", "profiles", "observer_pos", "mtu_budget", "bytes_per_entity"), &QNPriorityAccumulator::select_entities, DEFVAL(1200), DEFVAL(19));
}

double QNPriorityAccumulator::_get_debt(int peer_id, int entity_id) {
	if (!_debt.has(peer_id)) return 0.0;
	Dictionary peer_debt = _debt[peer_id];
	return peer_debt.get(entity_id, 0.0);
}

void QNPriorityAccumulator::_add_debt(int peer_id, int entity_id, double amount) {
	if (!_debt.has(peer_id)) {
		_debt[peer_id] = Dictionary();
	}
	Dictionary peer_debt = _debt[peer_id];
	double current = peer_debt.get(entity_id, 0.0);
	peer_debt[entity_id] = current + amount;
	_debt[peer_id] = peer_debt;
}

void QNPriorityAccumulator::_clear_debt(int peer_id, int entity_id) {
	if (_debt.has(peer_id)) {
		Dictionary peer_debt = _debt[peer_id];
		if (peer_debt.has(entity_id)) {
			peer_debt.erase(entity_id);
			_debt[peer_id] = peer_debt;
		}
	}
}

void QNPriorityAccumulator::cleanup_entity(int entity_id) {
	Array keys = _debt.keys();
	for (int i = 0; i < keys.size(); i++) {
		int peer_id = keys[i];
		Dictionary peer_debt = _debt[peer_id];
		if (peer_debt.has(entity_id)) {
			peer_debt.erase(entity_id);
			_debt[peer_id] = peer_debt;
		}
	}
}

void QNPriorityAccumulator::_cleanup_peer(int peer_id) {
	if (_debt.has(peer_id)) {
		_debt.erase(peer_id);
	}
}

struct ScoredItem {
	int id;
	double score;
	Dictionary state;
	
	bool operator<(const ScoredItem& other) const {
		return score > other.score; // Sort descending
	}
};

Dictionary QNPriorityAccumulator::select_entities(int peer_id, const Dictionary &candidates, const Dictionary &profiles, const Vector3 &observer_pos, int mtu_budget, int bytes_per_entity) {
	std::vector<ScoredItem> scored_list;
	
	Array keys = candidates.keys();
	for (int i = 0; i < keys.size(); i++) {
		int entity_id = keys[i];
		Dictionary st = candidates[entity_id];
		Vector3 pos = st.get("pos", Vector3());
		
		Ref<QNEntityProfile> profile;
		if (profiles.has(entity_id)) {
			profile = profiles[entity_id];
		}
		
		double base_priority = profile.is_valid() ? profile->get_base_priority() : 1.0;
		double cull_radius = profile.is_valid() ? profile->get_spatial_culling_radius() : 50.0;
		
		double dist = observer_pos.distance_to(pos);
		
		if (dist > cull_radius && entity_id != peer_id) {
			_add_debt(peer_id, entity_id, 0.1);
			continue;
		}
		
		double distance_factor = Math::max(1.0, dist);
		double score = (base_priority * 100.0) / distance_factor;
		score += _get_debt(peer_id, entity_id);
		
		if (entity_id == peer_id) {
			score += 100000.0;
		}
		
		ScoredItem item;
		item.id = entity_id;
		item.score = score;
		item.state = st;
		scored_list.push_back(item);
	}
	
	std::sort(scored_list.begin(), scored_list.end());
	
	Dictionary selected;
	int current_bytes = 0;
	
	for (const ScoredItem &item : scored_list) {
		if (current_bytes + bytes_per_entity <= mtu_budget) {
			selected[item.id] = item.state;
			current_bytes += bytes_per_entity;
			_clear_debt(peer_id, item.id);
		} else {
			_add_debt(peer_id, item.id, item.score * 0.5);
		}
	}
	
	return selected;
}
