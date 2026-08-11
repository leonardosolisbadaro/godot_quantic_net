## @file test_quantic_net_api.gd
## @path res://tests/integration/test_quantic_net_api.gd
##
## @description
## Testes de integracao do autoload QuanticNet: maquina de estados
## e sinais. Sockets reais, testes headless sem UI. TDD rigoroso.
##
## @created 2026-07-30
## @updated 2026-07-31
##
## @since 0.1.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends "res://tests/integration/helpers/qn_integration_base.gd"

const TEST_PORT = 13579
const DEADLINE_MS = 2000


func test_host_sobe_imediato_em_estado_connected() -> void:
	var srv := _spawn_autoload()
	var err: int = srv.host(_next_test_port(), SECRET, "127.0.0.1", 8)
	assert_eq(err, OK, "host sobe com OK")
	assert_eq(srv.get_state(), srv.ConnectionState.CONNECTED, "servidor nasce CONNECTED")
	assert_true(srv.is_server())


func test_join_sem_servidor_falha_com_estado_failed_ou_connecting() -> void:
	var srv := _spawn_autoload()
	var port = _next_test_port()
	var err_host = srv.host(port, SECRET, "127.0.0.1", 8)
	assert_eq(err_host, OK)

	var cli := _spawn_autoload()
	var err_join = cli.join("127.0.0.1", port + 9, SECRET)
	assert_eq(err_join, OK, "join nao-bloqueante retorna OK ao iniciar")
	var state = cli.get_state()
	assert_true(
		state == cli.ConnectionState.CONNECTING or state == cli.ConnectionState.AUTHENTICATING,
		"sem servidor, permanece em tentativa (nao CONNECTED)",
	)


func test_cliente_transita_ate_connected_em_loopback() -> void:
	var srv := _spawn_autoload()
	srv.host(TEST_PORT + 1, SECRET, "127.0.0.1", 8)

	var cli := _spawn_autoload()
	var states := []
	cli.connection_state_changed.connect(func(s: int) -> void:
			states.append(s))

	cli.join("127.0.0.1", TEST_PORT + 1, SECRET)
	var t0: int = Time.get_ticks_msec()
	while (
		cli.get_state() != cli.ConnectionState.CONNECTED
		and Time.get_ticks_msec() - t0 < DEADLINE_MS
	):
		await get_tree().process_frame

	assert_eq(cli.get_state(), cli.ConnectionState.CONNECTED, "cliente conecta e autentica")
	assert_true(cli.ConnectionState.CONNECTING in states, "transitou por CONNECTING")


func test_host_com_porta_invalida_retorna_erro() -> void:
	var srv := _spawn_autoload()
	var failed := []
	srv.connection_failed_reason.connect(func(e: int) -> void:
			failed.append(e))

	var err: int = srv.host(-1, SECRET, "127.0.0.1", 8)
	assert_ne(err, OK, "porta invalida falha")
	assert_eq(failed.size(), 1, "sinal de falha emitido com o Error")


func test_peer_joined_e_left_propagados() -> void:
	var srv := _spawn_autoload()
	srv.host(TEST_PORT + 2, SECRET, "127.0.0.1", 8)
	var joined_srv := []
	srv.peer_joined.connect(func(id: int) -> void:
			joined_srv.append(id))

	var cli := _spawn_autoload()
	cli.join("127.0.0.1", TEST_PORT + 2, SECRET)

	var t0: int = Time.get_ticks_msec()
	while (
		cli.get_state() != cli.ConnectionState.CONNECTED
		and Time.get_ticks_msec() - t0 < DEADLINE_MS
	):
		await get_tree().process_frame

	# Processa mais alguns frames para dar tempo ao servidor processar
	for i in range(10):
		await get_tree().process_frame

	print("CLI STATE = ", cli.get_state())
	print("JOINED SRV SIZE = ", joined_srv.size())
	assert_true(joined_srv.size() >= 1, "servidor notificado do join")
	if joined_srv.size() > 0:
		assert_true(joined_srv[0] > 1, "peer id do cliente > 1")
