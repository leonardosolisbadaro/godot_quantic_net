extends SceneTree
class MyPeer extends MultiplayerPeerExtension:
	func _get_connection_status(): return MultiplayerPeer.CONNECTION_CONNECTED
	func _get_unique_id(): return 1
	func _get_max_packet_size(): return 1024
	func _get_available_packet_count(): return 1
	func _get_packet_script() -> PackedByteArray:
		print("GET PACKET SCRIPT CALLED!")
		return PackedByteArray([1, 2, 3])
	func _get_packet_peer(): return 2
	
func _init():
	var peer = MyPeer.new()
	var api = SceneMultiplayer.new()
	api.multiplayer_peer = peer
	peer.peer_connected.emit(2)
	api.poll()
	quit()
