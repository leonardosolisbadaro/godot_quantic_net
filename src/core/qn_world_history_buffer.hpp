#ifndef QN_WORLD_HISTORY_BUFFER_H
#define QN_WORLD_HISTORY_BUFFER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <deque>

namespace godot {

class QNWorldHistoryBuffer : public RefCounted {
	GDCLASS(QNWorldHistoryBuffer, RefCounted)

private:
	// Store historical states:
	// A deque of dictionaries. Each dictionary contains:
	// "ts" : int (timestamp)
	// "entities" : Dictionary (key: entity_id, value: Dictionary{"pos", "radius"})
	std::deque<Dictionary> _history;
	
	// Max length of history in ticks. Assuming 60Hz, 90 ticks = 1.5 seconds.
	int _max_history_ticks;

	// Math logic for raycast vs sphere
	bool _ray_intersects_sphere(const Vector3 &origin, const Vector3 &dir, const Vector3 &center, double radius) const;

protected:
	static void _bind_methods();

public:
	QNWorldHistoryBuffer();
	~QNWorldHistoryBuffer();

	void set_max_history_ticks(int max_ticks);
	int get_max_history_ticks() const;

	void push_state(int timestamp, const Dictionary &world_snapshot);
	void clear();
	
	// Performs a raycast at the exact timestamp.
	// Returns a Dictionary: empty if no hit, or {"entity_id": int, "hit_point": Vector3} if hit.
	Dictionary raycast_past(const Vector3 &origin, const Vector3 &direction, int timestamp) const;
};

} // namespace godot

#endif // QN_WORLD_HISTORY_BUFFER_H
