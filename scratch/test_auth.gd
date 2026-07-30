extends SceneTree

class DummyPeer extends MultiplayerPeerExtension:
	var q = []
	func _get_connection_status(): return MultiplayerPeer.CONNECTION_CONNECTED
	func _get_unique_id(): return 1
	func _get_max_packet_size(): return 1024
	func _get_available_packet_count(): return q.size()
	func _get_packet_peer(): return q[0].peer
	func _get_packet_channel(): return q[0].ch
	func _get_packet_mode(): return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _get_packet_script():
		print("Get packet called!")
		return q.pop_front().data

func _init():
	var peer = DummyPeer.new()
	var api = SceneMultiplayer.new()
	api.multiplayer_peer = peer
	api.auth_callback = Callable(self, "_on_auth")
	peer.peer_connected.emit(2)
	
	# Push an auth packet that exactly mimics the real one
	var pba = PackedByteArray([0x07, 0x00])
	pba.append_array("tok-integracao".to_utf8_buffer())
	peer.q.append({"peer": 2, "ch": 0, "data": pba})
	
	api.poll()
	print("POLL FINISHED. Did auth callback fire?")
	quit()

func _on_auth(id: int, data: PackedByteArray):
	print("AUTH FIRED for ", id, " with data: ", data.get_string_from_utf8())
