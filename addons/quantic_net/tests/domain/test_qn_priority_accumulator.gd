## @file test_qn_priority_accumulator.gd
## @path res://addons/quantic_net/tests/domain/test_qn_priority_accumulator.gd
##
## @description
## Testes unitários para o despachante de rede QNPriorityAccumulator, validando o rank 
## baseado em MTU, distância, profile e debito de pacotes (prevenção de starvation).
##
## @created 2026-08-01
## @updated 2026-08-01
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNPriorityAccumulator = preload("res://addons/quantic_net/src/domain/qn_priority_accumulator.gd")
const QNNetProfile = preload("res://addons/quantic_net/src/domain/qn_net_profile.gd")

func test_must_prioritize_closest_entities():
	var acc = QNPriorityAccumulator.new()
	var observer_pos = Vector3.ZERO
	var mtu_budget = 40 # Cabe exatas 2 entidades (2 * 19 = 38 bytes)
	
	var candidates = {
		2: {"pos": Vector3(10, 0, 0)}, # Entidade Longe
		3: {"pos": Vector3(2, 0, 0)},  # Entidade Perto
		4: {"pos": Vector3(5, 0, 0)}   # Entidade Intermediária
	}
	
	var profiles = {
		2: QNNetProfile.preset_standard(),
		3: QNNetProfile.preset_standard(),
		4: QNNetProfile.preset_standard()
	}
	
	var selected = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)
	
	# Cabe 2 entidades. As mais próximas devem ganhar (3 e 4)
	assert_eq(selected.size(), 2, "Apenas duas entidades devem caber no budget do MTU")
	assert_true(selected.has(3), "A entidade 3 (mais próxima) deve estar inclusa")
	assert_true(selected.has(4), "A entidade 4 (intermediária) deve estar inclusa")
	assert_false(selected.has(2), "A entidade 2 (longe) deve ser descartada por falta de espaço")

func test_must_accumulate_debt_and_prevent_starvation():
	var acc = QNPriorityAccumulator.new()
	var observer_pos = Vector3.ZERO
	var mtu_budget = 20 # Cabe apenas 1 entidade (1 * 19 = 19 bytes)
	
	var candidates = {
		2: {"pos": Vector3(10, 0, 0)}, # Longe
		3: {"pos": Vector3(2, 0, 0)},  # Perto
	}
	
	var profiles = {
		2: QNNetProfile.preset_standard(),
		3: QNNetProfile.preset_standard()
	}
	
	# Tick 1: A entidade 3 ganha pois está mais perto
	var sel_1 = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)
	assert_true(sel_1.has(3))
	assert_false(sel_1.has(2))
	
	# Para simular "passagem do tempo sem mover", rodamos novamente. 
	# A Entidade 2 acumulou débito, então o score dela sobe a cada iteração!
	var sel_final = null
	var loops = 0
	
	for i in range(10):
		loops += 1
		var sel = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)
		if sel.has(2):
			sel_final = sel
			break
			
	assert_not_null(sel_final, "Eventualmente a Entidade 2 deve ganhar devido ao acúmulo de débito")
	assert_true(loops < 10, "A Entidade 2 não deve morrer de fome; venceu após %d ticks" % loops)

func test_must_cull_entities_outside_radius():
	var acc = QNPriorityAccumulator.new()
	var observer_pos = Vector3.ZERO
	var mtu_budget = 1200
	
	var candidates = {
		2: {"pos": Vector3(60, 0, 0)}, # Fora do Cull Radius (50m default)
		3: {"pos": Vector3(40, 0, 0)}, # Dentro do Cull Radius
	}
	
	var profiles = {
		2: QNNetProfile.preset_standard(), # cull_radius = 50.0
		3: QNNetProfile.preset_standard()
	}
	
	var selected = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)
	assert_eq(selected.size(), 1, "Apenas a entidade dentro do cull radius deve ser enviada")
	assert_true(selected.has(3))
	assert_false(selected.has(2))
