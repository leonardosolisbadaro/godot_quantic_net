## @file demo_main.gd
## @path res://addons/quantic_net/demo/demo_main.gd
##
## @description
## Cena demo bare metal do QuanticNet: 1 servidor, 2 clientes com cubos
## sincronizados via host/join/submit_state/remote_state e sinais
## publicos do autoload. Nao conhece internals do plugin.
##
## @created 2026-07-29
## @updated 2026-08-02
##
## @since 0.2.0
## @lastModifiedIn 0.3.0-rc.1
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
var _last_rx := {}
var _netem_active := false
var _can_send_state := false

var _profiles = [
	QuanticNet.NetProfile.new(20.0, 5.0, 50.0), # 1: Padrão (20Hz)
	QuanticNet.NetProfile.new(10.0, 3.0, 30.0), # 2: Intermediário (10Hz)
	QuanticNet.NetProfile.new(5.0, 1.0, 10.0), # 3: Prop (5Hz)
	QuanticNet.NetProfile.new(1.0, 0.5, 5.0), # 4: Muito Lento (1Hz)
	QuanticNet.NetProfile.new(60.0, 10.0, 100.0) # 5: Extremo (60Hz)
]
var _current_profile_idx = 0
var _next_prop_id = 1000

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
		_netem_active = "--netem" in args
		# Registra callback de peer join para autorizar envio de estado com pequeno delay
		QuanticNet.peer_joined.connect(func(id: int):
			if id == QuanticNet.get_unique_id():
				# Delay para SceneMultiplayer assentar o peer internamente
				get_tree().create_timer(0.1).timeout.connect(func(): _can_send_state = true)
		)
		
		QuanticNet.join("127.0.0.1", PORT, SECRET, _netem_active)
		QuanticNet.set_netem_config(0.10, 150, 50) # 10% perda, 150ms atraso, 50ms jitter
		print("[DEMO] Cliente conectando (netem=%s) [Pressione 'N' para alternar]" % ("true" if _netem_active else "false"))
		_setup_client_scene()
		
	# A demo precisa do MESMO `MultiplayerAPI` que o QuanticNet instanciou,
	# caso contrário, os @rpc nativos de `demo_main.gd` falharão silenciosamente.
	get_tree().set_multiplayer(QuanticNet.get_tree().get_multiplayer(QuanticNet.get_path()), self.get_path())

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			QuanticNet.toggle_netem()
			_netem_active = not _netem_active
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			auto_move = not auto_move
			print("[DEMO] Auto-move: ", auto_move)
		elif event.keycode == KEY_L:
			if Engine.max_fps == 0:
				Engine.max_fps = 60
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print("[DEMO] FPS Limitado: ", "SIM (60)" if Engine.max_fps == 60 else "NAO (Unlimited)")
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			_current_profile_idx = event.keycode - KEY_1
			if QuanticNet.is_server():
				_apply_profile.rpc_id(1, QuanticNet.get_unique_id(), _current_profile_idx)
			else:
				_apply_profile.rpc_id(1, QuanticNet.get_unique_id(), _current_profile_idx)
		elif event.keycode == KEY_SPACE:
			_request_spawn_props.rpc_id(1, 100, true) # 'SPACE' reseta para 100
		elif event.keycode == KEY_0:
			_request_spawn_props.rpc_id(1, 0, true) # '0' zera todos
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_request_spawn_props.rpc_id(1, 10, false) # '+' adiciona 10
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_request_remove_props.rpc_id(1, 10) # '-' remove 10
		elif event.keycode == KEY_ASTERISK or event.keycode == KEY_KP_MULTIPLY:
			_request_scale_props.rpc_id(1, 2.0) # '*' multiplica por 2
		elif event.keycode == KEY_SLASH or event.keycode == KEY_KP_DIVIDE:
			_request_scale_props.rpc_id(1, 0.5) # '/' divide por 2

@rpc("any_peer", "call_local")
func _apply_profile(peer_id: int, profile_idx: int) -> void:
	if QuanticNet.is_server():
		if profile_idx >= 0 and profile_idx < _profiles.size():
			QuanticNet.change_entity_profile(peer_id, _profiles[profile_idx])
			print("[SERVER] Perfil alterado para o Peer %d -> Index: %d (%.0f HZ)" % [peer_id, profile_idx, _profiles[profile_idx].tick_rate_hz])

@rpc("any_peer", "call_local")
func _request_spawn_props(count: int, clear_previous: bool) -> void:
	if not QuanticNet.is_server(): return
	
	if clear_previous:
		var to_remove = []
		for id in cubes.keys():
			if id >= 1000: to_remove.append(id)
		for id in to_remove:
			if QuanticNet.get_registry().has(id):
				QuanticNet.get_registry().erase(id)
			cubes[id].queue_free()
			cubes.erase(id)
		_next_prop_id = 1000
		print("[SERVER] Limpando props anteriores...")
		
	for i in range(count):
		var prop_id = _next_prop_id
		_next_prop_id += 1
		QuanticNet.register_entity(prop_id, false, true, _profiles[2]) # Perfil Prop (5Hz)
		
		# Inicia exatamente na posição onde o physics_process vai atualizá-lo, evitando 'drifting' interpolado inicial.
		QuanticNet.get_registry()[prop_id].pos = _calc_prop_pos(prop_id - 1000, auto_time)
		
		_on_peer_joined(prop_id)
		
	print("[SERVER] Spawnei %d props! Total atual de props: %d" % [count, _next_prop_id - 1000])

@rpc("any_peer", "call_local")
func _request_remove_props(count: int) -> void:
	var removed = 0
	var keys = cubes.keys()
	keys.reverse() # Remove os últimos criados primeiro
	for id in keys:
		if id >= 1000:
			if QuanticNet.is_server() and QuanticNet.get_registry().has(id):
				QuanticNet.get_registry().erase(id)
			cubes[id].queue_free()
			cubes.erase(id)
			removed += 1
			if removed >= count:
				break
				
	if QuanticNet.is_server():
		print("[SERVER] Removidos %d props! Props restantes: %d" % [removed, _next_prop_id - 1000 - removed])
		# Ajusta id proximo (opcional)
		_next_prop_id -= removed
		if _next_prop_id < 1000: _next_prop_id = 1000

@rpc("any_peer", "call_local")
func _request_scale_props(factor: float) -> void:
	if not QuanticNet.is_server(): return
	var current = maxi(0, _next_prop_id - 1000)
	var target = int(current * factor)
	if target > current:
		_request_spawn_props(target - current, false)
	elif target < current:
		_request_remove_props(current - target)

func _setup_server_props() -> void:
	# Inicia com 5 props
	_request_spawn_props(5, true)

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
	
	var hud = CanvasLayer.new()
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	var vbox = VBoxContainer.new()
	
	var shortcuts = [
		"CONTROLES IN-GAME:",
		"Setas      : Mover",
		"Enter      : Auto-Move On/Off",
		"L          : Destravar FPS / V-Sync",
		"N          : Ativar/Desativar NETEM",
		"1 a 5      : Mudar Perfil de Rede (Tick Rate)",
		"SPACE      : Spawna 100 Props (reseta)",
		"+ / -      : Adiciona/Remove 10 Props",
		"* / /      : Multiplica/Divide total por 2",
		"0          : Remove todos os Props"
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
	add_child(hud)

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
		mat.albedo_color = Color.CYAN # Ciano para Outros Clientes Reais
		
	mesh.material = mat
	cube.mesh = mesh
	
	if id == QuanticNet.get_unique_id():
		# O próprio jogador inicia em zero e será movido localmente.
		cube.position = Vector3(0, 0.5, 0)
	elif QuanticNet.is_server():
		# O servidor mantém os props em posições determinísticas calculadas depois.
		cube.position = Vector3(0, 0.5, 0)
	else:
		cube.visible = false
		
	cube.name = "Cube_%d" % id
	add_child(cube)
	cubes[id] = cube
	
	if id == QuanticNet.get_unique_id():
		# Adiciona uma área translúcida ao redor do jogador para visualizar o Cull Radius (10m)
		var area = MeshInstance3D.new()
		var area_mesh = CylinderMesh.new()
		area_mesh.top_radius = 10.0
		area_mesh.bottom_radius = 10.0
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
		
	# Servidor: Atualiza fisicamente todos os props (bots) em movimento contínuo
	if QuanticNet.is_server():
		auto_time += delta
		var reg = QuanticNet.get_registry()
		var server_now = Time.get_ticks_msec()
		
		for prop_id in reg.keys():
			if prop_id >= 1000:
				var p = reg[prop_id]
				p.pos = _calc_prop_pos(prop_id - 1000, auto_time)
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
		
		# Envia estado para o servidor se estivermos autorizados.
		if _can_send_state and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
			QuanticNet.submit_state(cube.position, cube.rotation, 0, delta)

func _process(delta: float) -> void:
	if QuanticNet.is_server():
		return
		
	var fps := Engine.get_frames_per_second()
	var my_id = QuanticNet.get_unique_id()
	
	var prof = _profiles[_current_profile_idx]
	var prof_str = "%.0f HZ" % prof.tick_rate_hz
	
	var netem_str = "NETEM - LOSS 10%%, DELAY 150ms, JITTER 50ms" if _netem_active else "NETEM - OFF"
	DisplayServer.window_set_title("#%d | FPS %d | %s | %s" % [my_id, fps, prof_str, netem_str])
	
	# Desabilita/Oculta cubos que não recebem atualizações há mais de 0.5 segundo (saíram do AoI)
	var now = Time.get_ticks_msec()
	var my_pos = cubes[my_id].position if cubes.has(my_id) else Vector3.ZERO
	
	for id in cubes.keys():
		if id != my_id:
			var dist = my_pos.distance_to(cubes[id].position)
			# Culling visual no cliente: 
			# Props têm raio 10.0m. Outros peers têm raio 50.0m (default).
			var max_dist = 11.0 if id >= 1000 else 52.0
			
			if dist > max_dist:
				cubes[id].visible = false
			elif _last_rx.has(id) and now - _last_rx[id] > 500:
				cubes[id].visible = false
			else:
				cubes[id].visible = true
				
	# Aplica estado interpolado de peers remotos puramente no frame visual (desacoplado de fisica).
	for id in cubes.keys():
		if id == my_id:
			continue
		var s := QuanticNet.remote_state(id)
		if not s.is_empty():
			cubes[id].position = s["pos"]
			cubes[id].rotation = s["rot"]

func _on_state(owner: int, pos: Vector3, rot: Vector3, _custom: int) -> void:
	if not QuanticNet.is_server():
		if _last_rx.has(owner):
			var gap = Time.get_ticks_msec() - _last_rx[owner]
			if owner >= 1000 and gap > 200:
				print("[CLIENT] Recebeu %d apos %d ms! Pos: %s" % [owner, gap, str(pos)])
				
	_last_rx[owner] = Time.get_ticks_msec()
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

func _calc_prop_pos(offset: int, time: float) -> Vector3:
	# Golden angle (~2.3999 radianos) distribui radialmente sem depender do count.
	var angle = offset * 2.4 + time * 0.2
	var radius = 5.0 + (offset % 10) * 2.0 + sin(time * 0.5 + offset) * 2.0
	return Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	print("[DEMO] snapback (seq=%d reason=%d replay=%d)" % [seq, reason, replay.size()])
