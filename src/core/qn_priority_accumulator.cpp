#include "qn_priority_accumulator.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/array.hpp>
#include "qn_entity_profile.hpp"
#include <vector>
#include <algorithm>
#include <unordered_set>

using namespace godot;

static const double MAX_DEBT_PER_TICK = 500.0;

struct ScoredItem {
	int id;
	double score;
	
	bool operator<(const ScoredItem& other) const {
		return score > other.score; // Sort descending
	}
};

QNPriorityAccumulator::QNPriorityAccumulator() {
}

QNPriorityAccumulator::~QNPriorityAccumulator() {
}

void QNPriorityAccumulator::_bind_methods() {
	ClassDB::bind_method(D_METHOD("cleanup_entity", "entity_id"), &QNPriorityAccumulator::cleanup_entity);
	ClassDB::bind_method(D_METHOD("_cleanup_peer", "peer_id"), &QNPriorityAccumulator::_cleanup_peer);
	ClassDB::bind_method(D_METHOD("select_entities", "peer_id", "candidates", "profiles", "observer_pos", "mtu_budget", "bytes_per_entity"), &QNPriorityAccumulator::select_entities);
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

PackedInt32Array QNPriorityAccumulator::select_entities(int peer_id, const Dictionary &candidates, const Dictionary &profiles, const Vector3 &observer_pos, int mtu_budget, int bytes_per_entity) {
	PackedInt32Array result;
	std::vector<ScoredItem> scored_list;
	Array keys = candidates.keys();
	
	// Limpeza de Memory Leak: Expurgar dívidas velhas
	auto peer_it = _debt.find(peer_id);
	if (peer_it != _debt.end()) {
		auto it = peer_it->second.begin();
		while (it != peer_it->second.end()) {
			if (!candidates.has(it->first)) {
				it = peer_it->second.erase(it);
			} else {
				++it;
			}
		}
	}

	for (int i = 0; i < keys.size(); i++) {
		int entity_id = keys[i];
		Dictionary cand_data = candidates[entity_id];
		Vector3 pos = cand_data.get("pos", Vector3());
		
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
		scored_list.push_back(item);
	}
	
	std::sort(scored_list.begin(), scored_list.end());
	
	int current_bytes = 0;
	for (const ScoredItem &item : scored_list) {
		if (current_bytes + bytes_per_entity <= mtu_budget) {
			result.push_back(item.id);
			current_bytes += bytes_per_entity;
			_clear_debt(peer_id, item.id);
		} else {
			_add_debt(peer_id, item.id, Math::min(item.score * 0.5, MAX_DEBT_PER_TICK));
		}
	}
	
	return result;
}

void QNPriorityAccumulator::select_entities_fast(int peer_id, const std::vector<int> &candidates, const std::unordered_map<int, QNEntityState> &registry, const std::unordered_map<int, QNEntityState> &current_states, const std::unordered_map<int, Ref<QNEntityProfile>> &profiles, const Vector3 &observer_pos, int mtu_budget, int bytes_per_entity, std::vector<int> &out_selected) {
	std::vector<ScoredItem> scored_list;
	scored_list.reserve(candidates.size());
	
	// Limpeza O(1): Usar unordered_set para consulta rapida em vez de O(N*M)
	std::unordered_set<int> cand_set(candidates.begin(), candidates.end());
	auto peer_it = _debt.find(peer_id);
	if (peer_it != _debt.end()) {
		auto it = peer_it->second.begin();
		while (it != peer_it->second.end()) {
			if (cand_set.find(it->first) == cand_set.end()) {
				it = peer_it->second.erase(it);
			} else {
				++it;
			}
		}
	}

	for (int i = 0; i < candidates.size(); i++) {
		int entity_id = candidates[i];
		
		Vector3 pos;
		auto cs_it = current_states.find(entity_id);
		if (cs_it != current_states.end()) {
			pos = cs_it->second.pos;
		} else {
			auto reg_it = registry.find(entity_id);
			if (reg_it != registry.end()) {
				pos = reg_it->second.pos;
			}
		}
		
		double base_priority = 1.0;
		auto prof_it = profiles.find(entity_id);
		if (prof_it != profiles.end() && prof_it->second.is_valid()) {
			base_priority = prof_it->second->get_base_priority();
		}
		
		double dist = observer_pos.distance_to(pos);
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
	
	int current_bytes = 0;
	
	for (const ScoredItem &item : scored_list) {
		if (current_bytes + bytes_per_entity <= mtu_budget) {
			out_selected.push_back(item.id);
			current_bytes += bytes_per_entity;
			_clear_debt(peer_id, item.id);
		} else {
			_add_debt(peer_id, item.id, Math::min(item.score * 0.5, MAX_DEBT_PER_TICK));
		}
	}
}
