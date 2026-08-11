## @file test_qn_client_session_snapback.gd
## @path res://tests/unit/use_cases/test_qn_client_session_snapback.gd
##
## @description
## Testes de snapback: estado autoritativo reescrito, inputs drenados
## e lista de replay entregue ao jogo com seq e reason corretos.
## Metodologia AAA sobre bitwes/Gut; transporte fake (memoria) injetado;
## relogio deterministico; sem socket, sem SceneTree de rede.
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badar� (Gemini 3.1 Pro - High)

extends GutTest

var _sent: Array


func _new_session(my_id := 2) -> RefCounted:
	_sent = []
	var sess: RefCounted = QNClientSession.new()
	sess.init(func(to: int, data: PackedByteArray, ch: int, mode: int) -> void:
			_sent.append({ }))
	sess.set_local_id(my_id)
	return sess


func _snapback_pkt(seq: int, pos: Vector3, reason: int) -> PackedByteArray:
	var pkt := PackedByteArray([QNSerializer.TYPE_SNAPBACK]) # 2 = TYPE_SNAPBACK
	pkt.append_array(QNSerializer.encode_snapback(seq, pos, Vector3.ZERO, 2000, reason))
	return pkt


func test_snapback_reescreve_estado_local_e_drena() -> void:
	# Arrange: 4 inputs pendentes (seq 1..4)
	var sess := _new_session()
	for i: int in 4:
		sess.record_input(i + 1, Vector2.ONE, 0.0, 0.05, 1000 + i * 50)
	sess.local_pos = Vector3(99, 0, 99)
	var events := []
	sess.snapback_received.connect(
		func(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
			events.append({ "seq": seq, "reason": reason, "replay": replay.size() })
	)
	# Act: servidor corrige para origem, confirmando ate seq=2
	sess.handle_packet(_snapback_pkt(2, Vector3.ZERO, 2), 1500)
	# Assert
	assert_true(sess.local_pos.distance_to(Vector3.ZERO) < 0.01, "posicao local reescrita pela autoridade")
	assert_eq(sess.pending_inputs(), 2, "seqs 3,4 seguem pendentes")
	assert_eq(events.size(), 1, "sinal emitido")
	assert_eq(events[0]["seq"], 2)
	assert_eq(events[0]["reason"], 2, "reason reject")
	assert_eq(events[0]["replay"], 2, "2 inputs devolvidos para replay")


func test_replay_preserva_ordem_e_dados_dos_inputs() -> void:
	# Arrange
	var sess := _new_session()
	sess.record_input(5, Vector2(1, 0), 0.1, 0.05, 1000)
	sess.record_input(6, Vector2(0, -1), 0.2, 0.05, 1050)
	var captured := []
	sess.snapback_received.connect(
		func(seq: int, pos: Vector3, rot: Vector3, reason: int, replay: Array) -> void:
			captured.assign(replay)
	)
	# Act: confirma ate seq=4 (anterior aos dois)
	sess.handle_packet(_snapback_pkt(4, Vector3.ZERO, 1), 1500)
	# Assert: replay vem na ordem de gravacao, com move/dt intactos
	assert_eq(captured.size(), 2)
	assert_eq(captured[0]["seq"], 5, "ordem cronologica")
	assert_eq(captured[0]["move"], Vector2(1, 0), "dados do input preservados")
	assert_eq(captured[1]["rot_delta"], 0.2)


func test_snapback_corrompido_ignorado() -> void:
	# Arrange
	var sess := _new_session()
	sess.local_pos = Vector3(5, 0, 5)
	# Act
	sess.handle_packet(PackedByteArray([QNSerializer.TYPE_SNAPBACK, 1]), 1500) # TYPE_SNAPBACK
	# Assert
	assert_eq(sess.local_pos, Vector3(5, 0, 5), "estado local intocado")
