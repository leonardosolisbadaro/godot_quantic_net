extends Node3D

var owner_id := 0

func _ready() -> void:
	# Build MeshInstance3D with Red Color
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	
	var cap_mesh = CapsuleMesh.new()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	cap_mesh.material = mat
	
	mesh_inst.mesh = cap_mesh
	mesh_inst.position = Vector3(0, 1, 0)
	add_child(mesh_inst)

func _physics_process(_delta: float) -> void:
	if owner_id == 0: return
	
	var state = QuanticNet.remote_state(owner_id)
	
	if not state.is_empty():
		global_position = state["pos"]
		rotation = state["rot"]
