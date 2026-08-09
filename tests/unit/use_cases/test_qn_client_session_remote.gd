## @file test_qn_client_session_remote.gd
## @path res://tests/unit/use_cases/test_qn_client_session_remote.gd
##
## @description
## Testes de peers remotos: interp buffer alimentado, loss tracker
## por seq, remote_state interpolado e loss_of.
## Metodologia AAA sobre bitwes/Gut; transporte fake (memoria) injetado;
## relogio deterministico; sem socket, sem SceneTree de rede.
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

var _sent: Array


func _new_session(my_id := 2) -> RefCounted:
	_sent = []
	var sess: RefCounted = QNClientSession.new()
	sess.init(func(to: int, data: PackedByteArray, ch: int, mode: int) -> void:
			_sent.append({ }))
	sess.set_local_id(my_id)
	return sess


func _state_from(owner: int, seq: int, pos: Vector3, ts: int) -> PackedByteArray:
	var pkt := PackedByteArray([1]) # 1 = TYPE_STATE
	pkt.resize(5)
	pkt.encode_u32(1, owner)
	pkt.append_array(QNSerializer.encode_state_seq(seq, pos, Vector3.ZERO, ts, 0))
	return pkt


func _snapshot_from(seq: int) -> PackedByteArray:
	var buf = QNBitBuffer.new()
	buf.write_bits(seq, 16)
	buf.write_bits(0, 16) # ack
	buf.write_bits(1000, 32) # server_now
	buf.write_bits(0, 8) # num_entities
	var pkt = PackedByteArray([4]) # TYPE_SNAPSHOT
	pkt.append_array(buf.get_buffer())
	return pkt


func test_estado_remoto_alimenta_interp_e_sinal() -> void:
	# Arrange
	var sess := _new_session()
	var received := []
	sess.remote_state_received.connect(
		func(owner: int, pos: Vector3, rot: Vector3, custom: int) -> void:
			received.append({ "owner": owner, "pos": pos })
	)
	# Act: dois snapshots do peer 3
	sess.handle_packet(_state_from(3, 1, Vector3.ZERO, 1000), 1100)
	sess.handle_packet(_state_from(3, 2, Vector3(1, 0, 0), 1100), 1200)
	# Assert
	assert_eq(received.size(), 2, "sinal por snapshot remoto")
	assert_eq(received[0]["owner"], 3)


func test_remote_state_interpola_entre_snapshots() -> void:
	# Arrange: sincroniza o clock primeiro (offset 0 para simplificar)
	var sess := _new_session()
	sess.record_input(1, Vector2.ZERO, 0.0, 0.05, 0)
	sess.handle_packet(_state_from(2, 1, Vector3.ZERO, 20), 40)
	# Dois snapshots do peer 3 em t=1000 e t=1100
	sess.handle_packet(_state_from(3, 1, Vector3.ZERO, 1000), 1000)
	sess.handle_packet(_state_from(3, 2, Vector3(2, 0, 0), 1100), 1100)
	# Act: amostra no meio do intervalo + render delay (60ms)
	var s: Dictionary = sess.remote_state(3, 1000 + 50 + 60)
	# Assert: posicao interpolada ~x=1
	assert_false(s.is_empty(), "ha estado interpolado")
	assert_almost_eq(s["pos"].x, 1.0, 0.2, "lerp no meio do caminho")


func test_remote_state_desconhecido_retorna_vazio() -> void:
	# Arrange
	var sess := _new_session()
	# Act + Assert
	assert_eq(sess.remote_state(99, 1000), { }, "peer desconhecido sem estado")


func test_loss_tracker_conta_gap_do_peer() -> void:
	# Arrange
	var sess := _new_session()
	# Act: seq 1, depois seq 5 (3 perdidos)
	sess.handle_packet(_snapshot_from(1), 1000)
	sess.handle_packet(_snapshot_from(5), 1200)
	# Assert: 3 perdidos em 5 => 60%
	assert_almost_eq(sess.loss_of(3), 60.0, 0.1, "gaps de seq viram perda")


func test_pacote_corrompido_ignorado() -> void:
	# Arrange
	var sess := _new_session()
	# Act
	sess.handle_packet(PackedByteArray([1, 2]), 1000)
	# Assert
	assert_eq(sess.remote_state(0, 1000), { }, "nada registrado")
