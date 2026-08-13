extends SceneTree
func _init():
    var methods = ClassDB.class_get_method_list("QNSpatialGrid")
    for m in methods:
        if m.name == "set_world_bounds":
            print("ARGS FOR set_world_bounds:")
            for arg in m.args:
                print(arg.name, arg.type)
    quit()
