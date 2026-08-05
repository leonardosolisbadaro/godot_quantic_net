#include "qn_net_hook.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

QNNetHook::QNNetHook() {
	base.instantiate();
	
	base->connect("connected_to_server", callable_mp(this, &QNNetHook::_on_connected_to_server));
	base->connect("connection_failed", callable_mp(this, &QNNetHook::_on_connection_failed));
	base->connect("server_disconnected", callable_mp(this, &QNNetHook::_on_server_disconnected));
	base->connect("peer_connected", callable_mp(this, &QNNetHook::_on_peer_connected));
	base->connect("peer_disconnected", callable_mp(this, &QNNetHook::_on_peer_disconnected));
	base->connect("peer_authenticating", callable_mp(this, &QNNetHook::_on_peer_authenticating));
	base->connect("peer_packet", callable_mp(this, &QNNetHook::_on_peer_packet));
}

QNNetHook::~QNNetHook() {
	close();
}

void QNNetHook::_bind_methods() {
	ClassDB::bind_method(D_METHOD("close"), &QNNetHook::close);
	ClassDB::bind_method(D_METHOD("get_base"), &QNNetHook::get_base);
	ClassDB::bind_method(D_METHOD("set_hooks", "outgoing_rpc", "incoming_packet", "outgoing_packet", "config_add"), &QNNetHook::set_hooks);
	ClassDB::bind_method(D_METHOD("send_custom", "to_peer", "data", "channel", "mode"), &QNNetHook::send_custom, DEFVAL(1), DEFVAL(MultiplayerPeer::TRANSFER_MODE_UNRELIABLE));
	
	ADD_SIGNAL(MethodInfo("peer_authenticating", PropertyInfo(Variant::INT, "id")));
	ADD_SIGNAL(MethodInfo("peer_authentication_failed", PropertyInfo(Variant::INT, "id")));
	ADD_SIGNAL(MethodInfo("custom_packet", PropertyInfo(Variant::INT, "from_peer"), PropertyInfo(Variant::PACKED_BYTE_ARRAY, "data"), PropertyInfo(Variant::INT, "channel")));
}

void QNNetHook::close() {
	if (base.is_valid()) {
		base->disconnect("connected_to_server", callable_mp(this, &QNNetHook::_on_connected_to_server));
		base->disconnect("connection_failed", callable_mp(this, &QNNetHook::_on_connection_failed));
		base->disconnect("server_disconnected", callable_mp(this, &QNNetHook::_on_server_disconnected));
		base->disconnect("peer_connected", callable_mp(this, &QNNetHook::_on_peer_connected));
		base->disconnect("peer_disconnected", callable_mp(this, &QNNetHook::_on_peer_disconnected));
		base->disconnect("peer_authenticating", callable_mp(this, &QNNetHook::_on_peer_authenticating));
		base->disconnect("peer_packet", callable_mp(this, &QNNetHook::_on_peer_packet));
		
		base->set_multiplayer_peer(Ref<MultiplayerPeer>());
		base.unref();
	}
	on_outgoing_rpc = Callable();
	on_incoming_packet = Callable();
	on_outgoing_packet = Callable();
	on_config_add = Callable();
}

Ref<SceneMultiplayer> QNNetHook::get_base() const {
	return base;
}

void QNNetHook::set_hooks(Callable p_outgoing_rpc, Callable p_incoming_packet, Callable p_outgoing_packet, Callable p_config_add) {
	on_outgoing_rpc = p_outgoing_rpc;
	on_incoming_packet = p_incoming_packet;
	on_outgoing_packet = p_outgoing_packet;
	on_config_add = p_config_add;
}

void QNNetHook::_on_connected_to_server() {
	emit_signal("connected_to_server");
}
void QNNetHook::_on_connection_failed() {
	emit_signal("connection_failed");
}
void QNNetHook::_on_server_disconnected() {
	emit_signal("server_disconnected");
}
void QNNetHook::_on_peer_connected(int id) {
	emit_signal("peer_connected", id);
}
void QNNetHook::_on_peer_disconnected(int id) {
	emit_signal("peer_disconnected", id);
}
void QNNetHook::_on_peer_authenticating(int id) {
	emit_signal("peer_authenticating", id);
}
void QNNetHook::_on_peer_packet(int id, const PackedByteArray &data) {
	PackedByteArray packet = data;
	if (on_incoming_packet.is_valid()) {
		Variant filtered = on_incoming_packet.call(id, packet);
		if (filtered.get_type() == Variant::NIL) return;
		packet = filtered;
	}
	emit_signal("custom_packet", id, packet, 1);
}

Error QNNetHook::_poll() {
	if (base.is_null()) return ERR_UNCONFIGURED;
	return base->poll();
}

Error QNNetHook::_rpc(int32_t p_peer, Object *p_object, const StringName &p_method, const Array &p_args) {
	if (base.is_null()) return ERR_UNCONFIGURED;
	if (on_outgoing_rpc.is_valid()) {
		Variant ret = on_outgoing_rpc.call(p_peer, p_object, p_method, p_args);
		if (!ret.operator bool()) {
			return OK; // Discarded by hook
		}
	}
	return base->rpc(p_peer, p_object, p_method, p_args);
}

Error QNNetHook::_object_configuration_add(Object *p_object, const Variant &p_config) {
	if (base.is_null()) return ERR_UNCONFIGURED;
	if (on_config_add.is_valid()) {
		on_config_add.call(p_object, p_config);
	}
	return base->object_configuration_add(p_object, p_config);
}

Error QNNetHook::_object_configuration_remove(Object *p_object, const Variant &p_config) {
	if (base.is_null()) return ERR_UNCONFIGURED;
	return base->object_configuration_remove(p_object, p_config);
}

Error QNNetHook::send_custom(int to_peer, PackedByteArray data, int channel, int mode) {
	if (base.is_null()) return ERR_UNCONFIGURED;
	if (on_outgoing_packet.is_valid()) {
		Variant filtered = on_outgoing_packet.call(to_peer, data);
		if (filtered.get_type() == Variant::NIL) {
			return OK;
		}
		data = filtered;
	}
	return base->send_bytes(data, to_peer, (MultiplayerPeer::TransferMode)mode, channel);
}

void QNNetHook::_set_multiplayer_peer(const Ref<MultiplayerPeer> &p_peer) {
	if (base.is_valid()) {
		base->set_multiplayer_peer(p_peer);
	}
}

Ref<MultiplayerPeer> QNNetHook::_get_multiplayer_peer() {
	if (base.is_valid()) {
		return base->get_multiplayer_peer();
	}
	return Ref<MultiplayerPeer>();
}

int32_t QNNetHook::_get_unique_id() const {
	if (base.is_valid()) {
		return base->get_unique_id();
	}
	return 0;
}

int32_t QNNetHook::_get_remote_sender_id() const {
	if (base.is_valid()) {
		return base->get_remote_sender_id();
	}
	return 0;
}

PackedInt32Array QNNetHook::_get_peer_ids() const {
	if (base.is_valid()) {
		return base->get_peers();
	}
	return PackedInt32Array();
}
