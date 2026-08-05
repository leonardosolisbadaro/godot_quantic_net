#ifndef QN_DTLS_BOOTSTRAP_H
#define QN_DTLS_BOOTSTRAP_H

#include <godot_cpp/core/object.hpp>
#include <godot_cpp/classes/e_net_connection.hpp>
#include <godot_cpp/classes/x509_certificate.hpp>
#include <godot_cpp/classes/crypto_key.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>

namespace godot {

class QNDTLSBootstrap : public Object {
	GDCLASS(QNDTLSBootstrap, Object)

protected:
	static void _bind_methods();

public:
	static const char* PROD_CERT_PATH;
	static const char* PROD_KEY_PATH;
	static const char* DEV_CERT_PATH;
	static const char* DEV_KEY_PATH;
	static const char* CERT_HOSTNAME;

	static String normalize_bind_ip(const String &bind_ip);
	static Dictionary load_or_create_server_credentials();
	static Ref<X509Certificate> load_client_certificate();

	static Ref<ENetConnection> host(int port, const String &bind_ip = "*", int max_peers = 32, Array err_out = Array());
	static Ref<ENetConnection> join(const String &ip, int port, const String &hostname = "quanticnet", Array err_out = Array());

private:
	static void _set_err(Array &err_out, Error err);
};

} // namespace godot

#endif // QN_DTLS_BOOTSTRAP_H
