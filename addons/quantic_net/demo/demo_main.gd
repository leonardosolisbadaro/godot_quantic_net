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
	"max_speed": 6.0, # Velocidade máxima teórica de um player (usado no Anti-Speedhack)
	"hard_cap": 20.0, # Velocidade absurda (cair, teleportar) onde a interpolação é desligada e vira um "teleporte visual" (snap)
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
var _status_lbl: Label
var _reconnect_btn: Button

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
var _auto_move: bool = false

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
		
	# 4. Conectando os Sinais Vitais (Event-Driven Architecture)
	# O QuanticNet emite sinais limpos quando eventos ocorrem nas entranhas do C++.
	QuanticNet.connection_state_changed.connect(_on_conn_state)
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.pong_received.connect(_on_pong_received)
	QuanticNet.state_received.connect(_on_state)
	QuanticNet.snapback_received.connect(_on_snapback)
	
	# 5. Configura cenário 3D visual mínimo para que a tela não fique cinza.
	_setup_scene()
	
	# 6. Iniciando os Motores (Bootstrapping do ENet + DTLS)
	if _is_server:
		print("[DEMO] Iniciando SERVIDOR QuanticNet (Porta %d)..." % PORT)
		QuanticNet.host(PORT, SECRET, "127.0.0.1", MAX_PEERS, _network_config)
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
		"CONTROLES IN-GAME (Fase 2):",
		"Setas/WASD : Mover (Fase 4)",
		"Enter      : Auto-Move On/Off",
		"F          : Destravar FPS / V-Sync",
		"N          : Ativar/Desativar NETEM"
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
	# Fase 2: O QuanticNet é hiper-otimizado e não gera tráfego isolado de PING. 
	# O cálculo de RTT pega carona ("Piggybacking") no cabeçalho dos pacotes 
	# de estado das entidades (Players). Como na Fase 2 ainda não temos entidades, 
	# a rede ficaria muda. Para forçar o Profiler a acordar, disparamos um 
	# Vector3.ZERO fantasma periodicamente.
	if not QuanticNet.is_server() and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		QuanticNet.submit_state(Vector3.ZERO, Vector3.ZERO, 0, delta)

func _process(_delta: float) -> void:
	# O _process é assíncrono à física e é atrelado apenas à Placa de Vídeo (Taxa de atualização do Monitor).
	# Usamos ele exclusivamente para ler métricas visuais cruas, evitando poluir o Thread de física.
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
			
		var total_peers = QuanticNet.get_registry().size()
		_diag_lbl_peers.text = "Entidades Registradas: %d" % total_peers

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

func _on_peer_left(peer_id: int) -> void:
	print("[DEMO] Peer Left: %d" % peer_id)

func _on_state(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
	# Fase 2 ignora processamento espacial visual, mas o sinal já está 
	# pronto para quando as entidades forem criadas nas fases seguintes.
	pass

func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	# O Snapback é o corretivo severo do Servidor (Reconciliação). 
	# Se a simulação do cliente discordou gravemente da matriz de física do Servidor,
	# recebemos esta "bronca" para teletransportar o corpo e reprocessar os inputs (replay).
	print("[DEMO] Snapback Recebido (Reconciliação Forçada): %s" % str(pos))

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
			
			# No Godot puro, testes de rede são perfeitos. 
			# O QuanticNet injeta este "ruído e caos" nativamente nas rotas UDP 
			# da Engine em C++ simulando cenários catastróficos reais.
			QuanticNet.set_netem_config(loss, lat, jit, dup)
			var status = "ON (Loss: %.0f%% | Lat: %dms | Jit: %dms)" % [loss, lat, jit] if _netem_active else "OFF"
			print("[DEMO] NETEM Toggle: %s" % status)
			
		# [F] - Toggle V-Sync e Max FPS (Teste de Stress visual)
		elif event.keycode == KEY_F:
			if Engine.max_fps == 0:
				Engine.max_fps = TARGET_FPS
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print("[DEMO] FPS Limitado: ", "SIM (60Hz)" if Engine.max_fps == 60 else "NÃO (Unlimited)")
			
		# [ENTER] - Toggle Auto-Move (Será integrado na Fase 4)
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_auto_move = not _auto_move
			print("[DEMO] Auto-move: ", _auto_move)
