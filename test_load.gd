extends SceneTree

func _init():
	var script = load("res://addons/quantic_net/src/infrastructure/quantic_net_autoload.gd")
	if script == null:
		print("FAILED TO LOAD SCRIPT!")
	else:
		print("SCRIPT: ", script)
		var instance = script.new()
		print("INSTANCE: ", instance)
	quit()
