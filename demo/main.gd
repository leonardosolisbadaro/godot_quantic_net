extends Node

var host_btn: Button
var join_btn: Button
var world: Node3D

var PORT = 9999
const SECRET = "qnet_demo_secret"
var _players := {}

func _ready() -> void:
	# Build UI
	var ui = CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = 200
	vbox.offset_bottom = 100
	ui.add_child(vbox)
	
	host_btn = Button.new()
	host_btn.name = "HostButton"
	host_btn.text = "Host"
	vbox.add_child(host_btn)
	
	join_btn = Button.new()
	join_btn.name = "JoinButton"
	join_btn.text = "Join"
	vbox.add_child(join_btn)
	
	# Build World
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	
	var ground = MeshInstance3D.new()
	ground.name = "Ground"
	var p_mesh = PlaneMesh.new()
	p_mesh.size = Vector2(50, 50)
	ground.mesh = p_mesh
	world.add_child(ground)
	
	var light = DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	light.shadow_enabled = true
	light.transform = Transform3D(Basis().rotated(Vector3(1, 0, 0), -PI/4), Vector3(0, 10, 0))
	world.add_child(light)
	
	# Connect signals
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)

func _on_host_pressed() -> void:
	var err = QuanticNet.host(PORT, SECRET)
	if err == OK:
		host_btn.disabled = true
		join_btn.disabled = true
		_spawn_local_player(1)
	else:
		print("Failed to host: ", err)

func _on_join_pressed() -> void:
	var err = QuanticNet.join("127.0.0.1", PORT, SECRET)
	if err == OK:
		host_btn.disabled = true
		join_btn.disabled = true
	else:
		print("Failed to join: ", err)

func _on_peer_joined(id: int) -> void:
	print("Peer joined: ", id)
	if id == multiplayer.get_unique_id():
		_spawn_local_player(id)
	else:
		_spawn_remote_player(id)

func _on_peer_left(id: int) -> void:
	print("Peer left: ", id)
	if _players.has(id):
		_players[id].queue_free()
		_players.erase(id)

func _spawn_local_player(id: int) -> void:
	if _players.has(id): return
	var player_script = preload("res://demo/player.gd")
	var p = CharacterBody3D.new()
	p.set_script(player_script)
	p.name = str(id)
	p.position = Vector3(randf_range(-2, 2), 1, randf_range(-2, 2))
	world.add_child(p)
	_players[id] = p

func _spawn_remote_player(id: int) -> void:
	if _players.has(id): return
	var remote_script = preload("res://demo/remote_player.gd")
	var p = Node3D.new()
	p.set_script(remote_script)
	p.name = str(id)
	p.set("owner_id", id) # Since script is attached dynamically, we use set() to be safe before _ready
	world.add_child(p)
	_players[id] = p
