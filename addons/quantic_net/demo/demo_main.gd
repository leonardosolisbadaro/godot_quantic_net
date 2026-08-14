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
## @updated 2026-08-14
##
## @since 0.5.0
## @lastModifiedIn 0.9.0
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends Node3D

# ==============================================================================
# 1. CONSTANTES DE REDE, ENDEREÇAMENTO E TOPOLOGIA (QUANTICNET)
# ==============================================================================
## Porta UDP padrão utilizada para bind e escuta do host autoritativo.
const PORT := 4242
## Token compartilhado de segurança para handshake e autorização inicial DTLS.
const SECRET := "demo-secret"
## Endereço IP padrão de loopback local para conexões de teste na mesma máquina.
const DEFAULT_BIND_IP := "127.0.0.1"
## Número máximo de conexões simultâneas suportadas na topologia da demo.
const MAX_PEERS := 32
## Limiar de ID de entidade: IDs < 1000 são avatares de peers; IDs >= 1000 são props de ambiente.
const PEER_ID_THRESHOLD := 1000
## IDs autoritativos dos props dinâmicos instanciados e governados exclusivamente pelo host.
const SERVER_PROPS: Array[int] = [1001, 1002, 1003]
## Taxa padrão de transmissão e processamento em Hz do servidor de rede.
const NET_SERVER_TICK_RATE := 20.0
## Quantidade de ticks imóveis necessários para uma entidade entrar no estado dormente.
const NET_DORMANCY_THRESHOLD_TICKS := 60
## Tamanho espacial (em metros) de cada célula do grid de particionamento espacial.
const NET_GRID_CULLING_SIZE := 100.0

# ==============================================================================
# 2. CONSTANTES DE ANTI-CHEAT, LIMITES FÍSICOS E NETEM (PARÂMETROS DE REDE)
# ==============================================================================
## Velocidade máxima elástica tolerada pelo validador antes de registrar infração.
const NET_MAX_SPEED := 300.0
## Distância máxima permitida antes de abortar interpolação e aplicar Snap corretivo.
const NET_HARD_CAP := 500.0
## Fronteira física invisível do mundo cúbico (entidades além deste limite são purgadas).
const NET_WORLD_BOUNDS := 500.0
## Quantidade máxima de violações permitidas antes da desconexão compulsória (Kick).
const NET_MAX_STRIKES := 5
## Tempo limite (em segundos) para finalizar as chaves criptográficas DTLS.
const NET_AUTH_TIMEOUT := 3.0
## Porcentagem padrão simulada de perda de pacotes no modo de emulação de rede.
const NETEM_LOSS_DEFAULT := 10.0
## Latência simulada base (em milissegundos) injetada na conexão via NETEM.
const NETEM_LATENCY_DEFAULT := 150
## Variância randômica (Jitter em milissegundos) adicionada ao RTT no NETEM.
const NETEM_JITTER_DEFAULT := 50
## Taxa percentual de duplicação simulada de pacotes no socket virtual.
const NETEM_DUP_DEFAULT := 0.0

# ==============================================================================
# 3. CONSTANTES DE GAMEPLAY, MOVIMENTO E INTERPOLAÇÃO
# ==============================================================================
## Velocidade linear máxima permitida para o deslocamento do avatar do cliente.
const CLIENT_MOVE_SPEED := 30.0
## Velocidade de interpolação exponencial (lerp) das entidades remotas na tela.
const INTERP_LERP_SPEED := 5.0
## Velocidade de rotação suave esférica (slerp) dos avatares para alinhamento direcional.
const ROTATION_SLERP_SPEED := 15.0
## Discrepância espacial máxima antes de cancelar a interpolação suave e forçar snap.
const CULLING_SNAP_DISTANCE_THRESHOLD := 10.0
## Raio da órbita da trajetória de movimentação automática de teste.
const AUTO_MOVE_RADIUS := 8.0
## Frequência angular da trajetória automática em forma de 8 (Lemniscata).
const AUTO_MOVE_SPEED := 1.5
## Raio da órbita circular descrita pelos props autoritativos no servidor.
const PROP_ORBIT_RADIUS := 4.0
## Espaçamento temporal de defasagem de fase entre props orbitando simultaneamente.
const PROP_ORBIT_SPACING := 3.0
## Altura fixa de sustentação dos props acima do chão durante a órbita.
const PROP_HEIGHT := 0.5
## Distância inicial padrão de culling visual local do cliente.
const DEFAULT_VIEW_DISTANCE := 100.0
## Passo de ajuste para aumentar ou diminuir a distância de culling local via teclado (+/-).
const VIEW_DISTANCE_STEP := 2.0
## Limite mínimo inferior para o raio de visão e culling do cliente local.
const VIEW_DISTANCE_MIN := 2.0

# ==============================================================================
# 4. CONSTANTES DE ENTIDADES, MALHAS E COLISORES FÍSICOS (CAPSULES)
# ==============================================================================
## Dimensões geométricas da caixa representativa do avatar do jogador (1x2x1 metros).
const PLAYER_MESH_SIZE := Vector3(1.0, 2.0, 1.0)
## Dimensões geométricas da caixa representativa dos props dinâmicos (1x1x1 metro).
const PROP_MESH_SIZE := Vector3(1.0, 1.0, 1.0)
## Raio geométrico da cápsula de colisão do jogador (metros).
const PLAYER_COLLIDER_RADIUS := 0.5
## Altura total da cápsula de colisão do jogador (metros).
const PLAYER_COLLIDER_HEIGHT := 2.0
## Raio geométrico da cápsula de colisão dos props (metros).
const PROP_COLLIDER_RADIUS := 0.5
## Altura total da cápsula de colisão dos props (metros).
const PROP_COLLIDER_HEIGHT := 1.0
## Transparência (Alpha) da cápsula de colisão de depuração.
const COLLIDER_ALPHA := 0.35
## Raio da esfera indicadora do ponto de contato na base da cápsula.
const CONTACT_POINT_RADIUS := 0.08
## Cor visual de destaque atribuída ao avatar do cliente local (verde).
const LOCAL_PLAYER_COLOR := Color.GREEN
## Cor visual padrão atribuída aos avatares de peers remotos (vermelho).
const REMOTE_PLAYER_COLOR := Color.RED
## Cor visual padrão atribuída às entidades inanimadas (props/amarelo).
const PROP_COLOR := Color.YELLOW
## Elevação padrão em Y para o centro de massa da entidade acima do chão.
const ENTITY_DEFAULT_Y_OFFSET := 0.5
## Dimensões da malha indicativa de orientação (viseira frontal) do jogador.
const PLAYER_VISOR_SIZE := Vector3(0.6, 0.2, 0.2)
## Dimensões da malha indicativa de orientação (viseira frontal) dos props.
const PROP_VISOR_SIZE := Vector3(0.2, 0.2, 0.2)
## Deslocamento espacial frontal da viseira indicativa na malha do jogador.
const PLAYER_VISOR_OFFSET := Vector3(0.0, 0.2, -0.51)
## Deslocamento espacial frontal da viseira indicativa na malha do prop.
const PROP_VISOR_OFFSET := Vector3(0.0, 0.2, -0.41)
## Deslocamento vertical da etiqueta flutuante 3D de coordenadas acima da entidade.
const COORD_LABEL_OFFSET := Vector3(0.0, 1.5, 0.0)
## Escala de amostragem de pixels para legibilidade do texto na Label3D.
const COORD_LABEL_PIXEL_SIZE := 0.015
## Espessura do contorno escuro da Label3D de coordenadas.
const COORD_LABEL_OUTLINE_SIZE := 4

# ==============================================================================
# 5. CONSTANTES DE ANÉIS DE CULLING (DECALS GPU) E GRADE ESPACIAL
# ==============================================================================
## Altura vertical de projeção da caixa AABB do Decal sobre o relevo (metros).
const DECAL_PROJECTION_HEIGHT := 100.0
## Fator de esmaecimento superior da projeção do Decal (upper fade).
const DECAL_UPPER_FADE := 0.3
## Fator de esmaecimento inferior da projeção do Decal (lower fade).
const DECAL_LOWER_FADE := 0.3
## Resolução em pixels da textura 2D procedural gerada em memória para os anéis de Decal.
const DECAL_TEXTURE_SIZE := 512
## Espessura do traço do anel em pixels na textura procedural de 512x512.
const DECAL_RING_THICKNESS_PX := 2.0
## Nível de transparência (Alpha) da cor do anel de presença da entidade.
const PRESENCE_RING_ALPHA := 0.6
## Cor azul translúcida indicativa do anel de alcance de visão (FOV) do cliente local.
const FOV_RING_COLOR := Color(0.0, 0.7, 1.0, 0.9)
## Raio de presença padrão de contingência para entidades sem metadados explícitos.
const FALLBACK_PRESENCE_RADIUS := 20.0
## Raio de presença padrão inicial assumido pelos avatares de rede.
const DEFAULT_PRESENCE_RADIUS := 100.0
## Dimensão lateral padrão da célula da grade espacial do core em C++.
const SPATIAL_GRID_CELL_SIZE := 100.0
## Altura da malha de visualização da célula espacial no chão.
const SPATIAL_CELL_DEBUG_HEIGHT := 0.05
## Cor roxa translúcida sutil para destaque da célula espacial ativa.
const SPATIAL_GRID_DEBUG_COLOR := Color(0.6, 0.0, 1.0, 0.05)
## Elevação vertical da malha de depuração da célula espacial ativa.
const SPATIAL_GRID_Y_OFFSET := 0.025

# ==============================================================================
# 6. CONSTANTES DE TERRENO PROCEDURAL (HEIGHTMAP, RUÍDO E NAVMESH)
# ==============================================================================
## Meia-dimensão (Half Size) do quadrado do terreno (500m = 1000x1000m total).
const TERRAIN_HALF_SIZE := 500.0
## Quantidade de subdivisões por eixo para gerar a malha densa do terreno (100x100 quads).
const TERRAIN_SUBDIVISIONS := 100
## Escala de amplitude vertical máxima em metros aplicada ao ruído do terreno.
const TERRAIN_HEIGHT_SCALE := 35.0
## Frequência espacial padrão do gerador FastNoiseLite para curvas amplas de colinas e montanhas.
const TERRAIN_NOISE_FREQUENCY := 0.004
## Quantidade de oitavas fractais para adicionar microdetalhes ao relevo procedural.
const TERRAIN_NOISE_OCTAVES := 4
## Semente pseudoaleatória padrão para sincronização determinística entre servidor e cliente.
const TERRAIN_SEED := 1337
## Cor de albedo do terreno procedural iluminado (tom terra/grama estilizado).
const TERRAIN_COLOR := Color(0.18, 0.22, 0.16)
## Rugosidade da superfície do material do terreno para reduzir reflexos especulares excessivos.
const TERRAIN_ROUGHNESS := 0.9
## Padrão de formatação do caminho de cache em disco da NavigationMesh 3D.
const TERRAIN_NAVMESH_CACHE_TEMPLATE := "user://terrain_navmesh_s%d_h%d_f%d.res"
## Inclinação máxima permitida para caminhabilidade na NavigationMesh (graus).
const NAVMESH_MAX_SLOPE := 45.0
## Altura padrão do agente para o cálculo do túnel de navegação.
const NAVMESH_AGENT_HEIGHT := 2.0
## Altura máxima de degrau que o agente consegue transpor verticalmente.
const NAVMESH_AGENT_MAX_CLIMB := 0.5
## Tamanho da célula de voxel da NavigationMesh no plano horizontal.
const NAVMESH_CELL_SIZE := 0.5
## Altura da célula de voxel da NavigationMesh no plano vertical.
const NAVMESH_CELL_HEIGHT := 0.25
## Raio do agente para o cálculo geométrico dos limites navegáveis da NavMesh.
const NAVMESH_AGENT_RADIUS := 0.5
## Meia-dimensão (Half Size) do quadrado da malha de navegação (500m = 1000x1000m total).
const NAVMESH_HALF_SIZE := 500.0
## Elevação sutil em Y das faces poligonais do NavMesh para evitar Z-Fighting com o chão.
const NAVMESH_FACES_ELEVATION := 0.05
## Cor e transparência ciano da superfície translúcida de depuração da NavMesh.
const NAVMESH_FACES_COLOR := Color(0.0, 0.4, 0.8, 0.05)
## Elevação em Y das linhas de contorno do wireframe do NavMesh para sobrepor as faces.
const NAVMESH_WIREFRAME_ELEVATION := 0.06
## Cor e transparência das bordas do wireframe da malha de navegação.
const NAVMESH_WIREFRAME_COLOR := Color(0.0, 0.7, 0.9, 0.25)

# ==============================================================================
# 7. CONSTANTES DE AMBIENTE 3D, CÂMERA E ILUMINAÇÃO
# ==============================================================================
## Dimensões em metros do plano de chão escuro renderizado para o cliente.
const FLOOR_PLANE_SIZE := Vector2(1000.0, 1000.0)
## Cor de albedo do material fosco do piso da cena.
const FLOOR_COLOR := Color(0.15, 0.15, 0.15)
## Ângulo e inclinação inicial da luz direcional solar com sombras ativadas.
const SUN_LIGHT_ROTATION := Vector3(-45.0, 45.0, 0.0)
## Alcance máximo em metros da sombra ortogonal ultraleve da luz solar em torno do jogador.
const SUN_SHADOW_MAX_DISTANCE := 60.0
## Proporção de distância onde o esmaecimento suave da sombra se inicia.
const SUN_SHADOW_FADE_START := 0.7
## Rotação angular isométrica inicial do pivô de câmera.
const CAMERA_START_ROT := Vector3(-35.0, 0.0, 0.0)
## Comprimento padrão do braço da mola da câmera em terceira pessoa.
const CAMERA_DEFAULT_SPRING_LENGTH := 25.0
## Comprimento estendido do braço da mola para a visualização aérea panorâmica.
const CAMERA_HIGH_SPRING_LENGTH := 150.0
## Margem de colisão do SpringArm3D para evitar clipping com a geometria da cena.
const CAMERA_SPRING_MARGIN := 0.5
## Elevação vertical do ponto focal do pivô da câmera em relação aos pés do jogador.
const CAMERA_TARGET_Y_OFFSET := 1.0
## Velocidade de interpolação (lerp) suave do pivô e zoom da câmera.
const CAMERA_LERP_SPEED := 5.0
## Sensibilidade angular do mouse durante o controle em modo capturado.
const MOUSE_SENSITIVITY := 0.3
## Limite inferior de inclinação vertical (Pitch) da câmera (olhando para cima).
const CAMERA_PITCH_MIN := -89.0
## Limite superior de inclinação vertical (Pitch) da câmera (olhando para baixo).
const CAMERA_PITCH_MAX := 15.0
## Distância mínima permitida para aproximação máxima do zoom da câmera.
const ZOOM_MIN := 5.0
## Distância máxima permitida para afastamento do zoom da câmera.
const ZOOM_MAX := 200.0
## Passo de incremento ou decremento de zoom a cada rolagem da roda do mouse.
const ZOOM_STEP := 2.0

# ==============================================================================
# 8. CONSTANTES DE TIRO, LASER E PROTOCOLO CUSTOMIZADO
# ==============================================================================
## Identificador de operação (Opcode) para disparos instantâneos (Hitscan).
const GAME_OP_SHOOT_HITSCAN := 32
## Identificador de operação (Opcode) para disparos com tempo de voo físico.
const GAME_OP_SHOOT_PHYSICS := 33
## Dimensões do feixe de laser instanciado nos disparos visuais.
const LASER_MESH_SIZE := Vector3(0.2, 2.0, 0.2)
## Cor ciano atribuída aos disparos do tipo Hitscan.
const LASER_COLOR_HITSCAN := Color.AQUA
## Cor laranja atribuída aos disparos do tipo Physics.
const LASER_COLOR_PHYSICS := Color.ORANGE
## Multiplicador de energia de emissão do material brilhante do laser.
const LASER_EMISSION_ENERGY := 5.0
## Ponto de origem relativo acima do atirador para o surgimento do laser.
const LASER_START_OFFSET := Vector3(0.0, 2.0, 0.0)
## Vetor de deslocamento vertical da animação do feixe de laser.
const LASER_ANIM_OFFSET := Vector3(0.0, 10.0, 0.0)
## Duração em segundos da animação do disparo de laser antes de liberar o nó.
const LASER_ANIM_DURATION := 0.5
## Tamanho mínimo em bytes do payload de vetor de posição empacotado (3 floats de 4 bytes).
const PACKET_POSITION_BYTE_SIZE := 12
## Deslocamento de byte inicial do componente X no pacote binário de disparo.
const PACKET_OFFSET_POS_X := 0
## Deslocamento de byte inicial do componente Y no pacote binário de disparo.
const PACKET_OFFSET_POS_Y := 4
## Deslocamento de byte inicial do componente Z no pacote binário de disparo.
const PACKET_OFFSET_POS_Z := 8

# ==============================================================================
# 9. CONSTANTES DE PERFIS DINÂMICOS DE TESTE (TECLADO 1 A 0)
# ==============================================================================
## Frequência de atualização inicial do perfil padrão de jogadores humanos.
const PROFILE_PLAYER_HZ := 60.0
## Prioridade inicial do jogador na fila do acumulador de largura de banda.
const PROFILE_PLAYER_PRIO := 1.0
## Raio máximo padrão de transmissão do perfil do jogador.
const PROFILE_PLAYER_CULL := 100.0
## Frequência de atualização reduzida para props e objetos inanimados.
const PROFILE_PROP_HZ := 5.0
## Prioridade reduzida na fila de banda para entidades de cenário.
const PROFILE_PROP_PRIO := 0.5
## Raio de culling espacial restrito para props.
const PROFILE_PROP_CULL := 20.0

## Frequência selecionada pelo atalho de teclado 1 (20 Hz).
const PROFILE_HZ_KEY_1 := 20.0
## Frequência selecionada pelo atalho de teclado 2 (30 Hz).
const PROFILE_HZ_KEY_2 := 30.0
## Frequência selecionada pelo atalho de teclado 3 (60 Hz).
const PROFILE_HZ_KEY_3 := 60.0
## Frequência selecionada pelo atalho de teclado 4 (5 Hz).
const PROFILE_HZ_KEY_4 := 5.0
## Frequência selecionada pelo atalho de teclado 5 (1 Hz).
const PROFILE_HZ_KEY_5 := 1.0

## Raio de culling selecionado pelo atalho de teclado 6 (5 metros).
const PROFILE_CULL_KEY_6 := 5.0
## Raio de culling selecionado pelo atalho de teclado 7 (10 metros).
const PROFILE_CULL_KEY_7 := 10.0
## Raio de culling selecionado pelo atalho de teclado 8 (20 metros).
const PROFILE_CULL_KEY_8 := 20.0
## Raio de culling selecionado pelo atalho de teclado 9 (50 metros).
const PROFILE_CULL_KEY_9 := 50.0
## Raio de culling selecionado pelo atalho de teclado 0 (100 metros).
const PROFILE_CULL_KEY_0 := 100.0

## Frequência padrão memorizada no perfil dinâmico dos clientes.
const CLIENT_DYNAMIC_PROFILE_HZ := 60.0
## Prioridade padrão memorizada no perfil dinâmico dos clientes.
const CLIENT_DYNAMIC_PROFILE_PRIO := 1.0

# ==============================================================================
# 10. CONSTANTES DE MÉTRICAS, PROFILER E CONVERSÕES MATEMÁTICAS
# ==============================================================================
## Intervalo mínimo (em milissegundos) entre atualizações de métricas textuais na UI.
const UI_UPDATE_RATE_MS := 250
## Fator multiplicador para conversão de bytes para megabytes (1024 * 1024).
const BYTES_TO_MB := 1048576.0
## Fator multiplicador para conversão de segundos para milissegundos.
const SEC_TO_MS := 1000.0
## Taxa alvo de quadros por segundo para sincronização vertical e testes de carga.
const TARGET_FPS := 60
## Valor sentinela inicial máximo para comparações de mínimos em ponto flutuante.
const SENTINEL_MAX_FLOAT := 9999.0
## Valor sentinela inicial máximo para comparações de mínimos inteiros.
const SENTINEL_MAX_INT := 9999
## Percentil inferior utilizado para quantificar o 1% Low de FPS (quedas bruscas).
const PERCENTILE_1_LOW := 0.01

## Tamanho máximo da janela de histórico móvel de FPS (600 ticks = 10 segundos a 60Hz).
const FPS_HISTORY_MAX := 600
## Tamanho máximo da janela de histórico móvel do tempo de processamento de frame.
const FRAME_TIME_HISTORY_MAX := 600
## Tamanho máximo da janela de histórico móvel do RTT (Ping).
const RTT_HISTORY_MAX := 50
## Tamanho máximo da janela de histórico móvel de RAM do servidor (600 ticks = 10s a 60Hz).
const SERVER_RAM_HISTORY_MAX := 600

# ==============================================================================
# 11. CONSTANTES DE INTERFACE DO USUÁRIO (HUD)
# ==============================================================================
## Margem padrão em pixels para ancoragem de painéis na interface gráfica.
const UI_MARGIN_STD := 20
## Margem expandida em pixels para afastamento do topo na barra lateral de atalhos.
const UI_MARGIN_LARGE := 40
## Espaçamento vertical entre os painéis de System Profiler e Network Profiler.
const UI_SPACER := 15
## Espessura grossa de contorno escuro para realce de textos de controle.
const OUTLINE_THICK := 4
## Espessura fina de contorno escuro para os valores numéricos de diagnóstico.
const OUTLINE_THIN := 3
## Cor branca translúcida dos textos da lista de atalhos do teclado.
const UI_SHORTCUTS_FONT_COLOR := Color(1.0, 1.0, 1.0, 0.8)
## Cor branca translúcida dos textos de métricas do sistema e rede.
const UI_METRICS_FONT_COLOR := Color(1.0, 1.0, 1.0, 0.9)


# Dicionário passado para a Engine C++ (QuanticNet) durante a inicialização via `host()` ou `join()`.
# Concentra todas as regras de validação, limites de desconexão e parâmetros do emulador de rede (NETEM).
var _global_network_parameters = {
	"max_speed": NET_MAX_SPEED, # Limiar elástico do Anti-Speedhack. Alto para acomodar os solavancos drásticos causados pela simulação do Netem.
	"hard_cap": NET_HARD_CAP, # Se a distância do vetor ultrapassar este limite, a Engine descarta interpolações suaves e aplica um "Snap" (teleporte corretivo absoluto).
	"world_bounds": NET_WORLD_BOUNDS, # Fronteira matemática invisível. Entidades além dessa borda são removidas do registro autoritativo para poupar processamento Culling.
	"max_strikes": NET_MAX_STRIKES, # Contador de punição. Inputs flagrados por validação incorreta somam strikes até a desconexão compulsória (Kick).
	"auth_timeout": NET_AUTH_TIMEOUT, # Margem (em segundos) para finalizar as chaves DTLS antes de derrubar a tentativa.
	"netem_loss": NETEM_LOSS_DEFAULT, # Simulação de colisão em redes ruins: % de pacotes que a placa virtual engolirá.
	"netem_latency": NETEM_LATENCY_DEFAULT, # Injeção de RTT base forçado na rede local (Loopback).
	"netem_jitter": NETEM_JITTER_DEFAULT, # Flutuação randômica do atraso, imitando redes Mobile 4G instáveis.
	"netem_dup": NETEM_DUP_DEFAULT, # Simula retransmissões fantasmas em roteadores congestionados.
	"server_tick_rate": NET_SERVER_TICK_RATE, # Taxa fixa do loop de rede desacoplado da engine de física.
	"dormancy_threshold_ticks": NET_DORMANCY_THRESHOLD_TICKS, # Ticks sem movimento até declarar a entidade inerte e cessar o envio na banda.
	"grid_culling_size": NET_GRID_CULLING_SIZE, # O tamanho fixo de cada célula do Spatial Partitioning do QuanticNet
	"sync_adjacent_grids": true, # Habilita o envio de updates para chunks adjacentes ao jogador (Evita o cap de 50m/cell)
}

# Controle de estado da topologia local
@export var enable_server_ram_profiling: bool = true
@export var server_ram_log_interval_sec: float = 10.0

@export_group("Procedural Terrain")
## Ativa ou desativa a geração procedural de relevo 3D com FastNoiseLite.
@export var enable_heightmap_terrain: bool = true
## Escala máxima de elevação vertical do relevo (amplitude em metros).
@export var terrain_height_scale: float = TERRAIN_HEIGHT_SCALE
## Frequência do ruído do terreno (valores menores criam colinas mais amplas).
@export var terrain_noise_frequency: float = TERRAIN_NOISE_FREQUENCY
## Semente do gerador de ruído para controle de reprodução procedural.
@export var terrain_seed: int = TERRAIN_SEED

var auto_spawn_clients: bool = true
var _is_acting_as_server: bool = false
var _terrain_noise: FastNoiseLite
var _terrain_mesh_instance: MeshInstance3D
var _terrain_static_body: StaticBody3D
var _terrain_faces: PackedVector3Array = PackedVector3Array()
var _terrain_height_grid: PackedFloat32Array = PackedFloat32Array()

# ==============================================================================
# PERFIS DE ENTIDADES (TICK RATES E CULLING)
# ==============================================================================
var _entity_profile_player: QNEntityProfile
var _entity_profile_prop: QNEntityProfile
var _active_profiles: Dictionary = { }

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
var _is_camera_high: bool = false
var _current_zoom: float = CAMERA_DEFAULT_SPRING_LENGTH
var _active_visual_entities_map: Dictionary = { }
var _client_predicted_position: Vector3 = Vector3(0, 0, 0)
var _client_predicted_rotation: Vector3 = Vector3(0, 0, 0)
var _is_auto_movement_enabled: bool = false
var _auto_movement_center_origin: Vector3 = Vector3.ZERO
var _auto_movement_elapsed_time: float = 0.0
var _server_authoritative_props_time: float = 0.0
var _client_local_culling_radius: float = DEFAULT_VIEW_DISTANCE
var _show_culling_rings: bool = true
var _show_collider_visual: bool = true
var _cached_ring_texture: ImageTexture = null
var _ui_label_connection_status: Label

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
var _camera_pivot: Node3D
var _spring_arm: SpringArm3D

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
var _frames_per_second_minimum: int = SENTINEL_MAX_INT
var _frames_per_second_maximum: int = 0

var _frame_time_history: Array[float] = []
var _frame_time_minimum: float = SENTINEL_MAX_FLOAT
var _frame_time_maximum: float = 0.0

var _physics_time_history: Array[float] = []
var _physics_time_minimum: float = SENTINEL_MAX_FLOAT
var _physics_time_maximum: float = 0.0

# Histórico de RAM no Servidor
var _server_ram_history: Array[float] = []
var _server_ram_minimum: float = SENTINEL_MAX_FLOAT
var _server_ram_maximum: float = 0.0
var _server_ram_last_log_ms: int = 0

# ==============================================================================
# CICLO DE VIDA (LIFECYCLE) - O PONTO DE ENTRADA
# ==============================================================================


func _ready() -> void:
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
		print("Iniciando topologia automática: 1 Servidor, 2 Clientes...")
		is_server = true

		# Cliente 1 (Conexão limpa e perfeita)
		OS.create_instance(["--client"])

		# Cliente 2 (Conexão caótica via emulador de rede)
		OS.create_instance(["--client", "--netem"])

		DisplayServer.window_set_title("1")

	if is_server:
		DisplayServer.window_set_title("1")

	if is_client:
		var title = "Connecting..."
		if use_netem:
			title += " (NETEM ON)"
		DisplayServer.window_set_title(title)

	_is_acting_as_server = is_server

	# Configura a UI de diagnóstico via código (Apenas para Clientes)
	if not _is_acting_as_server:
		_setup_ui()

	# Perfis Dinâmicos (Tick Rate vs Priority vs Culling Radius)
	_entity_profile_player = QNEntityProfile.new()
	_entity_profile_player.init(PROFILE_PLAYER_HZ, PROFILE_PLAYER_PRIO, PROFILE_PLAYER_CULL)
	_entity_profile_prop = QNEntityProfile.new()
	_entity_profile_prop.init(PROFILE_PROP_HZ, PROFILE_PROP_PRIO, PROFILE_PROP_CULL)

	# Bindings de Sinais Assíncronos (Event-Driven Architecture)
	# Delega respostas de eventos de rede originados no C++ para handlers locais no GDScript. Abordagem preferível ao pooling síncrono no _process para evitar gargalos.
	# O QuanticNet emite sinais limpos quando eventos ocorrem nas entranhas do C++.
	QuanticNet.connection_state_changed.connect(_on_conn_state)

	# Autenticação e Topologia
	QuanticNet.peer_joined.connect(_on_peer_joined)
	QuanticNet.peer_left.connect(_on_peer_left)
	QuanticNet.pong_received.connect(_on_pong_received)
	QuanticNet.state_received.connect(_on_state)
	QuanticNet.snapback_received.connect(_on_snapback)
	QuanticNet.custom_packet_received.connect(_on_custom_packet_received)

	# Instancia o ambiente 3D mínimo (Lighting, Floor, Culling Rings) isolando lógicas de apresentação.
	_setup_scene()

	# Força o FPS cravado inicial para o atalho F funcionar corretamente
	Engine.max_fps = TARGET_FPS

	await get_tree().physics_frame
	if _is_acting_as_server:
		print("Iniciando SERVIDOR QuanticNet (Porta %d)..." % PORT)
		_global_network_parameters["navigation_map"] = get_world_3d().get_navigation_map()

		if QuanticNet.host(PORT, SECRET, DEFAULT_BIND_IP, MAX_PEERS, _global_network_parameters) == OK:
			_active_profiles[1] = _entity_profile_player

		# O Mundo Aberto não utiliza Regions (Instanciamento Rígido).
		# Todos habitam o mesmo continuum espacial e são regidos unicamente pelo QNSpatialGrid.

		# O Servidor instancia e gerencia Props de forma Autoritativa (Eles não possuem clientes enviando input)
		for prop_id in SERVER_PROPS:
			QuanticNet.register_entity(prop_id, false, true, _entity_profile_prop)
			_active_profiles[prop_id] = _entity_profile_prop
	else:
		print("Iniciando CLIENTE QuanticNet...")
		QuanticNet.join(DEFAULT_BIND_IP, PORT, SECRET, use_netem, _global_network_parameters)

	# Encapsulamento de Rede e Bypass do SceneTree
	# Injeta a implementação nativa em C++ no SceneTree, permitindo o roteamento direto e processamento isolado do QuanticNet.
	# Este é o truque de ouro: forçamos a Árvore de Cena do Godot a enxergar o roteador (MultiplayerAPI)
	# que o QuanticNet construiu em C++. Isso faz com que RPCs nativos funcionem de forma transparente
	# através dos túneis ultra-otimizados do nosso plugin.
	get_tree().set_multiplayer(QuanticNet.get_tree().get_multiplayer(QuanticNet.get_path()), self.get_path())

	print("Inicialização concluída. Conexão engatilhada e Sinais Ativos.")


func _notification(what: int) -> void:
	# Tratamento de Sinal do Sistema Operacional (Window Close).
	# A destruição limpa do socket UDP é obrigatória em arquiteturas C++. O encerramento bruto sem desconexão prévia
	# causa o travamento das portas locais no ENet e vazamento de threads, bloqueando o roteador de instanciar novos bindings.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		QuanticNet.disconnect_net(true)
		get_tree().quit()


func _init_terrain_noise() -> void:
	_terrain_noise = FastNoiseLite.new()
	_terrain_noise.seed = terrain_seed
	_terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_terrain_noise.frequency = terrain_noise_frequency
	_terrain_noise.fractal_octaves = TERRAIN_NOISE_OCTAVES

	# Pré-computa a matriz de altitudes da malha poligonal para amostragem baricêntrica em O(1)
	var stride := TERRAIN_SUBDIVISIONS + 1
	var total_verts := stride * stride
	_terrain_height_grid.resize(total_verts)
	var hs := TERRAIN_HALF_SIZE
	var step := (hs * 2.0) / float(TERRAIN_SUBDIVISIONS)

	for i in range(stride):
		var z := -hs + i * step
		for j in range(stride):
			var x := -hs + j * step
			_terrain_height_grid[j + i * stride] = _terrain_noise.get_noise_2d(x, z) * terrain_height_scale


## Retorna a altitude exata da face poligonal da malha/NavMesh em coordenadas globais (X, Z) via interpolação baricêntrica.
func get_terrain_height(x: float, z: float) -> float:
	if not enable_heightmap_terrain or _terrain_height_grid.is_empty():
		return 0.0

	var hs := TERRAIN_HALF_SIZE
	var step := (hs * 2.0) / float(TERRAIN_SUBDIVISIONS)
	var gx := (x + hs) / step
	var gz := (z + hs) / step

	var j := clampi(int(floor(gx)), 0, TERRAIN_SUBDIVISIONS - 1)
	var i := clampi(int(floor(gz)), 0, TERRAIN_SUBDIVISIONS - 1)
	var fx := clampf(gx - float(j), 0.0, 1.0)
	var fz := clampf(gz - float(i), 0.0, 1.0)

	var stride := TERRAIN_SUBDIVISIONS + 1
	var y00 := _terrain_height_grid[j + i * stride]
	var y10 := _terrain_height_grid[(j + 1) + i * stride]
	var y01 := _terrain_height_grid[j + (i + 1) * stride]
	var y11 := _terrain_height_grid[(j + 1) + (i + 1) * stride]

	# Triângulo 1 (Anti-horário p00 -> p10 -> p11): fx >= fz
	if fx >= fz:
		return y00 + fx * (y10 - y00) + fz * (y11 - y10)
	# Triângulo 2 (p00 -> p11 -> p01): fx < fz
	else:
		return y00 + fz * (y01 - y00) + fx * (y11 - y01)


func _generate_terrain_mesh() -> ArrayMesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hs := TERRAIN_HALF_SIZE
	var step := (hs * 2.0) / float(TERRAIN_SUBDIVISIONS)
	_terrain_faces.resize(TERRAIN_SUBDIVISIONS * TERRAIN_SUBDIVISIONS * 6)
	var face_idx := 0
	var stride := TERRAIN_SUBDIVISIONS + 1

	for i in range(TERRAIN_SUBDIVISIONS):
		var z0 := -hs + i * step
		var z1 := z0 + step
		for j in range(TERRAIN_SUBDIVISIONS):
			var x0 := -hs + j * step
			var x1 := x0 + step

			var y00 := _terrain_height_grid[j + i * stride]
			var y10 := _terrain_height_grid[(j + 1) + i * stride]
			var y01 := _terrain_height_grid[j + (i + 1) * stride]
			var y11 := _terrain_height_grid[(j + 1) + (i + 1) * stride]

			var p00 := Vector3(x0, y00, z0)
			var p10 := Vector3(x1, y10, z0)
			var p01 := Vector3(x0, y01, z1)
			var p11 := Vector3(x1, y11, z1)

			# Triângulo 1 (Anti-horário para face virada para cima)
			st.add_vertex(p00)
			st.add_vertex(p10)
			st.add_vertex(p11)
			_terrain_faces[face_idx] = p00
			_terrain_faces[face_idx + 1] = p10
			_terrain_faces[face_idx + 2] = p11
			face_idx += 3

			# Triângulo 2
			st.add_vertex(p00)
			st.add_vertex(p11)
			st.add_vertex(p01)
			_terrain_faces[face_idx] = p00
			_terrain_faces[face_idx + 1] = p11
			_terrain_faces[face_idx + 2] = p01
			face_idx += 3

	st.generate_normals()
	st.index()
	return st.commit()


func _setup_scene() -> void:
	_init_terrain_noise()
	_scene_world_root_node = Node3D.new()
	add_child(_scene_world_root_node)

	# NavMesh para o validador do servidor e clientes (1000x1000m)
	var nav_region = NavigationRegion3D.new()
	var nav_mesh: NavigationMesh = null

	var terrain_mesh: ArrayMesh = null
	if enable_heightmap_terrain:
		terrain_mesh = _generate_terrain_mesh()

		# Criação do colisor físico para física, lasers e raycasts
		_terrain_static_body = StaticBody3D.new()
		var col_shape = CollisionShape3D.new()
		col_shape.shape = terrain_mesh.create_trimesh_shape()
		_terrain_static_body.add_child(col_shape)
		_scene_world_root_node.add_child(_terrain_static_body)

		# Tentativa de carregar a NavigationMesh do cache binário em disco (< 2ms)
		var cache_file = TERRAIN_NAVMESH_CACHE_TEMPLATE % [
			terrain_seed,
			int(terrain_height_scale),
			int(terrain_noise_frequency * 10000.0),
		]
		if ResourceLoader.exists(cache_file):
			nav_mesh = ResourceLoader.load(cache_file) as NavigationMesh

		# Caso não exista em cache, gera diretamente a partir da malha indexada do terreno e salva
		if nav_mesh == null or nav_mesh.get_polygon_count() == 0:
			nav_mesh = NavigationMesh.new()
			nav_mesh.create_from_mesh(terrain_mesh)
			ResourceSaver.save(nav_mesh, cache_file)
	else:
		nav_mesh = NavigationMesh.new()
		var hs := NAVMESH_HALF_SIZE
		var v0 := Vector3(-hs, 0.0, -hs)
		var v1 := Vector3(hs, 0.0, -hs)
		var v2 := Vector3(hs, 0.0, hs)
		var v3 := Vector3(-hs, 0.0, hs)
		nav_mesh.vertices = PackedVector3Array([v0, v1, v2, v3])
		nav_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
		nav_mesh.add_polygon(PackedInt32Array([0, 2, 3]))

	nav_region.navigation_mesh = nav_mesh
	_scene_world_root_node.add_child(nav_region)

	if _is_acting_as_server:
		return # Servidor opera de forma pura/headless (zero câmeras, luzes, chão ou malhas visuais)

	# Uma câmera isométrica, uma luz direcional com sombras e um chão/terreno (Apenas Clientes)
	_camera_pivot = Node3D.new()
	add_child(_camera_pivot)

	_spring_arm = SpringArm3D.new()
	_spring_arm.spring_length = CAMERA_DEFAULT_SPRING_LENGTH
	_spring_arm.margin = CAMERA_SPRING_MARGIN
	_spring_arm.position.y = CAMERA_TARGET_Y_OFFSET # Look at player's head
	_camera_pivot.add_child(_spring_arm)

	_camera = Camera3D.new()
	_spring_arm.add_child(_camera)

	_camera_pivot.rotation_degrees = CAMERA_START_ROT

	var light := DirectionalLight3D.new()
	light.rotation_degrees = SUN_LIGHT_ROTATION
	light.shadow_enabled = true
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = SUN_SHADOW_MAX_DISTANCE
	light.directional_shadow_fade_start = SUN_SHADOW_FADE_START
	add_child(light)

	# Terreno ou Chão plano (Floor)
	if enable_heightmap_terrain and terrain_mesh != null:
		_terrain_mesh_instance = MeshInstance3D.new()
		_terrain_mesh_instance.mesh = terrain_mesh
		var terrain_mat = StandardMaterial3D.new()
		terrain_mat.albedo_color = TERRAIN_COLOR
		terrain_mat.roughness = TERRAIN_ROUGHNESS
		_terrain_mesh_instance.material_override = terrain_mat
		_scene_world_root_node.add_child(_terrain_mesh_instance)
	else:
		var floor_mesh = MeshInstance3D.new()
		var plane = PlaneMesh.new()
		plane.size = FLOOR_PLANE_SIZE
		floor_mesh.mesh = plane
		var floor_mat = StandardMaterial3D.new()
		floor_mat.albedo_color = FLOOR_COLOR
		floor_mesh.material_override = floor_mat
		_scene_world_root_node.add_child(floor_mesh)

	# Visualização dinâmica do NavMesh (Overlay translúcido + Wireframe neon)
	var nav_visual = _create_navmesh_visual(nav_mesh)
	nav_visual.visible = false # Inicia oculta por padrão
	_scene_world_root_node.add_child(nav_visual)

	# Fix Initial Client Position em relação ao relevo do terreno
	_client_predicted_position.y = get_terrain_height(
		_client_predicted_position.x,
		_client_predicted_position.z,
	)


func _create_navmesh_visual(nav_mesh: NavigationMesh) -> Node3D:
	var root = Node3D.new()
	root.name = "NavMeshVisual"

	var verts = nav_mesh.vertices
	var poly_count = nav_mesh.get_polygon_count()
	if poly_count == 0 or verts.is_empty():
		return root

	# 1. Superfície Translúcida Discreta (Triângulos)
	var st_faces = SurfaceTool.new()
	st_faces.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(poly_count):
		var poly = nav_mesh.get_polygon(i)
		for j in range(1, poly.size() - 1):
			st_faces.add_vertex(verts[poly[0]] + Vector3(0.0, NAVMESH_FACES_ELEVATION, 0.0))
			st_faces.add_vertex(verts[poly[j]] + Vector3(0.0, NAVMESH_FACES_ELEVATION, 0.0))
			st_faces.add_vertex(verts[poly[j + 1]] + Vector3(0.0, NAVMESH_FACES_ELEVATION, 0.0))

	var faces_mesh = st_faces.commit()
	var faces_inst = MeshInstance3D.new()
	faces_inst.mesh = faces_mesh
	var faces_mat = StandardMaterial3D.new()
	faces_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	faces_mat.albedo_color = NAVMESH_FACES_COLOR # Ciano/azul sutil e transparente
	faces_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	faces_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	faces_inst.material_override = faces_mat
	faces_inst.name = "Faces"
	root.add_child(faces_inst)

	# 2. Contornos Wireframe Discretos (Bordas)
	var st_lines = SurfaceTool.new()
	st_lines.begin(Mesh.PRIMITIVE_LINES)
	for i in range(poly_count):
		var poly = nav_mesh.get_polygon(i)
		for j in range(poly.size()):
			var next_idx = (j + 1) % poly.size()
			st_lines.add_vertex(verts[poly[j]] + Vector3(0.0, NAVMESH_WIREFRAME_ELEVATION, 0.0))
			st_lines.add_vertex(
				verts[poly[next_idx]] + Vector3(0.0, NAVMESH_WIREFRAME_ELEVATION, 0.0)
			)

	var lines_mesh = st_lines.commit()
	var lines_inst = MeshInstance3D.new()
	lines_inst.mesh = lines_mesh
	var lines_mat = StandardMaterial3D.new()
	lines_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lines_mat.albedo_color = NAVMESH_WIREFRAME_COLOR # Linhas de contorno suaves
	lines_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lines_inst.material_override = lines_mat
	lines_inst.name = "Wireframe"
	root.add_child(lines_inst)

	return root


## Gera e armazena em cache a textura 2D procedural do anel com antialiasing para projeção via Decal.
func _get_ring_texture() -> ImageTexture:
	if _cached_ring_texture != null:
		return _cached_ring_texture
	var img_size := DECAL_TEXTURE_SIZE
	var img = Image.create(img_size, img_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(img_size * 0.5, img_size * 0.5)
	var outer_r := float(img_size) * 0.48
	var mid_r := outer_r - (DECAL_RING_THICKNESS_PX * 0.5)
	var half_w := DECAL_RING_THICKNESS_PX * 0.5

	for y in range(img_size):
		for x in range(img_size):
			var d = Vector2(x + 0.5, y + 0.5).distance_to(center)
			var dist_to_mid = absf(d - mid_r)
			if dist_to_mid <= half_w + 1.5:
				var t = clampf(1.0 - (dist_to_mid / (half_w + 1.5)), 0.0, 1.0)
				# Curva cúbica hermite suave (Smoothstep)
				var alpha = t * t * (3.0 - 2.0 * t)
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
			else:
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 0.0))

	_cached_ring_texture = ImageTexture.create_from_image(img)
	return _cached_ring_texture


## Cria um projetor GPU nativo (Decal) para desenhar o anel de AoI/FOV perfeitamente sobre o relevo 3D.
func _create_decal_ring(color: Color, radius: float, ring_name: String) -> Decal:
	var decal = Decal.new()
	decal.name = ring_name
	decal.size = Vector3(radius * 2.0, DECAL_PROJECTION_HEIGHT, radius * 2.0)
	decal.texture_albedo = _get_ring_texture()
	decal.modulate = color
	decal.upper_fade = DECAL_UPPER_FADE
	decal.lower_fade = DECAL_LOWER_FADE
	decal.distance_fade_enabled = false
	return decal


## Cria a representação visual do colisor físico de cápsula e do ponto de apoio/contato no chão.
func _create_capsule_collider_visual(id: int, is_local: bool) -> Node3D:
	var root = Node3D.new()
	root.name = "ColliderVisual"

	var is_player := id < PEER_ID_THRESHOLD
	var c_radius := PLAYER_COLLIDER_RADIUS if is_player else PROP_COLLIDER_RADIUS
	var c_height := PLAYER_COLLIDER_HEIGHT if is_player else PROP_COLLIDER_HEIGHT

	# 1. Malha da Cápsula Translúcida (Volume do Collider)
	var cap_inst = MeshInstance3D.new()
	var cap_mesh = CapsuleMesh.new()
	cap_mesh.radius = c_radius
	cap_mesh.height = c_height
	cap_mesh.radial_segments = 16
	cap_mesh.rings = 8
	cap_inst.mesh = cap_mesh

	var cap_mat = StandardMaterial3D.new()
	cap_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var base_col = LOCAL_PLAYER_COLOR if is_local else (REMOTE_PLAYER_COLOR if is_player else PROP_COLOR)
	cap_mat.albedo_color = Color(base_col.r, base_col.g, base_col.b, COLLIDER_ALPHA)
	cap_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cap_mat.no_depth_test = true
	cap_mat.render_priority = 5
	cap_inst.material_override = cap_mat
	root.add_child(cap_inst)

	# 2. Marcador do Ponto de Contato Físico na Base Inferior (Toca o chão/NavMesh)
	var contact_inst = MeshInstance3D.new()
	var contact_mesh = SphereMesh.new()
	contact_mesh.radius = CONTACT_POINT_RADIUS
	contact_mesh.height = CONTACT_POINT_RADIUS * 2.0
	contact_inst.mesh = contact_mesh

	var contact_mat = StandardMaterial3D.new()
	contact_mat.albedo_color = Color.WHITE
	contact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	contact_mat.no_depth_test = true
	contact_mat.render_priority = 6
	contact_inst.material_override = contact_mat
	contact_inst.position = Vector3(0.0, -c_height / 2.0, 0.0) # Base inferior que toca o terreno
	root.add_child(contact_inst)

	root.visible = _show_collider_visual
	return root

# ==============================================================================
# APRESENTAÇÃO E MÉTRICAS DE DIAGNÓSTICO (CANVAS LAYER)
# ==============================================================================


func _setup_ui() -> void:
	if _is_acting_as_server:
		return

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

	# ... (Dicas e Atalhos na Direita) ...
	var margin_shortcuts = MarginContainer.new()
	margin_shortcuts.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	margin_shortcuts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin_shortcuts.add_theme_constant_override("margin_right", UI_MARGIN_STD)
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
		",          : Toggle NavMesh Visual",
		"C          : Toggle Colliders (Capsule)",
	]

	for s in shortcuts:
		var lbl = Label.new()
		lbl.text = s
		lbl.add_theme_color_override("font_color", UI_SHORTCUTS_FONT_COLOR)
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
		l.add_theme_color_override("font_color", UI_METRICS_FONT_COLOR)
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
		l.add_theme_color_override("font_color", UI_METRICS_FONT_COLOR)
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
		# Profiling de Memória RAM no Servidor (Headless-Safe)
		if enable_server_ram_profiling:
			var ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_TO_MB
			_server_ram_history.append(ram_mb)
			if _server_ram_history.size() > SERVER_RAM_HISTORY_MAX:
				_server_ram_history.pop_front()

			if ram_mb < _server_ram_minimum:
				_server_ram_minimum = ram_mb
			if ram_mb > _server_ram_maximum:
				_server_ram_maximum = ram_mb

			var now = Time.get_ticks_msec()
			var log_interval_ms = int(server_ram_log_interval_sec * SEC_TO_MS)
			if now - _server_ram_last_log_ms >= log_interval_ms:
				_server_ram_last_log_ms = now
				var ram_sum = 0.0
				for r in _server_ram_history:
					ram_sum += r
				var ram_avg = ram_sum / _server_ram_history.size() if _server_ram_history.size() > 0 else ram_mb
				var min_disp = _server_ram_minimum if _server_ram_minimum != SENTINEL_MAX_FLOAT else ram_mb
				print(
					"[SERVER PROFILER] RAM (Static): %.2f MB | Avg(%d): %.2f MB | Min: %.2f MB | Max: %.2f MB"
					% [ram_mb, _server_ram_history.size(), ram_avg, min_disp, _server_ram_maximum]
				)

		# Lógica Autoritativa de Servidor: O servidor tem o monopólio sobre o movimento dos Props.
		_server_authoritative_props_time += delta
		for i in range(SERVER_PROPS.size()):
			var prop_id = SERVER_PROPS[i]
			var offset_time = _server_authoritative_props_time + (i * PROP_ORBIT_SPACING)
			var pos = Vector3(
				sin(offset_time) * PROP_ORBIT_RADIUS,
				0.0,
				cos(offset_time) * PROP_ORBIT_RADIUS + (i * PROP_ORBIT_SPACING),
			)
			pos.y = get_terrain_height(pos.x, pos.z) + PROP_HEIGHT

			QuanticNet.update_entity_state(prop_id, pos, Vector3.ZERO, 0, Time.get_ticks_msec())

	elif (
		not QuanticNet.is_server()
		and QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED
	):
		if not _is_auto_movement_enabled:
			var speed = CLIENT_MOVE_SPEED
			var input_dir = Vector3.ZERO

			if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
				input_dir.z -= 1
			if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
				input_dir.z += 1
			if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
				input_dir.x -= 1
			if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
				input_dir.x += 1

			if input_dir.length_squared() > 0:
				input_dir = input_dir.normalized()
				if _camera_pivot:
					input_dir = input_dir.rotated(Vector3.UP, _camera_pivot.rotation.y)

				_client_predicted_rotation = Vector3(0, atan2(-input_dir.x, -input_dir.z), 0)

			# Client-Side Prediction: Movimenta instantaneamente o avatar local na malha visual
			# antes mesmo do servidor validar, garantindo responsividade imediata (Zero Input Lag).
			_client_predicted_position += input_dir * speed * delta
		else:
			_auto_movement_elapsed_time += delta
			var t := _auto_movement_elapsed_time

			# Trajetória paramétrica contínua (Lemniscata de Gerono / Figura em 8)
			var offset_x = sin(t * AUTO_MOVE_SPEED) * AUTO_MOVE_RADIUS
			var offset_z = sin(t * AUTO_MOVE_SPEED * 2.0) * (AUTO_MOVE_RADIUS * 0.5)
			_client_predicted_position = _auto_movement_center_origin + Vector3(
				offset_x,
				0.0,
				offset_z,
			)

			# Vetor velocidade analítico para orientação tangencial perfeitamente suave
			var vel_x = cos(t * AUTO_MOVE_SPEED) * AUTO_MOVE_SPEED * AUTO_MOVE_RADIUS
			var vel_z = cos(t * AUTO_MOVE_SPEED * 2.0) * 2.0 * AUTO_MOVE_SPEED * (
				AUTO_MOVE_RADIUS * 0.5
			)
			var move_dir = Vector3(vel_x, 0.0, vel_z)
			if move_dir.length_squared() > 0.0001:
				move_dir = move_dir.normalized()
				_client_predicted_rotation = Vector3(0, atan2(-move_dir.x, -move_dir.z), 0)

		_client_predicted_position.y = get_terrain_height(
			_client_predicted_position.x,
			_client_predicted_position.z,
		)

		_update_visual(QuanticNet.get_unique_id(), _client_predicted_position, true)

		# Envia a predição otimista de forma cravada para a Engine C++ assinar e rotear
		QuanticNet.submit_state(_client_predicted_position, _client_predicted_rotation, 0, delta)


func _process(_delta: float) -> void:
	if _is_acting_as_server:
		return # O servidor opera de forma puramente lógica e sem renderização (Headless)

	# O _process roda de forma assíncrona (destravado do tick rate de rede), preso apenas ao V-Sync do monitor.
	# Por isso, toda a lógica de Snapshot Interpolation e Lerping visual vive exclusivamente aqui.
	if QuanticNet.get_state() == QuanticNet.ConnectionState.CONNECTED:
		if _camera_pivot:
			var target_cam_pos = _client_predicted_position
			var target_cam_rot = _camera_pivot.rotation_degrees
			var target_spring = _current_zoom

			if _is_camera_high:
				target_spring = CAMERA_HIGH_SPRING_LENGTH # Apenas afasta a câmera, não trava a rotação

			_camera_pivot.position = _camera_pivot.position.lerp(
				target_cam_pos,
				_delta * CAMERA_LERP_SPEED,
			)

			_spring_arm.spring_length = lerp(
				_spring_arm.spring_length,
				target_spring,
				_delta * CAMERA_LERP_SPEED,
			)

		var now = Time.get_ticks_msec()
		for id in _active_visual_entities_map.keys():
			if id == QuanticNet.get_unique_id():
				var visual = _active_visual_entities_map[id]
				var current_quat = Quaternion.from_euler(visual.rotation)
				var target_quat = Quaternion.from_euler(_client_predicted_rotation)
				visual.rotation = current_quat \
						.slerp(target_quat, _delta * ROTATION_SLERP_SPEED) \
						.get_euler()
			else:
				var interp_state = QuanticNet.remote_state(id)
				if not interp_state.is_empty():
					var visual = _active_visual_entities_map[id]
					var target_pos = interp_state.get("pos", visual.position)
					var y_off = visual.mesh.size.y / 2.0 if (visual.mesh and visual.mesh is BoxMesh) else ENTITY_DEFAULT_Y_OFFSET
					target_pos.y = get_terrain_height(target_pos.x, target_pos.z) + y_off

					var target_rot = interp_state.get("rot", visual.rotation)
					var current_quat = Quaternion.from_euler(visual.rotation)
					var target_quat = Quaternion.from_euler(target_rot)
					visual.rotation = current_quat \
							.slerp(target_quat, _delta * ROTATION_SLERP_SPEED) \
							.get_euler()

					# Culling Visual (FOV Local e Aura da Entidade)
					var rad = visual.get_meta("presence_radius", DEFAULT_PRESENCE_RADIUS)
					var dist = _client_predicted_position.distance_to(target_pos)
					var is_visible = (dist <= _client_local_culling_radius) and (dist <= rad)

					if not visual.visible and is_visible:
						# Evita o efeito fantasma (snap) de interpolação quando uma entidade acabou de nascer no raio de visão.
						visual.position = target_pos
						visual.visible = true
					elif not is_visible:
						visual.visible = false

					if visual.visible:
						# Se a discrepância for superior ao limiar (retorno de culling ou teleporte), aplica snap imediato em vez de patinar
						if visual.position.distance_to(target_pos) > CULLING_SNAP_DISTANCE_THRESHOLD:
							visual.position = target_pos
						else:
							visual.position = visual.position.lerp(
								target_pos,
								_delta * INTERP_LERP_SPEED,
							)
							visual.position.y = get_terrain_height(
								visual.position.x,
								visual.position.z,
							) + y_off

					visual.visible = is_visible
					var lbl = visual.get_node_or_null("CoordLabel") as Label3D
					if lbl:
						lbl.text = "ID: %d [R]\nX: %.1f | Y: %.1f | Z: %.1f" % [
							id,
							visual.position.x,
							visual.position.y,
							visual.position.z,
						]

		# Sempre atualiza a malha visual dos anéis, reagindo dinamicamente caso o profile mude.
		_update_dynamic_rings()

	# Histórico de FPS
	var current_fps = Engine.get_frames_per_second()
	if current_fps > 0:
		_frames_per_second_history.append(current_fps)
		if _frames_per_second_history.size() > FPS_HISTORY_MAX:
			_frames_per_second_history.pop_front()
		if current_fps < _frames_per_second_minimum:
			_frames_per_second_minimum = current_fps
		if current_fps > _frames_per_second_maximum:
			_frames_per_second_maximum = current_fps

	# Histórico de Frame Time (Tempo para montar o visual e a lógica)
	var frame_ms = Performance.get_monitor(Performance.TIME_PROCESS) * SEC_TO_MS
	if frame_ms > 0:
		_frame_time_history.append(frame_ms)
		if _frame_time_history.size() > FRAME_TIME_HISTORY_MAX:
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
	if _is_acting_as_server:
		return

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
		var fps_win = _frames_per_second_history.size()
		_ui_diagnostic_label_fps.text = "FPS: %d | Avg(%d): %d | Min: %d | Max: %d | 1%% Low: %d" % [
			current_fps,
			fps_win,
			fps_avg,
			_frames_per_second_minimum if _frames_per_second_minimum != SENTINEL_MAX_INT else 0,
			_frames_per_second_maximum,
			fps_1_low,
		]
		var frame_min_disp = _frame_time_minimum if _frame_time_minimum != SENTINEL_MAX_FLOAT else 0.0
		var f_win = _frame_time_history.size()
		_ui_diagnostic_label_frametime.text = "Frame Time: %.2f ms | Avg(%d): %.2f | Min: %.2f | Max: %.2f" % [
			frame_ms,
			f_win,
			frame_avg,
			frame_min_disp,
			_frame_time_maximum,
		]
		var phys_min_disp = _physics_time_minimum if _physics_time_minimum != SENTINEL_MAX_FLOAT else 0.0
		var p_win = _physics_time_history.size()
		_ui_diagnostic_label_phys.text = "Physics Time: %.2f ms | Avg(%d): %.2f | Min: %.2f | Max: %.2f" % [
			phys_ms,
			p_win,
			phys_avg,
			phys_min_disp,
			_physics_time_maximum,
		]

		var ram_mb = Performance.get_monitor(Performance.MEMORY_STATIC) / BYTES_TO_MB
		_ui_diagnostic_label_mem.text = "RAM (Static): %.2f MB" % ram_mb

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
			var rtt_win = _round_trip_time_history.size()
			_ui_diagnostic_label_rtt.text = "RTT (ms): %.0f | Avg(%d): %.0f | Min: %.0f | Max: %.0f" % [
				_network_round_trip_time,
				rtt_win,
				rtt_avg,
				rtt_min_disp,
				_round_trip_time_maximum,
			]
			var l_win = _packet_loss_history.size()
			_ui_diagnostic_label_loss.text = "Packet Loss: %.1f%% | Avg(%d): %.1f%% | Min: %.1f%% | Max: %.1f%%" % [
				current_loss,
				l_win,
				loss_avg,
				loss_min_disp,
				_packet_loss_maximum,
			]
			_ui_diagnostic_label_offset.text = "Clock Offset: %.1f ms" % _network_clock_offset
		else:
			_ui_diagnostic_label_rtt.text = "RTT (ms): Aguardando..."
			_ui_diagnostic_label_loss.text = "Packet Loss: Aguardando..."
			_ui_diagnostic_label_offset.text = "Clock Offset: Aguardando..."

		var visible_total = 0
		var visible_peers = 0
		var visible_props = 0

		var known_total = 0
		var known_peers = 0
		var known_props = 0

		if QuanticNet.is_server():
			var registry = QuanticNet.get_registry()
			for k in registry:
				visible_total += 1
				known_total += 1
				if k < PEER_ID_THRESHOLD:
					visible_peers += 1
					known_peers += 1
				else:
					visible_props += 1
					known_props += 1
			_ui_diagnostic_label_peers.text = "Entities: %d (Peers: %d | Props: %d)" % [
				visible_total,
				visible_peers,
				visible_props,
			]
		else:
			for id in _active_visual_entities_map.keys():
				known_total += 1
				var is_peer = (id < PEER_ID_THRESHOLD)
				if is_peer:
					known_peers += 1
				else:
					known_props += 1

				if _active_visual_entities_map[id].visible:
					visible_total += 1
					if is_peer:
						visible_peers += 1
					else:
						visible_props += 1

			_ui_diagnostic_label_peers.text = "Entities (Visible/Known): %d/%d (Peers: %d/%d | Props: %d/%d)" % [
				visible_total,
				known_total,
				visible_peers,
				known_peers,
				visible_props,
				known_props,
			]

# ==============================================================================
# BINDINGS ASSÍNCRONOS DE REDE (EVENT-DRIVEN ARCHITECTURE)
# ==============================================================================


func _on_conn_state(state: int) -> void:
	if _is_acting_as_server:
		return

	# Máquina de estados global exposta pelo Autoload do QuanticNet
	match state:
		QuanticNet.ConnectionState.DISCONNECTED:
			_ui_label_connection_status.text = "DISCONNECTED"
			_ui_label_connection_status.add_theme_color_override("font_color", Color.GRAY)
			DisplayServer.window_set_title("Disconnected")
			_clear_world()
		QuanticNet.ConnectionState.CONNECTING:
			_ui_label_connection_status.text = "CONNECTING..."
			_ui_label_connection_status.add_theme_color_override("font_color", Color.YELLOW)
		QuanticNet.ConnectionState.AUTHENTICATING:
			_ui_label_connection_status.text = "AUTHENTICATING..."
			_ui_label_connection_status.add_theme_color_override("font_color", Color.ORANGE)
		QuanticNet.ConnectionState.CONNECTED:
			_ui_label_connection_status.text = "CONNECTED"
			_ui_label_connection_status.add_theme_color_override("font_color", Color.GREEN)
			var my_id = QuanticNet.get_unique_id()
			var title = str(my_id)
			if _is_network_emulation_active:
				title += " (NETEM ON)"
			DisplayServer.window_set_title(title)
		QuanticNet.ConnectionState.FAILED:
			_ui_label_connection_status.text = "FAILED"
			_ui_label_connection_status.add_theme_color_override("font_color", Color.RED)
			DisplayServer.window_set_title("Disconnected")
			_clear_world()


func _clear_world() -> void:
	# Purga o registro visual local. 
	# Sem o aval do servidor (Autoridade), qualquer entidade remanescente é apenas um fantasma estéril.
	_active_visual_entities_map.clear()
	if _scene_world_root_node:
		for child in _scene_world_root_node.get_children():
			child.queue_free()


func _on_pong_received(rtt: float, offset: float) -> void:
	# Este sinal é disparado pela engine nativa (C++) a cada resposta temporal do Servidor.
	# Diferente do ICMP estéril, o QuanticNet acopla timestamps criptografados no cabeçalho do UDP,
	# entregando métricas de precisão sub-milissegundo para calcular o Ping (RTT) real e a defasagem (Offset) do relógio cliente-servidor.
	_network_round_trip_time = rtt
	_network_clock_offset = offset

	if rtt > 0:
		_round_trip_time_history.append(rtt)
		if _round_trip_time_history.size() > RTT_HISTORY_MAX:
			_round_trip_time_history.pop_front()

		if rtt < _round_trip_time_minimum:
			_round_trip_time_minimum = rtt
		if rtt > _round_trip_time_maximum:
			_round_trip_time_maximum = rtt


func _on_peer_joined(peer_id: int) -> void:
	print("Peer Joined: %d" % peer_id)
	if _is_acting_as_server:
		QuanticNet.register_entity(peer_id, true, true, _entity_profile_player)
		_active_profiles[peer_id] = _entity_profile_player

		# Sincroniza a Aura (Culling Radius) com os clientes para que eles não assumam o valor default de 20m
		# 1. Informa o novo Peer sobre as Auras de todos que já estão no mapa
		for id in _active_profiles.keys():
			var rad = _active_profiles[id].get_spatial_culling_radius()
			rpc_id(peer_id, "client_update_visual_radius", id, rad)

			# 2. Informa os Peers antigos sobre a Aura do novato
			if id != peer_id and id < PEER_ID_THRESHOLD:
				rpc_id(
					id,
					"client_update_visual_radius",
					peer_id,
					_entity_profile_player.get_spatial_culling_radius(),
				)


func _on_peer_left(peer_id: int) -> void:
	if _is_acting_as_server:
		QuanticNet.unregister_entity(peer_id)
		_active_profiles.erase(peer_id)
		return

	if _active_visual_entities_map.has(peer_id):
		var v = _active_visual_entities_map[peer_id]
		v.queue_free()
		_active_visual_entities_map.erase(peer_id)


func _update_visual(id: int, pos: Vector3, is_local: bool) -> void:
	if not _active_visual_entities_map.has(id):
		var mesh_inst = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = PLAYER_MESH_SIZE if id < PEER_ID_THRESHOLD else PROP_MESH_SIZE
		mesh_inst.mesh = box
		var mat = StandardMaterial3D.new()
		var entity_color: Color
		var presence_radius: float

		if is_local:
			entity_color = LOCAL_PLAYER_COLOR
			presence_radius = _entity_profile_player.get_spatial_culling_radius()
		elif id < PEER_ID_THRESHOLD:
			entity_color = REMOTE_PLAYER_COLOR
			presence_radius = _active_profiles \
					.get(id, _entity_profile_player) \
					.get_spatial_culling_radius()
		else:
			entity_color = PROP_COLOR
			presence_radius = _entity_profile_prop.get_spatial_culling_radius()

		mat.albedo_color = entity_color
		mesh_inst.material_override = mat
		mesh_inst.set_meta("presence_radius", presence_radius)

		# Anel de Presença (AoI da Entidade - Projetado via Decal sobre o terreno)
		var presence_color = entity_color
		presence_color.a = PRESENCE_RING_ALPHA # Translúcido
		var presence_ring = _create_decal_ring(presence_color, presence_radius, "PresenceRing")
		mesh_inst.add_child(presence_ring)

		# Anel de Visão (FOV - Apenas para o Cliente Local - Projetado via Decal)
		if is_local:
			var fov_ring = _create_decal_ring(
				FOV_RING_COLOR,
				_client_local_culling_radius,
				"FOVRing",
			)
			mesh_inst.add_child(fov_ring)

		# Representação Visual do Colisor Físico Cápsula e Ponto de Apoio/Contato com a NavMesh
		var collider_vis = _create_capsule_collider_visual(id, is_local)
		mesh_inst.add_child(collider_vis)

		# --- [DIAGNOSTIC] Label3D para prova determinística de coordenadas ---
		var lbl = Label3D.new()
		lbl.name = "CoordLabel"
		lbl.pixel_size = COORD_LABEL_PIXEL_SIZE
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.position = COORD_LABEL_OFFSET
		lbl.modulate = Color.WHITE
		lbl.outline_modulate = Color.BLACK
		lbl.outline_size = COORD_LABEL_OUTLINE_SIZE
		mesh_inst.add_child(lbl)
		# Visor (Rosto)
		var visor = MeshInstance3D.new()
		var vmesh = BoxMesh.new()
		vmesh.size = PLAYER_VISOR_SIZE if id < PEER_ID_THRESHOLD else PROP_VISOR_SIZE
		visor.mesh = vmesh
		var vmat = StandardMaterial3D.new()
		vmat.albedo_color = Color.BLACK
		visor.material_override = vmat
		visor.position = PLAYER_VISOR_OFFSET if id < PEER_ID_THRESHOLD else PROP_VISOR_OFFSET # -Z é a frente no Godot
		mesh_inst.add_child(visor)
		# ---------------------------------------------------------------------
		mesh_inst.position = pos
		_scene_world_root_node.add_child(mesh_inst)
		_active_visual_entities_map[id] = mesh_inst

	var visual = _active_visual_entities_map[id]
	if is_local:
		var y_offset = ENTITY_DEFAULT_Y_OFFSET
		if visual.mesh and visual.mesh is BoxMesh:
			y_offset = visual.mesh.size.y / 2.0
		visual.position = pos + Vector3(0, y_offset, 0)

		var lbl = visual.get_node_or_null("CoordLabel") as Label3D
		if lbl:
			lbl.text = "ID: %d [L]\nX: %.1f | Y: %.1f | Z: %.1f" % [id, pos.x, pos.y, pos.z]


func _update_dynamic_rings() -> void:
	var is_local_client = not QuanticNet.is_server()
	var local_id = QuanticNet.get_unique_id()

	for id in _active_visual_entities_map.keys():
		var vis = _active_visual_entities_map[id]
		var is_local = (is_local_client and id == local_id)

		# Atualiza Presence Ring (Decal)
		var presence_node = vis.get_node_or_null("PresenceRing") as Decal
		if presence_node:
			presence_node.visible = _show_culling_rings
			var pradius = vis.get_meta("presence_radius", FALLBACK_PRESENCE_RADIUS)
			var target_size = Vector3(pradius * 2.0, DECAL_PROJECTION_HEIGHT, pradius * 2.0)
			if presence_node.size != target_size:
				presence_node.size = target_size

		# Atualiza FOV Ring (Decal)
		if is_local:
			var fov_node = vis.get_node_or_null("FOVRing") as Decal
			if fov_node:
				fov_node.visible = _show_culling_rings
				var target_fov_size = Vector3(
					_client_local_culling_radius * 2.0,
					DECAL_PROJECTION_HEIGHT,
					_client_local_culling_radius * 2.0,
				)
				if fov_node.size != target_fov_size:
					fov_node.size = target_fov_size

	# Representação Visual da Grade Espacial do Core C++ (Broad-phase real)
	if is_local_client:
		var spatial_node = _scene_world_root_node.get_node_or_null("SpatialAreaVisualizer") as MeshInstance3D
		if not spatial_node:
			spatial_node = MeshInstance3D.new()
			spatial_node.name = "SpatialAreaVisualizer"
			var box_mesh = BoxMesh.new()
			box_mesh.size = Vector3(
				SPATIAL_GRID_CELL_SIZE,
				SPATIAL_CELL_DEBUG_HEIGHT,
				SPATIAL_GRID_CELL_SIZE,
			)
			spatial_node.mesh = box_mesh
			var mat = StandardMaterial3D.new()
			mat.albedo_color = SPATIAL_GRID_DEBUG_COLOR # Roxo BEM translúcido para ser sutil
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			spatial_node.material_override = mat
			_scene_world_root_node.add_child(spatial_node)

		spatial_node.visible = _show_culling_rings

		if spatial_node.visible:
			var pos = _client_predicted_position
			var cell_size = SPATIAL_GRID_CELL_SIZE

			var cx = floor(pos.x / cell_size)
			var cz = floor(pos.z / cell_size)

			var min_x = cx * cell_size
			var max_x = (cx + 1) * cell_size
			var min_z = cz * cell_size
			var max_z = (cz + 1) * cell_size

			var size_x = max_x - min_x
			var size_z = max_z - min_z

			var bmesh = spatial_node.mesh as BoxMesh
			if bmesh:
				if bmesh.size.x != size_x or bmesh.size.z != size_z:
					bmesh.size = Vector3(size_x, SPATIAL_CELL_DEBUG_HEIGHT, size_z)

			# A grade global na engine centralizada
			spatial_node.position = Vector3(
				min_x + (size_x / 2.0),
				SPATIAL_GRID_Y_OFFSET,
				min_z + (size_z / 2.0),
			)


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


func _spawn_laser(start_pos: Vector3, color: Color) -> void:
	# print("[DEBUG] Spawning laser at: ", start_pos, " | Is Server: ", QuanticNet.is_server())
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = LASER_MESH_SIZE
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = LASER_EMISSION_ENERGY
	mesh.material_override = mat
	mesh.position = start_pos + LASER_START_OFFSET
	_scene_world_root_node.add_child(mesh)

	var tween = get_tree().create_tween()
	tween.tween_property(mesh, "position", mesh.position + LASER_ANIM_OFFSET, LASER_ANIM_DURATION)
	tween.tween_callback(mesh.queue_free)


func _on_snapback(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
	# O evento de Snapback (Reconciliação) é o coração do Anti-Cheat arquitetural.
	# Quando o servidor flagra a predição local do cliente desrespeitando o modelo físico, ele dispara este sinal,
	# forçando o cliente a aceitar o vetor do servidor e re-simular os inputs na fila (replay) que ainda não chegaram.
	print("Snapback Recebido (Reconciliação Forçada): %s" % str(pos))

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
	if _is_acting_as_server:
		return

	# Consome atalhos de depuração evitando colisões com a Interface 2D (Botões e Caixas de Texto).
	# O isolamento em `_unhandled_input` previne tiros acidentais quando o jogador tenta interagir com a UI.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_current_zoom = max(ZOOM_MIN, _current_zoom - ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_current_zoom = min(ZOOM_MAX, _current_zoom + ZOOM_STEP)

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _camera_pivot:
			_camera_pivot.rotation_degrees.y -= event.relative.x * MOUSE_SENSITIVITY
			_camera_pivot.rotation_degrees.x -= event.relative.y * MOUSE_SENSITIVITY
			_camera_pivot.rotation_degrees.x = clamp(
				_camera_pivot.rotation_degrees.x,
				CAMERA_PITCH_MIN,
				CAMERA_PITCH_MAX,
			)

	if event is InputEventKey and event.pressed and not event.echo:
		# [SPACE] - Toggle Câmera Alta
		if event.keycode == KEY_SPACE:
			_is_camera_high = not _is_camera_high

		# [N] - Toggle Netem (Network Emulation)
		if event.keycode == KEY_N:
			_is_network_emulation_active = not _is_network_emulation_active
			var loss = _global_network_parameters["netem_loss"] if _is_network_emulation_active else 0.0
			var lat = _global_network_parameters["netem_latency"] if _is_network_emulation_active else 0
			var jit = _global_network_parameters["netem_jitter"] if _is_network_emulation_active else 0
			var dup = _global_network_parameters["netem_dup"] if _is_network_emulation_active else 0.0

			QuanticNet.set_netem_config(loss, lat, jit, dup)
			var status = "ON (Loss: %.0f%% | Lat: %dms | Jit: %dms)" % [loss, lat, jit] if _is_network_emulation_active else "OFF"
			print("NETEM Toggle: %s" % status)

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
			print("System Profiler resetado!")

		# [F2] - Resetar Métricas de Network
		elif event.keycode == KEY_F2:
			_round_trip_time_history.clear()
			_round_trip_time_minimum = SENTINEL_MAX_FLOAT
			_round_trip_time_maximum = 0.0
			_packet_loss_history.clear()
			_packet_loss_minimum = SENTINEL_MAX_FLOAT
			_packet_loss_maximum = 0.0
			print("Network Profiler resetado!")

		# [F] - Toggle V-Sync e Max FPS (Teste de Stress visual)
		elif event.keycode == KEY_F:
			if Engine.max_fps == 0:
				Engine.max_fps = TARGET_FPS
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
			else:
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			print(
				"FPS Limitado: ",
				"SIM (60Hz)" if Engine.max_fps == 60 else "NÃO (Unlimited)",
			)

		# [ENTER] - Toggle Auto-Move
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_is_auto_movement_enabled = not _is_auto_movement_enabled
			if _is_auto_movement_enabled:
				_auto_movement_center_origin = _client_predicted_position
				_auto_movement_elapsed_time = 0.0
			print("Auto-move: ", _is_auto_movement_enabled)

		# [+ / -] - Client View Distance (Visual Culling)
		elif event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD:
			_client_local_culling_radius += VIEW_DISTANCE_STEP
			print("View Distance: ", _client_local_culling_radius)
		elif event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT:
			_client_local_culling_radius = maxf(
				VIEW_DISTANCE_MIN,
				_client_local_culling_radius - VIEW_DISTANCE_STEP,
			)
			print("View Distance: ", _client_local_culling_radius)

		elif event.keycode == KEY_H:
			_show_culling_rings = not _show_culling_rings
			for id in _active_visual_entities_map.keys():
				var vis = _active_visual_entities_map[id]
				var presence_ring = vis.get_node_or_null("PresenceRing") as Decal
				if presence_ring:
					presence_ring.visible = _show_culling_rings
				var fov_ring = vis.get_node_or_null("FOVRing") as Decal
				if fov_ring:
					fov_ring.visible = _show_culling_rings

			var spatial_node = _scene_world_root_node.get_node_or_null("SpatialAreaVisualizer")
			if spatial_node:
				spatial_node.visible = _show_culling_rings

			print("Culling Rings: ", "Exibidos" if _show_culling_rings else "Ocultos")

		# [,] (Vírgula) - Toggle NavMesh Visual
		elif event.keycode == KEY_COMMA:
			var nav_vis = _scene_world_root_node.get_node_or_null("NavMeshVisual")
			if nav_vis:
				nav_vis.visible = not nav_vis.visible
				print("NavMesh Visual: ", "Exibido" if nav_vis.visible else "Oculto")

		# [C] - Toggle Colisor Cápsula Visual
		elif event.keycode == KEY_C:
			_show_collider_visual = not _show_collider_visual
			for id in _active_visual_entities_map.keys():
				var vis = _active_visual_entities_map[id]
				var col_vis = vis.get_node_or_null("ColliderVisual")
				if col_vis:
					col_vis.visible = _show_collider_visual
			print("Collider Visual: ", "Exibido" if _show_collider_visual else "Oculto")

		elif event.keycode >= KEY_0 and event.keycode <= KEY_9:
			var target_tick = -1.0
			var target_cull = -1.0

			match event.keycode:
				KEY_1:
					target_tick = PROFILE_HZ_KEY_1
				KEY_2:
					target_tick = PROFILE_HZ_KEY_2
				KEY_3:
					target_tick = PROFILE_HZ_KEY_3
				KEY_4:
					target_tick = PROFILE_HZ_KEY_4
				KEY_5:
					target_tick = PROFILE_HZ_KEY_5
				KEY_6:
					target_cull = PROFILE_CULL_KEY_6
				KEY_7:
					target_cull = PROFILE_CULL_KEY_7
				KEY_8:
					target_cull = PROFILE_CULL_KEY_8
				KEY_9:
					target_cull = PROFILE_CULL_KEY_9
				KEY_0:
					target_cull = PROFILE_CULL_KEY_0

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
		var old_prof = _active_profiles.get(peer_id, _entity_profile_player)
		var t = new_tick if new_tick > 0 else old_prof.get_tick_rate_hz()
		var c = new_culling if new_culling > 0 else old_prof.get_spatial_culling_radius()
		var new_prof = QNEntityProfile.new()
		new_prof.init(t, old_prof.get_base_priority(), c)

		_active_profiles[peer_id] = new_prof
		QuanticNet.change_entity_profile(peer_id, new_prof)
		rpc("client_update_visual_radius", peer_id, c)
		print("Perfil Atualizado para Peer %d: %.1fHz | Culling: %.1fm" % [peer_id, t, c])


@rpc("authority", "call_local")
func client_update_visual_radius(peer_id: int, new_radius: float) -> void:
	if _active_visual_entities_map.has(peer_id):
		var vis = _active_visual_entities_map[peer_id]
		vis.set_meta("presence_radius", new_radius)

	# Memoriza o raio no cliente para caso a entidade saia do range (seja deletada) e volte depois!
	if not QuanticNet.is_server():
		var prof = QNEntityProfile.new()
		prof.init(CLIENT_DYNAMIC_PROFILE_HZ, CLIENT_DYNAMIC_PROFILE_PRIO, new_radius)
		_active_profiles[peer_id] = prof


func _on_custom_packet_received(peer_id: int, ptype: int, data: PackedByteArray) -> void:
	if ptype == GAME_OP_SHOOT_HITSCAN or ptype == GAME_OP_SHOOT_PHYSICS:
		if data.size() >= PACKET_POSITION_BYTE_SIZE:
			var pos = Vector3(
				data.decode_float(PACKET_OFFSET_POS_X),
				data.decode_float(PACKET_OFFSET_POS_Y),
				data.decode_float(PACKET_OFFSET_POS_Z),
			)
			var color = LASER_COLOR_HITSCAN if ptype == GAME_OP_SHOOT_HITSCAN else LASER_COLOR_PHYSICS

			if QuanticNet.is_server():
				# Broadcast for other clients
				for other_id in QuanticNet.get_active_peers():
					if other_id != peer_id and other_id > 1:
						QuanticNet.send_game_packet(other_id, ptype, data, true)

				# Se o servidor também for visual, spawna localmente
				if not OS.has_feature("dedicated_server") and peer_id != 1:
					_spawn_laser(pos, color)
			else:
				# Sou cliente e recebi isso do servidor (significa que outro cliente atirou)
				_spawn_laser(pos, color)
