extends SceneTree

func _init():
	var h = MultiplayerAPIExtension.new()
	for sig in h.get_signal_list():
		print(sig.name)
	print("OK")
	quit()
