extends SceneTree
func _init():
	var cls = ClassDB.class_get_method_list("MultiplayerPeerExtension")
	for m in cls:
		if m.name.begins_with("_"):
			var args_str = ""
			for a in m.args:
				args_str += a.name + ": " + str(a.type) + ", "
			print(m.name, " -> ", args_str)
	quit()
