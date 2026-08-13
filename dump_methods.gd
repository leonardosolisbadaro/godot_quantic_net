extends SceneTree
func _init():
    print("METHODS OF QNHostSession:")
    for m in ClassDB.class_get_method_list("QNHostSession"):
        print(m.name)
    print("METHODS OF QNSpatialGrid:")
    for m in ClassDB.class_get_method_list("QNSpatialGrid"):
        print(m.name)
    quit()
