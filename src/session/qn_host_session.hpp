#ifndef QN_HOST_SESSION_H
#define QN_HOST_SESSION_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <deque>
#include <map>

#include "core/qn_priority_accumulator.hpp"
#include "core/qn_entity_profile.hpp"
#include "core/qn_spatial_grid.hpp"
#include "core/qn_world_history_buffer.hpp"

namespace godot {

class QNHostSession : public RefCounted {
	GDCLASS(QNHostSession, RefCounted)

private:
	static const int SNAPBACK_REASON_CLAMP = 1;
	static const int SNAPBACK_REASON_REJECT = 2;

	struct RegionData {
		AABB aabb;
	};

	Dictionary _registry;
	std::map<int, RegionData> _regions; // Region ID -> RegionData
	int _server_seq;
	std::deque<Dictionary> _world_history;
	Ref<QNPriorityAccumulator> _accumulator;
	Ref<QNSpatialGrid> _grid;
	Ref<QNWorldHistoryBuffer> _rewind_buffer;
	std::vector<Dictionary> _dict_pool;
	
	Dictionary _stats;
	Ref<RefCounted> validator;

protected:
	static void _bind_methods();
	Dictionary _get_pooled_dict();

public:
	QNHostSession();
	~QNHostSession();

	void set_validator(const Ref<RefCounted> &v);
	Ref<RefCounted> get_validator() const;
	
	void _on_validator_peer_rejected(int id, String reason, int strikes);

	void register_entity(int entity_id, bool is_peer, bool has_initial_state, Ref<QNEntityProfile> profile = nullptr);
	void on_peer_authenticated(int peer_id, Ref<QNEntityProfile> profile = nullptr);
	void unregister_entity(int entity_id);
	void change_entity_profile(int entity_id, Ref<QNEntityProfile> new_profile);
	void update_entity_state(int entity_id, const Vector3 &pos, const Vector3 &rot, int custom_id, int ts);
	
	void add_region(int region_id, const Vector3 &center, const Vector3 &extents);
	void remove_region(int region_id);
	void clear_regions();
	
	void on_peer_disconnected(int peer_id);
	
	void on_client_snapshot(int peer_id, const PackedByteArray &data, int now);
	void tick_broadcast(int now);
	
	Dictionary query_raycast(const Vector3 &origin, const Vector3 &direction, double max_dist, int timestamp) const;
	Array query_box(const Vector3 &center, const Vector3 &extents, int timestamp) const;
	Array query_sphere(const Vector3 &center, double radius, int timestamp) const;

	Dictionary get_registry();
	Array get_registry_keys() const;
	Vector3 get_entity_position(int entity_id) const;
	Ref<QNSpatialGrid> get_grid() const;
};

} // namespace godot

#endif // QN_HOST_SESSION_H
