## @file test_qn_host_session.gd
## @path res://tests/unit/use_cases/test_qn_host_session.gd
##
## @description
## Testes unitários para QNHostSession, responsável pela orquestração autoritativa.
##
## @created 2026-07-30
## @updated 2026-07-30
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNHostSession = preload("res://addons/quantic_net/src/use_cases/qn_host_session.gd")
const QNSerializer = preload("res://addons/quantic_net/src/domain/qn_serializer.gd")
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
	assert_eq(entity.id, 42)
	assert_eq(entity.pos, Vector3.ZERO)
	assert_eq(entity.rot, Vector3.ZERO)
	assert_eq(entity.profile, "MMO")

func test_snapshot_valido_aceito_e_atualiza_registry() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession
	session.validator = autofree(QNServerValidator.new()) as QNServerValidator
	session.on_peer_authenticated(10)
	var pos := Vector3(1, 0, 1)
	var pkt := QNSerializer.encode_state_seq(10, pos, Vector3.ZERO, 1000, 0)
	
	# Act
	session.on_client_snapshot(10, pkt, 1000)
	
	# Assert
	var entity = session.get_registry()[10]
	assert_true(entity.pos.distance_to(pos) < 0.05, "Posicao legitima deve atualizar a entidade")

func test_snapshot_com_speedhack_gera_clamp_e_snapback() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession
	session.validator = autofree(QNServerValidator.new()) as QNServerValidator
	session.on_peer_authenticated(10)
	
	# Snapshot inicial
	var pkt0 := QNSerializer.encode_state_seq(1, Vector3.ZERO, Vector3.ZERO, 1000, 0)
	session.on_client_snapshot(10, pkt0, 1000)
	
	var sent_snapbacks := []
	session.snapback_requested.connect(func(id, pkt): sent_snapbacks.append({"id": id, "pkt": pkt}))
	
	# Speedhack (10 metros em 1 segundo - max speed = 6)
	var pkt1 := QNSerializer.encode_state_seq(2, Vector3(0, 0, 10), Vector3.ZERO, 2000, 0)
	
	# Act
	session.on_client_snapshot(10, pkt1, 2000)
	
	# Assert
	var entity = session.get_registry()[10]
	assert_true(abs(entity.pos.z - 6.0) < 0.05, "Speedhack gera clamp na capacidade maxima permitida")
	
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
	session.snapback_requested.connect(func(id, pkt): sent_snapbacks.append({"id": id, "pkt": pkt}))
	var rejections := []
	session.peer_rejected.connect(func(id, r, s): rejections.append(s))
	
	# Y = -100 (fora dos limites)
	var pkt := QNSerializer.encode_state_seq(1, Vector3(0, -100, 0), Vector3.ZERO, 1000, 0)
	
	# Act
	session.on_client_snapshot(10, pkt, 1000)
	
	# Assert
	var entity = session.get_registry()[10]
	assert_eq(entity.pos, Vector3.ZERO, "Reject nao altera a posicao da entidade")
	assert_eq(sent_snapbacks.size(), 1, "Deve despachar snapback forçando a voltar")
	var snap_data = QNSerializer.decode_state_seq(sent_snapbacks[0].pkt)
	assert_eq(snap_data["custom_id"], 2, "Motivo do snapback = reject (2)")
	assert_eq(rejections.size(), 1, "Deve propagar o reject com strikes")

func test_tick_broadcast_emite_array_de_estados() -> void:
	# Arrange
	var session := autofree(QNHostSession.new()) as QNHostSession
	session.on_peer_authenticated(10)
	session.on_peer_authenticated(20)
	
	var broadcasted := []
	session.broadcast_ready.connect(func(arr): broadcasted.append(arr))
	
	# Act
	session.tick_broadcast(1000)
	
	# Assert
	assert_eq(broadcasted.size(), 1, "Deve emitir uma vez por tick")
	assert_eq(broadcasted[0].size(), 2, "Array deve conter o estado de todos os 2 peers")
	assert_true(broadcasted[0][0].has("id"), "Os itens do array tem propriedades de estado")

