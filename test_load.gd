extends SceneTree
func _init():
	var peer = load("res://addons/quantic_net/src/infrastructure/qn_net_hook.gd")
	if peer:
		print("SUCCESS")
	else:
		print("FAILED")
	quit()
