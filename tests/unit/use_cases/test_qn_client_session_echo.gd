## @file test_qn_client_session_echo.gd
## @path res://tests/unit/use_cases/test_qn_client_session_echo.gd
##
## @description
## Testes do echo autoritativo: clock-sync NTP de 3 argumentos via
## lookup de sent_ts, drain de inputs confirmados e sinal pong_received.
## Metodologia AAA sobre bitwes/Gut; transporte fake (memoria) injetado;
## relogio deterministico; sem socket, sem SceneTree de rede.
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badar� (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest




var _sent: Array

func _new_session(my_id := 2) -> RefCounted:
	_sent = []
	var sess: RefCounted = QNClientSession.new()
	sess.init(func(to: int, data: PackedByteArray, ch: int, mode: int) -> void:
		_sent.append({}))
	sess.set_local_id(my_id)
	return sess

func _echo_pkt(owner: int, seq: int, server_ts: int) -> PackedByteArray:
	var pkt := PackedByteArray([1]) # 1 = TYPE_STATE
	pkt.resize(5)
	pkt.encode_u32(1, owner)
	pkt.append_array(QNSerializer.encode_state_seq(seq, Vector3.ZERO, Vector3.ZERO, server_ts, 0))
	return pkt

func test_echo_proprio_sincroniza_clock_com_sent_ts() -> void:
	# Arrange: cliente enviou seq=1 em t=1000 (RTT simulado 80ms, offset 500)
	var sess := _new_session()
	sess.record_input(1, Vector2.ONE, 0.0, 0.05, 1000)
	var pongs := []
	sess.pong_received.connect(func(rtt: float, off: float) -> void: pongs.append(rtt))
	# Act: servidor recarimba ts=1540 (1000 + 500 offset + 40 metade RTT); cliente recebe em 1080
	sess.handle_packet(_echo_pkt(2, 1, 1540), 1080)
	# Assert: rtt = 1080-1000 = 80; offset = 1540 - (1000+40) = 500
	assert_true(sess.is_clock_synced(), "clock sincronizado pelo echo")
	assert_almost_eq(sess.clock_rtt(), 80.0, 0.1, "RTT derivado do sent_ts")
	assert_almost_eq(sess.clock_offset(), 500.0, 0.1, "offset NTP de 3 argumentos")
	assert_eq(pongs.size(), 1, "sinal pong_received emitido")

func test_echo_confirma_inputs_ate_o_seq() -> void:
	# Arrange: 3 inputs pendentes
	var sess := _new_session()
	for i: int in 3:
		sess.record_input(i + 1, Vector2.ONE, 0.0, 0.05, 1000 + i * 50)
	# Act: servidor confirma ate seq=2
	sess.handle_packet(_echo_pkt(2, 2, 1600), 1200)
	# Assert: sobra apenas o seq=3
	assert_eq(sess.pending_inputs(), 1, "drain remove confirmados")

func test_echo_de_outro_owner_nao_toca_clock_nem_inputs() -> void:
	# Arrange
	var sess := _new_session()
	sess.record_input(1, Vector2.ONE, 0.0, 0.05, 1000)
	# Act: estado de OUTRO peer (owner=3)
	sess.handle_packet(_echo_pkt(3, 9, 1600), 1200)
	# Assert
	assert_false(sess.is_clock_synced(), "clock nao sincroniza com echo alheio")
	assert_eq(sess.pending_inputs(), 1, "inputs preservados")
