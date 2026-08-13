## @file qn_chunk_manager.gd
## @path res://addons/quantic_net/demo/qn_chunk_manager.gd
##
## @description
## Gerenciador rústico de Chunks 3D e NavMesh dinâmico para a demo.
## Substitui o chão infinito por um grid carregado sob demanda,
## com geometria procedimental para testar o validador Y (Flyhack).
##
## @created 2026-08-12
## @updated 2026-08-12
##
## @since 0.9.0
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends Node3D

const CHUNK_SIZE = 100.0 # 100x100 metros
const RENDER_RADIUS = 1 # 1 chunk para cada lado (3x3 grid = 9 chunks)

var _active_chunks: Dictionary = {}
var _material: StandardMaterial3D

func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.vertex_color_use_as_albedo = true

# positions_of_interest: Array[Vector3]
func update_chunks(positions_of_interest: Array) -> void:
	var needed_chunks = {}
	
	for pos in positions_of_interest:
		var cx = int(floor(pos.x / CHUNK_SIZE))
		var cz = int(floor(pos.z / CHUNK_SIZE))
		
		# Define os chunks necessários ao redor desta posição
		for x in range(cx - RENDER_RADIUS, cx + RENDER_RADIUS + 1):
			for z in range(cz - RENDER_RADIUS, cz + RENDER_RADIUS + 1):
				var key = Vector2(x, z)
				needed_chunks[key] = true
				
	# Remove os chunks que não são mais necessários
	var keys_to_remove = []
	for key in _active_chunks.keys():
		if not needed_chunks.has(key):
			_active_chunks[key].queue_free()
			keys_to_remove.append(key)
			
	for key in keys_to_remove:
		_active_chunks.erase(key)
		
	# Gera os chunks que faltam
	for key in needed_chunks.keys():
		if not _active_chunks.has(key):
			_active_chunks[key] = _generate_chunk(key.x, key.y)
			add_child(_active_chunks[key])

func get_height(gx: float, gz: float) -> float:
	# Matemática simples de terreno contínuo (Seno x Cosseno)
	# var h1 = sin(gx * 0.1) * cos(gz * 0.1) * 15.0
	# var h2 = sin(gx * 0.05 + 10.0) * 5.0
	# return h1 + h2
	return 0.0 # PLANO PARA TESTES

func _generate_chunk(cx: int, cz: int) -> Node3D:
	var chunk_root = Node3D.new()
	var cx_world = cx * CHUNK_SIZE
	var cz_world = cz * CHUNK_SIZE
	chunk_root.position = Vector3(cx_world, 0, cz_world)
	chunk_root.name = "Chunk_%d_%d" % [cx, cz]
	
	var nav_region = NavigationRegion3D.new()
	var nav_mesh = NavigationMesh.new()

	# Malha visual
	var visual_mesh = MeshInstance3D.new()

	# Usando SurfaceTool para gerar a malha com triângulos reais
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Cores intercaladas (checkerboard) em cinza
	var is_even = (int(abs(cx)) + int(abs(cz))) % 2 == 0
	var c = Color(0.2, 0.2, 0.2) if is_even else Color(0.3, 0.3, 0.3)
	st.set_color(c)
	var hs = CHUNK_SIZE / 2.0
	var gx = cx * CHUNK_SIZE
	var gz = cz * CHUNK_SIZE

	var v0 = Vector3(-hs, 0, -hs)
	var v1 = Vector3(hs, 0, -hs)
	var v2 = Vector3(hs, 0, hs)
	var v3 = Vector3(-hs, 0, hs)

	# A altura agora é absoluta baseada no Global X, Z.
	# Com isso, se dois chunks encostarem na mesma coordenada, eles têm a exata mesma altura!
	v0.y = get_height(gx + v0.x, gz + v0.z)
	v1.y = get_height(gx + v1.x, gz + v1.z)
	v2.y = get_height(gx + v2.x, gz + v2.z)
	v3.y = get_height(gx + v3.x, gz + v3.z)

	# Vertices (Visual) - Face 1
	st.set_normal(Vector3(0, 1, 0)) # simplificado
	st.set_color(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_uv(Vector2(1, 0)); st.add_vertex(v1)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v2)

	# Vertices (Visual) - Face 2
	st.set_color(c)
	st.set_uv(Vector2(0, 0)); st.add_vertex(v0)
	st.set_uv(Vector2(1, 1)); st.add_vertex(v2)
	st.set_uv(Vector2(0, 1)); st.add_vertex(v3)

	st.generate_normals()
	visual_mesh.mesh = st.commit()
	visual_mesh.material_override = _material

	# NavMesh (Matemático)
	# Usamos 2 triângulos perfeitos (coplanares) em vez de 1 Quad torto, garantindo a fusão perfeita.
	nav_mesh.vertices = PackedVector3Array([v0, v1, v2, v3])
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	nav_mesh.add_polygon(PackedInt32Array([0, 2, 3]))
	nav_region.navigation_mesh = nav_mesh
	
	# Adiciona os nós à hierarquia
	nav_region.add_child(visual_mesh)
	chunk_root.add_child(nav_region)
	
	return chunk_root
