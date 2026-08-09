## @file test_qn_host_session.gd
## @path res://tests/unit/use_cases/test_qn_host_session.gd
##
## @description
## Testes unitários para QNHostSession, responsável pela orquestração autoritativa.
##
## @created 2026-07-30
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNServerValidator = preload("res://addons/quantic_net/src/domain/qn_server_validator.gd")


func test_peer_autenticado_aloca_entidade_com_perfil_mmo() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession

	# Act
	session.on_peer_authenticated(42)

	# Assert
	var registry = session.get_registry()
	assert_true(registry.has(42), "Entidade deve ser registrada no dicionario de sessoes.")

	var entity = registry[42]
	assert_eq(entity["id"], 42)
	assert_eq(entity["pos"], Vector3.ZERO)
	assert_eq(entity["rot"], Vector3.ZERO)
	assert_true(entity["profile"] != null, "Perfil alocado como objeto QNNetProfile")


func test_snapshot_valido_aceito_e_atualiza_registry() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession
	session.validator = autofree(QNServerValidator.new()) as QNServerValidator
	session.on_peer_authenticated(10)
	var pos := Vector3(1, 0, 1)
	var pkt := PackedByteArray([0, 0])
	pkt.append_array(
		QNSerializer.encode_state_history(
			[{ "seq": 10, "pos": pos, "rot": Vector3.ZERO, "ts": 1000, "custom_id": 0 }]
		)
	)

	# Act
	session.on_client_snapshot(10, pkt, 1000)

	# Assert
	var entity = session.get_registry()[10]
	assert_true(entity["pos"].distance_to(pos) < 0.05, "Posicao legitima deve atualizar a entidade")


func test_snapshot_com_speedhack_gera_clamp_e_snapback() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession
	session.validator = autofree(QNServerValidator.new()) as QNServerValidator
	session.on_peer_authenticated(10)

	# Snapshot inicial
	var pkt0 := PackedByteArray([0, 0])
	pkt0.append_array(
		QNSerializer.encode_state_history(
			[{ "seq": 1, "pos": Vector3.ZERO, "rot": Vector3.ZERO, "ts": 1000, "custom_id": 0 }]
		)
	)
	session.on_client_snapshot(10, pkt0, 1000)

	var sent_snapbacks := []
	session.snapback_requested.connect(
		func(id, pkt):
			sent_snapbacks.append({ "id": id, "pkt": pkt })
	)

	# Speedhack (10 metros em 1 segundo - max speed = 6)
	var pkt1 := PackedByteArray([0, 0])
	pkt1.append_array(
		QNSerializer.encode_state_history(
			[
				{
					"seq": 2,
					"pos": Vector3(0, 0, 10),
					"rot": Vector3.ZERO,
					"ts": 2000,
					"custom_id": 0,
				}
			]
		)
	)

	# Act
	session.on_client_snapshot(10, pkt1, 2000)

	# Assert
	var entity = session.get_registry()[10]
	assert_true(
		abs(entity["pos"].z - 6.0) < 0.05,
		"Speedhack gera clamp na capacidade maxima permitida",
	)

	assert_eq(sent_snapbacks.size(), 1, "Deve despachar pacote de correcao (snapback)")
	var snap_data = QNSerializer.decode_state_seq(sent_snapbacks[0].pkt)
	assert_true(abs(snap_data["pos"].z - 6.0) < 0.05, "Pacote reverso carrega posicao clampada")
	assert_eq(snap_data["custom_id"], 1, "Motivo do snapback = clamp (1)")


func test_snapshot_fora_do_mundo_gera_reject_e_kick() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession
	session.validator = autofree(QNServerValidator.new()) as QNServerValidator
	session.on_peer_authenticated(10)

	var sent_snapbacks := []
	session.snapback_requested.connect(
		func(id, pkt):
			sent_snapbacks.append({ "id": id, "pkt": pkt })
	)
	var rejections := []
	session.peer_rejected.connect(func(id, r, s):
			rejections.append(s))

	# Y = -100 (fora dos limites)
	var pkt := PackedByteArray([0, 0])
	pkt.append_array(
		QNSerializer.encode_state_history(
			[
				{
					"seq": 1,
					"pos": Vector3(0, -100, 0),
					"rot": Vector3.ZERO,
					"ts": 1000,
					"custom_id": 0,
				}
			]
		)
	)

	# Act
	session.on_client_snapshot(10, pkt, 1000)

	# Assert
	var entity = session.get_registry()[10]
	assert_eq(entity["pos"], Vector3.ZERO, "Reject nao altera a posicao da entidade")
	assert_eq(sent_snapbacks.size(), 1, "Deve despachar snapback forçando a voltar")
	var snap_data = QNSerializer.decode_state_seq(sent_snapbacks[0].pkt)
	assert_eq(snap_data["custom_id"], 2, "Motivo do snapback = reject (2)")
	assert_eq(rejections.size(), 1, "Deve propagar o reject com strikes")


func test_tick_broadcast_emite_array_de_estados() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession
	session.on_peer_authenticated(10)
	session.on_peer_authenticated(20)

	# Força has_state para entrar no broadcast sem depender de pacotes e validadores
	session.get_registry()[10]["has_state"] = true
	session.get_registry()[20]["has_state"] = true

	var sent_packets := []
	session.packet_ready.connect(
		func(id: int, pkt: PackedByteArray):
			sent_packets.append({ "id": id, "pkt": pkt })
	)

	# Act
	session.tick_broadcast(1000)

	# Assert
	assert_eq(sent_packets.size(), 2, "Deve emitir um pacote para cada peer")
