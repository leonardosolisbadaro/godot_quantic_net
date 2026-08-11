import re

with open("addons/quantic_net/demo/demo_main.gd", "r", encoding="utf-8") as f:
    content = f.read()

# ADD CONSTANTS BLOCK
new_constants = """
# Constantes de Visualização de Entidades (Meshes e Labels)
const PLAYER_MESH_SIZE := Vector3(1, 2, 1)
const PROP_MESH_SIZE := Vector3(1, 1, 1)
const LOCAL_PLAYER_COLOR := Color.GREEN
const REMOTE_PLAYER_COLOR := Color.RED
const PROP_COLOR := Color.YELLOW
const COORD_LABEL_OFFSET := Vector3(0, 1.5, 0)
const COORD_LABEL_PIXEL_SIZE := 0.015
const COORD_LABEL_OUTLINE_SIZE := 4

# Constantes de Efeitos e Animações (Laser Hitscan/Físico)
const LASER_MESH_SIZE := Vector3(0.2, 2.0, 0.2)
const LASER_EMISSION_ENERGY := 5.0
const LASER_START_OFFSET := Vector3(0, 2, 0)
const LASER_ANIM_OFFSET := Vector3(0, 10, 0)
const LASER_ANIM_DURATION := 0.5

# Constantes de Topologia e Endereçamento
const DEFAULT_BIND_IP := "127.0.0.1"
"""

anchor = """const SECRET := "demo-secret"
"""
# Only inject if not already there
if "Constantes de Visualização de Entidades" not in content:
    content = content.replace(anchor, anchor + "\n" + new_constants)

content = content.replace("""		box.size = Vector3(1, 2, 1) if id < 1000 else Vector3(1, 1, 1)""",
"""		box.size = PLAYER_MESH_SIZE if id < 1000 else PROP_MESH_SIZE""")

content = content.replace("""			entity_color = Color.GREEN""", """			entity_color = LOCAL_PLAYER_COLOR""")
content = content.replace("""			entity_color = Color.RED""", """			entity_color = REMOTE_PLAYER_COLOR""")
content = content.replace("""			entity_color = Color.YELLOW""", """			entity_color = PROP_COLOR""")

content = content.replace("""			else:
				presence_radius = 20.0""",
"""			else:
				presence_radius = PROFILE_PLAYER_CULL""")

content = content.replace("""		lbl.pixel_size = 0.015""", """		lbl.pixel_size = COORD_LABEL_PIXEL_SIZE""")
content = content.replace("""		lbl.position = Vector3(0, 1.5, 0)""", """		lbl.position = COORD_LABEL_OFFSET""")
content = content.replace("""		lbl.outline_size = 4""", """		lbl.outline_size = COORD_LABEL_OUTLINE_SIZE""")

content = content.replace("""	box.size = Vector3(0.2, 2.0, 0.2)""", """	box.size = LASER_MESH_SIZE""")
content = content.replace("""	mat.emission_energy_multiplier = 5.0""", """	mat.emission_energy_multiplier = LASER_EMISSION_ENERGY""")
content = content.replace("""	mesh.position = start_pos + Vector3(0, 2, 0)""", """	mesh.position = start_pos + LASER_START_OFFSET""")
content = content.replace("""	tween.tween_property(mesh, "position", mesh.position + Vector3(0, 10, 0), 0.5)""", """	tween.tween_property(mesh, "position", mesh.position + LASER_ANIM_OFFSET, LASER_ANIM_DURATION)""")

content = content.replace("""QuanticNet.host(PORT, SECRET, "127.0.0.1", MAX_PEERS, _global_network_parameters)""", """QuanticNet.host(PORT, SECRET, DEFAULT_BIND_IP, MAX_PEERS, _global_network_parameters)""")
content = content.replace("""QuanticNet.join("127.0.0.1", PORT, SECRET, use_netem, _global_network_parameters)""", """QuanticNet.join(DEFAULT_BIND_IP, PORT, SECRET, use_netem, _global_network_parameters)""")

with open("addons/quantic_net/demo/demo_main.gd", "w", encoding="utf-8") as f:
    f.write(content)
