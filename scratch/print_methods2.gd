extends SceneTree
func _init():
	for m in MultiplayerPeerExtension.new().get_method_list():
		if m.name.begins_with("_"):
			print(m.name)
	quit()
