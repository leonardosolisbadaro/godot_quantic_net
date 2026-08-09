## @file test_qn_dtls_bootstrap_handshake.gd
## @path res://tests/integration/test_qn_dtls_bootstrap_handshake.gd
##
## @description
## Testes de handshake DTLS real em loopback: host + client com polling
## e deadline; caminho feliz conecta; cert errado e' rejeitado no pinning.
## Teste de INTEGRACAO (sockets reais em loopback): handshake DTLS entre
## host e client na mesma maquina. Primeira suite do repo a usar rede real
## e await de frames; deadline generoso para evitar flakiness em CI.
##
## @created 2026-07-29
## @updated 2026-07-30
##
## @since 0.1.0
## @lastModifiedIn 0.2.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest



const TEST_PORT := 47901
const HANDSHAKE_DEADLINE_MS := 3000

## Helper: bombeia service() nas duas pontas ate a condicao ou o deadline.
func _pump_until(host: ENetConnection, client: ENetConnection, deadline_ms: int) -> bool:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < deadline_ms:
		host.service()
		client.service()
		await get_tree().process_frame
	return true

func test_handshake_host_client_conecta_em_loopback() -> void:
	# Arrange: sobe host com cert dev e client com pinning do mesmo cert
	_cleanup_dev_certs()
	var err_h := [OK]
	var err_c := [OK]
	var host: ENetConnection = QNDTLSBootstrap.host(TEST_PORT, "127.0.0.1", 8, err_h)
	assert_not_null(host, "host DTLS sobe (err=%d)" % err_h[0])
	var client: ENetConnection = QNDTLSBootstrap.join("127.0.0.1", TEST_PORT, "quanticnet", err_c)
	assert_not_null(client, "client DTLS criado (err=%d)" % err_c[0])
	# Act: bombeia ate o client reportar conectado (ou deadline)
	var t0: int = Time.get_ticks_msec()
	var connected := false
	while Time.get_ticks_msec() - t0 < HANDSHAKE_DEADLINE_MS:
		host.service()
		client.service()
		var peers = client.get_peers()
		if peers.size() > 0 and peers[0].get_state() == ENetPacketPeer.STATE_CONNECTED:
			connected = true
			break
		await get_tree().process_frame
	# Assert
	assert_true(connected, "handshake DTLS completo em loopback dentro do deadline")
	# Cleanup
	client.destroy()
	host.destroy()

func test_client_com_cert_errado_nao_completa_handshake() -> void:
	# Arrange: host com cert A; client forja um cert B (autoassinado distinto)
	_cleanup_dev_certs()
	var host: ENetConnection = QNDTLSBootstrap.host(TEST_PORT + 1, "127.0.0.1", 8, [OK])
	var crypto := Crypto.new()
	var wrong_key: CryptoKey = crypto.generate_rsa(2048)
	var wrong_cert: X509Certificate = crypto.generate_self_signed_certificate(
		wrong_key, "CN=quanticnet,O=Atacante,C=XX")
	var client := ENetConnection.new()
	client.create_host(1, 1, 0, 0)
	client.dtls_client_setup("quanticnet", TLSOptions.client(wrong_cert))
	client.connect_to_host("127.0.0.1", TEST_PORT + 1)
	# Act: bombeia pelo deadline inteiro
	var t0: int = Time.get_ticks_msec()
	var connected := false
	while Time.get_ticks_msec() - t0 < HANDSHAKE_DEADLINE_MS:
		host.service()
		client.service()
		var peers = client.get_peers()
		if peers.size() > 0 and peers[0].get_state() == ENetPacketPeer.STATE_CONNECTED:
			connected = true
			break
		await get_tree().process_frame
	# Assert: pinning rejeita — nunca conecta
	assert_false(connected, "cert que nao bate com o pinning e' rejeitado no handshake")
	# Limpa erros de engine esperados neste teste (TLS handshake fail)
	for err in gut.error_tracker.get_current_test_errors():
		err.handled = true
	# Cleanup
	client.destroy()
	host.destroy()

func test_host_com_porta_invalida_retorna_erro() -> void:
	# Arrange + Act: porta fora do range valido
	var err_out := [OK]
	var enet: ENetConnection = QNDTLSBootstrap.host(-1, "127.0.0.1", 8, err_out)
	# Assert
	assert_null(enet, "porta invalida nao sobe host")
	assert_ne(err_out[0], OK, "erro de bind propagado")

func _cleanup_dev_certs() -> void:
	for p in ["user://qnet_cert.crt", "user://qnet_cert.key"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
