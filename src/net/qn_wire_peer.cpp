#include "qn_wire_peer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/file_access.hpp>

using namespace godot;

QNWirePeer::QNWirePeer() {
	obfuscate = false;
	netem_enabled = false;
	netem_loss_pct = 0.0;
	netem_latency_ms = 0;
	netem_jitter_ms = 0;
	netem_dup_pct = 0.0;
	_next_id = 2;
	_is_server_flag = false;
	_client_id = 2;
	_status = CONNECTION_DISCONNECTED;
	_target_peer = 0;
	_transfer_channel = 0;
	_transfer_mode = TRANSFER_MODE_UNRELIABLE;
	_refusing_connections = false;
	_current_packet_peer = 0;
	_current_packet_channel = 0;
}

QNWirePeer::~QNWirePeer() {
}

void QNWirePeer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "enet", "is_server"), &QNWirePeer::initialize);
	ClassDB::bind_method(D_METHOD("set_netem_config", "enabled", "loss", "latency", "jitter", "dup"), &QNWirePeer::set_netem_config);
	ClassDB::bind_method(D_METHOD("set_client_id", "id"), &QNWirePeer::set_client_id);
	ClassDB::bind_method(D_METHOD("set_obfuscate", "p_obfuscate"), &QNWirePeer::set_obfuscate);
}

void QNWirePeer::initialize(const Ref<ENetConnection> &p_enet, bool p_is_server) {
	_is_server_flag = p_is_server;
	if (p_enet.is_valid()) {
		enet = p_enet;
		_status = _is_server_flag ? CONNECTION_CONNECTED : CONNECTION_CONNECTING;
		_worker_running = true;
		_worker_thread = std::thread(&QNWirePeer::_worker_loop, this);
	}
}

void QNWirePeer::set_netem_config(bool enabled, double loss, int latency, int jitter, double dup) {
	netem_enabled = enabled;
	netem_loss_pct = loss;
	netem_latency_ms = latency;
	netem_jitter_ms = jitter;
	netem_dup_pct = dup;
}

void QNWirePeer::set_client_id(int id) {
	_client_id = id;
}

void QNWirePeer::set_obfuscate(bool p_obfuscate) {
	obfuscate = p_obfuscate;
}

PackedByteArray QNWirePeer::_encode(int vchannel, const PackedByteArray &payload) {
	int flags = 0;
	PackedByteArray body = payload;
	
	if (body.size() > 16) {
		PackedByteArray comp = body.compress(FileAccess::COMPRESSION_DEFLATE);
		if (comp.size() < body.size()) {
			body = comp;
			flags |= FLAG_COMPRESS;
		}
	}
			
	if (obfuscate) {
		flags |= FLAG_OBFUSCATE;
		uint8_t *ptr = body.ptrw();
		for (int i = 0; i < body.size(); i++) {
			ptr[i] ^= 0x5A;
		}
	}
	
	PackedByteArray w;
	w.resize(5);
	w.encode_u16(0, MAGIC);
	w.encode_u8(2, WIRE_VER);
	w.encode_u8(3, vchannel);
	w.encode_u8(4, flags);
	w.append_array(body);
	return w;
}

PackedByteArray QNWirePeer::_decode(const PackedByteArray &wire) {
	if (wire.size() < 5) {
		return PackedByteArray();
	}
		
	int magic = wire.decode_u16(0);
	if (magic != MAGIC) {
		return PackedByteArray();
	}
		
	int version = wire.decode_u8(2);
	if (version != WIRE_VER) {
		return PackedByteArray();
	}
		
	int flags = wire.decode_u8(4);
	PackedByteArray payload = wire.slice(5);
	
	if (flags & FLAG_OBFUSCATE) {
		uint8_t *ptr = payload.ptrw();
		for (int i = 0; i < payload.size(); i++) {
			ptr[i] ^= 0x5A;
		}
	}
			
	if (flags & FLAG_COMPRESS) {
		PackedByteArray decomp = payload.decompress_dynamic(-1, FileAccess::COMPRESSION_DEFLATE);
		if (decomp.is_empty()) {
			decomp = payload.decompress_dynamic(65536, FileAccess::COMPRESSION_DEFLATE);
		}
		
		if (!decomp.is_empty()) {
			payload = decomp;
		} else {
			return PackedByteArray();
		}
	}
	return payload;
}

void QNWirePeer::_queue_netem(int vchannel, const PackedByteArray &payload, uint64_t current_ts) {
	int copies = 1;
	if (netem_enabled) {
		if (netem_loss_pct > 0.0 && UtilityFunctions::randf() < netem_loss_pct) {
			return;
		}
		if (netem_dup_pct > 0.0 && UtilityFunctions::randf() < netem_dup_pct) {
			copies = 2;
		}
	}
			
	for (int i = 0; i < copies; i++) {
		int delay = netem_latency_ms;
		if (netem_jitter_ms > 0) {
			int jitter = (int)UtilityFunctions::randfn(0.0, (double)netem_jitter_ms);
			delay += jitter;
			if (delay < 0) {
				delay = 0;
			}
		}
				
		NetemPacket pkt;
		pkt.channel = vchannel;
		pkt.payload = payload;
		pkt.release_ts = current_ts + delay;
		pkt.target = _target_peer;
		pkt.flag = (_transfer_mode == TRANSFER_MODE_RELIABLE) ? ENetPacketPeer::FLAG_RELIABLE : ENetPacketPeer::FLAG_UNSEQUENCED;
		_outbound_ring.push(pkt);
	}
}

void QNWirePeer::_drain_worker_netem(uint64_t current_ts) {
	std::deque<NetemPacket> ready;
	std::deque<NetemPacket> remaining;
	
	for (const NetemPacket &pkt : _worker_netem_queue) {
		if (pkt.release_ts <= current_ts) {
			ready.push_back(pkt);
		} else {
			remaining.push_back(pkt);
		}
	}
			
	for (NetemPacket &pkt : ready) {
		_worker_send_packet(pkt.payload, pkt.target, pkt.channel, pkt.flag);
		pkt.payload.clear(); // Fix memory leak
	}
		
	_worker_netem_queue = remaining;
}

void QNWirePeer::_worker_send_packet(const PackedByteArray &payload, int target, int channel, int flag) {
	if (enet.is_null()) return;
	
	if (target == 0) {
		enet->broadcast(channel, payload, flag);
	} else {
		if (_worker_id_to_ep.find(target) != _worker_id_to_ep.end()) {
			Ref<ENetPacketPeer> ep = _worker_id_to_ep[target];
			if (ep.is_valid()) {
				ep->send(channel, payload, flag);
			}
		}
	}
}

Error QNWirePeer::_put_packet(const uint8_t *p_buffer, int32_t p_buffer_size) {
	PackedByteArray b;
	b.resize(p_buffer_size);
	memcpy(b.ptrw(), p_buffer, p_buffer_size);
	return _put_packet_script(b);
}

Error QNWirePeer::_put_packet_script(const PackedByteArray &p_buffer) {
	uint64_t current_ts = Time::get_singleton()->get_ticks_msec();
	PackedByteArray encoded = _encode(_transfer_channel, p_buffer);
	_queue_netem(_transfer_channel, encoded, current_ts);
	return OK;
}

Error QNWirePeer::_get_packet(const uint8_t **r_buffer, int32_t *r_buffer_size) {
	current_out_packet = _get_packet_script();
	*r_buffer = current_out_packet.ptr();
	*r_buffer_size = current_out_packet.size();
	return OK;
}

PackedByteArray QNWirePeer::_get_packet_script() {
	if (_in_queue.size() > 0) {
		InPacket pkt = _in_queue.front();
		_in_queue.front().data.clear(); // Explicitly clear before pop to prevent leak
		_in_queue.pop_front();
		_current_packet_peer = pkt.peer;
		_current_packet_channel = pkt.channel;
		return pkt.data;
	}
	return PackedByteArray();
}

int32_t QNWirePeer::_get_available_packet_count() const {
	return _in_queue.size();
}

int32_t QNWirePeer::_get_max_packet_size() const {
	return 1048576;
}

int32_t QNWirePeer::_get_packet_channel() const {
	if (_in_queue.size() > 0) {
		return _in_queue.front().channel;
	}
	return _current_packet_channel;
}

MultiplayerPeer::TransferMode QNWirePeer::_get_packet_mode() const {
	return TRANSFER_MODE_RELIABLE;
}

void QNWirePeer::_set_transfer_channel(int32_t p_channel) {
	_transfer_channel = p_channel;
}

int32_t QNWirePeer::_get_transfer_channel() const {
	return _transfer_channel;
}

void QNWirePeer::_set_transfer_mode(MultiplayerPeer::TransferMode p_mode) {
	_transfer_mode = p_mode;
}

MultiplayerPeer::TransferMode QNWirePeer::_get_transfer_mode() const {
	return _transfer_mode;
}

void QNWirePeer::_set_target_peer(int32_t p_peer) {
	_target_peer = p_peer;
}

int32_t QNWirePeer::_get_packet_peer() const {
	if (_in_queue.size() > 0) {
		return _in_queue.front().peer;
	}
	return _current_packet_peer;
}

bool QNWirePeer::_is_server() const {
	return _is_server_flag;
}

void QNWirePeer::_close() {
	if (_worker_running.load()) {
		_worker_running = false;
		if (_worker_thread.joinable()) {
			_worker_thread.join();
		}
	}
	_worker_ep_to_id.clear();
	_worker_id_to_ep.clear();
	_worker_netem_queue.clear();
}

void QNWirePeer::_disconnect_peer(int32_t p_peer, bool p_force) {
	NetemPacket pkt;
	pkt.channel = p_force ? -10 : -11;
	pkt.target = p_peer;
	_outbound_ring.push(pkt);
}

int32_t QNWirePeer::_get_unique_id() const {
	return _is_server_flag ? 1 : _client_id;
}

void QNWirePeer::_set_refuse_new_connections(bool p_enable) {
	_refusing_connections = p_enable;
}

bool QNWirePeer::_is_refusing_new_connections() const {
	return _refusing_connections;
}

bool QNWirePeer::_is_server_relay_supported() const {
	return false;
}

MultiplayerPeer::ConnectionStatus QNWirePeer::_get_connection_status() const {
	return _status;
}

void QNWirePeer::_worker_loop() {
	while (_worker_running.load()) {
		if (enet.is_null()) {
			std::this_thread::sleep_for(std::chrono::milliseconds(5));
			continue;
		}

		NetemPacket out_pkt;
		while (_outbound_ring.pop(out_pkt)) {
			if (out_pkt.channel == -10 || out_pkt.channel == -11) {
				if (_worker_id_to_ep.find(out_pkt.target) != _worker_id_to_ep.end()) {
					Ref<ENetPacketPeer> ep = _worker_id_to_ep[out_pkt.target];
					if (ep.is_valid()) {
						if (out_pkt.channel == -10) ep->peer_disconnect_now();
						else ep->peer_disconnect();
					}
				}
			} else {
				_worker_netem_queue.push_back(out_pkt);
			}
		}

		uint64_t current_ts = Time::get_singleton()->get_ticks_msec();
		_drain_worker_netem(current_ts);

		Array event = enet->service(1);
		while (event.size() > 0 && (int)event[0] != ENetConnection::EVENT_NONE) {
			int type = event[0];
			if (type == ENetConnection::EVENT_ERROR) break;
			
			Ref<ENetPacketPeer> ep = event[1];
			if (ep.is_valid()) {
				uint64_t ep_id = ep->get_instance_id();
				
				if (type == ENetConnection::EVENT_CONNECT) {
					int id = _is_server_flag ? _next_id++ : 1;
					_worker_ep_to_id[ep_id] = id;
					_worker_id_to_ep[id] = ep;
					
					InPacket conn_pkt;
					conn_pkt.channel = -1;
					conn_pkt.peer = id;
					_inbound_ring.push(conn_pkt);
					
				} else if (type == ENetConnection::EVENT_DISCONNECT) {
					if (_worker_ep_to_id.find(ep_id) != _worker_ep_to_id.end()) {
						int id = _worker_ep_to_id[ep_id];
						InPacket disc_pkt;
						disc_pkt.channel = -2;
						disc_pkt.peer = id;
						_inbound_ring.push(disc_pkt);
						
						_worker_ep_to_id.erase(ep_id);
						_worker_id_to_ep.erase(id);
					}
				} else if (type == ENetConnection::EVENT_RECEIVE) {
					if (_worker_ep_to_id.find(ep_id) != _worker_ep_to_id.end()) {
						PackedByteArray data = ep->get_packet();
						PackedByteArray decoded = _decode(data);
						if (decoded.size() > 0) {
							InPacket in_pkt;
							in_pkt.peer = _worker_ep_to_id[ep_id];
							in_pkt.data = decoded;
							in_pkt.channel = event[2];
							_inbound_ring.push(in_pkt);
						}
					}
				}
			}
			
			event = enet->service(0);
		}
		
		// Constraint de CPU: Previne que a Worker Thread assuma 100% de uso do núcleo 
		// caso o select() nativo do ENet retorne imediatamente (ex: sem pacotes entrantes mas muitos sainteis).
		// Dormir por 1ms garante que a thread ceda tempo para a GPU e a Godot Engine (Evitando congelamentos).
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
}

void QNWirePeer::_poll() {
	InPacket pkt;
	while (_inbound_ring.pop(pkt)) {
		if (pkt.channel == -1) {
			if (!_is_server_flag) {
				_status = CONNECTION_CONNECTED;
			}
			emit_signal("peer_connected", pkt.peer);
		} else if (pkt.channel == -2) {
			if (!_is_server_flag) {
				_status = CONNECTION_DISCONNECTED;
			}
			emit_signal("peer_disconnected", pkt.peer);
		} else {
			_in_queue.push_back(pkt);
		}
	}
}
