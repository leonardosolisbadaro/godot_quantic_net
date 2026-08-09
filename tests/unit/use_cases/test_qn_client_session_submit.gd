## @file test_qn_client_session_submit.gd
## @path res://tests/unit/use_cases/test_qn_client_session_submit.gd
##
## @description
## Testes de envio do QNClientSession: rate-limit de 20Hz, seq
## crescente, pacote no formato do protocolo e registro de inputs.
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
	sess.init(
		func(to: int, data: PackedByteArray, ch: int, mode: int) -> void:
			_sent.append({ "to": to, "data": data, "ch": ch, "mode": mode })
	)
	sess.set_local_id(my_id)
	return sess


func test_rate_limit_so_envia_apos_intervalo() -> void:
	# Arrange
	var sess := _new_session()
	# Act: dois submits com dt pequeno (abaixo de 50ms acumulado)
	var first: bool = sess.submit_state(Vector3.ONE, Vector3.ZERO, 0, 0.02, 1000)
	var second: bool = sess.submit_state(Vector3.ONE, Vector3.ZERO, 0, 0.02, 1020)
	# Assert: nenhum pacote ainda
	assert_false(first, "dt=0.02 abaixo do intervalo")
	assert_false(second, "acumulado 0.04 ainda abaixo de 0.05")
	assert_eq(_sent.size(), 0)


func test_envia_quando_acumulado_atinge_50ms() -> void:
	# Arrange
	var sess := _new_session()
	# Act
	sess.submit_state(Vector3.ONE, Vector3.ZERO, 0, 0.02, 1000)
	sess.submit_state(Vector3.ONE, Vector3.ZERO, 0, 0.02, 1020)
	var third: bool = sess.submit_state(Vector3(2, 0, 0), Vector3.ZERO, 0, 0.02, 1040)
	# Assert: terceiro submit (acumulado 0.06) dispara 1 pacote
	assert_true(third, "acumulado >= 0.05 envia")
	assert_eq(_sent.size(), 1)
	assert_eq(_sent[0]["to"], 1, "enviado ao servidor (peer 1)")
	assert_eq(_sent[0]["ch"], 1, "canal de estado")


func test_pacote_tem_formato_do_protocolo_com_seq_crescente() -> void:
	# Arrange
	var sess := _new_session()
	# Act: dois envios completos
	for i: int in 2:
		for j: int in 3:
			sess.submit_state(Vector3(i, 0, 0), Vector3.ZERO, 0, 0.02, 1000 + (i * 3 + j) * 20)
	# Assert: seq 1 e 2, tipo STATE, posicao quantizada
	assert_eq(_sent.size(), 2)
	assert_eq(_sent[0]["data"].decode_u8(0), 1) # TYPE_STATE
	var hist1: Array = QNSerializer.decode_state_history(_sent[0]["data"].slice(3))
	var hist2: Array = QNSerializer.decode_state_history(_sent[1]["data"].slice(3))
	assert_eq(hist1[0]["seq"], 1, "primeiro envio seq=1")
	assert_eq(hist2[0]["seq"], 2, "segundo envio seq=2")


func test_submit_sem_id_valido_nao_envia() -> void:
	# Arrange: id ainda nao atribuido (0)
	var sess := _new_session(0)
	# Act
	var ok: bool = sess.submit_state(Vector3.ONE, Vector3.ZERO, 0, 0.06, 1000)
	# Assert
	assert_false(ok, "sem id de rede, nao transmite")
	assert_eq(_sent.size(), 0)


func test_record_input_alimenta_buffer_pendente() -> void:
	# Arrange
	var sess := _new_session()
	# Act
	sess.record_input(1, Vector2.ONE, 0.0, 0.05, 1000)
	sess.record_input(2, Vector2.ZERO, 0.0, 0.05, 1050)
	# Assert
	assert_eq(sess.pending_inputs(), 2, "dois inputs pendentes de confirmacao")
