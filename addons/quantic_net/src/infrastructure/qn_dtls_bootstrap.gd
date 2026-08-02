## @file qn_dtls_bootstrap.gd
## @path res://addons/quantic_net/src/infrastructure/qn_dtls_bootstrap.gd
##
## @description
## Bootstrap DTLS para host e client: geracao/reuso de par de chaves
## (dev em user://, producao em res://certs/), TLSOptions da 4.7.1,
## create_host_bound/create_client, propagacao de Error e pinning de cert.
## Camada: Infrastructure (acoplamento direto a APIs Godot permitido apenas aqui).
##
## @created 2026-07-29
## @updated 2026-07-30
##
## @since 0.1.0
## @lastModifiedIn 0.2.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

## Sobe a camada de transporte seguro. Nao conhece NetHook, sessoes ou
## protocolo do jogo: entrega uma ENetConnection configurada com DTLS,
## pronta para ser embrulhada pelo QNWirePeer. Erros retornam via Error;
## nunca apenas push_error.

## Certificado publico embutido no build do CLIENTE (producao).
const PROD_CERT_PATH := "res://certs/server.crt"
## Chave privada — SOMENTE no build do SERVIDOR (excluida do export cliente).
const PROD_KEY_PATH := "res://certs/server.key"
## Fallback de desenvolvimento (gerado na primeira execucao local).
const DEV_CERT_PATH := "user://qnet_cert.crt"
const DEV_KEY_PATH := "user://qnet_cert.key"
## CN do certificado dev e hostname verificado pelo client no pinning.
const CERT_HOSTNAME := "quanticnet"

## Normaliza o bind_ip da casca do autoload ("*") para o formato aceito
## pela create_host_bound na 4.7.1.
static func normalize_bind_ip(bind_ip: String) -> String:
	return "0.0.0.0" if bind_ip == "*" or bind_ip.is_empty() else bind_ip

## Garante um par (key, cert) para o servidor: producao (res://) tem
## prioridade; ausente, gera/reusa o par de desenvolvimento em user://.
## Retorna {"key": CryptoKey, "cert": X509Certificate} ou {} em falha.
static func load_or_create_server_credentials() -> Dictionary:
	if ResourceLoader.exists(PROD_KEY_PATH) and ResourceLoader.exists(PROD_CERT_PATH):
		var key := load(PROD_KEY_PATH) as CryptoKey
		var cert := load(PROD_CERT_PATH) as X509Certificate
		if key and cert:
			return {"key": key, "cert": cert}
	# dev: reusa se ja existir em user://
	if FileAccess.file_exists(DEV_CERT_PATH) and FileAccess.file_exists(DEV_KEY_PATH):
		var k := CryptoKey.new()
		var c := X509Certificate.new()
		if k.load(DEV_KEY_PATH) == OK and c.load(DEV_CERT_PATH) == OK:
			return {"key": k, "cert": c}
	# dev: gera par novo e persiste
	var crypto := Crypto.new()
	var key: CryptoKey = crypto.generate_rsa(2048)
	var cert: X509Certificate = crypto.generate_self_signed_certificate(
		key, "CN=%s,O=QuanticNet,C=BR" % CERT_HOSTNAME)
	if cert.save(DEV_CERT_PATH) != OK or key.save(DEV_KEY_PATH) != OK:
		return {}
	return {"key": key, "cert": cert}

## Carrega o certificado publico do servidor para o client fazer pinning.
## Producao: res://certs/server.crt (embutido no export). Dev: user://.
static func load_client_certificate() -> X509Certificate:
	var source: String = PROD_CERT_PATH if ResourceLoader.exists(PROD_CERT_PATH) else DEV_CERT_PATH
	if not FileAccess.file_exists(source):
		return null
	var cert := X509Certificate.new()
	if cert.load(source) != OK:
		return null
	return cert

## Sobe um servidor DTLS. Retorna a ENetConnection pronta ou null.
## Out-param opcional via Array de 1 posicao para expor o Error detalhado:
##   var err_out := [OK]
##   var enet := QNDTLSBootstrap.host(4242, "0.0.0.0", 32, err_out)
static func host(port: int, bind_ip: String = "*", max_peers: int = 32, err_out: Array = []) -> ENetConnection:
	if port < 0 or port > 65535:
		_set_err(err_out, ERR_INVALID_PARAMETER)
		return null
	var creds: Dictionary = load_or_create_server_credentials()
	if creds.is_empty():
		_set_err(err_out, ERR_CANT_CREATE)
		return null
	var enet := ENetConnection.new()
	var err: Error = enet.create_host_bound(normalize_bind_ip(bind_ip), port, max_peers)
	if err != OK:
		_set_err(err_out, err)
		return null
	enet.dtls_server_setup(TLSOptions.server(creds["key"], creds["cert"]))
	_set_err(err_out, OK)
	return enet

## Conecta um cliente DTLS com pinning do certificado do servidor.
## hostname: CN esperado do cert (default = CERT_HOSTNAME dev).
static func join(ip: String, port: int, hostname: String = CERT_HOSTNAME, err_out: Array = []) -> ENetConnection:
	var cert: X509Certificate = load_client_certificate()
	if cert == null:
		_set_err(err_out, ERR_FILE_NOT_FOUND)
		return null
	var enet := ENetConnection.new()
	var err: Error = enet.create_host(1, 1, 0, 0)
	if err != OK:
		_set_err(err_out, err)
		return null
	enet.dtls_client_setup(hostname, TLSOptions.client(cert))
	var peer = enet.connect_to_host(ip, port)
	if peer == null:
		_set_err(err_out, ERR_CANT_CONNECT)
		return null
	_set_err(err_out, OK)
	return enet

static func _set_err(err_out: Array, err: Error) -> void:
	if err_out.size() > 0:
		err_out[0] = err
