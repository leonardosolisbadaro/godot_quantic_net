extends SceneTree

func _init():
	var host = ENetConnection.new()
	host.create_host_bound("127.0.0.1", 9999, 1, 0, 0, 0)
	var cli = ENetConnection.new()
	cli.create_host(1, 0, 0, 0)
	var peer = cli.connect_to_host("127.0.0.1", 9999, 1, 0)
	
	for i in range(10):
		host.service(10)
		cli.service(10)
		
	peer.send(0, PackedByteArray([1, 2, 3]), ENetPacketPeer.FLAG_RELIABLE)
	cli.flush()
	
	for i in range(10):
		var evt = host.service(10)
		if evt.size() > 0 and evt[0] == ENetConnection.EVENT_RECEIVE:
			print("EVT: ", evt)
			print("PACKET: ", evt[1].get_packet())
			break
	quit()
