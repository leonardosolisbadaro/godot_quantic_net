import sys

content = """#include "qn_priority_accumulator.hpp"
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
	// select_entities is no longer exposed to GDScript because it returns PackedInt32Array and uses internal C++ types
}

double QNPriorityAccumulator::_get_debt(int peer_id, int entity_id) {
	auto it = _debt.find(peer_id);
	if (it == _debt.end()) return 0.0;
	auto e_it = it->second.find(entity_id);
	if (e_it == it->second.end()) return 0.0;
	return e_it->second;
}

void QNPriorityAccumulator::_add_debt(int peer_id, int entity_id, double amount) {
	_debt[peer_id][entity_id] += amount;
}

void QNPriorityAccumulator::_clear_debt(int peer_id, int entity_id) {
	auto it = _debt.find(peer_id);
	if (it != _debt.end()) {
		it->second.erase(entity_id);
	}
}

void QNPriorityAccumulator::cleanup_entity(int entity_id) {
	for (auto& pair : _debt) {
		pair.second.erase(entity_id);
	}
}

void QNPriorityAccumulator::_cleanup_peer(int peer_id) {
	_debt.erase(peer_id);
}

struct ScoredItem {
	int id;
	double score;
	
	bool operator<(const ScoredItem& other) const {
		return score > other.score; // Sort descending
	}
};

PackedInt32Array QNPriorityAccumulator::select_entities(int peer_id, const PackedInt32Array &candidates, const Dictionary &registry, const Dictionary &current_states, const Vector3 &observer_pos, int mtu_budget, int bytes_per_entity) {
	std::vector<ScoredItem> scored_list;
	
	// Create a quick lookup for candidates
	std::vector<int> cand_vec;
	for (int i = 0; i < candidates.size(); i++) cand_vec.push_back(candidates[i]);
	
	// Limpeza de Memory Leak: Expurgar dívidas velhas
	auto peer_it = _debt.find(peer_id);
	if (peer_it != _debt.end()) {
		auto it = peer_it->second.begin();
		while (it != peer_it->second.end()) {
			if (std::find(cand_vec.begin(), cand_vec.end(), it->first) == cand_vec.end()) {
				it = peer_it->second.erase(it);
			} else {
				++it;
			}
		}
	}

	for (int i = 0; i < candidates.size(); i++) {
		int entity_id = candidates[i];
		
		Vector3 pos;
		if (current_states.has(entity_id)) {
			pos = ((Dictionary)current_states[entity_id]).get("pos", Vector3());
		} else if (registry.has(entity_id)) {
			pos = ((Dictionary)registry[entity_id]).get("pos", Vector3());
		}
		
		Ref<QNEntityProfile> profile;
		if (registry.has(entity_id)) {
			profile = ((Dictionary)registry[entity_id]).get("profile", Variant());
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
		scored_list.push_back(item);
	}
	
	std::sort(scored_list.begin(), scored_list.end());
	
	PackedInt32Array selected;
	int current_bytes = 0;
	
	for (const ScoredItem &item : scored_list) {
		if (current_bytes + bytes_per_entity <= mtu_budget) {
			selected.push_back(item.id);
			current_bytes += bytes_per_entity;
			_clear_debt(peer_id, item.id);
		} else {
			_add_debt(peer_id, item.id, item.score * 0.5);
		}
	}
	
	return selected;
}
"""

with open('src/core/qn_priority_accumulator.cpp', 'w', encoding='utf-8') as f:
    f.write(content)
