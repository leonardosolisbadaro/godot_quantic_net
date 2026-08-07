## @file demo_main.gd
## @path res://addons/quantic_net/demo/demo_main.gd
##
## @description
## Cena demo principal e Ponto de Entrada (Entry Point) do QuanticNet.
## 
## Esta demo foi construída passo-a-passo (Fase 1 e Fase 2) com o objetivo primário de ser um 
## "Playground Educativo" (Bare Metal). Ao invés de mergulhar instantaneamente em mecânicas complexas 
## de um jogo específico (movimentação, câmeras complexas, inventários), este arquivo expõe a 
## anatomia crua do plugin.
## 
## Aqui você encontrará a fundação necessária para um MMO 3D:
## - Auto-Topologia: O script clona a si mesmo para abrir Servidor e Clientes simulando um ambiente real.
## - Profilers Robustos: Métricas reais de CPU, GPU, Engine e Rede (com médias, mínimos e máximos).
## - Inicialização de Rede: Injeção do MultiplayerAPI, host, join e suporte automático ao DTLS.
## - Netem (Network Emulation): Injeção nativa de latência, perda e jitter direto na placa simulada.
##
## @created 2026-08-06
## @updated 2026-08-06
##
## @since 0.5.0
## @lastModifiedIn 0.5.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends Node3D

# ==============================================================================
# CONSTANTES GLOBAIS DE SISTEMA E PERFORMANCE
# ==============================================================================
const UI_UPDATE_RATE_MS := 250
const BYTES_TO_MB := 1048576.0
const SEC_TO_MS := 1000.0
const TARGET_FPS := 60
const SENTINEL_MAX_FLOAT := 9999.0
const SENTINEL_MAX_INT := 9999

const RTT_HISTORY_MAX := 50
const MAX_PEERS := 32
const PERCENTILE_1_LOW := 0.01

# Constantes de Cena (Mundo 3D)
const CAMERA_START_POS := Vector3(0, 8, 10)
const CAMERA_START_ROT := Vector3(-35, 0, 0)
const FLOOR_SIZE := Vector2(40, 40)

# Constantes de Interface
const UI_MARGIN_STD := 20
const UI_MARGIN_LARGE := 40
const UI_SPACER := 15
const OUTLINE_THICK := 4
const OUTLINE_THIN := 3

# ==============================================================================
# VARIÁVEIS DE REDE E CONFIGURAÇÕES DO QUANTICNET
# ==============================================================================
# A porta e o segredo são a fundação do DTLS e da conexão. 
# O "secret" é um token de autenticação simétrica primária exigido pelo QuanticNet 
# para bloquear pacotes de scanners ou conexões espúrias antes mesmo de alocar memória.
const PORT := 4242
const SECRET := "demo-secret"

# Este dicionário é passado diretamente para as funções host() e join(). 
# Ele define as regras globais de comportamento autoritativo do Servidor e da Emulação.
var _network_config = {
	"max_speed": 30.0, # Tolerância elevada do Anti-Speedhack (Absorve os Jitters extremos do NETEM)
	"hard_cap": 50.0, # Velocidade absurda (cair, teleportar) onde a interpolação é desligada e vira um "teleporte visual" (snap)
	"world_bounds": 60.0, # Limites do mundo (anti-fly/anti-void)
	"max_strikes": 5, # Quantas vezes um cliente pode enviar pacotes inválidos antes de ser kickado
	"auth_timeout": 3.0, # Tempo máximo (segundos) tolerado na fase de handshake
	"netem_loss": 10.0, # [NETEM] % de perda de pacote forçada
	"netem_latency": 150, # [NETEM] Milissegundos atrasados intencionalmente na fila de despacho
	"netem_jitter": 50, # [NETEM] Variação aleatória do atraso (simulando 4G/Wifi oscilante)
	"netem_dup": 0.0 # [NETEM] % de duplicação de pacotes (simula re-envios fantasma de rotas ruins)
}

# Controle de estado da topologia local
var _is_server: bool = false
var _my_id: int = 0

# ==============================================================================
# PERFIS DE ENTIDADES (FASE 3)
# ==============================================================================
var _profile_player: QNEntityProfile
var _profile_npc: QNEntityProfile
var _profile_prop: QNEntityProfile
var _profile_projectile: QNEntityProfile

# ------------------------------------------------------------------------------
# RASTREAMENTO E HISTÓRICOS DE REDE (ALIMENTADO VIA SINAIS)
# ------------------------------------------------------------------------------
# Diferente do "Ping" de terminal (ICMP), o QuanticNet mede o RTT (Round Trip Time)
# embutindo os timestamps no cabeçalho dos pacotes UDP. Nós escutamos o sinal 
# 'pong_received' para atualizar essas variáveis na UI, garantindo que reflitam 
# exatamente o pulso real da rede no jogo.
var _current_rtt: float = 0.0
var _current_offset: float = 0.0
var _rtt_history: Array[float] = []
var _rtt_min: float = SENTINEL_MAX_FLOAT
var _rtt_max: float = 0.0

var _loss_history: Array[float] = []
var _loss_min: float = SENTINEL_MAX_FLOAT
var _loss_max: float = 0.0

# ==============================================================================
# VARIÁVEIS DE ESTADO DA INTERFACE E SISTEMA
# ==============================================================================
var _world_root: Node3D
var _entities_visuals: Dictionary = {}
var _local_pos: Vector3 = Vector3(0, 1.0, 0)
var _auto_move: bool = false
var _auto_move_origin: Vector3 = Vector3.ZERO
var _auto_move_time: float = 0.0
var _server_props: Array = [1001, 1002, 1003] # [Fase 5] Props
var _server_props_time: float = 0.0
var _client_view_distance: float = 12.0
var _client_cull_ring: MeshInstance3D
var _server_cull_ring: MeshInstance3D
var _status_lbl: Label
var _reconnect_btn: Button
var _last_shot_time: int = 0 # [Fase 6] Cooldown de tiros

# Labels do System Profiler (CPU, RAM, GPU, Engine)
var _diag_lbl_fps: Label
var _diag_lbl_frametime: Label
var _diag_lbl_phys: Label
var _diag_lbl_mem: Label
var _diag_lbl_vram: Label
var _diag_lbl_draws: Label
var _diag_lbl_nodes: Label

# Labels do Network Profiler (RTT, Loss, Offset)
var _diag_lbl_netem: Label
var _diag_lbl_rtt: Label
var _diag_lbl_loss: Label
var _diag_lbl_offset: Label
var _diag_lbl_peers: Label

# ------------------------------------------------------------------------------
# VARIÁVEIS DE CONTROLE DE THROTTLE E ESTATÍSTICA
# ------------------------------------------------------------------------------
# O '_last_ui_update_ms' é crucial. Modificar textos na UI do Godot recalcula 
# fontes e malhas (meshes) 2D. Se fizermos isso a 144Hz (todo frame), causaremos 
# gargalo na CPU. Nós estrangulamos (throttle) a UI para atualizar apenas a cada 250ms.
var _last_ui_update_ms: int = 0
var _netem_active: bool = false

# Histórico para cálculos estatísticos (1% Low, Médias)
# Mantemos um array com os últimos 600 valores (10 segundos a 60fps)
var _fps_history: Array[int] = []
const FPS_HISTORY_MAX = 600
var _fps_min: int = SENTINEL_MAX_INT
var _fps_max: int = 0

var _frame_ms_history: Array[float] = []
var _frame_ms_min: float = SENTINEL_MAX_FLOAT
var _frame_ms_max: float = 0.0

var _phys_ms_history: Array[float] = []
var _phys_ms_min: float = SENTINEL_MAX_FLOAT
var _phys_ms_max: float = 0.0


# ==============================================================================
# CICLO DE VIDA (LIFECYCLE) - O PONTO DE ENTRADA
# ==============================================================================

func _ready() -> void:
	# 1. Configura a UI de diagnóstico via código (Clean Architecture, zero painéis sujos na árvore)
	_setup_ui()
	
	# 2. Força o V-Sync para estabilizar os testes locais em 60Hz.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	
	# 3. Mágica da Topologia Automática (Auto-Spawn)
	# Ao invés de compilarmos executáveis separados, lemos os parâmetros da linha de comando.
	# Se a demo for executada diretamente pelo Godot (F5), ela não terá parâmetros. 
	# Nesse caso, a própria demo "clona" duas novas janelas via OS.create_instance e se torna o Servidor.
	var args = OS.get_cmdline_user_args()
	var is_server = args.has("--server")
	var is_client = args.has("--client")
	var use_netem = args.has("--netem")
	
	if use_netem:
		_netem_active = true
		
	if not is_server and not is_client:
		print("[DEMO] Iniciando topologia automática: 1 Servidor, 2 Clientes...")
		is_server = true
		
		# Cliente 1 (Conexão limpa e perfeita)
		OS.create_instance(["--client"])
		
		# Cliente 2 (Conexão caótica via emulador de rede)
		OS.create_instance(["--client", "--netem"])
		
		DisplayServer.window_set_title("QuanticNet - SERVER (Fase 1)")
		
	if is_client:
		var title = "QuanticNet - CLIENT"
		if use_netem:
			title += " (NETEM ON)"
		title += " (Fase 2)"
		DisplayServer.window_set_title(title)
		
	_is_server = is_server
		
	# 4. Perfis Dinâmicos (Tick Rate vs Priority vs Culling Radius)
	_profile_player = QNEntityProfile.new()
	_profile_player.init(60.0, 1.0, 20.0) # 60Hz default, 20m culling
	
	_profile_npc = QNEntityProfile.new()
	_profile_npc.init(20.0, 1.0, 20.0) # 20Hz
	
	_profile_prop = QNEntityProfile.new()
	_profile_prop.init(5.0, 0.5, 20.0) # 5Hz Default
	
	_profile_projectile = QNEntityProfile.new()
	_profile_projectile.init(60.0, 3.0, 50.0) # 60Hz (Prioridade Extrema)
		
	# 5. Conectando os Sinais Vitais (Event-Driven Architecture)
	# O QuanticNet emite sinais limpos quando eventos ocorrem nas entranhas do C++.
	QuanticNet.connection_state_changed.connect(_on_conn_state)
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.pong_received.connect(_on_pong_received)
	QuanticNet.state_received.connect(_on_state)
	QuanticNet.snapback_received.connect(_on_snapback)
	
	# 5. Configura cenário 3D visual mínimo para que a tela não fique cinza.
	_setup_scene()
	
	# 6. Força o FPS cravado inicial para o atalho F funcionar corretamente
	Engine.max_fps = TARGET_FPS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	
	# 7. Iniciando os Motores (Bootstrapping do ENet + DTLS)
	if _is_server:
		print("[DEMO] Iniciando SERVIDOR QuanticNet (Porta %d)..." % PORT)
		QuanticNet.host(PORT, SECRET, "127.0.0.1", MAX_PEERS, _network_config)
		
		# O Servidor registra a si mesmo (ID 1)
		QuanticNet.register_entity(1, true, true, _profile_player)
		
		# [Fase 5] Servidor instanciando Props Autoritativos
		for prop_id in _server_props:
			QuanticNet.register_entity(prop_id, false, true, _profile_prop)
	else:
		print("[DEMO] Iniciando CLIENTE QuanticNet...")
		QuanticNet.join("127.0.0.1", PORT, SECRET, use_netem, _network_config)
		
	# 7. Blindagem e Encapsulamento da Engine
	# Este é o truque de ouro: forçamos a Árvore de Cena do Godot a enxergar o roteador (MultiplayerAPI)
	# que o QuanticNet construiu em C++. Isso faz com que RPCs nativos funcionem de forma transparente 
	# através dos túneis ultra-otimizados do nosso plugin.
	get_tree().set_multiplayer(QuanticNet.get_tree().get_multiplayer(QuanticNet.get_path()), self.get_path())
	
	print("[DEMO] Fase 2 inicializada. Conexão engatilhada e Sinais Ativos.")

func _notification(what: int) -> void:
	# Captura o evento de "X" (fechar janela) a nível de Sistema Operacional.
	# Desconectar manualmente limpa as filas de UDP e destrói as Threads internas em C++,
	# evitando "Zombies" na RAM ou portas presas no Roteador.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		QuanticNet.disconnect_net(true)
		get_tree().quit()

func _setup_scene() -> void:
	# Uma câmera isométrica, uma luz direcional com sombras e um chão escuro.
	var cam := Camera3D.new()
	cam.position = CAMERA_START_POS
	cam.rotation_degrees = CAMERA_START_ROT
	add_child(cam)
	
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	add_child(light)
	
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = FLOOR_SIZE
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.25)
	plane.material = mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	
	_world_root = Node3D.new()
	add_child(_world_root)
	
	if not _is_server:
		_client_cull_ring = _create_ring(Color(0.0, 1.0, 0.0, 0.3), 10.0, 0.1)
		add_child(_client_cull_ring)
		_server_cull_ring = _create_ring(Color(1.0, 1.0, 0.0, 0.3), 10.2, 0.2)
		add_child(_server_cull_ring)

func _create_ring(color: Color, radius: float, y_offset: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - 0.2
	mesh.outer_radius = radius
	mesh.rings = 64
	mesh.ring_segments = 32
	mi.mesh = mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position.y = y_offset
	return mi


# ==============================================================================
# INTERFACE DE USUÁRIO (HUD & PROFILERS)
# ==============================================================================

func _setup_ui() -> void:
	# CanvasLayer garante que nossos textos flutuem na tela 2D ignorando a câmera 3D.
	var hud = CanvasLayer.new()
	
	# ... (Barra do topo - Status) ...
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	
	_status_lbl = Label.new()
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_lbl.text = "OFFLINE (Aguardando Sinal)"
	_status_lbl.add_theme_color_override("font_color", Color.GRAY)
	top_panel.add_child(_status_lbl)
	hud.add_child(top_panel)
	
	# ... (Dicas e Atalhos na Esquerda) ...
	var margin_shortcuts = MarginContainer.new()
	margin_shortcuts.add_theme_constant_override("margin_left", UI_MARGIN_STD)
	margin_shortcuts.add_theme_constant_override("margin_top", UI_MARGIN_LARGE)
	
	var vbox_shortcuts = VBoxContainer.new()
	var shortcuts = [
		"CONTROLES IN-GAME (Fase 4):",
		"F1         : Resetar System Metrics",
		"F2         : Resetar Network Metrics",
		"Setas/WASD : Mover (CSP)",
		"Enter      : Auto-Move On/Off",
		"F          : Destravar FPS / V-Sync",
		"N          : Ativar/Desativar NETEM",
		"1 a 5      : Profile Peers (20 a 1Hz)",
		"6 a 0      : Profile Culling (5 a 100m)"
	]
	
	for s in shortcuts:
		var lbl = Label.new()
		lbl.text = s
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
		lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		lbl.add_theme_constant_override("outline_size", OUTLINE_THICK) # Outline para legibilidade contra luzes brilhantes
		vbox_shortcuts.add_child(lbl)
		
	margin_shortcuts.add_child(vbox_shortcuts)
	hud.add_child(margin_shortcuts)
	
	# ... (Agregador de Profilers na Inferior Esquerda) ...
	var diag_margin = MarginContainer.new()
	diag_margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	diag_margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	diag_margin.add_theme_constant_override("margin_left", UI_MARGIN_STD)
	diag_margin.add_theme_constant_override("margin_bottom", UI_MARGIN_STD)
	
	var diag_vbox = VBoxContainer.new()
	
	# ---> SYSTEM PROFILER (Métricas Vitais da Engine)
	var diag_title = Label.new()
	diag_title.text = "[ SYSTEM PROFILER ]"
	diag_title.add_theme_color_override("font_color", Color.YELLOW)
	diag_vbox.add_child(diag_title)
	
	_diag_lbl_fps = Label.new()
	_diag_lbl_frametime = Label.new()
	_diag_lbl_phys = Label.new()
	_diag_lbl_mem = Label.new()
	_diag_lbl_vram = Label.new()
	_diag_lbl_draws = Label.new()
	_diag_lbl_nodes = Label.new()
	
	var labels_sys = [_diag_lbl_fps, _diag_lbl_frametime, _diag_lbl_phys, _diag_lbl_mem, _diag_lbl_vram, _diag_lbl_draws, _diag_lbl_nodes]
	for l in labels_sys:
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", OUTLINE_THIN)
		diag_vbox.add_child(l)
		
	var diag_spacer = Control.new()
	diag_spacer.custom_minimum_size = Vector2(0, UI_SPACER)
	diag_vbox.add_child(diag_spacer)
	
	# ---> NETWORK PROFILER (Métricas Vitais da Conexão UDP/DTLS)
	var net_title = Label.new()
	net_title.text = "[ NETWORK PROFILER ]"
	net_title.add_theme_color_override("font_color", Color.CYAN)
	diag_vbox.add_child(net_title)
	
	_diag_lbl_netem = Label.new()
	_diag_lbl_rtt = Label.new()
	_diag_lbl_loss = Label.new()
	_diag_lbl_offset = Label.new()
	_diag_lbl_peers = Label.new()
	
	var labels_net = [_diag_lbl_netem, _diag_lbl_rtt, _diag_lbl_loss, _diag_lbl_offset, _diag_lbl_peers]
	for l in labels_net:
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", OUTLINE_THIN)
		diag_vbox.add_child(l)
		
	diag_margin.add_child(diag_vbox)
	hud.add_child(diag_margin)
	add_child(hud)


# ==============================================================================
# LOOPS E ATUALIZAÇÕES VISUAIS (GAME LOOP)
# ==============================================================================

func _physics_process(delta: float) -> void:
	# O _physics_process é síncrono e cravado (60Hz default). 
	# Toda a matemática de movimentação, predição e rede pesada ocorre aqui.
	if QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		# [Fase 5] Servidor move Props Autoritativamente
		_server_props_time += delta
		for i in range(_server_props.size()):
			var prop_id = _server_props[i]
			var offset_time = _server_props_time + (i * 2.0)
			var pos = Vector3(sin(offset_time) * 4.0, 0.5, cos(offset_time) * 4.0 + (i * 3.0))
			QuanticNet.update_entity_state(prop_id, pos, Vector3.ZERO, 0, Time.get_ticks_msec())
			_update_visual(prop_id, pos, false) # Atualiza o visual do próprio servidor
			
	if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		var speed = 6.0 # Desacoplado da rede! (Player anda a 6m/s, mas o server tolera até 30m/s por conta do Jitter)
		var input_dir = Vector3.ZERO
		
		if not _auto_move:
			if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): input_dir.z -= 1
			if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): input_dir.z += 1
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): input_dir.x -= 1
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): input_dir.x += 1
		else:
			_auto_move_time += delta
			# Simula inputs agressivos mudando de direção rapidamente para testar o Client-Side Prediction sob estresse
			input_dir.x = sin(_auto_move_time * 3.0)
			input_dir.z = cos(_auto_move_time * 2.0)
			
		if input_dir.length_squared() > 0:
			input_dir = input_dir.normalized()
			
		# Se auto-move estiver ativo e sair do limite, forçar input_dir pro centro
		if _auto_move and _local_pos.distance_to(_auto_move_origin) > 8.0:
			input_dir = (_auto_move_origin - _local_pos).normalized()
			
		# [Fase 4] Client-Side Prediction: Movimenta instantaneamente o boneco local
		_local_pos += input_dir * speed * delta
		_update_visual(QuanticNet.get_unique_id(), _local_pos, true)
		
		# [Fase 6] Combate Zero-RPC
		var custom_input = 0
		var now = Time.get_ticks_msec()
		if now - _last_shot_time > 200:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				custom_input = 1 # Laser Hitscan
				_last_shot_time = now
				_spawn_laser(_local_pos, Color.AQUA)
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				custom_input = 2 # Projétil Físico
				_last_shot_time = now
				_spawn_laser(_local_pos, Color.ORANGE)
		
		# Envia a predição otimista de forma cravada para a Engine C++ assinar e rotear
		QuanticNet.submit_state(_local_pos, Vector3.ZERO, custom_input, delta)

func _process(_delta: float) -> void:
	# O _process é assíncrono à física e é atrelado apenas à Placa de Vídeo (Taxa de atualização do Monitor).
	# Usamos ele exclusivamente para ler métricas visuais cruas, evitando poluir o Thread de física.
	# [Fase 5] Snapshot Interpolation (Cliente suavizando os Props e Remotos)
	if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		var now = Time.get_ticks_msec()
		for id in _entities_visuals.keys():
			if id != QuanticNet.get_unique_id():
				var interp_state = QuanticNet.remote_state(id)
				if not interp_state.is_empty():
					var visual = _entities_visuals[id]
					var target_pos = interp_state.get("pos", visual.position)
					var last_up = visual.get_meta("last_update", now)
					
					# Culling Visual
					var rad = _profile_player.get_spatial_culling_radius() if id < 1000 else _profile_prop.get_spatial_culling_radius()
					var dist = _local_pos.distance_to(visual.position)
					
					# Se passou de 0.5s sem atualizar, o servidor removeu (Server Culling)
					# Se dist > _client_view_distance, o cliente ocultou localmente (Client Culling)
					var is_visible = (dist <= _client_view_distance) and (now - last_up <= 500)
					
					if not visual.visible and is_visible:
						# Acabou de entrar no raio (ou voltou a receber pacotes), não vamos patinar! 
						visual.position = target_pos
					else:
						# Visual Lerp PESADO (5.0) para mascarar Buffer Underruns extremos do Netem (Elasticidade)
						visual.position = visual.position.lerp(target_pos, _delta * 5.0)
					
					visual.visible = is_visible
					
		if _client_cull_ring and _server_cull_ring:
			_client_cull_ring.position = _local_pos
			_client_cull_ring.position.y = 0.1
			_server_cull_ring.position = _local_pos
			_server_cull_ring.position.y = 0.2
			
			if _client_cull_ring.mesh.outer_radius != _client_view_distance:
				_client_cull_ring.mesh.inner_radius = maxf(0.1, _client_view_distance - 0.2)
				_client_cull_ring.mesh.outer_radius = _client_view_distance
				
			var srv_rad = _profile_player.get_spatial_culling_radius()
			if _server_cull_ring.mesh.outer_radius != srv_rad + 0.3:
				_server_cull_ring.mesh.inner_radius = srv_rad + 0.1
				_server_cull_ring.mesh.outer_radius = srv_rad + 0.3
	# Histórico de FPS
	var current_fps = Engine.get_frames_per_second()
	if current_fps > 0:
		_fps_history.append(current_fps)
		if _fps_history.size() > FPS_HISTORY_MAX: _fps_history.pop_front()
		if current_fps < _fps_min: _fps_min = current_fps
		if current_fps > _fps_max: _fps_max = current_fps
		
	# Histórico de Frame Time (Tempo para montar o visual e a lógica)
	var frame_ms = Performance.get_monitor(Performance.TIME_PROCESS) * SEC_TO_MS
	if frame_ms > 0:
		_frame_ms_history.append(frame_ms)
		if _frame_ms_history.size() > FPS_HISTORY_MAX: _frame_ms_history.pop_front()
		if frame_ms < _frame_ms_min: _frame_ms_min = frame_ms
		if frame_ms > _frame_ms_max: _frame_ms_max = frame_ms
		
	# Histórico de Physics Time (O quão suada a CPU está para processar o Netcode)
	var phys_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * SEC_TO_MS
	if phys_ms > 0:
		_phys_ms_history.append(phys_ms)
		if _phys_ms_history.size() > FPS_HISTORY_MAX: _phys_ms_history.pop_front()
		if phys_ms < _phys_ms_min: _phys_ms_min = phys_ms
		if phys_ms > _phys_ms_max: _phys_ms_max = phys_ms
		
	# Histórico de Perdas
	var loss_val = 0.0
	if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		var id_to_check = QuanticNet.get_unique_id()
		var t2 = QuanticNet.get_telemetry(id_to_check)
		if t2:
			loss_val = t2.get_current_loss()
			_loss_history.append(loss_val)
			if _loss_history.size() > FPS_HISTORY_MAX: _loss_history.pop_front()
			if loss_val < _loss_min: _loss_min = loss_val
			if loss_val > _loss_max: _loss_max = loss_val
		
	_update_ui(current_fps, frame_ms, phys_ms, loss_val)

func _update_ui(current_fps: int, frame_ms: float, phys_ms: float, current_loss: float) -> void:
	var now_ms = Time.get_ticks_msec()
	
	# (Throttle) Ignora a atualização visual se passou menos do que UI_UPDATE_RATE_MS desde a última
	if now_ms - _last_ui_update_ms > UI_UPDATE_RATE_MS:
		_last_ui_update_ms = now_ms
		
		# --- Processamento Matemático dos Arrays de Histórico ---
		var fps_avg = 0
		var fps_1_low = 0
		if _fps_history.size() > 0:
			var sum = 0
			for f in _fps_history: sum += f
			fps_avg = sum / _fps_history.size()
			
			# O "1% Low" é crucial para MMOs: ele descarta os picos altos e te diz 
			# qual foi o Pior FPS do pior engasgo que o seu jogador sentiu recentemente.
			var sorted_fps = _fps_history.duplicate()
			sorted_fps.sort()
			var low_1_idx = max(0, int(sorted_fps.size() * PERCENTILE_1_LOW))
			fps_1_low = sorted_fps[low_1_idx]
			
		var frame_avg = 0.0
		if _frame_ms_history.size() > 0:
			var sum = 0.0
			for f in _frame_ms_history: sum += f
			frame_avg = sum / _frame_ms_history.size()
			
		var phys_avg = 0.0
		if _phys_ms_history.size() > 0:
			var sum = 0.0
			for p in _phys_ms_history: sum += p
			phys_avg = sum / _phys_ms_history.size()
			
		var rtt_avg = 0.0
		if _rtt_history.size() > 0:
			var sum = 0.0
			for r in _rtt_history: sum += r
			rtt_avg = sum / _rtt_history.size()
		var rtt_min_disp = _rtt_min if _rtt_min != SENTINEL_MAX_FLOAT else 0.0
		
		var loss_avg = 0.0
		if _loss_history.size() > 0:
			var sum = 0.0
			for l in _loss_history: sum += l
			loss_avg = sum / _loss_history.size()
		var loss_min_disp = _loss_min if _loss_min != SENTINEL_MAX_FLOAT else 0.0
			
		# --- Injeção nas Labels (System Profiler) ---
		_diag_lbl_fps.text = "FPS: %d | Avg: %d | Min: %d | Max: %d | 1%% Low: %d" % [current_fps, fps_avg, _fps_min, _fps_max, fps_1_low]
		var frame_min_disp = _frame_ms_min if _frame_ms_min != SENTINEL_MAX_FLOAT else 0.0
		_diag_lbl_frametime.text = "Frame Time: %.2f ms | Avg: %.2f | Min: %.2f | Max: %.2f" % [frame_ms, frame_avg, frame_min_disp, _frame_ms_max]
		var phys_min_disp = _phys_ms_min if _phys_ms_min != SENTINEL_MAX_FLOAT else 0.0
		_diag_lbl_phys.text = "Physics Time: %.2f ms | Avg: %.2f | Min: %.2f | Max: %.2f" % [phys_ms, phys_avg, phys_min_disp, _phys_ms_max]
		
		var ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_TO_MB
		_diag_lbl_mem.text = "RAM (Static): %.2f MB" % ram_mb
		
		var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_TO_MB
		_diag_lbl_vram.text = "VRAM (Video): %.2f MB" % vram_mb
		
		var draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_diag_lbl_draws.text = "Draw Calls: %d" % draws
		
		var active_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var orphan_nodes = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		var objects = Performance.get_monitor(Performance.OBJECT_COUNT)
		_diag_lbl_nodes.text = "Nodes: %d | Orphans: %d | Objects: %d" % [active_nodes, orphan_nodes, objects]
		
		# --- Injeção nas Labels (Network Profiler) ---
		var netem_str = "OFF"
		if _netem_active:
			var loss = _network_config["netem_loss"]
			var lat = _network_config["netem_latency"]
			var jit = _network_config["netem_jitter"]
			netem_str = "ON (Loss: %.0f%% | Lat: %dms | Jit: %dms)" % [loss, lat, jit]
		_diag_lbl_netem.text = "NETEM Status: %s" % netem_str
		
		var id_to_check = QuanticNet.get_unique_id()
		var t2 = QuanticNet.get_telemetry(id_to_check)
			
		if t2:
			_diag_lbl_rtt.text = "RTT (ms): %.0f | Avg: %.0f | Min: %.0f | Max: %.0f" % [_current_rtt, rtt_avg, rtt_min_disp, _rtt_max]
			_diag_lbl_loss.text = "Packet Loss: %.1f%% | Avg: %.1f%% | Min: %.1f%% | Max: %.1f%%" % [current_loss, loss_avg, loss_min_disp, _loss_max]
			_diag_lbl_offset.text = "Clock Offset: %.1f ms" % _current_offset
		else:
			_diag_lbl_rtt.text = "RTT (ms): Aguardando..."
			_diag_lbl_loss.text = "Packet Loss: Aguardando..."
			_diag_lbl_offset.text = "Clock Offset: Aguardando..."
			
		var total_entities = 0
		var count_peers = 0
		var count_props = 0
		
		if QuanticNet.is_server():
			var registry = QuanticNet.get_registry()
			total_entities = registry.size()
			for k in registry:
				if registry[k].get("is_peer", false):
					count_peers += 1
				else:
					count_props += 1
		else:
			for id in _entities_visuals.keys():
				var last_up = _entities_visuals[id].get_meta("last_update", now_ms)
				if now_ms - last_up <= 500:
					total_entities += 1
					if id < 1000:
						count_peers += 1
					else:
						count_props += 1
				
		_diag_lbl_peers.text = "Entities: %d (Peers: %d | Props: %d)" % [total_entities, count_peers, count_props]

# ==============================================================================
# SINAIS DE REDE (EVENT-DRIVEN CALLBACKS)
# ==============================================================================

func _on_conn_state(state: int) -> void:
	# Máquina de estados global exposta pelo Autoload do QuanticNet
	match state:
		QuanticNet.ConnectionState.DISCONNECTED:
			_status_lbl.text = "DISCONNECTED"
			_status_lbl.add_theme_color_override("font_color", Color.GRAY)
		QuanticNet.ConnectionState.CONNECTING:
			_status_lbl.text = "CONNECTING..."
			_status_lbl.add_theme_color_override("font_color", Color.YELLOW)
		QuanticNet.ConnectionState.AUTHENTICATING:
			_status_lbl.text = "AUTHENTICATING..."
			_status_lbl.add_theme_color_override("font_color", Color.ORANGE)
		QuanticNet.ConnectionState.CONNECTED:
			_status_lbl.text = "CONNECTED"
			_status_lbl.add_theme_color_override("font_color", Color.GREEN)
		QuanticNet.ConnectionState.FAILED:
			_status_lbl.text = "FAILED"
			_status_lbl.add_theme_color_override("font_color", Color.RED)

func _on_pong_received(rtt: float, offset: float) -> void:
	# Sempre que o servidor responde a um carimbo de tempo embutido em um pacote, 
	# o QuanticNet calcula a viagem de ida e volta (RTT) e a desincronização 
	# dos relógios entre a sua máquina e o Servidor (Offset) e atira este sinal.
	_current_rtt = rtt
	_current_offset = offset
	
	_rtt_history.append(rtt)
	if _rtt_history.size() > RTT_HISTORY_MAX:
		_rtt_history.pop_front()
		
	if rtt < _rtt_min: _rtt_min = rtt
	if rtt > _rtt_max: _rtt_max = rtt

func _on_peer_joined(peer_id: int) -> void:
	print("[DEMO] Peer Joined: %d" % peer_id)
	if _is_server:
		QuanticNet.register_entity(peer_id, true, true, _profile_player)

func _on_peer_left(peer_id: int) -> void:
	print("[DEMO] Peer Left: %d" % peer_id)
	if _is_server:
		QuanticNet.unregister_entity(peer_id)
		
	if _entities_visuals.has(peer_id):
		var v = _entities_visuals[peer_id]
		v.queue_free()
		_entities_visuals.erase(peer_id)
		
func _update_visual(id: int, pos: Vector3, is_local: bool) -> void:
	if not _entities_visuals.has(id):
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1, 2, 1) if id < 1000 else Vector3(1, 1, 1)
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		if is_local:
			mat.albedo_color = Color.GREEN
		elif id < 1000:
			mat.albedo_color = Color.RED
		else:
			mat.albedo_color = Color.YELLOW
		mesh_inst.material_override = mat
		_world_root.add_child(mesh_inst)
		_entities_visuals[id] = mesh_inst
		
	var visual = _entities_visuals[id]
	if is_local or QuanticNet.is_server():
		visual.position = pos

func _on_state(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
	# Recebemos o Snapshot do Servidor confirmando onde o inimigo (ou nó mesmo) está.
	# Ignoramos a nós mesmos por ora porque usamos predição instantânea local.
	if owner != QuanticNet.get_unique_id():
		if not _entities_visuals.has(owner):
			_update_visual(owner, pos, false)
			
		var visual = _entities_visuals[owner]
		visual.set_meta("last_update", Time.get_ticks_msec())
			
		# [Fase 6] Disparo propagado via C++
		if custom == 1:
			_spawn_laser(pos, Color.AQUA)
		elif custom == 2:
			_spawn_laser(pos, Color.ORANGE)

func _spawn_laser(start_pos: Vector3, color: Color) -> void:
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.2, 2.0, 0.2)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	mesh.material_override = mat
	mesh.position = start_pos + Vector3(0, 2, 0)
	_world_root.add_child(mesh)
	
	var tween = get_tree().create_tween()
	tween.tween_property(mesh, "position", mesh.position + Vector3(0, 10, 0), 0.5)
	tween.tween_callback(mesh.queue_free)

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	# O Snapback é o corretivo severo do Servidor (Reconciliação). 
	# Se a simulação do cliente discordou gravemente da matriz de física do Servidor,
	# recebemos esta "bronca" para teletransportar o corpo e reprocessar os inputs (replay).
	print("[DEMO] Snapback Recebido (Reconciliação Forçada): %s" % str(pos))
	
	_local_pos = pos
	
	# [Fase 4] Re-apply pending inputs
	var speed = 6.0 # Velocidade do client fixada em 6.0 m/s
	for pending in replay:
		var dir = pending["move"]
		var dt = pending["dt"]
		_local_pos += Vector3(dir.x, 0, dir.y) * speed * dt

# ==============================================================================
# PROCESSAMENTO DE INPUTS GLOBAIS
# ==============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# _unhandled_input intercepta cliques que "vazaram" da Interface de Usuário.
	# Garante que um clique em um botão na UI não atire uma arma acidentalmente no 3D.
	if event is InputEventKey and event.pressed and not event.echo:
		# [N] - Toggle Netem (Network Emulation)
		if event.keycode == KEY_N:
			_netem_active = not _netem_active
			var loss = _network_config["netem_loss"] if _netem_active else 0.0
			var lat = _network_config["netem_latency"] if _netem_active else 0
			var jit = _network_config["netem_jitter"] if _netem_active else 0
			var dup = _network_config["netem_dup"] if _netem_active else 0.0
			
			QuanticNet.set_netem_config(loss, lat, jit, dup)
			var status = "ON (Loss: %.0f%% | Lat: %dms | Jit: %dms)" % [loss, lat, jit] if _netem_active else "OFF"
			print("[DEMO] NETEM Toggle: %s" % status)
			
		# [F1] - Resetar Métricas de System
		elif event.keycode == KEY_F1:
			_fps_history.clear()
			_fps_min = SENTINEL_MAX_INT
			_fps_max = 0
			_frame_ms_history.clear()
			_frame_ms_min = SENTINEL_MAX_FLOAT
			_frame_ms_max = 0.0
			_phys_ms_history.clear()
			_phys_ms_min = SENTINEL_MAX_FLOAT
			_phys_ms_max = 0.0
			print("[DEMO] System Profiler resetado!")
			
		# [F2] - Resetar Métricas de Network
		elif event.keycode == KEY_F2:
			_rtt_history.clear()
			_rtt_min = SENTINEL_MAX_FLOAT
			_rtt_max = 0.0
			_loss_history.clear()
			_loss_min = SENTINEL_MAX_FLOAT
			_loss_max = 0.0
			print("[DEMO] Network Profiler resetado!")
			
		# [F] - Toggle V-Sync e Max FPS (Teste de Stress visual)
		elif event.keycode == KEY_F:
			if Engine.max_fps == 0:
				Engine.max_fps = TARGET_FPS
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print("[DEMO] FPS Limitado: ", "SIM (60Hz)" if Engine.max_fps == 60 else "NÃO (Unlimited)")
			
		# [1-5] - Tick Rate do Profile
		elif event.keycode == KEY_1: _request_profile_change(20.0, -1)
		elif event.keycode == KEY_2: _request_profile_change(10.0, -1)
		elif event.keycode == KEY_3: _request_profile_change(5.0, -1)
		elif event.keycode == KEY_4: _request_profile_change(1.0, -1)
		elif event.keycode == KEY_5: _request_profile_change(60.0, -1)
		
		# [6-0] - Culling Radius do Profile
		elif event.keycode == KEY_6: _request_profile_change(-1, 5.0)
		elif event.keycode == KEY_7: _request_profile_change(-1, 10.0)
		elif event.keycode == KEY_8: _request_profile_change(-1, 20.0)
		elif event.keycode == KEY_9: _request_profile_change(-1, 50.0)
		elif event.keycode == KEY_0: _request_profile_change(-1, 100.0)
			
		# [ENTER] - Toggle Auto-Move (Será integrado na Fase 4)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_auto_move = not _auto_move
			if _auto_move:
				_auto_move_origin = _local_pos
			print("[DEMO] Auto-move: ", _auto_move)
			
		# [+ / -] - Client View Distance (Visual Culling)
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_client_view_distance += 2.0
			print("[DEMO] View Distance: ", _client_view_distance)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_client_view_distance = maxf(2.0, _client_view_distance - 2.0)
			print("[DEMO] View Distance: ", _client_view_distance)

# ==============================================================================
# PERFIS DINÂMICOS (TESTE DE ARQUITETURA)
# ==============================================================================

func _request_profile_change(tick: float, culling: float) -> void:
	# Atualiza o perfil local ANTES de avisar o Servidor
	var t = tick if tick > 0 else _profile_player.get_tick_rate_hz()
	var c = culling if culling > 0 else _profile_player.get_spatial_culling_radius()
	_profile_player.init(t, _profile_player.get_base_priority(), c)

	if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		rpc_id(1, "server_update_profile", QuanticNet.get_unique_id(), tick, culling)
	elif _is_server:
		server_update_profile(1, tick, culling)

@rpc("any_peer", "call_local")
func server_update_profile(peer_id: int, new_tick: float, new_culling: float) -> void:
	if not QuanticNet.is_server(): return
	var registry = QuanticNet.get_registry()
	if registry.has(peer_id):
		var old_prof = registry[peer_id].get("profile")
		if old_prof != null:
			var t = new_tick if new_tick > 0 else old_prof.get_tick_rate_hz()
			var c = new_culling if new_culling > 0 else old_prof.get_spatial_culling_radius()
			var new_prof = QNEntityProfile.new()
			new_prof.init(t, old_prof.get_base_priority(), c)
			QuanticNet.change_entity_profile(peer_id, new_prof)
			print("[DEMO] Perfil Atualizado para Peer %d: %.1fHz | Culling: %.1fm" % [peer_id, t, c])
