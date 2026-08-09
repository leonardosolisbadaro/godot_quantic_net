## @file test_qn_spatial_grid.gd
## @path res://tests/unit/test_qn_spatial_grid.gd
##
## @description
## Testes unitários para QNSpatialGrid (C++ GDExtension) validando a
## capacidade de Hashing Espacial, inserção e consultas radiais puras.
##
## @created 2026-08-04
## @updated 2026-08-04
##
## @since 0.5.0
## @lastModifiedIn 0.5.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

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
	assert_false(found.has(301), "A entidade 301 deve ter desaparecido da busca espacial apos ser removida")
