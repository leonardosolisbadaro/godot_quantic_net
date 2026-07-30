extends SceneTree

func _init():
	var peer = ENetMultiplayerPeer.new()
	var err = peer.create_client("127.0.0.1", 4444)
	print("create_client err: ", err)
	print("has dtls_client_setup: ", peer.host.has_method("dtls_client_setup"))
	quit()
