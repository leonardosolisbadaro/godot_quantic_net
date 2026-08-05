#include "qn_dtls_bootstrap.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/crypto.hpp>
#include <godot_cpp/classes/tls_options.hpp>

using namespace godot;

const char* QNDTLSBootstrap::PROD_CERT_PATH = "res://certs/server.crt";
const char* QNDTLSBootstrap::PROD_KEY_PATH = "res://certs/server.key";
const char* QNDTLSBootstrap::DEV_CERT_PATH = "user://qnet_cert.crt";
const char* QNDTLSBootstrap::DEV_KEY_PATH = "user://qnet_cert.key";
const char* QNDTLSBootstrap::CERT_HOSTNAME = "quanticnet";

void QNDTLSBootstrap::_bind_methods() {
	ClassDB::bind_static_method("QNDTLSBootstrap", D_METHOD("host", "port", "bind_ip", "max_peers", "err_out"), &QNDTLSBootstrap::host, DEFVAL("*"), DEFVAL(32), DEFVAL(Array()));
	ClassDB::bind_static_method("QNDTLSBootstrap", D_METHOD("join", "ip", "port", "hostname", "err_out"), &QNDTLSBootstrap::join, DEFVAL("quanticnet"), DEFVAL(Array()));
}

String QNDTLSBootstrap::normalize_bind_ip(const String &bind_ip) {
	return (bind_ip == "*" || bind_ip.is_empty()) ? "0.0.0.0" : bind_ip;
}

Dictionary QNDTLSBootstrap::load_or_create_server_credentials() {
	ResourceLoader *rl = ResourceLoader::get_singleton();
	if (rl->exists(PROD_KEY_PATH) && rl->exists(PROD_CERT_PATH)) {
		Ref<CryptoKey> key = rl->load(PROD_KEY_PATH);
		Ref<X509Certificate> cert = rl->load(PROD_CERT_PATH);
		if (key.is_valid() && cert.is_valid()) {
			Dictionary d;
			d["key"] = key;
			d["cert"] = cert;
			return d;
		}
	}
	
	if (FileAccess::file_exists(DEV_CERT_PATH) && FileAccess::file_exists(DEV_KEY_PATH)) {
		Ref<CryptoKey> k; k.instantiate();
		Ref<X509Certificate> c; c.instantiate();
		if (k->load(DEV_KEY_PATH) == OK && c->load(DEV_CERT_PATH) == OK) {
			Dictionary d;
			d["key"] = k;
			d["cert"] = c;
			return d;
		}
	}
	
	Ref<Crypto> crypto; crypto.instantiate();
	Ref<CryptoKey> key = crypto->generate_rsa(2048);
	Ref<X509Certificate> cert = crypto->generate_self_signed_certificate(key, String("CN=") + CERT_HOSTNAME + ",O=QuanticNet,C=BR");
	
	if (cert->save(DEV_CERT_PATH) != OK || key->save(DEV_KEY_PATH) != OK) {
		return Dictionary();
	}
	
	Dictionary d;
	d["key"] = key;
	d["cert"] = cert;
	return d;
}

Ref<X509Certificate> QNDTLSBootstrap::load_client_certificate() {
	ResourceLoader *rl = ResourceLoader::get_singleton();
	String source = rl->exists(PROD_CERT_PATH) ? PROD_CERT_PATH : DEV_CERT_PATH;
	
	if (!FileAccess::file_exists(source)) {
		return Ref<X509Certificate>();
	}
	
	Ref<X509Certificate> cert; cert.instantiate();
	if (cert->load(source) != OK) {
		return Ref<X509Certificate>();
	}
	
	return cert;
}

void QNDTLSBootstrap::_set_err(Array &err_out, Error err) {
	if (err_out.size() > 0) {
		err_out[0] = err;
	} else if (err_out.is_empty()) {
		err_out.push_back(err);
	}
}

Ref<ENetConnection> QNDTLSBootstrap::host(int port, const String &bind_ip, int max_peers, Array err_out) {
	if (port < 0 || port > 65535) {
		_set_err(err_out, ERR_INVALID_PARAMETER);
		return Ref<ENetConnection>();
	}
	
	Dictionary creds = load_or_create_server_credentials();
	if (creds.is_empty()) {
		_set_err(err_out, ERR_CANT_CREATE);
		return Ref<ENetConnection>();
	}
	
	Ref<ENetConnection> enet; enet.instantiate();
	Error err = enet->create_host_bound(normalize_bind_ip(bind_ip), port, max_peers);
	if (err != OK) {
		_set_err(err_out, err);
		return Ref<ENetConnection>();
	}
	
	Ref<TLSOptions> tls_opts = TLSOptions::server(creds["key"], creds["cert"]);
	enet->dtls_server_setup(tls_opts);
	_set_err(err_out, OK);
	return enet;
}

Ref<ENetConnection> QNDTLSBootstrap::join(const String &ip, int port, const String &hostname, Array err_out) {
	Ref<X509Certificate> cert = load_client_certificate();
	if (cert.is_null()) {
		_set_err(err_out, ERR_FILE_NOT_FOUND);
		return Ref<ENetConnection>();
	}
	
	Ref<ENetConnection> enet; enet.instantiate();
	Error err = enet->create_host(1, 1, 0, 0);
	if (err != OK) {
		_set_err(err_out, err);
		return Ref<ENetConnection>();
	}
	
	Ref<TLSOptions> tls_opts = TLSOptions::client(cert);
	enet->dtls_client_setup(hostname, tls_opts);
	
	Ref<ENetPacketPeer> peer = enet->connect_to_host(ip, port);
	if (peer.is_null()) {
		_set_err(err_out, ERR_CANT_CONNECT);
		return Ref<ENetConnection>();
	}
	
	_set_err(err_out, OK);
	return enet;
}
