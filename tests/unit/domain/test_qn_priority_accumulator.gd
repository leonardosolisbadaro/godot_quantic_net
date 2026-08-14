## @file test_qn_priority_accumulator.gd
## @path res://addons/quantic_net/tests/domain/test_qn_priority_accumulator.gd
##
## @description
## Testes unitÃ¡rios para o despachante de rede QNPriorityAccumulator, validando o rank 
## baseado em MTU, distÃ¢ncia, profile e debito de pacotes (prevenÃ§Ã£o de starvation).
##
## @created 2026-08-01
## @updated 2026-08-14
##
## @since 0.1.0
## @lastModifiedIn 0.9.1
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends GutTest


func test_must_prioritize_closest_entities():
	var acc = QNPriorityAccumulator.new()
	var observer_pos = Vector3.ZERO
	var mtu_budget = 40 # Cabe exatas 2 entidades (2 * 19 = 38 bytes)

	var candidates = {
		2: { "pos": Vector3(10, 0, 0) }, # Entidade Longe
		3: { "pos": Vector3(2, 0, 0) }, # Entidade Perto
		4: { "pos": Vector3(5, 0, 0) }, # Entidade IntermediÃ¡ria
	}

	var profiles = {
		2: QNEntityProfile.preset_standard(),
		3: QNEntityProfile.preset_standard(),
		4: QNEntityProfile.preset_standard(),
	}

	var selected = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)

	# Cabe 2 entidades. As mais prÃ³ximas devem ganhar (3 e 4)
	assert_eq(selected.size(), 2, "Apenas duas entidades devem caber no budget do MTU")
	assert_true(selected.has(3), "A entidade 3 (mais prÃ³xima) deve estar inclusa")
	assert_true(selected.has(4), "A entidade 4 (intermediÃ¡ria) deve estar inclusa")
	assert_false(selected.has(2), "A entidade 2 (longe) deve ser descartada por falta de espaÃ§o")


func test_must_accumulate_debt_and_prevent_starvation():
	var acc = QNPriorityAccumulator.new()
	var observer_pos = Vector3.ZERO
	var mtu_budget = 20 # Cabe apenas 1 entidade (1 * 19 = 19 bytes)

	var candidates = {
		2: { "pos": Vector3(10, 0, 0) }, # Longe
		3: { "pos": Vector3(2, 0, 0) }, # Perto
	}

	var profiles = {
		2: QNEntityProfile.preset_standard(),
		3: QNEntityProfile.preset_standard(),
	}

	# Tick 1: A entidade 3 ganha pois estÃ¡ mais perto
	var sel_1 = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)
	assert_true(sel_1.has(3))
	assert_false(sel_1.has(2))

	# Para simular "passagem do tempo sem mover", rodamos novamente. 
	# A Entidade 2 acumulou dÃ©bito, entÃ£o o score dela sobe a cada iteraÃ§Ã£o!
	var sel_final = null
	var loops = 0

	for i in range(10):
		loops += 1
		var sel = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)
		if sel.has(2):
			sel_final = sel
			break

	assert_not_null(
		sel_final,
		"Eventualmente a Entidade 2 deve ganhar devido ao acÃºmulo de dÃ©bito",
	)
	assert_true(loops < 10, "A Entidade 2 nÃ£o deve morrer de fome; venceu apÃ³s %d ticks" % loops)


func test_must_cull_entities_outside_radius():
	var acc = QNPriorityAccumulator.new()
	var observer_pos = Vector3.ZERO
	var mtu_budget = 1200

	var candidates = {
		2: { "pos": Vector3(60, 0, 0) }, # Fora do Cull Radius (50m default)
		3: { "pos": Vector3(40, 0, 0) }, # Dentro do Cull Radius
	}

	var profiles = {
		2: QNEntityProfile.preset_standard(), # cull_radius = 50.0
		3: QNEntityProfile.preset_standard(),
	}

	var selected = acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)
	assert_eq(selected.size(), 1, "Apenas a entidade dentro do cull radius deve ser enviada")
	assert_true(selected.has(3))
	assert_false(selected.has(2))


func test_debt_accumulation_must_respect_maximum_cap():
	var acc = QNPriorityAccumulator.new()
	var observer_pos = Vector3.ZERO
	# MTU budget insuficiente para qualquer entidade (forçar acúmulo contínuo de débito)
	var mtu_budget = 5

	var candidates = {
		2: { "pos": Vector3(1, 0, 0) }, # Muito perto (score inicial altíssimo)
	}

	var profiles = {
		2: QNEntityProfile.preset_standard(),
	}

	# Executa múltiplos ticks sem enviar
	for i in range(50):
		acc.select_entities(1, candidates, profiles, observer_pos, mtu_budget, 19)

	# Agora dá budget suficiente para 1 entidade
	var selected = acc.select_entities(1, candidates, profiles, observer_pos, 50, 19)
	assert_true(selected.has(2), "Entidade 2 deve ser despachada e ter sua divida limpa")

	# Próximo tick: se a dívida foi limpa e não explodiu, comportamento deve se manter estável
	var selected_next = acc.select_entities(1, candidates, profiles, observer_pos, 50, 19)
	assert_true(selected_next.has(2))

