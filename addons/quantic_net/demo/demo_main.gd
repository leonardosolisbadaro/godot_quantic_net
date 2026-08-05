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
var _diag_lbl_phys: Label
var _diag_lbl_mem: Label
var _diag_lbl_nodes: Label
var _diag_lbl_orphan: Label
var _diag_lbl_rtt: Label
var _diag_lbl_loss: Label
var _diag_lbl_offset: Label
var _diag_lbl_peers: Label
var _reconnect_btn: Button

# Domínio de Gameplay (Regras, Limites e Constantes)
const GAME_VARS = {
	"prop_start": 1000,
	"prop_end": 20000,
	"bullet_start": 20000,
	"max_fps": 60,
	"cull_ms": 2000,
	"hit_blink_ms": 150,
	"interp_speed": 10.0,
	"player_speed": 5.0,
	"bullet_speed": 40.0,
	"bullet_life": 3.0,
	"bullet_radius": 0.5,
	"bullet_height": 1.0,
	"hit_sphere_radius": 1.0,
	"spawn_offset": 1.0
}

var _last_ui_update_ms := 0
var _current_offset := 0.0
var _netem_active := false
var _current_profile_idx := 0
var _next_prop_id := GAME_VARS.prop_start

# Estado Local
var cubes := {}
var active_bullets := {}
var _fps_min := 9999
var _fps_max := 0
var _my_id := 0
var _is_server := false
var _culling_disk: MeshInstance3D
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

var _network_config = {
	"max_speed": 6.0,
	"hard_cap": 20.0,
	"world_bounds": 60.0,
	"max_strikes": 5,
	"auth_timeout": 3.0,
	"netem_loss": 10.0,
	"netem_latency": 150,
	"netem_jitter": 50,
	"netem_dup": 0.0
}

func _create_profile(hz: float, priority: float, cull: float) -> QNEntityProfile:
	var p = QNEntityProfile.new()
	p.init(hz, priority, cull)
	return p

func _ready() -> void:
	# Parse args
	var args = OS.get_cmdline_user_args()
	_is_server = args.has("--server")
	var is_client = args.has("--client")
	var use_netem = args.has("--netem")
	if use_netem:
		_netem_active = true
	
	if not _is_server and not is_client:
		print("Iniciando topologia automática: 1 Servidor, 2 Clientes...")
		_is_server = true
		
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
	
	_profiles.push_back(_create_profile(60.0, 1.0, 150.0)) # 0: Players / Veículos Rápidos
	_profiles.push_back(_create_profile(20.0, 0.5, 100.0)) # 1: NPCs / Mobs (Tick híbrido)
	_profiles.push_back(_create_profile(10.0, 0.1, 200.0)) # 2: Ambiente / Clima (Low-tick longo alcance)
	_profiles.push_back(_create_profile(10.0, 1.0, 50.0)) # 3: Props Interativos / Loot
	_profiles.push_back(_create_profile(60.0, 2.0, 200.0)) # 4: Projéteis / Hitboxes Críticas
	
	QuanticNet.connection_state_changed.connect(_on_conn_state)
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_joined.connect(func(id: int):
		if id == QuanticNet.get_unique_id():
			_my_id = id
	)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.pong_received.connect(func(rtt: float, off: float):
		_current_rtt = rtt
		_current_offset = off
	)
	QuanticNet.state_received.connect(_on_state)
	QuanticNet.snapback_received.connect(_on_snapback)
	
	if _is_server:
		print("Iniciando SERVIDOR QuanticNet (Porta %d)..." % PORT)
		QuanticNet.host(PORT, SECRET, "127.0.0.1", 32, _network_config)
		_server_spawn_props()
	else:
		print("Iniciando CLIENTE QuanticNet...")
		QuanticNet.join("127.0.0.1", PORT, SECRET, use_netem, _network_config)

	get_tree().set_multiplayer(QuanticNet.get_tree().get_multiplayer(QuanticNet.get_path()), self.get_path())

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

	# Disco de Culling (Visual Interest Area)
	if not _is_server:
		var torus = TorusMesh.new()
		torus.inner_radius = 49.5
		torus.outer_radius = 50.0
		torus.rings = 64
		var d_mat = StandardMaterial3D.new()
		d_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.3)
		d_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		d_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		torus.material = d_mat
		_culling_disk = MeshInstance3D.new()
		_culling_disk.mesh = torus
		add_child(_culling_disk)
		
func _setup_ui() -> void:
	var hud = CanvasLayer.new()
	
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.text = "OFFLINE"
	_status_lbl.add_theme_color_override("font_color", Color.GRAY)
	top_panel.add_child(_status_lbl)
	hud.add_child(top_panel)
	
	_reconnect_btn = Button.new()
	_reconnect_btn.text = "Reconectar"
	_reconnect_btn.visible = false
	_reconnect_btn.focus_mode = Control.FOCUS_NONE
	var btn_margin = MarginContainer.new()
	btn_margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	btn_margin.add_theme_constant_override("margin_top", 40)
	var center_btn = CenterContainer.new()
	center_btn.add_child(_reconnect_btn)
	btn_margin.add_child(center_btn)
	hud.add_child(btn_margin)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	var vbox = VBoxContainer.new()
	
	var shortcuts = [
		"CONTROLES IN-GAME:",
		"Setas/WASD : Mover",
		"Enter      : Auto-Move On/Off",
		"F          : Destravar FPS / V-Sync",
		"N          : Ativar/Desativar NETEM",
		"1 a 5      : Mudar Perfil de Rede (Tick Rate)",
		"SPACE      : Spawna 100 Props (reseta)",
		"+ / -      : Adiciona/Remove 10 Props",
		"* / /      : Multiplica/Divide total por 2",
		"0          : Remove todos os Props",
		"Mouse Esq  : Tiro Hitscan (Laser)",
		"Mouse Dir  : Projétil (Bala)"
	]
	
	for s in shortcuts:
		var lbl = Label.new()
		lbl.text = s
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", 4)
		vbox.add_child(lbl)
		
	margin.add_child(vbox)
	hud.add_child(margin)
	
	var diag_margin = MarginContainer.new()
	diag_margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	diag_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	diag_margin.add_theme_constant_override("margin_left", 20)
	diag_margin.add_theme_constant_override("margin_bottom", 20)
	var diag_vbox = VBoxContainer.new()
	
	var diag_title = Label.new()
	diag_title.text = "[ SYSTEM PROFILER ]"
	diag_title.add_theme_color_override("font_color", Color.YELLOW)
	diag_vbox.add_child(diag_title)
	
	_diag_lbl_fps = Label.new()
	_diag_lbl_phys = Label.new()
	_diag_lbl_mem = Label.new()
	_diag_lbl_nodes = Label.new()
	_diag_lbl_orphan = Label.new()
	
	var labels_sys = [_diag_lbl_fps, _diag_lbl_phys, _diag_lbl_mem, _diag_lbl_nodes, _diag_lbl_orphan]
	for l in labels_sys:
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 3)
		diag_vbox.add_child(l)
		
	var diag_spacer = Control.new()
	diag_spacer.custom_minimum_size = Vector2(0, 15)
	diag_vbox.add_child(diag_spacer)
	
	var net_title = Label.new()
	net_title.text = "[ NETWORK PROFILER ]"
	net_title.add_theme_color_override("font_color", Color.CYAN)
	diag_vbox.add_child(net_title)
	
	_diag_lbl_rtt = Label.new()
	_diag_lbl_loss = Label.new()
	_diag_lbl_offset = Label.new()
	_diag_lbl_peers = Label.new()
	
	var labels_net = [_diag_lbl_rtt, _diag_lbl_loss, _diag_lbl_offset, _diag_lbl_peers]
	for l in labels_net:
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 3)
		diag_vbox.add_child(l)
		
	diag_margin.add_child(diag_vbox)
	hud.add_child(diag_margin)
	
	add_child(hud)

func _on_conn_state(state: int) -> void:
	match state:
		QuanticNet.ConnectionState.DISCONNECTED:
			_status_lbl.text = "DISCONNECTED"
			_status_lbl.add_theme_color_override("font_color", Color.GRAY)
		QuanticNet.ConnectionState.CONNECTED:
			_status_lbl.text = "CONNECTED"
			_status_lbl.add_theme_color_override("font_color", Color.GREEN)

func _on_peer_joined(peer_id: int) -> void:
	print("Peer joined: ", peer_id)
	var mesh = BoxMesh.new()
	var cube = MeshInstance3D.new()
	cube.mesh = mesh
	
	var my_real_id = QuanticNet.get_unique_id()
	if peer_id == my_real_id:
		cube.material_override = mat_player_local
	elif peer_id >= GAME_VARS.bullet_start:
		var s_mesh = SphereMesh.new()
		s_mesh.radius = GAME_VARS.bullet_radius
		s_mesh.height = GAME_VARS.bullet_height
		cube.mesh = s_mesh
		cube.material_override = mat_bullet
	elif peer_id >= GAME_VARS.prop_start and peer_id < GAME_VARS.prop_end:
		cube.material_override = mat_prop
	else:
		cube.material_override = mat_player_remote
		
	if peer_id == QuanticNet.get_unique_id():
		cube.position = Vector3(0, 0.5, 0)
	elif QuanticNet.is_server():
		cube.position = Vector3(0, 0.5, 0)
	else:
		cube.visible = false
		
	add_child(cube)
	cubes[peer_id] = cube
	
	if QuanticNet.is_server() and peer_id < GAME_VARS.prop_start:
		QuanticNet.register_entity(peer_id, true, true, _profiles[0])
		# UPDATE_ENTITY_STATE e essencial para inserir a entidade no Grid Espacial
		# do servidor. Sem isso, ele nunca e enviado nos snapshots iniciais.
		QuanticNet.update_entity_state(peer_id, Vector3(0, 0.5, 0), Vector3.ZERO, 0, QuanticNet.get_server_time())

func _on_peer_left(peer_id: int) -> void:
	print("Peer left: ", peer_id)
	if cubes.has(peer_id):
		cubes[peer_id].queue_free()
		cubes.erase(peer_id)

func _on_state(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
	if not _is_server:
		_last_rx[owner] = Time.get_ticks_msec()
		if not cubes.has(owner) and owner != _my_id:
			_on_peer_joined(owner)
			
		if cubes.has(owner) and not cubes[owner].visible:
			cubes[owner].position = pos
			cubes[owner].rotation = rot
			cubes[owner].visible = true

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	print("[CLIENT] Snapback recebido! Reconciliando posicao para: ", pos)
	var my_id = QuanticNet.get_unique_id()
	if cubes.has(my_id):
		cubes[my_id].position = pos
		cubes[my_id].rotation = rot

func _server_spawn_props() -> void:
	var reg = QuanticNet.get_registry()
	for i in range(10):
		var prop_id = 1000 + i
		QuanticNet.register_entity(prop_id, false, true, _profiles[3])
		
		# Inicializa posicoes imediatamente apos o registro
		var initial_pos = _calc_prop_pos(prop_id - GAME_VARS.prop_start, 0.0)
		QuanticNet.update_entity_state(prop_id, initial_pos, Vector3.ZERO, 0, QuanticNet.get_server_time())
			
		_on_peer_joined(prop_id)

func _calc_prop_pos(offset: int, time: float) -> Vector3:
	var r = 10.0 + (offset % 3) * 5.0
	var speed = 0.5 + (offset % 2) * 0.5
	var angle = time * speed + offset * 0.7
	return Vector3(cos(angle) * r, 0.5, sin(angle) * r)

func _physics_process(delta: float) -> void:
	if QuanticNet.is_server():
		_server_physics(delta)
	
	if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		_client_physics(delta)

func _process(_delta: float) -> void:
	_update_ui()
	_apply_visuals()

func _update_ui() -> void:
	var now_ms = Time.get_ticks_msec()
	if _diag_lbl_fps != null and is_instance_valid(_diag_lbl_fps) and now_ms - _last_ui_update_ms > 250:
		_last_ui_update_ms = now_ms
		_diag_lbl_fps.text = "FPS: %d" % Engine.get_frames_per_second()
		_diag_lbl_phys.text = "Physics Time (sec): %.4f" % Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_diag_lbl_mem.text = "Static Mem: %.2f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
		_diag_lbl_nodes.text = "Active Nodes: %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		_diag_lbl_orphan.text = "Orphan Nodes: %d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		
		var c_peers = 0
		var c_props = 0
		for k in cubes:
			if k >= GAME_VARS.prop_start and k < GAME_VARS.prop_end: c_props += 1
			else: c_peers += 1
		_diag_lbl_peers.text = "Total Peers: %d | Props: %d" % [c_peers, c_props]
		
		var my_id = QuanticNet.get_unique_id()
		var t2 = QuanticNet.get_telemetry(my_id)
		if t2:
			_diag_lbl_rtt.text = "RTT: %.0f ms" % t2.get_current_rtt()
			_diag_lbl_loss.text = "Loss: %.1f%%" % t2.get_current_loss()
			_diag_lbl_offset.text = "Clock Offset: %.1f ms" % _current_offset
		else:
			_diag_lbl_rtt.text = "RTT (ms): N/A"
			_diag_lbl_loss.text = "Packet Loss: N/A"
			_diag_lbl_offset.text = "Clock Offset: N/A"
			
		var prof = _profiles[_current_profile_idx]
		var prof_str = "%.0f HZ" % prof.tick_rate_hz
		var title = "QuanticNet - %s #%d | FPS: %d | %s" % [
			"SERVER" if QuanticNet.is_server() else "CLIENT",
			my_id,
			Engine.get_frames_per_second(),
			prof_str
		]
		if _netem_active:
			title += " | [NETEM ON]"
		DisplayServer.window_set_title(title)

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
		move = Vector2(Input.get_axis("ui_left", "ui_right"), Input.get_axis("ui_up", "ui_down")).limit_length(1.0)
	
	cube.position.x += move.x * GAME_VARS.player_speed * delta
	cube.position.z += move.y * GAME_VARS.player_speed * delta
	
	if _culling_disk != null:
		_culling_disk.position = cube.position
		
	if move.length_squared() > 0.01:
		var target_rot = atan2(-move.x, -move.y)
		cube.rotation.y = lerp_angle(cube.rotation.y, target_rot, 15.0 * delta)
	
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
	var p_start = GAME_VARS.prop_start
	var p_end = GAME_VARS.prop_end
	
	for prop_id in reg:
		if prop_id >= p_start and prop_id < p_end:
			var offset = prop_id - p_start
			var angle = offset * 2.4 + auto_time_srv * 0.2
			var radius = 5.0 + (offset % 10) * 2.0 + sin(auto_time_srv * 0.5 + offset) * 2.0
			var new_pos = Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)
			
			var custom = 0
			if hit_timers.has(prop_id):
				if now >= hit_timers[prop_id]:
					hit_timers.erase(prop_id)
				else:
					custom = 1 # 1 = Hitted
			
			QuanticNet.update_entity_state(prop_id, new_pos, Vector3.ZERO, custom, now)
			if cubes.has(prop_id):
				cubes[prop_id].position = new_pos
			
	# 2. Processa Inputs dos Jogadores
	for p_id in reg:
		if p_id < GAME_VARS.prop_start: # Player
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
	for b_id in active_bullets:
		var b = active_bullets[b_id]
		b.pos += b.dir * b.speed * delta
		b.life -= delta
		
		if b.life <= 0:
			bullets_to_remove.append(b_id)
			continue
			
		var hits = QuanticNet.query_sphere(b.pos, GAME_VARS.bullet_radius, now)
		var hit_someone = false
		for hit_id in hits:
			if hit_id < GAME_VARS.bullet_start and hit_id != b.owner_id and hit_id >= GAME_VARS.prop_start and hit_id < GAME_VARS.prop_end:
				hit_timers[hit_id] = now + GAME_VARS.hit_blink_ms # Pisca por 150ms
				bullets_to_remove.append(b_id)
				hit_someone = true
				break
				
		if not hit_someone:
			QuanticNet.update_entity_state(b_id, b.pos, Vector3.ZERO, 0, now)
			if cubes.has(b_id):
				cubes[b_id].position = b.pos
			
	for b_id in bullets_to_remove:
		if active_bullets.has(b_id):
			active_bullets.erase(b_id)
			QuanticNet.unregister_entity(b_id)

func _server_execute_hitscan(p_id: int, p_state: Dictionary) -> void:
	var origin = p_state.pos
	var direction = - Basis.from_euler(p_state.rot).z.normalized()
	
	# Raycast Offset para não acertar o próprio jogador
	var ray_origin = origin + direction * GAME_VARS.spawn_offset
	
	# Usa o Timestamp exato em que o cliente disparou o input para o Lag Compensation
	var hit = QuanticNet.query_raycast(ray_origin, direction, 50.0, p_state.ts)
	
	if hit.has("entity_id"):
		var entity_id = hit["entity_id"]
		if entity_id >= GAME_VARS.prop_start and entity_id < GAME_VARS.prop_end and entity_id != p_id:
			hit_timers[entity_id] = QuanticNet.get_server_time() + GAME_VARS.hit_blink_ms

func _server_execute_projectile(p_id: int, p_state: Dictionary) -> void:
	var origin = p_state.pos
	var direction = - Basis.from_euler(p_state.rot).z.normalized()
	
	_bullet_counter += 1
	var b_id = GAME_VARS.bullet_start + (p_id * 1000) + (_bullet_counter % 1000)
	
	active_bullets[b_id] = {
		"pos": origin + direction * GAME_VARS.spawn_offset,
		"dir": direction,
		"speed": GAME_VARS.bullet_speed,
		"life": GAME_VARS.bullet_life,
		"owner_id": p_id
	}
	QuanticNet.register_entity(b_id, false, true, _profiles[4])

# ==============================================================
# VISUALIZAÇÃO E INTERPOLAÇÃO (Para Todos)
# ==============================================================
func _apply_visuals() -> void:
	var my_id = QuanticNet.get_unique_id()
	var now = Time.get_ticks_msec()
	
	if not QuanticNet.is_server():
		var to_cull = []
		for id in cubes:
			if id == my_id: continue
			
			# Consome Interpolation Buffer (Jitter Buffer) para peers/props/bullets
			var s := QuanticNet.get_remote_state(id)
			if not s.is_empty():
				cubes[id].position = s["pos"]
				cubes[id].rotation = s["rot"]
				
				# Feedback Visual Nativo (sem RPC)
				if id >= GAME_VARS.prop_start and id < GAME_VARS.prop_end:
					var custom = s.get("custom_id", 0)
					if custom == 1:
						cubes[id].material_override = mat_hit
					else:
						cubes[id].material_override = mat_prop
				
				cubes[id].visible = true
				
			# Visual Culling (destrói entidades que não recebem pacote há X ms)
			if _last_rx.has(id) and now - _last_rx[id] > GAME_VARS.cull_ms:
				to_cull.append(id)
				
		for cull_id in to_cull:
			if cubes.has(cull_id):
				cubes[cull_id].queue_free()
				cubes.erase(cull_id)
			_last_rx.erase(cull_id)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			_netem_active = not _netem_active
			var loss = _network_config["netem_loss"] if _netem_active else 0.0
			var lat = _network_config["netem_latency"] if _netem_active else 0
			var jit = _network_config["netem_jitter"] if _netem_active else 0
			var dup = _network_config["netem_dup"] if _netem_active else 0.0
			QuanticNet.set_netem_config(loss, lat, jit, dup)
			var status = "ON (%.0f%% Loss, %dms Delay, %dms Jitter)" % [loss, lat, jit] if _netem_active else "OFF"
			print("[DEMO] NETEM: %s" % status)
		elif event.keycode == KEY_F:
			if Engine.max_fps == 0:
				Engine.max_fps = GAME_VARS.max_fps
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print("[DEMO] FPS Limitado: ", "SIM (%d)" % GAME_VARS.max_fps if Engine.max_fps == GAME_VARS.max_fps else "NAO (Unlimited)")
			
		if not QuanticNet.is_server():
			# [CLIENT ADMIN BINDS (RPC TO SERVER)]
			if event.keycode == KEY_SPACE:
				_request_spawn_props.rpc_id(1, 100, true) # 'SPACE' reseta para 100
			elif event.keycode == KEY_0:
				_request_spawn_props.rpc_id(1, 0, true) # '0' zera todos
			elif event.keycode == KEY_EQUAL or event.keycode == KEY_PLUS:
				_request_spawn_props.rpc_id(1, 10, false) # '+' adiciona 10
			elif event.keycode == KEY_MINUS:
				_request_remove_props.rpc_id(1, 10) # '-' remove 10
			elif event.keycode == KEY_ASTERISK or event.keycode == KEY_KP_MULTIPLY:
				_request_scale_props.rpc_id(1, 2.0) # '*' multiplica por 2
			elif event.keycode == KEY_SLASH or event.keycode == KEY_KP_DIVIDE:
				_request_scale_props.rpc_id(1, 0.5) # '/' divide por 2

			# [CLIENT LOCAL BINDS]
			if event.keycode >= KEY_1 and event.keycode <= KEY_5:
				var target_idx = event.keycode - KEY_1
				if target_idx < _profiles.size():
					_current_profile_idx = target_idx
					_apply_profile.rpc_id(1, QuanticNet.get_unique_id(), _current_profile_idx)

# Os @rpc abaixo despacham comandos para o Servidor modificar as entidades registradas
@rpc("any_peer", "call_local")
func _apply_profile(peer_id: int, profile_idx: int) -> void:
	if QuanticNet.is_server():
		# Servidor valida a mudanca de perfil daquele peer_id
		if profile_idx >= 0 and profile_idx < _profiles.size():
			QuanticNet.change_entity_profile(peer_id, _profiles[profile_idx])
			print("[SERVER] Perfil alterado para o Peer %d -> Index: %d (%.0f HZ)" % [peer_id, profile_idx, _profiles[profile_idx].tick_rate_hz])
		
	if cubes.has(peer_id):
		var cube: MeshInstance3D = cubes[peer_id]
		var mat: StandardMaterial3D = cube.mesh.material
		if mat:
			var colors = [Color(0.2, 1.0, 0.2), Color(1.0, 1.0, 0.2), Color(1.0, 0.5, 0.2), Color(1.0, 0.2, 0.2), Color(0.5, 0.2, 1.0)]
			var target_color = colors[profile_idx % colors.size()]
			var tw = get_tree().create_tween()
			tw.tween_property(mat, "emission", target_color, 0.5)

@rpc("any_peer", "call_local")
func _request_spawn_props(count: int, clear_previous: bool) -> void:
	if clear_previous:
		var to_remove = []
		for id in cubes.keys():
			if id >= GAME_VARS.prop_start and id < GAME_VARS.prop_end: to_remove.append(id)
		for id in to_remove:
			if QuanticNet.is_server():
				QuanticNet.unregister_entity(id)
			else:
				QuanticNet.cleanup_entity(id)
			cubes[id].queue_free()
			cubes.erase(id)
			
		if QuanticNet.is_server():
			_next_prop_id = GAME_VARS.prop_start
			print("[SERVER] Limpando props anteriores...")
			
	if not QuanticNet.is_server(): return
		
	var reg = QuanticNet.get_registry()
	for i in range(count):
		var prop_id = _next_prop_id
		_next_prop_id += 1
		QuanticNet.register_entity(prop_id, false, true, _profiles[3])
		var initial_pos = _calc_prop_pos(prop_id - GAME_VARS.prop_start, auto_time)
		
		QuanticNet.update_entity_state(prop_id, initial_pos, Vector3.ZERO, 0, Time.get_ticks_msec())
			
		_on_peer_joined(prop_id)
		
	print("[SERVER] Spawnei %d props! Total atual de props: %d" % [count, _next_prop_id - GAME_VARS.prop_start])

@rpc("any_peer", "call_local")
func _request_remove_props(count: int) -> void:
	var removed = 0
	var keys = cubes.keys()
	keys.reverse()
	for id in keys:
		if id >= GAME_VARS.prop_start and id < GAME_VARS.prop_end:
			if QuanticNet.is_server():
				QuanticNet.unregister_entity(id)
			cubes[id].queue_free()
			cubes.erase(id)
			removed += 1
			if removed >= count:
				break
				
	if QuanticNet.is_server():
		print("[SERVER] Removidos %d props! Props restantes: %d" % [removed, _next_prop_id - GAME_VARS.prop_start - removed])
		_next_prop_id -= removed
		if _next_prop_id < GAME_VARS.prop_start: _next_prop_id = GAME_VARS.prop_start

@rpc("any_peer", "call_local")
func _request_scale_props(factor: float) -> void:
	# if not QuanticNet.is_server(): return
	var c_props = 0
	for id in cubes.keys():
		if id >= GAME_VARS.prop_start and id < GAME_VARS.prop_end: c_props += 1
		
	if factor > 1.0:
		var extra = c_props * (factor - 1.0)
		_request_spawn_props(extra, false)
	elif factor < 1.0:
		var remove_cnt = c_props * (1.0 - factor)
		_request_remove_props(remove_cnt)
