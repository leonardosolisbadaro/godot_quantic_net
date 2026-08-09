#ifndef QN_WIRE_PEER_H
#define QN_WIRE_PEER_H

#include <godot_cpp/classes/multiplayer_peer_extension.hpp>
#include <godot_cpp/classes/e_net_connection.hpp>
#include <godot_cpp/classes/e_net_packet_peer.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <deque>
#include <thread>
#include <atomic>
#include <map>
#include "qn_ring_buffer.hpp"

namespace godot {

struct NetemPacket {
	int channel;
	PackedByteArray payload;
	uint64_t release_ts;
	int target;
	int flag;
};

struct InPacket {
	int peer;
	PackedByteArray data;
	int channel;
};

class QNWirePeer : public MultiplayerPeerExtension {
	GDCLASS(QNWirePeer, MultiplayerPeerExtension)

private:
	static const int MAGIC = 0xC0B0;
	static const int WIRE_VER = 1;

	static const int FLAG_COMPRESS = 1;
	static const int FLAG_OBFUSCATE = 2;
	static const int FLAG_BROADCAST = 4;

	static const int CH_CONTROL = 0;
	static const int CH_STATE = 1;
	static const int CH_RELIABLE = 2;

	Ref<ENetConnection> enet;
	bool obfuscate;

	bool netem_enabled;
	double netem_loss_pct;
	int netem_latency_ms;
	int netem_jitter_ms;
	double netem_dup_pct;

	std::deque<InPacket> _in_queue;
	
	// --- Worker Thread Variables ---
	std::thread _worker_thread;
	std::atomic<bool> _worker_running{false};
	SPSCRingBuffer<NetemPacket, 4096> _outbound_ring;
	SPSCRingBuffer<InPacket, 4096> _inbound_ring;
	std::deque<NetemPacket> _worker_netem_queue;
	std::map<uint64_t, int> _worker_ep_to_id;
	std::map<int, Ref<ENetPacketPeer>> _worker_id_to_ep;
	void _worker_loop();
	void _drain_worker_netem(uint64_t current_ts);
	void _worker_send_packet(const PackedByteArray &payload, int target, int channel, int flag);
	// -------------------------------

	int _next_id;
	bool _is_server_flag;
	int _client_id;
	ConnectionStatus _status;

	int _target_peer;
	int _transfer_channel;
	TransferMode _transfer_mode;
	bool _refusing_connections;
	int _current_packet_peer;
	int _current_packet_channel;

	PackedByteArray _encode(int vchannel, const PackedByteArray &payload);
	PackedByteArray _decode(const PackedByteArray &wire);
	void _queue_netem(int vchannel, const PackedByteArray &payload, uint64_t current_ts);

protected:
	static void _bind_methods();

public:
	QNWirePeer();
	~QNWirePeer();

	void initialize(const Ref<ENetConnection> &p_enet, bool p_is_server);
	void set_netem_config(bool enabled, double loss, int latency, int jitter, double dup);
	void set_client_id(int id);
	void set_obfuscate(bool p_obfuscate);

	// Overrides for GDScript compatibility and MultiplayerPeer interface
	virtual Error _get_packet(const uint8_t **r_buffer, int32_t *r_buffer_size) override;
	virtual Error _put_packet(const uint8_t *p_buffer, int32_t p_buffer_size) override;
	virtual int32_t _get_available_packet_count() const override;
	virtual int32_t _get_max_packet_size() const override;

	virtual PackedByteArray _get_packet_script() override;
	virtual Error _put_packet_script(const PackedByteArray &p_buffer) override;

	virtual int32_t _get_packet_channel() const override;
	virtual MultiplayerPeer::TransferMode _get_packet_mode() const override;
	virtual void _set_transfer_channel(int32_t p_channel) override;
	virtual int32_t _get_transfer_channel() const override;
	virtual void _set_transfer_mode(MultiplayerPeer::TransferMode p_mode) override;
	virtual MultiplayerPeer::TransferMode _get_transfer_mode() const override;
	virtual void _set_target_peer(int32_t p_peer) override;
	virtual int32_t _get_packet_peer() const override;
	virtual bool _is_server() const override;
	virtual void _poll() override;
	virtual void _close() override;
	virtual void _disconnect_peer(int32_t p_peer, bool p_force) override;
	virtual int32_t _get_unique_id() const override;
	virtual void _set_refuse_new_connections(bool p_enable) override;
	virtual bool _is_refusing_new_connections() const override;
	virtual bool _is_server_relay_supported() const override;
	virtual ConnectionStatus _get_connection_status() const override;

private:
	PackedByteArray current_out_packet;
};

} // namespace godot

#endif // QN_WIRE_PEER_H
