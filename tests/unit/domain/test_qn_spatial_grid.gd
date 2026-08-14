## @file test_qn_spatial_grid.gd
## @path res://tests/unit/test_qn_spatial_grid.gd
##
## @description
## Testes unitários para QNSpatialGrid (C++ GDExtension) validando a
## capacidade de Hashing Espacial, inserção e consultas radiais puras.
##
## @created 2026-08-04
## @updated 2026-08-14
##
## @since 0.5.0
## @lastModifiedIn 0.9.1
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends GutTest

var grid: QNSpatialGrid


func before_each():
	# Arrange
	grid = QNSpatialGrid.new()


func after_each():
	grid = null


func test_must_insert_and_find_within_radius():
	# Arrange: 3 entidades. Duas perto, uma longe.
	grid.insert_entity(101, Vector3(0, 0, 0))
	grid.insert_entity(102, Vector3(10, 0, 10))
	grid.insert_entity(103, Vector3(200, 0, 200)) # Muito longe

	# Act: Buscar entidades no raio de 50 metros a partir do (0,0,0)
	var found = grid.get_entities_in_radius(Vector3(0, 0, 0), 50.0)

	# Assert
	assert_true(found.has(101), "Deve encontrar a entidade 101 que esta na origem")
	assert_true(found.has(102), "Deve encontrar a entidade 102 que esta a ~14 metros")
	assert_false(found.has(103), "NAO deve encontrar a entidade 103 que esta a ~280 metros")


func test_must_update_entity_position_across_cells():
	# Arrange: Entidade inserida longe
	grid.insert_entity(201, Vector3(500, 0, 500))

	# Assert inicial
	var found = grid.get_entities_in_radius(Vector3(0, 0, 0), 50.0)
	assert_false(found.has(201), "A entidade 201 nao deve estar no raio inicial")

	# Act: Mover a entidade para o centro (0,0,0) e atualizar a grid
	grid.update_entity(201, Vector3(5, 0, 5))
	found = grid.get_entities_in_radius(Vector3(0, 0, 0), 50.0)

	# Assert final
	assert_true(found.has(201), "A entidade 201 deve ser encontrada no raio apos atualizacao")


func test_must_remove_entity():
	# Arrange
	grid.insert_entity(301, Vector3(10, 0, 10))
	var found = grid.get_entities_in_radius(Vector3(0, 0, 0), 50.0)
	assert_true(found.has(301), "A entidade deve existir antes de ser removida")

	# Act
	grid.remove_entity(301)
	found = grid.get_entities_in_radius(Vector3(0, 0, 0), 50.0)

	# Assert
	assert_false(
		found.has(301),
		"A entidade 301 deve ter desaparecido da busca espacial apos ser removida",
	)


func test_duplicate_insert_entity_must_not_create_ghost_entities():
	# Arrange: Inserir entidade 401 na celula A (0,0,0)
	grid.insert_entity(401, Vector3(0, 0, 0))
	var found_a = grid.get_entities_in_radius(Vector3(0, 0, 0), 20.0)
	assert_true(found_a.has(401), "Entidade 401 deve estar na celula A")

	# Act: Inserir a MESMA entidade 401 na celula B (500,0,500) sem chamar remove_entity
	grid.insert_entity(401, Vector3(500, 0, 500))

	# Assert: A celula antiga A (0,0,0) NAO deve conter 401 como fantasma
	found_a = grid.get_entities_in_radius(Vector3(0, 0, 0), 20.0)
	assert_false(found_a.has(401), "A celula antiga NAO deve reter a entidade 401 como fantasma")

	# A celula nova B deve conter 401
	var found_b = grid.get_entities_in_radius(Vector3(500, 0, 500), 20.0)
	assert_true(found_b.has(401), "A celula nova deve conter a entidade 401")

	# Ao remover a entidade 401, ela deve sumir de todas as celulas
	grid.remove_entity(401)
	found_b = grid.get_entities_in_radius(Vector3(500, 0, 500), 20.0)
	assert_false(found_b.has(401), "Entidade 401 deve ser removida com sucesso")


func test_set_cell_size_must_clear_grid():
	# Arrange
	grid.insert_entity(501, Vector3(10, 0, 10))
	var found = grid.get_entities_in_radius(Vector3(10, 0, 10), 20.0)
	assert_true(found.has(501))

	# Act: Alterar o tamanho da celula
	grid.set_cell_size(100.0)

	# Assert: Grid deve ter sido limpa para evitar chaves orfas
	found = grid.get_entities_in_radius(Vector3(10, 0, 10), 20.0)
	assert_false(found.has(501), "Redimensionar cell_size deve invalidar/limpar chaves orfas da grid")

