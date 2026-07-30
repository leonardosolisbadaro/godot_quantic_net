extends SceneTree

class MyPeer extends MultiplayerPeerExtension:
	var q = []
	func _get_packet_peer() -> int:
		print("GET_PACKET_PEER CALLED! q.size = ", q.size())
		if q.size() > 0:
			return q[0].peer
		return 1
	func _get_packet_channel() -> int: return 0
	func _get_packet_mode() -> int: return 2
	func _put_packet_script(data: PackedByteArray) -> Error: return OK
	func _set_target_peer(peer_id: int) -> void: pass
	func _set_transfer_channel(channel: int) -> void: pass
	func _set_transfer_mode(mode: int) -> void: pass
	func _get_connection_status() -> int: return 2
	func _get_unique_id() -> int: return 2
	func _get_available_packet_count() -> int: return q.size()
	func _get_packet_script() -> PackedByteArray:
		print("GET_PACKET_SCRIPT CALLED")
		return q.pop_front().data
	func _poll() -> void: pass

func _init():
	var peer = MyPeer.new()
	var api = SceneMultiplayer.new()
	api.auth_callback = func(id, data): print("AUTH CALLBACK TRIGGERED: ", id, " ", data.hex_encode())
	api.multiplayer_peer = peer
	self.set_multiplayer(api)
	api.connected_to_server.connect(func(): print("EMITTED connected_to_server"))
	api.peer_connected.connect(func(id): print("EMITTED peer_connected: ", id))
	api.peer_authenticating.connect(func(id): print("EMITTED peer_authenticating: ", id))
	
	peer.peer_connected.emit(1)
	api.send_auth(1, "fake".to_utf8_buffer())
	peer.q.append({"peer": 1, "data": "0700".hex_decode()})
	print("POLL RETURN: ", api.poll())
	print("PEERS: ", api.get_peers())
	await self.create_timer(0.5).timeout
	quit()
