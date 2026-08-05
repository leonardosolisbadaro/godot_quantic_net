#ifndef QN_HOST_SESSION_H
#define QN_HOST_SESSION_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <deque>

#include "core/qn_priority_accumulator.hpp"
#include "core/qn_entity_profile.hpp"

namespace godot {

class QNHostSession : public RefCounted {
	GDCLASS(QNHostSession, RefCounted)

private:
	static const int SNAPBACK_REASON_CLAMP = 1;
	static const int SNAPBACK_REASON_REJECT = 2;

	Dictionary _registry;
	int _server_seq;
	std::deque<Dictionary> _world_history;
	Ref<QNPriorityAccumulator> _accumulator;
	
	Dictionary _stats;
	Ref<RefCounted> validator;

protected:
	static void _bind_methods();

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
	void on_peer_disconnected(int peer_id);
	
	void on_client_snapshot(int peer_id, const PackedByteArray &data, int now);
	void tick_broadcast(int now);
	
	Dictionary get_registry();
};

} // namespace godot

#endif // QN_HOST_SESSION_H
