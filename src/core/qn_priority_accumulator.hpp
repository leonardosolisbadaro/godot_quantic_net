#ifndef QN_PRIORITY_ACCUMULATOR_H
#define QN_PRIORITY_ACCUMULATOR_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace godot {

class QNPriorityAccumulator : public RefCounted {
	GDCLASS(QNPriorityAccumulator, RefCounted)

private:
	Dictionary _debt; // peer_id -> (entity_id -> float)

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

	Dictionary select_entities(int peer_id, const Dictionary &candidates, const Dictionary &profiles, const Vector3 &observer_pos, int mtu_budget = 1200, int bytes_per_entity = 19);
};

} // namespace godot

#endif // QN_PRIORITY_ACCUMULATOR_H
