extends SceneTree
func _init():
	var peer = load("res://addons/quantic_net/src/adapters/qn_wire_peer.gd")
	if peer:
		print("SUCCESS")
	else:
		print("FAILED")
	quit()
