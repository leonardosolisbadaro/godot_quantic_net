extends CharacterBody3D

const SPEED = 5.0
const ROTATION_SPEED = 3.0

var _custom_id := 0

func _ready() -> void:
	# Build CollisionShape3D
	var col = CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var col_shape = CapsuleShape3D.new()
	col.shape = col_shape
	col.position = Vector3(0, 1, 0)
	add_child(col)
	
	# Build MeshInstance3D
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.name = "MeshInstance3D"
	var cap_mesh = CapsuleMesh.new()
	mesh_inst.mesh = cap_mesh
	mesh_inst.position = Vector3(0, 1, 0)
	add_child(mesh_inst)
	
	# Build Camera3D
	var cam = Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 3, 5)
	cam.rotation_degrees = Vector3(-20, 0, 0)
	add_child(cam)
	
	# Only listen to snapbacks for our own character
	QuanticNet.snapback_received.connect(_on_snapback_received)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		var move_dir = Vector2.ZERO
		var rot_delta = 0.0
		
		if Input.is_action_pressed("ui_up"):
			move_dir.y += 1
		if Input.is_action_pressed("ui_down"):
			move_dir.y -= 1
		if Input.is_action_pressed("ui_left"):
			rot_delta += ROTATION_SPEED * delta
		if Input.is_action_pressed("ui_right"):
			rot_delta -= ROTATION_SPEED * delta
		
		rotation.y += rot_delta
		
		var forward = -transform.basis.z
		var velocity_3d = forward * move_dir.y * SPEED
		
		velocity = velocity_3d
		move_and_slide()
		
		QuanticNet.submit_state(global_position, rotation, _custom_id, delta)

func _on_snapback_received(seq: int, srv_pos: Vector3, srv_rot: Vector3, reason: int, replay_inputs: Array) -> void:
	global_position = srv_pos
	rotation = srv_rot
	
	for input in replay_inputs:
		rotation.y += input["rot_delta"]
		
		var forward = -transform.basis.z
		var move_dir_y = input["move"].y
		velocity = forward * move_dir_y * SPEED
		
		global_position += velocity * input["dt"]
