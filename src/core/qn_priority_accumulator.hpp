#ifndef QN_PRIORITY_ACCUMULATOR_H
#define QN_PRIORITY_ACCUMULATOR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include "core/qn_types.hpp"
#include "core/qn_entity_profile.hpp"
#include <map>
#include <vector>
#include <unordered_map>

namespace godot {

class QNPriorityAccumulator : public RefCounted {
	GDCLASS(QNPriorityAccumulator, RefCounted)

private:
	std::map<int, std::map<int, double>> _debt;

	double _get_debt(int peer_id, int entity_id);
	void _add_debt(int peer_id, int entity_id, double amount);
	void _clear_debt(int peer_id, int entity_id);

protected:
	static void _bind_methods();

public:
	QNPriorityAccumulator();
	~QNPriorityAccumulator();

	void cleanup_entity(int entity_id);
	void _cleanup_peer(int peer_id);

	PackedInt32Array select_entities(int peer_id, const Dictionary &candidates, const Dictionary &profiles, const Vector3 &observer_pos, int mtu_budget, int bytes_per_entity);
	void select_entities_fast(int peer_id, const std::vector<int> &candidates, const std::unordered_map<int, QNEntityState> &registry, const std::unordered_map<int, QNEntityState> &current_states, const std::unordered_map<int, Ref<QNEntityProfile>> &profiles, const Vector3 &observer_pos, int mtu_budget, int bytes_per_entity, std::vector<int> &out_selected);
};

} // namespace godot

#endif // QN_PRIORITY_ACCUMULATOR_H
