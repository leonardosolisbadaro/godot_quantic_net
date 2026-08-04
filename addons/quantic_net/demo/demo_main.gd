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
## `QuanticNet` em um projeto Godot 4.7.
##
## A Demo comprova que você não precisa herdar classes do QuanticNet
## para o seu jogo funcionar. Tudo é orquestrado de forma "Plug-and-play"
## através de chamadas ao Autoload (Single-Point of Entry).
##
## Como executar (terminal):
##   Servidor: godot --headless --path . -- --server
##   Cliente 1: godot --path . -- --client
##   Cliente 2: godot --path . -- --client --netem
##
## O plugin cuida de DTLS, clock-sync, snapback e interpolacao nos bastidores;
## este arquivo foca EXCLUSIVAMENTE em ler input, mover visualmente os cubos
## e despachar o estado para o motor de rede.

const PORT := 4242
const SECRET := "demo-secret"
const SPEED := 2.0

# Dicionário que mapeia o ID do Peer para a malha visual 3D (o "Avatar")
var cubes := {} # peer_id -> MeshInstance3D

class PeerTelemetrics:
	var rtt_avg: float = 0.0
	var rtt_min: float = INF
	var loss_avg: float = 0.0
	var loss_min: float = INF
	var offset: float = 0.0
	
	var _rtt_samples: Array[float] = []
	var _loss_samples: Array[float] = []
	const MAX_SAMPLES = 30
	
	func push_rtt(val: float) -> void:
		_rtt_samples.append(val)
		if _rtt_samples.size() > MAX_SAMPLES: _rtt_samples.pop_front()
		rtt_min = min(rtt_min, val)
		var sum = 0.0
		for v in _rtt_samples: sum += v
		rtt_avg = sum / max(1, _rtt_samples.size())
		
	func push_loss(val: float) -> void:
		_loss_samples.append(val)
		if _loss_samples.size() > MAX_SAMPLES: _loss_samples.pop_front()
		loss_min = min(loss_min, val)
		var sum = 0.0
		for v in _loss_samples: sum += v
		loss_avg = sum / max(1, _loss_samples.size())

var telemetrics := {} # peer_id -> PeerTelemetrics
var _poll_index: int = 0

var _diag_lbl_fps: Label
var _diag_lbl_phys: Label
var _diag_lbl_mem: Label
var _diag_lbl_nodes: Label
var _diag_lbl_orphan: Label

var auto_move := true
var auto_time := 0.0
var _last_rx := {}
var _netem_active := false
var _can_send_state := false

# Array contendo instâncias de perfis de rede (Tick Rates e Culling).
# Isso demonstra o "Hybrid Ticking" do QuanticNet, onde cada entidade
# pode ser atualizada em frequências distintas, priorizando a banda.
var _profiles = [
	QuanticNet.NetProfile.new(20.0, 5.0, 50.0), # 1: Padrão (20Hz)
	QuanticNet.NetProfile.new(10.0, 3.0, 30.0), # 2: Intermediário (10Hz)
	QuanticNet.NetProfile.new(5.0, 1.0, 10.0), # 3: Prop (5Hz) - Economiza muita banda
	QuanticNet.NetProfile.new(1.0, 0.5, 5.0), # 4: Muito Lento (1Hz) - Props inertes
	QuanticNet.NetProfile.new(60.0, 10.0, 100.0) # 5: Extremo (60Hz) - Para combate rápido
]
var _current_profile_idx = 0
var _next_prop_id = 1000

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		QuanticNet.disconnect_net(true)
		get_tree().quit()

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	
	# [1] CONECTAR SINAIS (Event-Driven)
	# Conectamos as respostas do QuanticNet ANTES de chamar host/join.
	# Isso garante que não perderemos os eventos iniciais de handshake.
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.state_received.connect(_on_state)
	QuanticNet.snapback_received.connect(_on_snapback)
	QuanticNet.pong_received.connect(func(rtt: float, off: float) -> void:
		print("[DEMO] RTT=%.0fms offset=%.1fms" % [rtt, off])
		var my_id = QuanticNet.get_unique_id()
		if not telemetrics.has(my_id): telemetrics[my_id] = PeerTelemetrics.new()
		telemetrics[my_id].push_rtt(rtt)
		telemetrics[my_id].offset = off
	)
		
	# Decide o papel desta instância baseado nos argumentos do terminal
	var args := OS.get_cmdline_user_args()
	if "--server" in args:
		# [2] INICIAR SERVIDOR
		# Levanta o servidor autoritativo em Background (com criptografia DTLS automática).
		QuanticNet.host(PORT, SECRET, "127.0.0.1", 8)
		print("[DEMO] Servidor na porta %d" % PORT)
		_setup_server_props()
	else:
		_netem_active = "--netem" in args
		
		# [PREVENÇÃO DE DESINCRONIZAÇÃO]
		# Apenas autorizamos o disparo do "Client-Side Prediction" local
		# APÓS o servidor confirmar a nossa identidade, e adicionamos um pequeno delay (0.1s)
		# para dar tempo ao SceneMultiplayer da Godot organizar as árvores de RPC internas.
		QuanticNet.peer_joined.connect(func(id: int):
			if id == QuanticNet.get_unique_id():
				get_tree().create_timer(0.1).timeout.connect(func(): _can_send_state = true)
		)
		
		# [3] INICIAR CLIENTE
		# O parâmetro _netem_active injeta problemas crônicos na rede se for `true`,
		# para testarmos se a nossa Extrapolação e Jitter Buffer funcionam!
		QuanticNet.join("127.0.0.1", PORT, SECRET, _netem_active)
		if _netem_active:
			QuanticNet.set_netem_config(0.10, 150, 50) # 10% perda, 150ms atraso, 50ms jitter
		print("[DEMO] Cliente conectando (netem=%s) [Pressione 'N' para alternar]" % ("true" if _netem_active else "false"))
		_setup_client_scene()
		
	# [CLONAGEM DO MULTIPLAYER API]
	# O QuanticNet blinda e encapsula a comunicação numa aba invisível da SceneTree (usando MultiplayerAPIExtension).
	# Para que possamos usar @rpc localmente NESTE script sem interrupções,
	# nós referenciamos o mesmo contexto Multiplayer que o plugin gerou internamente.
	get_tree().set_multiplayer(QuanticNet.get_tree().get_multiplayer(QuanticNet.get_path()), self.get_path())

func _unhandled_input(event: InputEvent) -> void:
	# Recebe comandos manuais do teclado para alterar configurações em tempo real
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			QuanticNet.toggle_netem()
			_netem_active = not _netem_active
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			auto_move = not auto_move
			print("[DEMO] Auto-move: ", auto_move)
		elif event.keycode == KEY_F:
			if Engine.max_fps == 0:
				Engine.max_fps = 60
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print("[DEMO] FPS Limitado: ", "SIM (60)" if Engine.max_fps == 60 else "NAO (Unlimited)")
		elif event.keycode >= KEY_1 and event.keycode <= KEY_5:
			# Solicita a mudança do perfil (ex: forçar atualização a 60Hz em combate)
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
	if not QuanticNet.is_server(): return
	
	if clear_previous:
		var to_remove = []
		for id in cubes.keys():
			if id >= 1000: to_remove.append(id)
		for id in to_remove:
			QuanticNet.unregister_entity(id)
			cubes[id].queue_free()
			cubes.erase(id)
			if telemetrics.has(id): telemetrics.erase(id)
		_next_prop_id = 1000
		print("[SERVER] Limpando props anteriores...")
		
	for i in range(count):
		var prop_id = _next_prop_id
		_next_prop_id += 1
		# Registramos uma entidade estúpida (ex: NPC/monstro falso) no QuanticNet.
		QuanticNet.register_entity(prop_id, false, true, _profiles[2]) # Perfil Prop (5Hz)
		
		# Inicia exatamente na posição onde o physics_process vai atualizá-lo, 
		# evitando que ele deslize artificialmente (drifting) ao nascer.
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
			QuanticNet.unregister_entity(id)
			cubes[id].queue_free()
			cubes.erase(id)
			if telemetrics.has(id): telemetrics.erase(id)
			removed += 1
			if removed >= count:
				break
				
	if QuanticNet.is_server():
		print("[SERVER] Removidos %d props! Props restantes: %d" % [removed, _next_prop_id - 1000 - removed])
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
	# O servidor automaticamente spawna 5 props fictícios na inicialização.
	_request_spawn_props(5, true)

func _setup_client_scene() -> void:
	# Monta a cena visual dinamicamente para o cliente (Câmera, Luz, Chão, HUD).
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
		"F          : Destravar FPS / V-Sync",
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
	
	# [DIAGNOSTIC PROFILER UI]
	var diag_margin = MarginContainer.new()
	diag_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	diag_margin.add_theme_constant_override("margin_left", 20)
	diag_margin.add_theme_constant_override("margin_top", 350)
	var diag_vbox = VBoxContainer.new()
	
	var diag_title = Label.new()
	diag_title.text = "ENGINE PROFILER"
	diag_title.add_theme_color_override("font_color", Color.YELLOW)
	diag_vbox.add_child(diag_title)
	
	_diag_lbl_fps = Label.new()
	_diag_lbl_phys = Label.new()
	_diag_lbl_mem = Label.new()
	_diag_lbl_nodes = Label.new()
	_diag_lbl_orphan = Label.new()
	
	var labels = [_diag_lbl_fps, _diag_lbl_phys, _diag_lbl_mem, _diag_lbl_nodes, _diag_lbl_orphan]
	for l in labels:
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 3)
		diag_vbox.add_child(l)
		
	diag_margin.add_child(diag_vbox)
	hud.add_child(diag_margin)
	
	add_child(hud)

func _on_peer_joined(id: int) -> void:
	# [CONSTRUÇÃO DO AVATAR]
	# Assim que o servidor relatar a presença de uma nova entidade, 
	# nós criamos a representação visual (Cubo) no cenário local.
	if cubes.has(id):
		return
	var cube := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	
	if id == QuanticNet.get_unique_id():
		mat.albedo_color = Color.GREEN # Jogador Local (Você)
	elif id >= 1000:
		mat.albedo_color = Color.RED # Props (NPCs controlados pelo servidor)
	else:
		mat.albedo_color = Color.CYAN # Outros Clientes Reais
		
	mat.emission_enabled = true
	mat.emission = Color.BLACK
	mat.emission_energy_multiplier = 2.0
		
	mesh.material = mat
	cube.mesh = mesh
	
	if not telemetrics.has(id): telemetrics[id] = PeerTelemetrics.new()
	
	if id == QuanticNet.get_unique_id():
		# O próprio jogador inicia em zero e será movido localmente.
		cube.position = Vector3(0, 0.5, 0)
	elif QuanticNet.is_server():
		# O servidor deve posicionar os props em suas posições corretas imediatamente
		# para que o snapshot inicial já leve a posição exata, evitando teleportes.
		if id >= 1000:
			cube.position = _calc_prop_pos(id - 1000, auto_time)
		else:
			cube.position = Vector3(0, 0.5, 0)
	else:
		# Avatares remotos começam invisíveis até que o 1º pacote contendo 
		# a sua posição real interpolada chegue.
		cube.visible = false
		
	cube.name = "Cube_%d" % id
	add_child(cube)
	cubes[id] = cube
	
	if id == QuanticNet.get_unique_id():
		# [DEBUG VISUAL: CULLING RADIUS]
		# Adiciona uma área translúcida ao redor do jogador local 
		# para demonstrar a distância exata em que outras entidades perdem relevância 
		# e deixam de receber atualizações para poupar rede (Spatial Hashing futuro).
		var area = MeshInstance3D.new()
		var area_mesh = CylinderMesh.new()
		area_mesh.top_radius = 10.0
		area_mesh.bottom_radius = 10.0
		area_mesh.height = 0.05
		
		var area_mat = StandardMaterial3D.new()
		area_mat.albedo_color = Color(0.0, 0.5, 1.0, 0.25) # Azul translúcido
		area_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		area_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		area.mesh = area_mesh
		area.position.y = -0.45 # Fica quase rente ao chão
		cube.add_child(area)
		
	print("[DEMO] peer %d ganhou cubo" % id)

func _on_peer_left(id: int) -> void:
	# O servidor informou que a entidade sumiu do mapa. Nós a apagamos da memória visual.
	if cubes.has(id):
		cubes[id].queue_free()
		cubes.erase(id)
	if telemetrics.has(id):
		telemetrics.erase(id)

func _physics_process(delta: float) -> void:
	# ======================================================================
	# FLUXO DO SERVIDOR (AUTORITATIVO)
	# ======================================================================
	if QuanticNet.is_server():
		# O servidor dita as regras do mundo. Neste caso simples, ele assume 
		# a inteligência artificial dos Props, calculando matematicamente 
		# suas posições no espaço e notificando o roteador de broadcast de que eles mudaram.
		auto_time += delta
		var reg = QuanticNet.get_registry()
		var server_now = Time.get_ticks_msec()
		
		for prop_id in reg.keys():
			if prop_id >= 1000:
				var p = reg[prop_id]
				p.pos = _calc_prop_pos(prop_id - 1000, auto_time)
				p.ts = server_now
				# Força a inserção da nova posição no cache interno 
				# para ser processado pelo ciclo de Broadcast nativo (Tick Híbrido).
				_on_state(prop_id, p.pos, p.rot, 0)
		return

	# ======================================================================
	# FLUXO DO CLIENTE (CLIENT-SIDE PREDICTION)
	# ======================================================================
	# O Cliente processa sua posição fisicamente **sem esperar confirmação** do servidor.
	# Ele se move instantaneamente, mas comunica a intenção via submit_state.
	var my_id := QuanticNet.get_unique_id()
	
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
		
		# Empacota o novo vetor e envia ao QuanticNet.
		# A camada do plugin irá embutir um "sequence ID" (ACK) a este input para gerenciar perdas UDP.
		if _can_send_state and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
			QuanticNet.submit_state(cube.position, cube.rotation, 0, delta)

func _process(delta: float) -> void:
	# [DIAGNOSTIC PROFILER ATUALIZAÇÃO]
	if _diag_lbl_fps != null and is_instance_valid(_diag_lbl_fps):
		_diag_lbl_fps.text = "FPS: %d" % Engine.get_frames_per_second()
		_diag_lbl_phys.text = "Physics Time (sec): %.4f" % Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		_diag_lbl_mem.text = "Static Mem: %.2f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)
		_diag_lbl_nodes.text = "Active Nodes: %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		_diag_lbl_orphan.text = "Orphan Nodes: %d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	# O Loop visual roda fora de `_physics_process` para maximizar a fluidez, 
	# independentemente da taxa estrita de física do servidor (geralmente 60fps constantes).
	if QuanticNet.is_server():
		return
		
	var fps := Engine.get_frames_per_second()
	var my_id = QuanticNet.get_unique_id()
	
	var prof = _profiles[_current_profile_idx]
	var prof_str = "%.0f HZ" % prof.tick_rate_hz
	
	var netem_str = "NETEM - LOSS 10%%, DELAY 150ms, JITTER 50ms" if _netem_active else "NETEM - OFF"
	DisplayServer.window_set_title("#%d | FPS %d | %s | %s" % [my_id, fps, prof_str, netem_str])
	
	# Staggered Polling para telemetria pesada (Loss)
	var keys = cubes.keys()
	if keys.size() > 0:
		var process_per_frame = maxi(1, keys.size() / 10) # Atualiza ~10% por frame
		for i in range(process_per_frame):
			_poll_index = (_poll_index + 1) % keys.size()
			var p_id = keys[_poll_index]
			if telemetrics.has(p_id):
				var loss = QuanticNet.loss_of(p_id)
				telemetrics[p_id].push_loss(loss)
	
	# Desabilita/Oculta cubos que não recebem atualizações há mais de 0.5 segundo (saíram do AoI)
	var now = Time.get_ticks_msec()
	var my_pos = cubes[my_id].position if cubes.has(my_id) else Vector3.ZERO
	
	# [VISUAL CULLING - DESENHO DA CENA]
	# Esconde e ignora a renderização de entidades que saíram 
	# da nossa área de interesse e pararam de nos enviar snapshots pelo servidor.
	for id in cubes.keys():
		if id != my_id:
			var dist = my_pos.distance_to(cubes[id].position)
			
			# Raio de descarte diferente para Props (10m) e Players reais (50m)
			var max_dist = 11.0 if id >= 1000 else 52.0
			
			if dist > max_dist:
				cubes[id].visible = false
			elif _last_rx.has(id) and now - _last_rx[id] > 500:
				cubes[id].visible = false
			else:
				cubes[id].visible = true
				
	# [SNAPSHOT INTERPOLATION REMOTA]
	# Em vez de ditar a posição diretamente quando a rede notifica, 
	# consumimos `remote_state` a cada quadro.
	# O QuanticNet usa seu Jitter Buffer circular interno e devolve uma mesclagem suave
	# entre os pacotes do passado (compensando latência oscilante do Netem).
	for id in cubes.keys():
		if id == my_id:
			continue
		var s := QuanticNet.remote_state(id)
		if not s.is_empty():
			cubes[id].position = s["pos"]
			cubes[id].rotation = s["rot"]

func _on_state(owner: int, pos: Vector3, rot: Vector3, _custom: int) -> void:
	# Sinal bruto disparado assim que o pacote desembarca no cliente
	# após ser decodificado pelo domínio.
	if not QuanticNet.is_server():
		if _last_rx.has(owner):
			var gap = Time.get_ticks_msec() - _last_rx[owner]
			# Se demorou mais de 200ms para receber a nova posição (devido a perda de pacote ou netem), 
			# imprime log alertando sobre o atraso
			if owner >= 1000 and gap > 200:
				print("[CLIENT] Recebeu %d apos %d ms! Pos: %s" % [owner, gap, str(pos)])
				
	_last_rx[owner] = Time.get_ticks_msec()
	
	# Prevenção: O pacote de um peer chegou, mas o sinal "peer_joined" da Engine 
	# atrasou internamente. Inicializamos o cubo preemptivamente.
	if not QuanticNet.is_server() and not cubes.has(owner) and owner != QuanticNet.get_unique_id():
		_on_peer_joined(owner)
		
	# Caso o pacote chegue, re-ativamos a visibilidade instantânea (Saindo do Culling Oculto).
	if not QuanticNet.is_server() and cubes.has(owner) and not cubes[owner].visible:
		cubes[owner].position = pos
		cubes[owner].rotation = rot
		cubes[owner].visible = true
		
	# No servidor, este é o momento onde o pacote validado do cliente 
	# altera de fato o estado global autoritativo mantido na memória visual do host.
	if QuanticNet.is_server() and cubes.has(owner):
		cubes[owner].position = pos
		cubes[owner].rotation = rot

func _calc_prop_pos(offset: int, time: float) -> Vector3:
	# Lógica matemática (sem uso do motor de colisão da Engine) 
	# que gera um movimento determinístico e harmônico para os Props no cenário.
	# Golden angle (~2.3999 radianos) distribui os cubos radialmente de forma uniforme.
	var angle = offset * 2.4 + time * 0.2
	var radius = 5.0 + (offset % 10) * 2.0 + sin(time * 0.5 + offset) * 2.0
	return Vector3(cos(angle) * radius, 0.5, sin(angle) * radius)

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	# [RECONCILIAÇÃO DO SERVIDOR]
	# O servidor cassou a nossa predição por irregularidade grave! 
	# Ex: andamos por dentro de uma parede, fomos empurrados, ou speedhack.
	# Num jogo real, faríamos algo como:
	# player.position = pos
	# for past_input in replay:
	#     player.move_with_input(past_input.dt) 
	print("[DEMO] snapback (seq=%d reason=%d replay=%d)" % [seq, reason, replay.size()])
