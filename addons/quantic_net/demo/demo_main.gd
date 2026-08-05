## @file demo_main.gd
## @path res://addons/quantic_net/demo/demo_main.gd
##
## @description
## Cena demo reconstruída do QuanticNet com ZERO RPCs.
## A demonstração foca 100% no uso da API pública, transmitindo inputs 
## via custom_id (bitmask) e exibindo hits pelo mesmo canal.
##
## @created 2026-08-05
## @updated 2026-08-05
##
## @since 0.5.0
## @lastModifiedIn 0.5.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends Node3D

const PORT := 4242
const SECRET := "demo-secret"

# HUD
var _status_lbl: Label
var _diag_lbl_fps: Label
var _diag_lbl_loss: Label
var _diag_lbl_rtt: Label

# Estado Local
var cubes := {}
var active_bullets := {}
var auto_move := false
var auto_time := 0.0
var _current_rtt := 0.0
var _last_rx := {}

# Server State
var prev_inputs := {}
var hit_timers := {}
var _bullet_counter := 0

# Visuals
var mat_player_local: StandardMaterial3D
var mat_player_remote: StandardMaterial3D
var mat_prop: StandardMaterial3D
var mat_bullet: StandardMaterial3D
var mat_hit: StandardMaterial3D

var _profiles = []

func _create_profile(hz: float, priority: float, cull: float) -> QNEntityProfile:
	var p = QNEntityProfile.new()
	p.init(hz, priority, cull)
	return p

func _ready() -> void:
	# Parse args
	var args = OS.get_cmdline_user_args()
	var is_server = args.has("--server")
	var is_client = args.has("--client")
	var use_netem = args.has("--netem")
	
	if not is_server and not is_client:
		print("Iniciando topologia automática: 1 Servidor, 2 Clientes...")
		is_server = true
		
		# Inicia Cliente 1 (Normal)
		OS.create_instance(["--client"])
		
		# Inicia Cliente 2 (Com Netem)
		OS.create_instance(["--client", "--netem"])
		
		DisplayServer.window_set_title("QuanticNet - SERVER")
		
	if is_client:
		DisplayServer.window_set_title("QuanticNet - CLIENT" + (" (NETEM)" if use_netem else ""))
		
	_setup_materials()
	_setup_ui()
	_setup_scene()
	
	_profiles.push_back(_create_profile(60.0, 1.0, 10.0)) # 0: Padrão
	_profiles.push_back(_create_profile(20.0, 0.5, 50.0)) # 1: Low-tick
	_profiles.push_back(_create_profile(10.0, 0.1, 5.0)) # 2: Background
	_profiles.push_back(_create_profile(10.0, 1.0, 20.0)) # 3: Props
	_profiles.push_back(_create_profile(60.0, 2.0, 100.0)) # 4: Bullets
	
	QuanticNet.connection_state_changed.connect(_on_conn_state)
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.pong_received.connect(func(rtt: float, off: float): _current_rtt = rtt)
	QuanticNet.state_received.connect(_on_state)
	
	if is_server:
		print("Iniciando SERVIDOR QuanticNet (Porta %d)..." % PORT)
		QuanticNet.host(PORT, SECRET)
		_server_spawn_props()
	else:
		print("Iniciando CLIENTE QuanticNet...")
		QuanticNet.join("127.0.0.1", PORT, SECRET)
		
		if use_netem:
			QuanticNet.set_netem_config(10.0, 100, 20) # 10% loss, 100ms latency, 20ms jitter

func _setup_materials() -> void:
	mat_player_local = StandardMaterial3D.new()
	mat_player_local.albedo_color = Color.GREEN
	
	mat_player_remote = StandardMaterial3D.new()
	mat_player_remote.albedo_color = Color.CYAN
	
	mat_prop = StandardMaterial3D.new()
	mat_prop.albedo_color = Color.RED
	
	mat_bullet = StandardMaterial3D.new()
	mat_bullet.albedo_color = Color.YELLOW
	
	mat_hit = StandardMaterial3D.new()
	mat_hit.albedo_color = Color.WHITE
	mat_hit.emission_enabled = true
	mat_hit.emission = Color.WHITE
	mat_hit.emission_energy_multiplier = 2.0

func _setup_scene() -> void:
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

func _setup_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.position = Vector2(20, 20)
	add_child(vbox)
	
	_status_lbl = Label.new()
	_status_lbl.text = "OFFLINE"
	vbox.add_child(_status_lbl)
	
	_diag_lbl_fps = Label.new()
	vbox.add_child(_diag_lbl_fps)
	
	_diag_lbl_rtt = Label.new()
	vbox.add_child(_diag_lbl_rtt)
	
	_diag_lbl_loss = Label.new()
	vbox.add_child(_diag_lbl_loss)
	
	var info = Label.new()
	info.text = "\n[CONTROLES]\nSetas/WASD: Mover\nBotão Esquerdo: Tiro Hitscan (Laser)\nBotão Direito: Projétil (Bala)\nEnter: Auto-Move"
	vbox.add_child(info)

func _on_conn_state(state: int) -> void:
	match state:
		QuanticNet.ConnectionState.DISCONNECTED:
			_status_lbl.text = "⚪ DISCONNECTED"
			_status_lbl.add_theme_color_override("font_color", Color.GRAY)
		QuanticNet.ConnectionState.CONNECTED:
			_status_lbl.text = "🟢 CONNECTED"
			_status_lbl.add_theme_color_override("font_color", Color.GREEN)

func _on_peer_joined(peer_id: int) -> void:
	print("Peer joined: ", peer_id)
	var mesh = BoxMesh.new()
	var cube = MeshInstance3D.new()
	cube.mesh = mesh
	
	if peer_id == QuanticNet.get_unique_id():
		cube.material_override = mat_player_local
	elif peer_id < 1000:
		cube.material_override = mat_player_remote
	else:
		cube.material_override = mat_prop
		
	add_child(cube)
	cubes[peer_id] = cube
	
	if QuanticNet.is_server() and peer_id < 1000:
		QuanticNet.register_entity(peer_id, true, true, _profiles[0])

func _on_peer_left(peer_id: int) -> void:
	print("Peer left: ", peer_id)
	if cubes.has(peer_id):
		cubes[peer_id].queue_free()
		cubes.erase(peer_id)

func _on_state(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
	if not QuanticNet.is_server():
		_last_rx[owner] = Time.get_ticks_msec()
		if not cubes.has(owner) and owner != QuanticNet.get_unique_id():
			_on_peer_joined(owner)

func _server_spawn_props() -> void:
	for i in range(10):
		var prop_id = 1000 + i
		QuanticNet.register_entity(prop_id, false, true, _profiles[3])
		_on_peer_joined(prop_id)

func _calc_prop_pos(offset: int, time: float) -> Vector3:
	var r = 10.0 + (offset % 3) * 5.0
	var speed = 0.5 + (offset % 2) * 0.5
	var angle = time * speed + offset * 0.7
	return Vector3(cos(angle) * r, 0, sin(angle) * r)

func _physics_process(delta: float) -> void:
	_update_ui()
	
	if QuanticNet.is_server():
		_server_physics(delta)
	
	if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		_client_physics(delta)
	
	_apply_visuals()

func _update_ui() -> void:
	if _diag_lbl_fps:
		_diag_lbl_fps.text = "FPS: %d" % Engine.get_frames_per_second()
		if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
			_diag_lbl_rtt.text = "RTT: %dms" % _current_rtt
			_diag_lbl_loss.text = "Loss: %.1f%%" % (QuanticNet.loss_of(1) * 100.0)

# ==============================================================
# FLUXO DO CLIENTE (Client-Side Prediction & API Polling)
# ==============================================================
func _client_physics(delta: float) -> void:
	var my_id = QuanticNet.get_unique_id()
	if not cubes.has(my_id): return
	
	var cube = cubes[my_id]
	var move := Vector2.ZERO
	
	if Input.is_action_just_pressed("ui_accept"):
		auto_move = !auto_move
		
	if auto_move:
		auto_time += delta
		move.x = cos(auto_time) + cos(auto_time * 2.3) * 0.3
		move.y = sin(auto_time) + sin(auto_time * 1.7) * 0.3
		move = move.normalized()
	else:
		move = Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down"))
	
	cube.position.x += move.x * 10.0 * delta
	cube.position.z += move.y * 10.0 * delta
	
	# Input Polling empacotado em custom_id
	var input_mask = 0
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		input_mask |= 1 # Shoot Hitscan
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		input_mask |= 2 # Shoot Projectile
		
	QuanticNet.submit_state(cube.position, cube.rotation, input_mask, delta)

# ==============================================================
# FLUXO DO SERVIDOR (Authoritative Logic)
# ==============================================================
func _server_physics(delta: float) -> void:
	var now = QuanticNet.get_server_time()
	var auto_time_srv = float(now) / 1000.0
	var reg = QuanticNet.get_registry()
	
	# 1. Movimenta Props
	for prop_id in reg.keys():
		if prop_id >= 1000 and prop_id < 20000:
			var new_pos = _calc_prop_pos(prop_id - 1000, auto_time_srv)
			
			# Processa Timer de Hit
			var custom = 0
			if hit_timers.has(prop_id):
				if now >= hit_timers[prop_id]:
					hit_timers.erase(prop_id)
				else:
					custom = 1 # 1 = Hitted
			
			QuanticNet.update_entity_state(prop_id, new_pos, Vector3.ZERO, custom, now)
			
	# 2. Processa Inputs dos Jogadores
	for p_id in reg.keys():
		if p_id < 1000: # Player
			var p_state = reg[p_id]
			if not p_state.has("has_state") or not p_state["has_state"]: continue
			
			var current_input = p_state.get("custom_id", 0)
			var prev_input = prev_inputs.get(p_id, 0)
			var just_pressed = current_input & ~prev_input
			
			if just_pressed & 1:
				_server_execute_hitscan(p_id, p_state)
			
			if just_pressed & 2:
				_server_execute_projectile(p_id, p_state)
				
			prev_inputs[p_id] = current_input

	# 3. Processa Balas Físicas
	var bullets_to_remove = []
	for b_id in active_bullets.keys():
		var b = active_bullets[b_id]
		b.pos += b.dir * b.speed * delta
		b.life -= delta
		
		if b.life <= 0:
			bullets_to_remove.append(b_id)
			continue
			
		var hits = QuanticNet.query_sphere(b.pos, 1.0, now)
		var hit_someone = false
		for hit_id in hits:
			if hit_id >= 1000 and hit_id < 20000:
				hit_timers[hit_id] = now + 150 # Pisca por 150ms
				bullets_to_remove.append(b_id)
				hit_someone = true
				break
				
		if not hit_someone:
			QuanticNet.update_entity_state(b_id, b.pos, Vector3.ZERO, 0, now)
			
	for b_id in bullets_to_remove:
		if active_bullets.has(b_id):
			active_bullets.erase(b_id)
			QuanticNet.unregister_entity(b_id)

func _server_execute_hitscan(p_id: int, p_state: Dictionary) -> void:
	var origin = p_state.pos
	var direction = - Basis.from_euler(p_state.rot).z.normalized()
	
	# Raycast Offset para não acertar o próprio jogador
	var ray_origin = origin + direction * 2.0
	
	# Usa o Timestamp exato em que o cliente disparou o input para o Lag Compensation
	var hit = QuanticNet.query_raycast(ray_origin, direction, 50.0, p_state.ts)
	
	if hit.has("entity_id"):
		var entity_id = hit["entity_id"]
		if entity_id >= 1000 and entity_id < 20000 and entity_id != p_id:
			hit_timers[entity_id] = QuanticNet.get_server_time() + 150

func _server_execute_projectile(p_id: int, p_state: Dictionary) -> void:
	var origin = p_state.pos
	var direction = - Basis.from_euler(p_state.rot).z.normalized()
	
	_bullet_counter += 1
	var b_id = 20000 + (p_id * 1000) + (_bullet_counter % 1000)
	
	active_bullets[b_id] = {
		"pos": origin + direction * 2.0,
		"dir": direction,
		"speed": 40.0,
		"life": 3.0
	}
	QuanticNet.register_entity(b_id, false, true, _profiles[4])

# ==============================================================
# VISUALIZAÇÃO E INTERPOLAÇÃO (Para Todos)
# ==============================================================
func _apply_visuals() -> void:
	var my_id = QuanticNet.get_unique_id()
	var now = Time.get_ticks_msec()
	
	for id in cubes.keys():
		if id == my_id: continue
		
		# Consome Interpolation Buffer (Jitter Buffer) para peers/props/bullets
		var s := QuanticNet.remote_state(id)
		if not s.is_empty():
			cubes[id].position = s["pos"]
			cubes[id].rotation = s["rot"]
			
			# Feedback Visual Nativo (sem RPC)
			if id >= 1000 and id < 20000:
				var custom = s.get("custom_id", 0)
				if custom == 1:
					cubes[id].material_override = mat_hit
				else:
					cubes[id].material_override = mat_prop
			
			cubes[id].visible = true
			
		# Visual Culling (oculta entidades que não recebem pacote há 2s)
		if _last_rx.has(id) and now - _last_rx[id] > 2000:
			cubes[id].visible = false

	# Desenha Balas dinâmicas recebidas da rede no Servidor
	if QuanticNet.is_server():
		var reg = QuanticNet.get_registry()
		for id in reg.keys():
			if id >= 20000:
				if not cubes.has(id):
					_on_peer_joined(id)
					var mesh = SphereMesh.new()
					mesh.radius = 0.5
					mesh.height = 1.0
					cubes[id].mesh = mesh
					cubes[id].material_override = mat_bullet
