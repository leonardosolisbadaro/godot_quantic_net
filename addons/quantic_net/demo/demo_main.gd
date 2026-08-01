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
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
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
		_setup_server_props()
	else:
		var netem := "--netem" in args
		QuanticNet.join("127.0.0.1", PORT, SECRET, netem)
		QuanticNet.set_netem_config(0.10, 150, 50) # 10% perda, 150ms atraso, 50ms jitter
		print("[DEMO] Cliente conectando (netem=%s) [Pressione 'N' para alternar]" % ("true" if netem else "false"))
		_setup_client_scene()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			QuanticNet.toggle_netem()
		elif event.keycode == KEY_L:
			if Engine.max_fps == 0:
				Engine.max_fps = 60
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print("[DEMO] FPS Limitado: ", "SIM (60)" if Engine.max_fps == 60 else "NAO (Unlimited)")

func _setup_server_props() -> void:
	# Cria 100 entidades (props) que existem apenas no servidor
	# Perfil customizado para a Demo: 5Hz, prioridade 1.0, e Cull Radius de apenas 5 metros!
	var prop_profile = QuanticNet.NetProfile.new(5.0, 1.0, 5.0) 
	
	for i in range(100):
		var prop_id = 1000 + i
		QuanticNet.register_entity(prop_id, false, true, prop_profile)
		
		# Distribui em círculo amplo para que a distância influencie no despache
		var angle = (i / 100.0) * TAU
		var radius = 10.0 + randf_range(-2, 2)
		QuanticNet.get_registry()[prop_id].pos = Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)
		
		_on_peer_joined(prop_id)

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
	
	if id == QuanticNet.get_unique_id():
		mat.albedo_color = Color.GREEN # Jogador Local
	elif id >= 1000:
		mat.albedo_color = Color.RED # Props (NPCs) do Servidor
	else:
		mat.albedo_color = Color(1.0, 0.5, 0.0) # Laranja para Outros Clientes
		
	mesh.material = mat
	cube.mesh = mesh
	
	if id == QuanticNet.get_unique_id() or QuanticNet.is_server():
		cube.position = Vector3(randf_range(-3, 3), 0.5, randf_range(-3, 3))
	else:
		cube.visible = false
		
	cube.name = "Cube_%d" % id
	add_child(cube)
	cubes[id] = cube
	
	if id == QuanticNet.get_unique_id():
		# Adiciona uma área translúcida ao redor do jogador para visualizar o Cull Radius (5m)
		var area = MeshInstance3D.new()
		var area_mesh = CylinderMesh.new()
		area_mesh.top_radius = 5.0
		area_mesh.bottom_radius = 5.0
		area_mesh.height = 0.05
		
		var area_mat = StandardMaterial3D.new()
		area_mat.albedo_color = Color(0.0, 0.5, 1.0, 0.25) # Azul preenchido semi-transparente
		area_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		area_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		area.mesh = area_mesh
		area.position.y = -0.45 # Fica quase rente ao chão
		cube.add_child(area)
		
	print("[DEMO] peer %d ganhou cubo" % id)

func _on_peer_left(id: int) -> void:
	if cubes.has(id):
		cubes[id].queue_free()
		cubes.erase(id)

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().quit()
	if Input.is_action_just_pressed("ui_accept"):
		auto_move = not auto_move
		print("[DEMO] Auto-move: ", auto_move)
		
	# Servidor: Atualiza fisicamente os 100 props (bots) em movimento contínuo
	if QuanticNet.is_server():
		auto_time += delta
		var reg = QuanticNet.get_registry()
		var server_now = Time.get_ticks_msec()
		
		for i in range(100):
			var prop_id = 1000 + i
			if reg.has(prop_id):
				var p = reg[prop_id]
				var angle = (i / 100.0) * TAU + auto_time * 0.2
				var radius = 10.0 + sin(auto_time * 0.5 + i) * 2.0
				p.pos.x = cos(angle) * radius
				p.pos.z = sin(angle) * radius
				p.ts = server_now
				_on_state(prop_id, p.pos, p.rot, 0)
			
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

func _process(delta: float) -> void:
	if QuanticNet.is_server():
		return
		
	var fps := Engine.get_frames_per_second()
	var mode := "LOCKED 60" if Engine.max_fps == 60 else "UNLIMITED"
	DisplayServer.window_set_title("QuanticNet Client - %d FPS [%s]" % [fps, mode])

	# Aplica estado interpolado de peers remotos puramente no frame visual (desacoplado de fisica).
	var my_id := QuanticNet.get_unique_id()
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
		
	if not QuanticNet.is_server() and cubes.has(owner) and not cubes[owner].visible:
		cubes[owner].position = pos
		cubes[owner].rotation = rot
		cubes[owner].visible = true
		
	# No servidor, atualiza cubos diretamente.
	if QuanticNet.is_server() and cubes.has(owner):
		cubes[owner].position = pos
		cubes[owner].rotation = rot

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	print("[DEMO] snapback (seq=%d reason=%d replay=%d)" % [seq, reason, replay.size()])
