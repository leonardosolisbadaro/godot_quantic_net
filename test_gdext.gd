extends SceneTree

func _init():
    print("Testing GDExtension Registration...")
    
    var wire = QNWirePeer.new()
    var bootstrap = QNDTLSBootstrap.new()
    
    print("Classes loaded successfully! Migrated core instances created.")
    
    quit()

