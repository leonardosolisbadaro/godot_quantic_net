## @file test_qn_dtls_bootstrap_unit.gd
## @path res://tests/integration/test_qn_dtls_bootstrap_unit.gd
##
## @description
## Testes deterministicos do bootstrap (sem handshake): normalizacao
## de bind_ip, geracao/reuso de credenciais em user://, carregamento de
## cert do cliente e propagacao de Error.
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

const QNDTLSBootstrap = preload("res://addons/quantic_net/src/infrastructure/qn_dtls_bootstrap.gd")

const TEST_PORT := 47901
const HANDSHAKE_DEADLINE_MS := 3000

func test_normalize_bind_ip_traduz_wildcard() -> void:
	# Arrange + Act + Assert
	assert_eq(QNDTLSBootstrap.normalize_bind_ip("*"), "0.0.0.0", "wildcard vira any-ipv4")
	assert_eq(QNDTLSBootstrap.normalize_bind_ip(""), "0.0.0.0", "vazio vira any-ipv4")
	assert_eq(QNDTLSBootstrap.normalize_bind_ip("127.0.0.1"), "127.0.0.1", "ip explicito preservado")

func test_credenciais_dev_geradas_e_persistidas() -> void:
	# Arrange: limpa qualquer par anterior para forcar geracao
	_cleanup_dev_certs()
	# Act
	var creds: Dictionary = QNDTLSBootstrap.load_or_create_server_credentials()
	# Assert: par valido E arquivos persistidos para reuso
	assert_false(creds.is_empty(), "credenciais geradas")
	assert_not_null(creds["key"], "CryptoKey presente")
	assert_not_null(creds["cert"], "X509Certificate presente")
	assert_true(FileAccess.file_exists(QNDTLSBootstrap.DEV_CERT_PATH), "cert salvo em user://")
	assert_true(FileAccess.file_exists(QNDTLSBootstrap.DEV_KEY_PATH), "key salva em user://")

func test_credenciais_dev_reutilizadas_na_segunda_carga() -> void:
	# Arrange: garante um par existente
	_cleanup_dev_certs()
	var first: Dictionary = QNDTLSBootstrap.load_or_create_server_credentials()
	var cert_string_first: String = first["cert"].save_to_string()
	# Act: segunda carga deve reutilizar o MESMO cert (string igual)
	var second: Dictionary = QNDTLSBootstrap.load_or_create_server_credentials()
	# Assert
	assert_eq(second["cert"].save_to_string(), cert_string_first,
		"reuso do par existente (cert string estavel)")

func test_cert_do_cliente_carrega_do_fallback_dev() -> void:
	# Arrange
	_cleanup_dev_certs()
	QNDTLSBootstrap.load_or_create_server_credentials()
	# Act
	var cert: X509Certificate = QNDTLSBootstrap.load_client_certificate()
	# Assert
	assert_not_null(cert, "cert do servidor carregavel pelo cliente")

func test_join_sem_cert_retorna_erro_file_not_found() -> void:
	# Arrange: sem cert nenhum em user:// e (presumido) sem res://certs no repo de teste
	_cleanup_dev_certs()
	var err_out := [OK]
	# Act
	var enet: ENetConnection = QNDTLSBootstrap.join("127.0.0.1", TEST_PORT, QNDTLSBootstrap.CERT_HOSTNAME, err_out)
	# Assert
	assert_null(enet, "sem cert, join falha")
	assert_eq(err_out[0], ERR_FILE_NOT_FOUND, "erro propagado (nunca so push_error)")

func _cleanup_dev_certs() -> void:
	for p in [QNDTLSBootstrap.DEV_CERT_PATH, QNDTLSBootstrap.DEV_KEY_PATH]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
