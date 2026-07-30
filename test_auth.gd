extends SceneTree

class MyPeer extends MultiplayerPeerExtension:
	func _get_packet_peer() -> int: return 1
	func _get_packet_channel() -> int: return 0
	func _get_packet_mode() -> int: return 2
	func _put_packet_script(data: PackedByteArray) -> Error:
		print("PUT PACKET: ", data.hex_encode())
		return OK
	func _get_connection_status() -> int: return 2
	func _get_unique_id() -> int: return 2

func _init():
	var peer = MyPeer.new()
	var api = SceneMultiplayer.new()
	api.multiplayer_peer = peer
	api.auth_callback = func(id, data): pass
	peer.peer_connected.emit(1)
	quit()
