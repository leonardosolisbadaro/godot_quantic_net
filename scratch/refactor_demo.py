import re

with open("addons/quantic_net/demo/demo_main.gd", "r", encoding="utf-8") as f:
    content = f.read()

# Normalize line endings
content = content.replace("\r\n", "\n")

# ADD CONSTANTS BLOCK
constants_block = """
# Constantes de Perfis Dinâmicos (Tick Rates e Culling Radius)
const PROFILE_PLAYER_HZ := 60.0 # Tick rate nativo de um jogador humano
const PROFILE_PLAYER_PRIO := 1.0 # Prioridade base na fila do acumulador visual
const PROFILE_PLAYER_CULL := 20.0 # Distância máxima onde a engine transmitirá estado

const PROFILE_PROP_HZ := 5.0 # Props inanimados atualizam raramente
const PROFILE_PROP_PRIO := 0.5 # Menor prioridade, só transmite se sobrar banda
const PROFILE_PROP_CULL := 20.0 

const PROFILE_NPC_HZ := 20.0 # NPCs se movem moderadamente
const PROFILE_NPC_PRIO := 1.0 
const PROFILE_NPC_CULL := 20.0

const PROFILE_PROJECT_HZ := 60.0 # Balas e projéteis requerem fluidez máxima
const PROFILE_PROJECT_PRIO := 3.0 # Prioridade extrema (fura a fila)
const PROFILE_PROJECT_CULL := 50.0 # Devem ser vistos de longe

# Constantes de Geração de Cena Visual
const WORLD_FLOOR_COLOR := Color(0.2, 0.2, 0.2)
const RING_THICKNESS := 0.2 # Espessura do anel de debug visual
const RING_SIDES := 64 # Segmentos do torus de debug
const RING_SEG := 32
const RING_Y_OFFSET := 0.05
const GRID_THICKNESS := 0.15 # Espessura da linha do grid visual
const CAMERA_LERP_SPEED := 5.0 # Suavização do acompanhamento da câmera
const LASER_COLOR_HITSCAN := Color.AQUA
const LASER_COLOR_PHYSICS := Color.ORANGE

# Constantes de Parâmetros de Host / Rede (Segurança e Anti-Cheat)
const NET_MAX_SPEED := 30.0 # Limiar elástico do Anti-Speedhack
const NET_HARD_CAP := 50.0 # Tolerância máxima de predição antes de Snap forçado
const NET_WORLD_BOUNDS := 60.0 # Fronteira invisível de Culling
const NET_MAX_STRIKES := 5 # Quantos strikes antes do jogador ser kickado
const NET_AUTH_TIMEOUT := 3.0 # Tempo limite para resolver criptografia DTLS
const NETEM_LOSS_DEFAULT := 10.0 # Porcentagem simulada de perdas de pacote
const NETEM_LATENCY_DEFAULT := 150 # Ping base simulado
const NETEM_JITTER_DEFAULT := 50 # Variância no Ping simulado
const NETEM_DUP_DEFAULT := 0.0 # Simulação de clones udp
"""

anchor = """const SECRET := "demo-secret"
"""
content = content.replace(anchor, anchor + "\n" + constants_block)

content = content.replace("""	"max_speed": 30.0, # Limiar elástico do Anti-Speedhack. Alto para acomodar os solavancos drásticos causados pela simulação do Netem.
	"hard_cap": 50.0, # Se a distância do vetor ultrapassar este limite, a Engine descarta interpolações suaves e aplica um "Snap" (teleporte corretivo absoluto).
	"world_bounds": 60.0, # Fronteira matemática invisível. Entidades além dessa borda são removidas do registro autoritativo para poupar processamento Culling.
	"max_strikes": 5, # Contador de punição. Inputs flagrados por validação incorreta somam strikes até a desconexão compulsória (Kick).
	"auth_timeout": 3.0, # Margem (em segundos) para finalizar as chaves DTLS antes de derrubar a tentativa.
	"netem_loss": 10.0, # Simulação de colisão em redes ruins: % de pacotes que a placa virtual engolirá.
	"netem_latency": 150, # Injeção de RTT base forçado na rede local (Loopback).
	"netem_jitter": 50, # Flutuação randômica do atraso, imitando redes Mobile 4G instáveis.
	"netem_dup": 0.0, # Simula retransmissões fantasmas em roteadores congestionados.""",
"""	"max_speed": NET_MAX_SPEED, # Limiar elástico do Anti-Speedhack. Alto para acomodar os solavancos drásticos causados pela simulação do Netem.
	"hard_cap": NET_HARD_CAP, # Se a distância do vetor ultrapassar este limite, a Engine descarta interpolações suaves e aplica um "Snap" (teleporte corretivo absoluto).
	"world_bounds": NET_WORLD_BOUNDS, # Fronteira matemática invisível. Entidades além dessa borda são removidas do registro autoritativo para poupar processamento Culling.
	"max_strikes": NET_MAX_STRIKES, # Contador de punição. Inputs flagrados por validação incorreta somam strikes até a desconexão compulsória (Kick).
	"auth_timeout": NET_AUTH_TIMEOUT, # Margem (em segundos) para finalizar as chaves DTLS antes de derrubar a tentativa.
	"netem_loss": NETEM_LOSS_DEFAULT, # Simulação de colisão em redes ruins: % de pacotes que a placa virtual engolirá.
	"netem_latency": NETEM_LATENCY_DEFAULT, # Injeção de RTT base forçado na rede local (Loopback).
	"netem_jitter": NETEM_JITTER_DEFAULT, # Flutuação randômica do atraso, imitando redes Mobile 4G instáveis.
	"netem_dup": NETEM_DUP_DEFAULT, # Simula retransmissões fantasmas em roteadores congestionados.""")

content = content.replace("""	_entity_profile_player.init(60.0, 1.0, 20.0) # Hz default, 20m culling
	_entity_profile_prop = QNEntityProfile.new()
	_entity_profile_prop.init(5.0, 0.5, 20.0) # Hz Default
	_entity_profile_npc = QNEntityProfile.new()
	_entity_profile_npc.init(20.0, 1.0, 20.0) # Hz
	_entity_profile_projectile = QNEntityProfile.new()
	_entity_profile_projectile.init(60.0, 3.0, 50.0) # Hz (Prioridade Extrema)""",
"""	_entity_profile_player.init(PROFILE_PLAYER_HZ, PROFILE_PLAYER_PRIO, PROFILE_PLAYER_CULL)
	_entity_profile_prop = QNEntityProfile.new()
	_entity_profile_prop.init(PROFILE_PROP_HZ, PROFILE_PROP_PRIO, PROFILE_PROP_CULL)
	_entity_profile_npc = QNEntityProfile.new()
	_entity_profile_npc.init(PROFILE_NPC_HZ, PROFILE_NPC_PRIO, PROFILE_NPC_CULL)
	_entity_profile_projectile = QNEntityProfile.new()
	_entity_profile_projectile.init(PROFILE_PROJECT_HZ, PROFILE_PROJECT_PRIO, PROFILE_PROJECT_CULL)""")

content = content.replace("""	var plane_ow := PlaneMesh.new()
	plane_ow.size = Vector2(80, 80)
	var mat_ow := StandardMaterial3D.new()
	mat_ow.albedo_color = Color(0.2, 0.2, 0.2) # Dark Gray""",
"""	var plane_ow := PlaneMesh.new()
	plane_ow.size = FLOOR_SIZE * 2.0
	var mat_ow := StandardMaterial3D.new()
	mat_ow.albedo_color = WORLD_FLOOR_COLOR""")

content = content.replace("""func _create_ring(color: Color, radius: float, y_offset: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - 0.2
	mesh.outer_radius = radius
	mesh.rings = 64
	mesh.ring_segments = 32""",
"""func _create_ring(color: Color, radius: float, y_offset: float) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var mesh = TorusMesh.new()
	mesh.inner_radius = radius - RING_THICKNESS
	mesh.outer_radius = radius
	mesh.rings = RING_SIDES
	mesh.ring_segments = RING_SEG""")

content = content.replace("""func _create_aoi_grid(color: Color, size: Vector2, y_offset: float) -> Node3D:
	var node = Node3D.new()
	var thickness = 0.15""",
"""func _create_aoi_grid(color: Color, size: Vector2, y_offset: float) -> Node3D:
	var node = Node3D.new()
	var thickness = GRID_THICKNESS""")

content = content.replace("""_camera.position = _camera.position.lerp(target_cam_pos, _delta * 5.0)""",
"""_camera.position = _camera.position.lerp(target_cam_pos, _delta * CAMERA_LERP_SPEED)""")


content = content.replace("""			_spawn_laser(_client_predicted_position, Color.AQUA)
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				custom_input = 2 # Projétil Físico
				_cooldown_timer_last_shot_ms = now
				_spawn_laser(_client_predicted_position, Color.ORANGE)""",
"""			_spawn_laser(_client_predicted_position, LASER_COLOR_HITSCAN)
			elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				custom_input = 2 # Projétil Físico
				_cooldown_timer_last_shot_ms = now
				_spawn_laser(_client_predicted_position, LASER_COLOR_PHYSICS)""")


content = content.replace("""			# Disparo Hitscan (Raio Laser) propagado via C++
			_spawn_laser(pos, Color.AQUA)
		elif custom == 2:
			# Disparo de Projétil Físico
			_spawn_laser(pos, Color.ORANGE)""",
"""			# Disparo Hitscan (Raio Laser) propagado via C++
			_spawn_laser(pos, LASER_COLOR_HITSCAN)
		elif custom == 2:
			# Disparo de Projétil Físico
			_spawn_laser(pos, LASER_COLOR_PHYSICS)""")

content = content.replace("""var presence_ring = _create_ring(presence_color, presence_radius, 0.05)""", """var presence_ring = _create_ring(presence_color, presence_radius, RING_Y_OFFSET)""")

with open("addons/quantic_net/demo/demo_main.gd", "w", encoding="utf-8") as f:
    f.write(content)
