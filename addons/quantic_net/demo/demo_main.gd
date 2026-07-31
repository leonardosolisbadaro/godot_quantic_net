## @file demo_main.gd
## @path res://addons/quantic_net/demo/demo_main.gd
##
## @description
## Cena demo bare metal do QuanticNet: 1 servidor, 2 clientes com cubos
## sincronizados via host/join/submit_state/remote_state e sinais
## publicos do autoload. Nao conhece internals do plugin.
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.2.0
## @lastModifiedIn 0.2.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends Node3D
## QuanticNet DEMO — Bare Metal
## =============================================
## Este script demonstra o uso MINIMO da API publica do autoload
## `QuanticNet` em um projeto Godot 4.7:
## - 1 servidor autoritativo (host) headless
## - 2 clientes (join) com cubos sincronizados em rede
## Como executar (terminal):
##   Servidor: godot --headless --path . -- --server
##   Cliente 1: godot --path . -- --client
##   Cliente 2: godot --path . -- --client --netem
## O plugin cuida de DTLS, clock-sync, snapback e interpolacao; este
## arquivo cuida SOMENTE da cena e do movimento dos cubos.

const PORT := 4242
const SECRET := "demo-secret"
const SPEED := 2.0

var cubes := {} # peer_id -> MeshInstance3D
var auto_move := true
var auto_time := 0.0


func _ready() -> void:
	# Conecta sinais ANTES de host/join.
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.state_received.connect(_on_state)
	QuanticNet.snapback_received.connect(_on_snapback)
	QuanticNet.pong_received.connect(func(rtt: float, off: float) -> void:
		print("[DEMO] RTT=%.0fms offset=%.1fms" % [rtt, off]))
	# Decide se somos servidor ou cliente usando args da linha de comando.
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		QuanticNet.host(PORT, SECRET, "127.0.0.1", 8)
		print("[DEMO] Servidor na porta %d" % PORT)
	else:
		var netem := "--netem" in args
		QuanticNet.join("127.0.0.1", PORT, SECRET, netem)
		print("[DEMO] Cliente conectando (netem=%s)" % ("true" if netem else "false"))
		_setup_client_scene()

func _setup_client_scene() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 8, 10)
	cam.rotation_degrees = Vector3(-35, 0, 0)
	add_child(cam)
	
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	add_child(light)
	
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 40)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.25)
	plane.material = mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)

func _on_peer_joined(id: int) -> void:
	# Cada peer vira um cubo. O servidor ve todos; o cliente ve todos
	# que o servidor autoriza. O proprio peer ganha um cubo controlavel.
	if cubes.has(id):
		return
	var cube := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.GREEN if id == QuanticNet.get_unique_id() else Color.RED
	mesh.material = mat
	cube.mesh = mesh
	cube.position = Vector3(randf_range(-3, 3), 0.5, randf_range(-3, 3))
	cube.name = "Cube_%d" % id
	add_child(cube)
	cubes[id] = cube
	print("[DEMO] peer %d ganhou cubo" % id)

func _on_peer_left(id: int) -> void:
	if cubes.has(id):
		cubes[id].queue_free()
		cubes.erase(id)

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
	if Input.is_action_just_pressed("ui_accept"):
		auto_move = not auto_move
		print("[DEMO] Auto-move: ", auto_move)
		
	# Servidor nao faz prediction local; so aplica estados validados.
	if QuanticNet.is_server():
		return
	var my_id := QuanticNet.get_unique_id()
	# Prediction local do cubo proprio (id do autoload).
	if my_id > 1 and cubes.has(my_id):
		var cube: MeshInstance3D = cubes[my_id]
		var move := Vector2.ZERO
		
		if auto_move:
			auto_time += delta
			# Simula input direcional em um círculo imperfeito (wobble)
			move.x = cos(auto_time) + cos(auto_time * 2.3) * 0.3
			move.y = sin(auto_time) + sin(auto_time * 1.7) * 0.3
			move = move.normalized()
		else:
			move = Vector2(
				Input.get_axis("ui_left", "ui_right"),
				Input.get_axis("ui_up", "ui_down"))
				
		cube.position.x += move.x * SPEED * delta
		cube.position.z += move.y * SPEED * delta
		# Envia estado para o servidor.
		QuanticNet.submit_state(cube.position, cube.rotation, 0, delta)
	# Aplica estado interpolado de peers remotos.
	for id in cubes.keys():
		if id == my_id:
			continue
		var s := QuanticNet.remote_state(id)
		if not s.is_empty():
			cubes[id].position = s["pos"]
			cubes[id].rotation = s["rot"]

func _on_state(owner: int, pos: Vector3, rot: Vector3, _custom: int) -> void:
	# Cria cubo remoto caso o sinal de peer_connected nativo nao tenha notificado ainda.
	if not QuanticNet.is_server() and not cubes.has(owner) and owner != QuanticNet.get_unique_id():
		_on_peer_joined(owner)
		
	# No servidor, atualiza cubos diretamente.
	if QuanticNet.is_server() and cubes.has(owner):
		cubes[owner].position = pos
		cubes[owner].rotation = rot

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	print("[DEMO] snapback (seq=%d reason=%d replay=%d)" % [seq, reason, replay.size()])
