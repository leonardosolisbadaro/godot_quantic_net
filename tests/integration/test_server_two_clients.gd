## @file test_server_two_clients.gd
## @path res://tests/integration/test_server_two_clients.gd
##
## @description
## Testes de integracao de rede real sob Netem (latencia, jitter e perdas).
## Simula conexao completa entre 1 Host e 2 Clientes em uma unica arvore.
## Avalia transmissao, validacao, tick server-side e coversao client-side.
##
## @created 2026-07-30
## @updated 2026-07-30
##
## @since 0.2.0
## @lastModifiedIn 0.2.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends "res://tests/integration/helpers/qn_integration_base.gd"

class _DummyValidator extends RefCounted:
	func validate(_p: int, pos: Vector3, rot: Vector3, _now: int) -> Dictionary:
		return {"action": "accept", "pos": pos, "rot": rot}

func test_integracao_dois_clientes_sob_netem_pesado() -> void:
	var port = _next_test_port()
	
	var srv := _spawn_autoload()
	var err_host = srv.host(port, SECRET, "127.0.0.1", 8)
	assert_eq(err_host, OK)
	srv._host_session.validator = _DummyValidator.new()
	
	var cli1 := _spawn_autoload()
	var err_join1 = cli1.join("127.0.0.1", port, SECRET)
	assert_eq(err_join1, OK)
	
	var cli2 := _spawn_autoload()
	var err_join2 = cli2.join("127.0.0.1", port, SECRET)
	assert_eq(err_join2, OK)
	cli2._wire._client_id = 3
	
	# Aguardar autenticação de ambos
	var elapsed := 0
	var dt = 0.016
	while elapsed < 3000:
		if cli1.get_state() == srv.ConnectionState.CONNECTED and cli2.get_state() == srv.ConnectionState.CONNECTED:
			break
		await wait_process_frames(1, "waiting handshake")
		elapsed += 16
		
	assert_eq(cli1.get_state(), srv.ConnectionState.CONNECTED, "cli1 autenticado")
	assert_eq(cli2.get_state(), srv.ConnectionState.CONNECTED, "cli2 autenticado")
	
	# Descobre os IDs
	var c1_id = cli1._hook.get_unique_id()
	var c2_id = cli2._hook.get_unique_id()
	
	# Ativa netem no srv (para drop e jitter afetando ambos os clients)
	# Vamos aplicar o netem de forma agressiva nos canais 0 e 1, com latencia de 60ms, jitter 25ms, perda 10%
	for peer in [srv, cli1, cli2]:
		if peer._wire:
			peer._wire.netem_latency_ms = 60
			peer._wire.netem_jitter_ms = 25
			peer._wire.netem_loss_pct = 0.1
			peer._wire.netem_enabled = true
	
	# Simulaçao 5s
	# A cada frame, os clients andam e submetem estado.
	var elapsed_sim := 0.0
	var duration := 5.0
	
	var pos_c1 = Vector3.ZERO
	var pos_c2 = Vector3.ZERO
	var speed = 1.5
	
	while elapsed_sim < duration:
		# movimento valido (aceito pelo validator)
		pos_c1.x += speed * dt
		pos_c2.z += speed * dt
		
		cli1.submit_state(pos_c1, Vector3.ZERO, 0, dt)
		cli2.submit_state(pos_c2, Vector3.ZERO, 0, dt)
		
		await wait_process_frames(1, "simulating netem")
		elapsed_sim += dt
	
	# Verificações oráculo
	# 1. Ambos os clients devem ter o clock sinwcronizado.
	assert_true(cli1.is_clock_synced(), "cli1 deve sincronizar o clock sob jitter")
	assert_true(cli2.is_clock_synced(), "cli2 deve sincronizar o clock sob jitter")
	
	var registry = srv.get_registry()
	var reg1 = registry.get(c1_id)
	var reg2 = registry.get(c2_id)
	assert_not_null(reg1, "host tem c1 no registry")
	assert_not_null(reg2, "host tem c2 no registry")
	
	if reg1 != null and reg2 != null:
		# Convergência: Host position vs Client position real
		var dist1 = pos_c1.distance_to(reg1.pos)
		var dist2 = pos_c2.distance_to(reg2.pos)
		
		# Pode haver lag de até ~300ms de roundtrip considerando os buffers e perdas
		# a 1.5m/s, 300ms é ~0.45m de erro. < 2.0m de erro é uma convergência segura.
		print("CLI1 EXPECTED: ", pos_c1, " SERVER: ", reg1.pos)
		assert_true(dist1 < 2.0, "cli1 no host converge para o esperado (dist=" + str(dist1) + ")")
		print("CLI2 EXPECTED: ", pos_c2, " SERVER: ", reg2.pos)
		assert_true(dist2 < 2.0, "cli2 no host converge para o esperado (dist=" + str(dist2) + ")")
	
	# 3. Relay do client2 no client1 (client prediction remote state)
	var cli1_ver_c2 = cli1.remote_state(c2_id)
	assert_not_null(cli1_ver_c2, "cli1 deve receber ticks globais do host com o estado de cli2")
	if cli1_ver_c2 != null and not cli1_ver_c2.is_empty():
		var dist_cli1_c2 = pos_c2.distance_to(cli1_ver_c2.pos)
		assert_true(dist_cli1_c2 < 2.0, "cli1 ve a posicao de c2 convergir remotamente (dist=" + str(dist_cli1_c2) + ")")
		
	# 4. Perda controlada (configurado: 10%, assert: < 35% por causa de reordenamentos agressivos)
	var loss1 = srv.loss_of(c1_id)
	var loss2 = srv.loss_of(c2_id)
	
	assert_true(loss1 >= 0 and loss1 <= 0.35, "perda medida de cli1 no host deve ficar <= 35% (" + str(loss1) + ")")
	assert_true(loss2 >= 0 and loss2 <= 0.35, "perda medida de cli2 no host deve ficar <= 35% (" + str(loss2) + ")")

func test_isolamento_netem_entre_dois_clientes() -> void:
	var port = _next_test_port()
	
	var srv := _spawn_autoload()
	srv.host(port, SECRET, "127.0.0.1", 8)
	srv._host_session.validator = _DummyValidator.new()
	
	var cli_lat := _spawn_autoload()
	cli_lat.join("127.0.0.1", port, SECRET)
	
	var cli_fast := _spawn_autoload()
	cli_fast.join("127.0.0.1", port, SECRET)
	cli_fast._wire._client_id = 3
	
	var elapsed := 0
	var dt = 0.016
	while elapsed < 3000:
		if cli_lat.get_state() == srv.ConnectionState.CONNECTED and cli_fast.get_state() == srv.ConnectionState.CONNECTED:
			break
		await wait_process_frames(1, "waiting handshake")
		elapsed += 16
		
	assert_eq(cli_lat.get_state(), srv.ConnectionState.CONNECTED)
	assert_eq(cli_fast.get_state(), srv.ConnectionState.CONNECTED)
	
	if cli_lat._wire:
		cli_lat._wire.netem_latency_ms = 200
		cli_lat._wire.netem_jitter_ms = 0
		cli_lat._wire.netem_loss_pct = 0.0
		cli_lat._wire.netem_enabled = true
	
	# Marcamos o tempo, damos tick no clock e esperamos PONG no client
	var t0 = Time.get_ticks_msec()
	
	# Damos um submit force em ambos com dt = 0.06 para forcar envio imediato
	cli_lat.submit_state(Vector3.ZERO, Vector3.ZERO, 0, 0.06)
	cli_fast.submit_state(Vector3.ZERO, Vector3.ZERO, 0, 0.06)
	
	# Espera PONG do cli_fast (rtt de loopback, < 50ms)
	var rtt_fast = -1
	var rtt_lat = -1
	elapsed = 0
	while elapsed < 2000:
		cli_lat.submit_state(Vector3.ZERO, Vector3.ZERO, 0, 0.016)
		cli_fast.submit_state(Vector3.ZERO, Vector3.ZERO, 0, 0.016)
		
		if cli_fast.is_clock_synced() and rtt_fast == -1:
			rtt_fast = Time.get_ticks_msec() - t0
		if cli_lat.is_clock_synced() and rtt_lat == -1:
			rtt_lat = Time.get_ticks_msec() - t0
		
		if rtt_fast != -1 and rtt_lat != -1:
			break
		
		await wait_process_frames(1, "waiting pongs")
		elapsed += 16
		
	assert_true(rtt_fast != -1, "fast recebeu pong")
	assert_true(rtt_lat != -1, "lat recebeu pong")
	
	if rtt_fast != -1 and rtt_lat != -1:
		assert_true(rtt_fast < 100, "cli_fast foi rapido (rtt=" + str(rtt_fast) + ")")
		assert_true(rtt_lat >= 150, "cli_lat demorou pelo netem local (rtt=" + str(rtt_lat) + ")")
