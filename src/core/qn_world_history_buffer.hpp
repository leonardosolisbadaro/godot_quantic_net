#ifndef QN_WORLD_HISTORY_BUFFER_H
#define QN_WORLD_HISTORY_BUFFER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/array.hpp>
#include "core/qn_types.hpp"
#include <deque>
#include <vector>
#include <map>
#include <unordered_map>

namespace godot {

class QNWorldHistoryBuffer : public RefCounted {
	GDCLASS(QNWorldHistoryBuffer, RefCounted)

private:
	// Store historical states:
	// A deque of dictionaries. Each dictionary contains:
	struct QNEntitySnapshot {
		Vector3 pos;
		Vector3 extents;
		int type;
	};

	struct QNWorldSnapshot {
		int ts;
		std::map<int, QNEntitySnapshot> entities;
	};

	int _max_history_ticks;
	std::deque<QNWorldSnapshot> _history;

	bool _ray_intersects_sphere(const Vector3 &origin, const Vector3 &dir, const Vector3 &center, double radius) const;
	bool _ray_intersects_aabb(const Vector3 &origin, const Vector3 &dir, const Vector3 &center, const Vector3 &extents) const;

	std::map<int, QNEntitySnapshot> _get_interpolated_state(int timestamp) const;

protected:
	static void _bind_methods();

public:
	QNWorldHistoryBuffer();
	~QNWorldHistoryBuffer();

	void set_max_history_ticks(int max_ticks);
	int get_max_history_ticks() const;

	void push_state(int timestamp, const Dictionary &world_snapshot);
	void push_state_internal(int timestamp, const Dictionary &world_snapshot, const std::vector<int> &active_entities);
	void push_state_native(int timestamp, const std::unordered_map<int, QNEntityState> &current_states, const std::vector<int> &active_entities);
	void clear();
	
	// Agnostic Time-Travel Queries
	Dictionary query_raycast(const Vector3 &origin, const Vector3 &direction, double max_dist, int timestamp) const;
	Array query_box(const Vector3 &center, const Vector3 &extents, int timestamp) const;
	Array query_sphere(const Vector3 &center, double radius, int timestamp) const;
};

} // namespace godot

#endif // QN_WORLD_HISTORY_BUFFER_H
