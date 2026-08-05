#ifndef QN_NET_HOOK_H
#define QN_NET_HOOK_H

#include <godot_cpp/classes/multiplayer_api_extension.hpp>
#include <godot_cpp/classes/scene_multiplayer.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

namespace godot {

class QNNetHook : public MultiplayerAPIExtension {
	GDCLASS(QNNetHook, MultiplayerAPIExtension)

private:
	Ref<SceneMultiplayer> base;

	Callable on_outgoing_rpc;
	Callable on_incoming_packet;
	Callable on_outgoing_packet;
	Callable on_config_add;

	void _on_connected_to_server();
	void _on_connection_failed();
	void _on_server_disconnected();
	void _on_peer_connected(int id);
	void _on_peer_disconnected(int id);
	void _on_peer_authenticating(int id);
	void _on_peer_packet(int id, const PackedByteArray &data);

protected:
	static void _bind_methods();

public:
	QNNetHook();
	~QNNetHook();

	void close();
	Ref<SceneMultiplayer> get_base() const;
	void set_hooks(Callable p_outgoing_rpc, Callable p_incoming_packet, Callable p_outgoing_packet, Callable p_config_add);

	Error send_custom(int to_peer, PackedByteArray data, int channel = 1, int mode = MultiplayerPeer::TRANSFER_MODE_UNRELIABLE);

	// Overrides
	virtual Error _poll() override;
	virtual Error _rpc(int32_t p_peer, Object *p_object, const StringName &p_method, const Array &p_args) override;
	virtual Error _object_configuration_add(Object *p_object, const Variant &p_config) override;
	virtual Error _object_configuration_remove(Object *p_object, const Variant &p_config) override;
	virtual void _set_multiplayer_peer(const Ref<MultiplayerPeer> &p_peer) override;
	virtual Ref<MultiplayerPeer> _get_multiplayer_peer() override;
	virtual int32_t _get_unique_id() const override;
	virtual PackedInt32Array _get_peer_ids() const override;
	virtual int32_t _get_remote_sender_id() const override;
};

} // namespace godot

#endif // QN_NET_HOOK_H
