## @file demo_main.gd
## @path res://addons/quantic_net/demo/demo_main.gd
##
## @description
## Cena principal de simulação e ponto de entrada da arquitetura QuanticNet.
##
## Este script atua como um "Playground Bare Metal". O objetivo não é simular
## mecânicas de um jogo complexo (como inventário ou física de veículos), mas sim expor
## e validar o comportamento bruto das abstrações de rede, culling e sincronização sob estresse.
##
## Fundações arquiteturais demonstradas aqui:
## - Topologia Espelhada: O script se duplica em instâncias independentes para simular Servidor e Clientes locais, evitando a necessidade de builds separados.
## - Profiling de Baixo Nível: Coleta e exibe ativamente as métricas vitais da Engine (CPU/RAM/GPU) cruzadas com o tráfego UDP (RTT/Jitter/Loss).
## - Handshake e Camada Segura: Exemplo claro de como acoplar o ENet e a criptografia DTLS usando os pacotes nativos da Godot.
## - Network Emulation (NETEM): Injeção artificial de cenários adversos de rede (latência, perdas e duplicação) para testar a resiliência do Client-Side Prediction.
##
## @created 2026-08-06
## @updated 2026-08-07
##
## @since 0.5.0
## @lastModifiedIn 0.6.0
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
# Limites do mundo físico instanciado (40x40 metros). O Culling Geral será um percentual disso.
const FLOOR_SIZE := Vector2(40, 40)
const SERVER_PROPS: Array[int] = [1001, 1002, 1003]
# O Grid Culling dividirá o mundo em chunks menores. Aqui definimos que o AoI (Area of Interest) cobrirá 50% do chão.
const GENERAL_AOI_RATIO := 0.5

# Constantes de Interface
const UI_MARGIN_STD := 20
const UI_MARGIN_LARGE := 40
const UI_SPACER := 15
const OUTLINE_THICK := 4
const OUTLINE_THIN := 3

# Constantes de Gameplay (Valores Extraídos para Configuração)
const DEFAULT_VIEW_DISTANCE := 12.0 # Raio dinâmico no qual o Cliente decide renderizar ou ocultar entidades locais.
const CLIENT_MOVE_SPEED := 6.0 # Deslocamento cravado do avatar. Variável blindada que o Servidor usará no Anti-Speedhack.
const SHOOT_COOLDOWN_MS := 200 # Limita o spam de "Zero-RPC" para evitar overhead na predição de inputs.
const SERVER_CULL_TIMEOUT_MS := 2000 # Define quanto tempo o Client aguarda antes de "matar" uma entidade visualmente por inanição de pacotes.
const INTERP_LERP_SPEED := 5.0 # Suavização visual (Client-Side Interpolation)

# Constantes de Padrão de Movimento (Auto-Move e Props)
const AUTO_MOVE_RADIUS := 8.0
const AUTO_MOVE_SPEED_X := 3.0
const AUTO_MOVE_SPEED_Z := 2.0
const PROP_ORBIT_RADIUS := 4.0
const PROP_ORBIT_SPACING := 3.0
const PROP_HEIGHT := 0.5

# ==============================================================================
# VARIÁVEIS DE REDE E CONFIGURAÇÕES DO QUANTICNET
# ==============================================================================
# Definem o canal de comunicação via Socket. A chave `SECRET` é vital para o Handshake DTLS;
# ela atua como um pre-shared token, descartando imediatamente scanners TCP/UDP ou acessos espúrios
# antes mesmo que o ENet aloque recursos, mitigando ataques de DDOS na camada de aplicação.
const PORT := 4242
const SECRET := "demo-secret"

# Dicionário passado para a Engine C++ (QuanticNet) durante a inicialização via `host()` ou `join()`.
# Concentra todas as regras de validação, limites de desconexão e parâmetros do emulador de rede (NETEM).
var _global_network_parameters = {
	"max_speed": 30.0, # Limiar elástico do Anti-Speedhack. Alto para acomodar os solavancos drásticos causados pela simulação do Netem.
	"hard_cap": 50.0, # Se a distância do vetor ultrapassar este limite, a Engine descarta interpolações suaves e aplica um "Snap" (teleporte corretivo absoluto).
	"world_bounds": 60.0, # Fronteira matemática invisível. Entidades além dessa borda são removidas do registro autoritativo para poupar processamento Culling.
	"max_strikes": 5, # Contador de punição. Inputs flagrados por validação incorreta somam strikes até a desconexão compulsória (Kick).
	"auth_timeout": 3.0, # Margem (em segundos) para finalizar as chaves DTLS antes de derrubar a tentativa.
	"netem_loss": 10.0, # Simulação de colisão em redes ruins: % de pacotes que a placa virtual engolirá.
	"netem_latency": 150, # Injeção de RTT base forçado na rede local (Loopback).
	"netem_jitter": 50, # Flutuação randômica do atraso, imitando redes Mobile 4G instáveis.
	"netem_dup": 0.0, # Simula retransmissões fantasmas em roteadores congestionados.
	# Determina se o Spatial Partitioning (Grid) C++ filtrará o envio global.
	# Quando habilitado, o servidor estilhaça o mapa em setores menores, economizando a largura de banda.
	# "grid_culling_enabled": true, # Obsoleto - Substituído por QNSpatialGrid no Core
	# "grid_culling_size": (FLOOR_SIZE.x * GENERAL_AOI_RATIO) / 2.0,
}

# Controle de estado da topologia local
var auto_spawn_clients: bool = true
var _is_acting_as_server: bool = false
var _local_peer_id: int = 0

# ==============================================================================
# PERFIS DE ENTIDADES (TICK RATES E CULLING)
# ==============================================================================
var _entity_profile_player: QNEntityProfile
var _entity_profile_prop: QNEntityProfile
var _entity_profile_npc: QNEntityProfile
var _entity_profile_projectile: QNEntityProfile
var _profile_region_a: QNEntityProfile
var _profile_region_b: QNEntityProfile

# ------------------------------------------------------------------------------
# RASTREAMENTO E HISTÓRICOS DE REDE (ALIMENTADO VIA SINAIS)
# ------------------------------------------------------------------------------
# A engine C++ descarta a verificação clássica por "Ping/ICMP", pois ela embutirá
# o timestamp nativamente no micro-cabeçalho customizado dos nossos datagramas UDP.
# Escutamos os sinais emitidos da camada nativa para popular a UI sem bloquear as threads.
var _network_round_trip_time: float = 0.0
var _network_clock_offset: float = 0.0
var _round_trip_time_history: Array[float] = []
var _round_trip_time_minimum: float = SENTINEL_MAX_FLOAT
var _round_trip_time_maximum: float = 0.0

var _packet_loss_history: Array[float] = []
var _packet_loss_minimum: float = SENTINEL_MAX_FLOAT
var _packet_loss_maximum: float = 0.0

# ==============================================================================
# VARIÁVEIS DE ESTADO DA INTERFACE E SISTEMA
# ==============================================================================
var _scene_world_root_node: Node3D
var _active_visual_entities_map: Dictionary = { }
var _client_predicted_position: Vector3 = Vector3(0, 1.0, 0)
var _is_auto_movement_enabled: bool = false
var _auto_movement_center_origin: Vector3 = Vector3.ZERO
var _auto_movement_elapsed_time: float = 0.0
var _server_authoritative_props_time: float = 0.0
var _client_local_culling_radius: float = DEFAULT_VIEW_DISTANCE
var _show_culling_rings: bool = true
var _ui_label_connection_status: Label
var _ui_button_reconnect: Button
var _cooldown_timer_last_shot_ms: int = 0 # Previne sobrecarga de Input na rede.

# Labels do System Profiler (CPU, RAM, GPU, Engine)
var _ui_diagnostic_label_fps: Label
var _ui_diagnostic_label_frametime: Label
var _ui_diagnostic_label_phys: Label
var _ui_diagnostic_label_mem: Label
var _ui_diagnostic_label_vram: Label
var _ui_diagnostic_label_draws: Label
var _ui_diagnostic_label_nodes: Label

# Labels do Network Profiler (RTT, Loss, Offset)
var _ui_diagnostic_label_netem: Label
var _ui_diagnostic_label_rtt: Label
var _ui_diagnostic_label_loss: Label
var _ui_diagnostic_label_offset: Label
var _ui_diagnostic_label_peers: Label

var _camera: Camera3D

# ------------------------------------------------------------------------------
# VARIÁVEIS DE CONTROLE DE THROTTLE E ESTATÍSTICA
# ------------------------------------------------------------------------------
# Atualizar elementos visuais constantemente gera um custo alto de CPU devido ao
# recálculo de layouts e fontes. O sistema utiliza um throttle de 250ms para
# equilibrar a legibilidade com a performance.
var _ui_throttle_last_update_ms: int = 0
var _is_network_emulation_active: bool = false

# Histórico para o cálculo de métricas de estabilidade, como o percentil 1% Low.
var _frames_per_second_history: Array[int] = []
const FPS_HISTORY_MAX = 600
var _frames_per_second_minimum: int = SENTINEL_MAX_INT
var _frames_per_second_maximum: int = 0

var _frame_time_history: Array[float] = []
var _frame_time_minimum: float = SENTINEL_MAX_FLOAT
var _frame_time_maximum: float = 0.0

var _physics_time_history: Array[float] = []
var _physics_time_minimum: float = SENTINEL_MAX_FLOAT
var _physics_time_maximum: float = 0.0

# ==============================================================================
# CICLO DE VIDA (LIFECYCLE) - O PONTO DE ENTRADA
# ==============================================================================


func _ready() -> void:
	# Configura a UI de diagnóstico via código (Clean Architecture, zero painéis sujos na árvore)
	_setup_ui()

	# Corrige a anomalia visual da Câmera do Servidor
	# A ilusão de ótica ocorria porque janelas de tamanhos diferentes mudam o FOV horizontal nativo da Godot (Keep Height).
	# Cravamos um tamanho de tela padrão para que Servidor e Cliente mostrem o mesmo volume de mundo 3D.
	# DisplayServer.window_set_size(Vector2i(1024, 768))

	# Força o V-Sync para estabilizar os testes locais em 60Hz.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	# Orquestração Automática de Topologia (Auto-Spawn)
	# Gerencia a inicialização simultânea do ambiente de teste simulando a arquitetura autoritativa do servidor e múltiplos clientes locais conectando-se ao loopback (127.0.0.1).
	# Ao invés de compilarmos executáveis separados, lemos os parâmetros da linha de comando.
	# Se a demo for executada diretamente pelo Godot (F5), ela não terá parâmetros.
	# Nesse caso, a própria demo "clona" duas novas janelas via OS.create_instance e se torna o Servidor.
	var args = OS.get_cmdline_user_args()
	var is_server = args.has("--server")
	var is_client = args.has("--client")
	var use_netem = args.has("--netem")

	if use_netem:
		_is_network_emulation_active = true

	if auto_spawn_clients and not is_server and not is_client:
		print("[DEMO] Iniciando topologia automática: 1 Servidor, 2 Clientes...")
		is_server = true

		# Cliente 1 (Conexão limpa e perfeita)
		OS.create_instance(["--client"])

		# Cliente 2 (Conexão caótica via emulador de rede)
		OS.create_instance(["--client", "--netem"])

		DisplayServer.window_set_title("QuanticNet - SERVER")

	if is_client:
		var title = "QuanticNet - CLIENT"
		if use_netem:
			title += " (NETEM ON)"
		DisplayServer.window_set_title(title)

	_is_acting_as_server = is_server

	# Perfis Dinâmicos (Tick Rate vs Priority vs Culling Radius)
	_entity_profile_player = QNEntityProfile.new()
	_entity_profile_player.init(60.0, 1.0, 20.0) # Hz default, 20m culling
	_entity_profile_prop = QNEntityProfile.new()
	_entity_profile_prop.init(5.0, 0.5, 20.0) # Hz Default
	_entity_profile_npc = QNEntityProfile.new()
	_entity_profile_npc.init(20.0, 1.0, 20.0) # Hz
	_entity_profile_projectile = QNEntityProfile.new()
	_entity_profile_projectile.init(60.0, 3.0, 50.0) # Hz (Prioridade Extrema)

	# Bindings de Sinais Assíncronos (Event-Driven Architecture)
	# Delega respostas de eventos de rede originados no C++ para handlers locais no GDScript. Abordagem preferível ao pooling síncrono no _process para evitar gargalos.
	# O QuanticNet emite sinais limpos quando eventos ocorrem nas entranhas do C++.
	QuanticNet.connection_state_changed.connect(_on_conn_state)
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.pong_received.connect(_on_pong_received)
	QuanticNet.state_received.connect(_on_state)
	QuanticNet.snapback_received.connect(_on_snapback)

	# Instancia o ambiente 3D mínimo (Lighting, Floor, Culling Rings) isolando lógicas de apresentação.
	_setup_scene()

	# Força o FPS cravado inicial para o atalho F funcionar corretamente
	Engine.max_fps = TARGET_FPS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

	# Inicialização do Handshake e da Camada de Transporte Segura (DTLS + ENet)
	if _is_acting_as_server:
		print("[DEMO] Iniciando SERVIDOR QuanticNet (Porta %d)..." % PORT)
		QuanticNet.host(PORT, SECRET, "127.0.0.1", MAX_PEERS, _global_network_parameters)

		# O Servidor registra a si mesmo (ID 1)
		# Se o seu servidor é puramente uma máquina autoritativa (não há um humano jogando nele),
		# ele não deveria ter um corpo físico na rede
		# QuanticNet.register_entity(1, true, true, _entity_profile_player)

		# O Mundo Aberto não utiliza Regions (Instanciamento Rígido).
		# Todos habitam o mesmo continuum espacial e são regidos unicamente pelo QNSpatialGrid.

		# O Servidor instancia e gerencia Props de forma Autoritativa (Eles não possuem clientes enviando input)
		for prop_id in SERVER_PROPS:
			QuanticNet.register_entity(prop_id, false, true, _entity_profile_prop)
	else:
		print("[DEMO] Iniciando CLIENTE QuanticNet...")
		QuanticNet.join("127.0.0.1", PORT, SECRET, use_netem, _global_network_parameters)

	# Encapsulamento de Rede e Bypass do SceneTree
	# Injeta a implementação nativa em C++ no SceneTree, permitindo o roteamento direto e processamento isolado do QuanticNet.
	# Este é o truque de ouro: forçamos a Árvore de Cena do Godot a enxergar o roteador (MultiplayerAPI)
	# que o QuanticNet construiu em C++. Isso faz com que RPCs nativos funcionem de forma transparente
	# através dos túneis ultra-otimizados do nosso plugin.
	get_tree().set_multiplayer(QuanticNet.get_tree().get_multiplayer(QuanticNet.get_path()), self.get_path())

	print("[DEMO] Inicialização concluída. Conexão engatilhada e Sinais Ativos.")


func _notification(what: int) -> void:
	# Tratamento de Sinal do Sistema Operacional (Window Close).
	# A destruição limpa do socket UDP é obrigatória em arquiteturas C++. O encerramento bruto sem desconexão prévia
	# causa o travamento das portas locais no ENet e vazamento de threads, bloqueando o roteador de instanciar novos bindings.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		QuanticNet.disconnect_net(true)
		get_tree().quit()


func _setup_scene() -> void:
	# Uma câmera isométrica, uma luz direcional com sombras e um chão escuro.
	_camera = Camera3D.new()
	_camera.position = CAMERA_START_POS
	_camera.rotation_degrees = CAMERA_START_ROT
	add_child(_camera)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.shadow_enabled = true
	add_child(light)

	# Chão Base do Mundo Aberto (Contínuo)
	var open_world_floor := MeshInstance3D.new()
	var plane_ow := PlaneMesh.new()
	plane_ow.size = Vector2(80, 80)
	var mat_ow := StandardMaterial3D.new()
	mat_ow.albedo_color = Color(0.2, 0.2, 0.2) # Dark Gray
	plane_ow.material = mat_ow
	open_world_floor.mesh = plane_ow
	open_world_floor.position = Vector3(0, 0, 0)
	add_child(open_world_floor)

	_scene_world_root_node = Node3D.new()
	add_child(_scene_world_root_node)


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


func _create_aoi_grid(color: Color, size: Vector2, y_offset: float) -> Node3D:
	var node = Node3D.new()
	var thickness = 0.15

	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	# Top edge
	var top = MeshInstance3D.new()
	var box_top = BoxMesh.new()
	box_top.size = Vector3(size.x, thickness, thickness)
	top.mesh = box_top
	top.position = Vector3(0, 0, -size.y / 2)
	top.material_override = mat
	node.add_child(top)

	# Bottom edge
	var bot = MeshInstance3D.new()
	var box_bot = BoxMesh.new()
	box_bot.size = Vector3(size.x, thickness, thickness)
	bot.mesh = box_bot
	bot.position = Vector3(0, 0, size.y / 2)
	bot.material_override = mat
	node.add_child(bot)

	# Left edge
	var left = MeshInstance3D.new()
	var box_left = BoxMesh.new()
	box_left.size = Vector3(thickness, thickness, size.y)
	left.mesh = box_left
	left.position = Vector3(-size.x / 2, 0, 0)
	left.material_override = mat
	node.add_child(left)

	# Right edge
	var right = MeshInstance3D.new()
	var box_right = BoxMesh.new()
	box_right.size = Vector3(thickness, thickness, size.y)
	right.mesh = box_right
	right.position = Vector3(size.x / 2, 0, 0)
	right.material_override = mat
	node.add_child(right)

	node.position.y = y_offset
	return node

# ==============================================================================
# APRESENTAÇÃO E MÉTRICAS DE DIAGNÓSTICO (CANVAS LAYER)
# ==============================================================================


func _setup_ui() -> void:
	# Criação Dinâmica da UI no CanvasLayer.
	# Isso desvincula completamente as métricas textuais 2D do espaço tridimensional da Câmera (3D),
	# evitando artefatos visuais quando o jogador se movimentar e mantendo o painel rígido na tela.
	var hud = CanvasLayer.new()

	# Container do Topo - Exibe o Estado Bruto da Conexão ENet (Handshake e Sessão).
	var top_panel = PanelContainer.new()
	top_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)

	_ui_label_connection_status = Label.new()
	_ui_label_connection_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui_label_connection_status.text = "OFFLINE (Aguardando Sinal)"
	_ui_label_connection_status.add_theme_color_override("font_color", Color.GRAY)
	top_panel.add_child(_ui_label_connection_status)
	hud.add_child(top_panel)

	# ... (Dicas e Atalhos na Esquerda) ...
	var margin_shortcuts = MarginContainer.new()
	margin_shortcuts.add_theme_constant_override("margin_left", UI_MARGIN_STD)
	margin_shortcuts.add_theme_constant_override("margin_top", UI_MARGIN_LARGE)

	var vbox_shortcuts = VBoxContainer.new()
	var shortcuts = [
		"CONTROLES IN-GAME:",
		"F1         : Resetar System Metrics",
		"F2         : Resetar Network Metrics",
		"Setas/WASD : Mover (CSP)",
		"Enter      : Auto-Move On/Off",
		"F          : Destravar FPS / V-Sync",
		"N          : Ativar/Desativar NETEM",
		"1 a 5      : Profile Peers (20 a 1Hz)",
		"6 a 0      : Profile Culling (5 a 100m)",
		"+ / -      : FOV Culling Local (Visão)",
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

	_ui_diagnostic_label_fps = Label.new()
	_ui_diagnostic_label_frametime = Label.new()
	_ui_diagnostic_label_phys = Label.new()
	_ui_diagnostic_label_mem = Label.new()
	_ui_diagnostic_label_vram = Label.new()
	_ui_diagnostic_label_draws = Label.new()
	_ui_diagnostic_label_nodes = Label.new()

	var labels_sys = [
		_ui_diagnostic_label_fps,
		_ui_diagnostic_label_frametime,
		_ui_diagnostic_label_phys,
		_ui_diagnostic_label_mem,
		_ui_diagnostic_label_vram,
		_ui_diagnostic_label_draws,
		_ui_diagnostic_label_nodes,
	]
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

	_ui_diagnostic_label_netem = Label.new()
	_ui_diagnostic_label_rtt = Label.new()
	_ui_diagnostic_label_loss = Label.new()
	_ui_diagnostic_label_offset = Label.new()
	_ui_diagnostic_label_peers = Label.new()

	var labels_net = [
		_ui_diagnostic_label_netem,
		_ui_diagnostic_label_rtt,
		_ui_diagnostic_label_loss,
		_ui_diagnostic_label_offset,
		_ui_diagnostic_label_peers,
	]
	for l in labels_net:
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", OUTLINE_THIN)
		diag_vbox.add_child(l)

	diag_margin.add_child(diag_vbox)
	hud.add_child(diag_margin)
	add_child(hud)

# ==============================================================================
# LOOPS DE INTERAÇÃO FÍSICA E INTERPOLAÇÃO VISUAL
# ==============================================================================


func _physics_process(delta: float) -> void:
	# O _physics_process opera sincronamente a 60Hz. Toda a carga pesada de matemática vetorial,
	# predição e serialização de pacotes UDP reside aqui para garantir determinismo.
	if QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		# Lógica Autoritativa de Servidor: O servidor tem o monopólio sobre o movimento dos Props.
		_server_authoritative_props_time += delta
		for i in range(SERVER_PROPS.size()):
			var prop_id = SERVER_PROPS[i]
			var offset_time = _server_authoritative_props_time + (i * PROP_ORBIT_SPACING)
			var pos = Vector3(
				sin(offset_time) * PROP_ORBIT_RADIUS,
				PROP_HEIGHT,
				cos(offset_time) * PROP_ORBIT_RADIUS + (i * PROP_ORBIT_SPACING),
			)

			QuanticNet.update_entity_state(prop_id, pos, Vector3.ZERO, 0, Time.get_ticks_msec())

			if _active_visual_entities_map.has(prop_id):
				var mat = _active_visual_entities_map[prop_id].material_override as StandardMaterial3D
				if QuanticNet.get_server_grid().is_in_bounds(pos):
					mat.albedo_color = Color.YELLOW
					mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				else:
					mat.albedo_color = Color.DIM_GRAY
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color.a = 0.3

	elif (
		not QuanticNet.is_server()
		and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED
	):
		var speed = CLIENT_MOVE_SPEED
		var input_dir = Vector3.ZERO

		if not _is_auto_movement_enabled:
			if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
				input_dir.z -= 1
			if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
				input_dir.z += 1
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
				input_dir.x -= 1
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
				input_dir.x += 1
		else:
			_auto_movement_elapsed_time += delta
			input_dir.x = sin(_auto_movement_elapsed_time * AUTO_MOVE_SPEED_X)
			input_dir.z = cos(_auto_movement_elapsed_time * AUTO_MOVE_SPEED_Z)

		if input_dir.length_squared() > 0:
			input_dir = input_dir.normalized()

		if (
			_is_auto_movement_enabled
			and _client_predicted_position.distance_to(_auto_movement_center_origin)
			> AUTO_MOVE_RADIUS
		):
			input_dir = (_auto_movement_center_origin - _client_predicted_position).normalized()

		# Client-Side Prediction: Movimenta instantaneamente o avatar local na malha visual
		# antes mesmo do servidor validar, garantindo responsividade imediata (Zero Input Lag).
		_client_predicted_position += input_dir * speed * delta
		_update_visual(QuanticNet.get_unique_id(), _client_predicted_position, true)

		var custom_input = 0
		var now = Time.get_ticks_msec()
		if now - _cooldown_timer_last_shot_ms > SHOOT_COOLDOWN_MS:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				custom_input = 1 # Laser Hitscan
				_cooldown_timer_last_shot_ms = now
				_spawn_laser(_client_predicted_position, Color.AQUA)
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				custom_input = 2 # Projétil Físico
				_cooldown_timer_last_shot_ms = now
				_spawn_laser(_client_predicted_position, Color.ORANGE)

		# Envia a predição otimista de forma cravada para a Engine C++ assinar e rotear
		QuanticNet.submit_state(_client_predicted_position, Vector3.ZERO, custom_input, delta)


func _process(_delta: float) -> void:
	# O _process roda de forma assíncrona (destravado do tick rate de rede), preso apenas ao V-Sync do monitor.
	# Por isso, toda a lógica de Snapshot Interpolation e Lerping visual vive exclusivamente aqui.
	if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		if _camera:
			var target_cam_pos = _client_predicted_position + CAMERA_START_POS
			_camera.position = _camera.position.lerp(target_cam_pos, _delta * 5.0)

		var now = Time.get_ticks_msec()
		for id in _active_visual_entities_map.keys():
			if id != QuanticNet.get_unique_id():
				var interp_state = QuanticNet.remote_state(id)
				if not interp_state.is_empty():
					var visual = _active_visual_entities_map[id]
					var target_pos = interp_state.get("pos", visual.position)
					var last_up = visual.get_meta("last_update", now)

					# Culling Visual
					var rad = _entity_profile_player.get_spatial_culling_radius() if id < 1000 else _entity_profile_prop.get_spatial_culling_radius()
					var dist = _client_predicted_position.distance_to(target_pos)

					# O Servidor define a malha absoluta, então se a entidade chegou no pacote, ela está visível no servidor.
					# Só precisamos nos preocupar com o culling local e se há atualização recente.
					var is_visible = (
						(dist <= _client_local_culling_radius)
						and (now - last_up <= SERVER_CULL_TIMEOUT_MS)
					)

					if not visual.visible and is_visible:
						# Evita o efeito fantasma (snap) de interpolação quando uma entidade acabou de nascer no raio de visão.
						visual.position = target_pos
					else:
						# Interpolação agressiva para corrigir Buffer Underruns mascarando pacotes perdidos ou estrangulados pelo NETEM.
						visual.position = visual.position.lerp(
							target_pos,
							_delta * INTERP_LERP_SPEED,
						)

					visual.visible = is_visible
					var lbl = visual.get_node_or_null("CoordLabel") as Label3D
					if lbl:
						lbl.text = "ID: %d [R]\nX: %.1f | Z: %.1f" % [
							id,
							visual.position.x,
							visual.position.z,
						]

		# Atualização Dinâmica Removida Daqui (Transferida para _update_dynamic_rings)

	elif QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		# Modo Monitor de Espectador (Server Capado).
		# O Servidor não recebe "_on_state" de peers nativamente na camada de lógica, ele processa C++ e emite o registro final.
		# Lemos o registro aqui para materializar visualmente os Peers e Props na Viewport local de diagnóstico do host.
		var keys = QuanticNet.get_registry_keys()
		var grid_enabled = _global_network_parameters.get("grid_culling_enabled", false)
		var aoi_limit = _global_network_parameters.get("grid_culling_size", 9999.0)

		for id in keys:
			if id == QuanticNet.get_unique_id():
				continue # Monitor não tem avatar próprio e não se renderiza

			# O registro base já contém o estado completo.
			var target_pos = QuanticNet.get_entity_position(id)

			# Cria a malha (nó visual) se esta entidade for recém descoberta
			if not _active_visual_entities_map.has(id):
				_update_visual(id, target_pos, false)

			# Interpolação suave para garantir que o Monitor exiba movimento fluido
			# em vez de "pulos" instantâneos a cada tick de rede.
			var vis = _active_visual_entities_map[id]
			vis.position = vis.position.lerp(target_pos, _delta * INTERP_LERP_SPEED)

			# Feedback visual do Filtro Geral renderizado nativamente no Host
			var grid = QuanticNet.get_server_grid()
			var is_inside_aoi = grid.is_in_bounds(target_pos) if grid else true

			# Identificamos se é peer pelo ID, já que o remote_state não empacota flags internas
			var is_peer = (id < 1000)
			var mat = vis.material_override as StandardMaterial3D

			if is_inside_aoi:
				mat.albedo_color = Color.RED if is_peer else Color.YELLOW
				mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			else:
				# Fantasma visual se a entidade transpassou as fronteiras físicas do Culling Geral
				mat.albedo_color = Color.DIM_GRAY if is_peer else Color.DARK_KHAKI
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				mat.albedo_color.a = 0.3

			var lbl = vis.get_node_or_null("CoordLabel") as Label3D
			if lbl:
				lbl.text = "ID: %d [Srv]\nX: %.1f | Z: %.1f" % [id, vis.position.x, vis.position.z]

	# Sempre atualiza a malha visual dos anéis, reagindo dinamicamente caso o profile mude.
	if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		_update_dynamic_rings()

	# Histórico de FPS
	var current_fps = Engine.get_frames_per_second()
	# if current_fps > 0:
	#	_frames_per_second_history.append(current_fps)
	#	if _frames_per_second_history.size() > FPS_HISTORY_MAX:
	#		_frames_per_second_history.pop_front()
	if current_fps < _frames_per_second_minimum:
		_frames_per_second_minimum = current_fps
	if current_fps > _frames_per_second_maximum:
		_frames_per_second_maximum = current_fps

	# Histórico de Frame Time (Tempo para montar o visual e a lógica)
	var frame_ms = Performance.get_monitor(Performance.TIME_PROCESS) * SEC_TO_MS
	if frame_ms > 0:
		_frame_time_history.append(frame_ms)
		if _frame_time_history.size() > FPS_HISTORY_MAX:
			_frame_time_history.pop_front()
		if frame_ms < _frame_time_minimum:
			_frame_time_minimum = frame_ms
		if frame_ms > _frame_time_maximum:
			_frame_time_maximum = frame_ms

	# Histórico de Physics Time (O quão suada a CPU está para processar o Netcode)
	var phys_ms = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * SEC_TO_MS
	if phys_ms > 0:
		_physics_time_history.append(phys_ms)
		if _physics_time_history.size() > FPS_HISTORY_MAX:
			_physics_time_history.pop_front()
		if phys_ms < _physics_time_minimum:
			_physics_time_minimum = phys_ms
		if phys_ms > _physics_time_maximum:
			_physics_time_maximum = phys_ms

	# Histórico de Perdas
	var loss_val = 0.0
	if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		var id_to_check = QuanticNet.get_unique_id()
		var t2 = QuanticNet.get_telemetry(id_to_check)
		if t2:
			loss_val = t2.get_current_loss()
			_packet_loss_history.append(loss_val)
			if _packet_loss_history.size() > FPS_HISTORY_MAX:
				_packet_loss_history.pop_front()
			if loss_val < _packet_loss_minimum:
				_packet_loss_minimum = loss_val
			if loss_val > _packet_loss_maximum:
				_packet_loss_maximum = loss_val

	_update_ui(current_fps, frame_ms, phys_ms, loss_val)


func _update_ui(current_fps: int, frame_ms: float, phys_ms: float, current_loss: float) -> void:
	var now_ms = Time.get_ticks_msec()

	# (Throttle) Ignora a atualização visual se passou menos do que UI_UPDATE_RATE_MS desde a última
	if now_ms - _ui_throttle_last_update_ms > UI_UPDATE_RATE_MS:
		_ui_throttle_last_update_ms = now_ms

		# --- Processamento Matemático dos Arrays de Histórico ---
		var fps_avg = 0
		var fps_1_low = 0
		if _frames_per_second_history.size() > 0:
			var sum = 0
			for f in _frames_per_second_history:
				sum += f
			fps_avg = sum / _frames_per_second_history.size()

			# O "1% Low" é crucial para MMOs: ele descarta os picos altos e te diz
			# qual foi o Pior FPS do pior engasgo que o seu jogador sentiu recentemente.
			var sorted_fps = _frames_per_second_history.duplicate()
			sorted_fps.sort()
			var low_1_idx = max(0, int(sorted_fps.size() * PERCENTILE_1_LOW))
			fps_1_low = sorted_fps[low_1_idx]

		var frame_avg = 0.0
		if _frame_time_history.size() > 0:
			var sum = 0.0
			for f in _frame_time_history:
				sum += f
			frame_avg = sum / _frame_time_history.size()

		var phys_avg = 0.0
		if _physics_time_history.size() > 0:
			var sum = 0.0
			for p in _physics_time_history:
				sum += p
			phys_avg = sum / _physics_time_history.size()

		var rtt_avg = 0.0
		if _round_trip_time_history.size() > 0:
			var sum = 0.0
			for r in _round_trip_time_history:
				sum += r
			rtt_avg = sum / _round_trip_time_history.size()
		var rtt_min_disp = _round_trip_time_minimum if _round_trip_time_minimum != SENTINEL_MAX_FLOAT else 0.0

		var loss_avg = 0.0
		if _packet_loss_history.size() > 0:
			var sum = 0.0
			for l in _packet_loss_history:
				sum += l
			loss_avg = sum / _packet_loss_history.size()
		var loss_min_disp = _packet_loss_minimum if _packet_loss_minimum != SENTINEL_MAX_FLOAT else 0.0

		# --- Injeção nas Labels (System Profiler) ---
		_ui_diagnostic_label_fps.text = "FPS: %d | Avg: %d | Min: %d | Max: %d | 1%% Low: %d" % [
			current_fps,
			fps_avg,
			_frames_per_second_minimum,
			_frames_per_second_maximum,
			fps_1_low,
		]
		var frame_min_disp = _frame_time_minimum if _frame_time_minimum != SENTINEL_MAX_FLOAT else 0.0
		_ui_diagnostic_label_frametime.text = "Frame Time: %.2f ms | Avg: %.2f | Min: %.2f | Max: %.2f" % [
			frame_ms,
			frame_avg,
			frame_min_disp,
			_frame_time_maximum,
		]
		var phys_min_disp = _physics_time_minimum if _physics_time_minimum != SENTINEL_MAX_FLOAT else 0.0
		_ui_diagnostic_label_phys.text = "Physics Time: %.2f ms | Avg: %.2f | Min: %.2f | Max: %.2f" % [
			phys_ms,
			phys_avg,
			phys_min_disp,
			_physics_time_maximum,
		]

		var ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_TO_MB
		_ui_diagnostic_label_mem.text = "RAM (Static): %.2f MB" % ram_mb

		var now_time = Time.get_ticks_msec()
		if QuanticNet.is_server() and now_time - get_meta("last_ram_print", 0) > 5000:
			print("[DEMO] Server RAM (Static): %.2f MB | FPS: %d" % [ram_mb, current_fps])
			set_meta("last_ram_print", now_time)

		var vram_mb = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / BYTES_TO_MB
		_ui_diagnostic_label_vram.text = "VRAM (Video): %.2f MB" % vram_mb

		var draws = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_ui_diagnostic_label_draws.text = "Draw Calls: %d" % draws

		var active_nodes = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var orphan_nodes = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
		var objects = Performance.get_monitor(Performance.OBJECT_COUNT)
		_ui_diagnostic_label_nodes.text = "Nodes: %d | Orphans: %d | Objects: %d" % [
			active_nodes,
			orphan_nodes,
			objects,
		]

		# --- Injeção nas Labels (Network Profiler) ---
		var netem_str = "OFF"
		if _is_network_emulation_active:
			var loss = _global_network_parameters["netem_loss"]
			var lat = _global_network_parameters["netem_latency"]
			var jit = _global_network_parameters["netem_jitter"]
			netem_str = "ON (Loss: %.0f%% | Lat: %dms | Jit: %dms)" % [loss, lat, jit]
		_ui_diagnostic_label_netem.text = "NETEM Status: %s" % netem_str

		var id_to_check = QuanticNet.get_unique_id()
		var t2 = QuanticNet.get_telemetry(id_to_check)

		if t2:
			_ui_diagnostic_label_rtt.text = "RTT (ms): %.0f | Avg: %.0f | Min: %.0f | Max: %.0f" % [
				_network_round_trip_time,
				rtt_avg,
				rtt_min_disp,
				_round_trip_time_maximum,
			]
			_ui_diagnostic_label_loss.text = "Packet Loss: %.1f%% | Avg: %.1f%% | Min: %.1f%% | Max: %.1f%%" % [
				current_loss,
				loss_avg,
				loss_min_disp,
				_packet_loss_maximum,
			]
			_ui_diagnostic_label_offset.text = "Clock Offset: %.1f ms" % _network_clock_offset
		else:
			_ui_diagnostic_label_rtt.text = "RTT (ms): Aguardando..."
			_ui_diagnostic_label_loss.text = "Packet Loss: Aguardando..."
			_ui_diagnostic_label_offset.text = "Clock Offset: Aguardando..."

		var total_entities = 0
		var count_peers = 0
		var count_props = 0

		if QuanticNet.is_server():
			var registry = QuanticNet.get_registry()
			for k in registry:
				var st = registry[k]
				var pos = st.get("pos", Vector3.ZERO)

				total_entities += 1
				if st.get("is_peer", false):
					count_peers += 1
				else:
					count_props += 1
		else:
			for id in _active_visual_entities_map.keys():
				var last_up = _active_visual_entities_map[id].get_meta("last_update", now_ms)
				if now_ms - last_up <= SERVER_CULL_TIMEOUT_MS:
					total_entities += 1
					if id < 1000:
						count_peers += 1
					else:
						count_props += 1

		_ui_diagnostic_label_peers.text = "Entities: %d (Peers: %d | Props: %d)" % [
			total_entities,
			count_peers,
			count_props,
		]

# ==============================================================================
# BINDINGS ASSÍNCRONOS DE REDE (EVENT-DRIVEN ARCHITECTURE)
# ==============================================================================


func _on_conn_state(state: int) -> void:
	# Máquina de estados global exposta pelo Autoload do QuanticNet
	match state:
		QuanticNet.ConnectionState.DISCONNECTED:
			_ui_label_connection_status.text = "DISCONNECTED"
			_ui_label_connection_status.add_theme_color_override("font_color", Color.GRAY)
		QuanticNet.ConnectionState.CONNECTING:
			_ui_label_connection_status.text = "CONNECTING..."
			_ui_label_connection_status.add_theme_color_override("font_color", Color.YELLOW)
		QuanticNet.ConnectionState.AUTHENTICATING:
			_ui_label_connection_status.text = "AUTHENTICATING..."
			_ui_label_connection_status.add_theme_color_override("font_color", Color.ORANGE)
		QuanticNet.ConnectionState.CONNECTED:
			_ui_label_connection_status.text = "CONNECTED"
			_ui_label_connection_status.add_theme_color_override("font_color", Color.GREEN)
		QuanticNet.ConnectionState.FAILED:
			_ui_label_connection_status.text = "FAILED"
			_ui_label_connection_status.add_theme_color_override("font_color", Color.RED)


func _on_pong_received(rtt: float, offset: float) -> void:
	# Este sinal é disparado pela engine nativa (C++) a cada resposta temporal do Servidor.
	# Diferente do ICMP estéril, o QuanticNet acopla timestamps criptografados no cabeçalho do UDP,
	# entregando métricas de precisão sub-milissegundo para calcular o Ping (RTT) real e a defasagem (Offset) do relógio cliente-servidor.
	_network_round_trip_time = rtt
	_network_clock_offset = offset

	_round_trip_time_history.append(rtt)
	if _round_trip_time_history.size() > RTT_HISTORY_MAX:
		_round_trip_time_history.pop_front()

	if rtt < _round_trip_time_minimum:
		_round_trip_time_minimum = rtt
	if rtt > _round_trip_time_maximum:
		_round_trip_time_maximum = rtt


func _on_peer_joined(peer_id: int) -> void:
	print("[DEMO] Peer Joined: %d" % peer_id)
	if _is_acting_as_server:
		QuanticNet.register_entity(peer_id, true, true, _entity_profile_player)


func _on_peer_left(peer_id: int) -> void:
	print("[DEMO] Peer Left: %d" % peer_id)
	if _is_acting_as_server:
		QuanticNet.unregister_entity(peer_id)

	if _active_visual_entities_map.has(peer_id):
		var v = _active_visual_entities_map[peer_id]
		v.queue_free()
		_active_visual_entities_map.erase(peer_id)


func _update_visual(id: int, pos: Vector3, is_local: bool) -> void:
	if not _active_visual_entities_map.has(id):
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(1, 2, 1) if id < 1000 else Vector3(1, 1, 1)
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		var entity_color: Color
		var presence_radius: float

		if is_local:
			entity_color = Color.GREEN
			presence_radius = _entity_profile_player.get_spatial_culling_radius()
		elif id < 1000:
			entity_color = Color.RED
			# Pega o raio de presença a partir do profile atual do servidor (se disponivel), senao default
			var registry = QuanticNet.get_registry()
			if registry.has(id) and registry[id].get("profile") != null:
				presence_radius = registry[id]["profile"].get_spatial_culling_radius()
			else:
				presence_radius = 20.0
		else:
			entity_color = Color.YELLOW
			presence_radius = _entity_profile_prop.get_spatial_culling_radius()

		mat.albedo_color = entity_color
		mesh_inst.material_override = mat
		mesh_inst.set_meta("presence_radius", presence_radius)

		# Anel de Presença (AoI da Entidade - Quem a vê)
		var presence_color = entity_color
		presence_color.a = 0.25 # Translúcido
		var presence_ring = _create_ring(presence_color, presence_radius, 0.05)
		presence_ring.name = "PresenceRing"
		mesh_inst.add_child(presence_ring)

		# Anel de Visão (FOV - Apenas para o Cliente Local - O que ele vê)
		if is_local:
			var fov_ring = _create_ring(
				Color(0.0, 0.5, 1.0, 0.3),
				_client_local_culling_radius,
				0.1,
			)
			fov_ring.name = "FOVRing"
			mesh_inst.add_child(fov_ring)

		# --- [DIAGNOSTIC] Label3D para prova determinística de coordenadas ---
		var lbl = Label3D.new()
		lbl.name = "CoordLabel"
		lbl.pixel_size = 0.015
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = Vector3(0, 1.5, 0)
		lbl.modulate = Color.WHITE
		lbl.outline_modulate = Color.BLACK
		lbl.outline_size = 4
		mesh_inst.add_child(lbl)
		# ---------------------------------------------------------------------
		mesh_inst.position = pos
		_scene_world_root_node.add_child(mesh_inst)
		_active_visual_entities_map[id] = mesh_inst

	var visual = _active_visual_entities_map[id]
	if is_local:
		visual.position = pos
		var lbl = visual.get_node_or_null("CoordLabel") as Label3D
		if lbl:
			lbl.text = "ID: %d [L]\nX: %.1f | Z: %.1f" % [id, pos.x, pos.z]


func _update_dynamic_rings() -> void:
	var is_local_client = not QuanticNet.is_server()
	var local_id = QuanticNet.get_unique_id()

	for id in _active_visual_entities_map.keys():
		var vis = _active_visual_entities_map[id]
		var is_local = (is_local_client and id == local_id)

		# Atualiza Presence Ring
		var presence_ring = vis.get_node_or_null("PresenceRing") as MeshInstance3D
		if presence_ring:
			presence_ring.visible = _show_culling_rings
			var target_radius = vis.get_meta("presence_radius", 20.0)

			if presence_ring.mesh.outer_radius != target_radius:
				presence_ring.mesh.inner_radius = maxf(0.1, target_radius - 0.2)
				presence_ring.mesh.outer_radius = target_radius

		# Atualiza FOV Ring
		if is_local:
			var fov_ring = vis.get_node_or_null("FOVRing") as MeshInstance3D
			if fov_ring:
				fov_ring.visible = _show_culling_rings
				if fov_ring.mesh.outer_radius != _client_local_culling_radius:
					fov_ring.mesh.inner_radius = maxf(0.1, _client_local_culling_radius - 0.2)
					fov_ring.mesh.outer_radius = _client_local_culling_radius


func _on_state(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
	# Recepção de Snapshot (Estado Oficial do Servidor).

	# Se o Host também for um jogador na mesma tela (e o cubo dele precisar existir fisicamente),
	# mas você quer forçar os clientes a ignorarem o pacote visual apenas dele, você pode bloquear
	# a entrada no evento de recepção.
	if owner == 1:
		return # Descarta sumariamente os pacotes visuais do servidor

	# Ignoramos a nós mesmos (owner == get_unique_id) porque a movimentação do nosso avatar
	# é baseada em Client-Side Prediction (Zero Input Lag), não em comandos do servidor.
	if owner != QuanticNet.get_unique_id():
		if not _active_visual_entities_map.has(owner):
			_update_visual(owner, pos, false)

		var visual = _active_visual_entities_map[owner]
		visual.set_meta("last_update", Time.get_ticks_msec())

		# Disparo propagado via C++
		if custom == 1:
			# Disparo Hitscan (Raio Laser) propagado via C++
			_spawn_laser(pos, Color.AQUA)
		elif custom == 2:
			# Disparo de Projétil Físico
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
	_scene_world_root_node.add_child(mesh)

	var tween = get_tree().create_tween()
	tween.tween_property(mesh, "position", mesh.position + Vector3(0, 10, 0), 0.5)
	tween.tween_callback(mesh.queue_free)


func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	# O evento de Snapback (Reconciliação) é o coração do Anti-Cheat arquitetural.
	# Quando o servidor flagra a predição local do cliente desrespeitando o modelo físico, ele dispara este sinal,
	# forçando o cliente a aceitar o vetor do servidor e re-simular os inputs na fila (replay) que ainda não chegaram.
	print("[DEMO] Snapback Recebido (Reconciliação Forçada): %s" % str(pos))

	_client_predicted_position = pos

	# Re-apply pending inputs (Re-predição)
	var speed = CLIENT_MOVE_SPEED # Velocidade do client fixada abstratamente
	for pending in replay:
		var dir = pending["move"]
		var dt = pending["dt"]
		_client_predicted_position += Vector3(dir.x, 0, dir.y) * speed * dt

# ==============================================================================
# PROCESSAMENTO DE INPUTS GLOBAIS
# ==============================================================================


func _unhandled_input(event: InputEvent) -> void:
	# Consome atalhos de depuração evitando colisões com a Interface 2D (Botões e Caixas de Texto).
	# O isolamento em `_unhandled_input` previne tiros acidentais quando o jogador tenta interagir com a UI.
	if event is InputEventKey and event.pressed and not event.echo:
		# [N] - Toggle Netem (Network Emulation)
		if event.keycode == KEY_N:
			_is_network_emulation_active = not _is_network_emulation_active
			var loss = _global_network_parameters["netem_loss"] if _is_network_emulation_active else 0.0
			var lat = _global_network_parameters["netem_latency"] if _is_network_emulation_active else 0
			var jit = _global_network_parameters["netem_jitter"] if _is_network_emulation_active else 0
			var dup = _global_network_parameters["netem_dup"] if _is_network_emulation_active else 0.0

			QuanticNet.set_netem_config(loss, lat, jit, dup)
			var status = "ON (Loss: %.0f%% | Lat: %dms | Jit: %dms)" % [loss, lat, jit] if _is_network_emulation_active else "OFF"
			print("[DEMO] NETEM Toggle: %s" % status)

		# [F1] - Resetar Métricas de System
		elif event.keycode == KEY_F1:
			_frames_per_second_history.clear()
			_frames_per_second_minimum = SENTINEL_MAX_INT
			_frames_per_second_maximum = 0
			_frame_time_history.clear()
			_frame_time_minimum = SENTINEL_MAX_FLOAT
			_frame_time_maximum = 0.0
			_physics_time_history.clear()
			_physics_time_minimum = SENTINEL_MAX_FLOAT
			_physics_time_maximum = 0.0
			print("[DEMO] System Profiler resetado!")

		# [F2] - Resetar Métricas de Network
		elif event.keycode == KEY_F2:
			_round_trip_time_history.clear()
			_round_trip_time_minimum = SENTINEL_MAX_FLOAT
			_round_trip_time_maximum = 0.0
			_packet_loss_history.clear()
			_packet_loss_minimum = SENTINEL_MAX_FLOAT
			_packet_loss_maximum = 0.0
			print("[DEMO] Network Profiler resetado!")

		# [F] - Toggle V-Sync e Max FPS (Teste de Stress visual)
		elif event.keycode == KEY_F:
			if Engine.max_fps == 0:
				Engine.max_fps = TARGET_FPS
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print(
				"[DEMO] FPS Limitado: ",
				"SIM (60Hz)" if Engine.max_fps == 60 else "NÃO (Unlimited)",
			)

		# [1-5] - Tick Rate do Profile
		elif event.keycode == KEY_1:
			_request_profile_change(20.0, -1)
		elif event.keycode == KEY_2:
			_request_profile_change(10.0, -1)
		elif event.keycode == KEY_3:
			_request_profile_change(5.0, -1)
		elif event.keycode == KEY_4:
			_request_profile_change(1.0, -1)
		elif event.keycode == KEY_5:
			_request_profile_change(60.0, -1)

		# [6-0] - Culling Radius do Profile
		elif event.keycode == KEY_6:
			_request_profile_change(-1, 5.0)
		elif event.keycode == KEY_7:
			_request_profile_change(-1, 10.0)
		elif event.keycode == KEY_8:
			_request_profile_change(-1, 20.0)
		elif event.keycode == KEY_9:
			_request_profile_change(-1, 50.0)
		elif event.keycode == KEY_0:
			_request_profile_change(-1, 100.0)

		# [ENTER] - Toggle Auto-Move
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_is_auto_movement_enabled = not _is_auto_movement_enabled
			if _is_auto_movement_enabled:
				_auto_movement_center_origin = _client_predicted_position
			print("[DEMO] Auto-move: ", _is_auto_movement_enabled)

		# [+ / -] - Client View Distance (Visual Culling)
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_client_local_culling_radius += 2.0
			print("[DEMO] View Distance: ", _client_local_culling_radius)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_client_local_culling_radius = maxf(2.0, _client_local_culling_radius - 2.0)
			print("[DEMO] View Distance: ", _client_local_culling_radius)

		elif event.keycode == KEY_H:
			_show_culling_rings = not _show_culling_rings
			for id in _active_visual_entities_map.keys():
				var vis = _active_visual_entities_map[id]
				var presence_ring = vis.get_node_or_null("PresenceRing") as MeshInstance3D
				if presence_ring:
					presence_ring.visible = _show_culling_rings
				var fov_ring = vis.get_node_or_null("FOVRing") as MeshInstance3D
				if fov_ring:
					fov_ring.visible = _show_culling_rings
			print("[DEMO] Culling Rings: ", "Exibidos" if _show_culling_rings else "Ocultos")

		elif event.keycode >= KEY_1 and event.keycode <= KEY_0:
			var target_tick = -1.0
			var target_cull = -1.0

			match event.keycode:
				KEY_1:
					target_tick = 20.0
				KEY_2:
					target_tick = 30.0
				KEY_3:
					target_tick = 60.0
				KEY_4:
					target_tick = 5.0
				KEY_5:
					target_tick = 1.0
				KEY_6:
					target_cull = 5.0
				KEY_7:
					target_cull = 10.0
				KEY_8:
					target_cull = 20.0
				KEY_9:
					target_cull = 50.0
				KEY_0:
					target_cull = 100.0

			_request_profile_change(target_tick, target_cull)

# ==============================================================================
# PERFIS DINÂMICOS (TESTE DE ARQUITETURA)
# ==============================================================================


func _request_profile_change(tick: float, culling: float) -> void:
	# O cliente APENAS solicita a alteração ao Servidor. A classe global NÃO é mutada.
	if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		rpc_id(1, "server_update_profile", tick, culling)
	elif _is_acting_as_server:
		server_update_profile(tick, culling)


@rpc("any_peer", "call_local")
func server_update_profile(new_tick: float, new_culling: float) -> void:
	if not QuanticNet.is_server():
		return

	# Identifica o autor do pedido de forma segura (impede spoofing de ID)
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = 1

	var registry = QuanticNet.get_registry()
	if registry.has(peer_id):
		var old_prof = registry[peer_id].get("profile")
		if old_prof != null:
			var t = new_tick if new_tick > 0 else old_prof.get_tick_rate_hz()
			var c = new_culling if new_culling > 0 else old_prof.get_spatial_culling_radius()
			var new_prof = QNEntityProfile.new()
			new_prof.init(t, old_prof.get_base_priority(), c)
			QuanticNet.change_entity_profile(peer_id, new_prof)
			rpc("client_update_visual_radius", peer_id, c)
			print(
				"[DEMO] Perfil Atualizado para Peer %d: %.1fHz | Culling: %.1fm" % [peer_id, t, c]
			)


@rpc("authority", "call_local")
func client_update_visual_radius(peer_id: int, new_radius: float) -> void:
	if _active_visual_entities_map.has(peer_id):
		var vis = _active_visual_entities_map[peer_id]
		vis.set_meta("presence_radius", new_radius)
