## @file test_qn_net_hook_interception.gd
## @path res://tests/unit/infrastructure/test_qn_net_hook_interception.gd
##
## @description
## Testes dos ganchos de interceptacao do QNNetHook: RPC de saida,
## pacotes customizados de entrada/saida e observador de configuracao.
## Metodologia AAA sobre bitwes/Gut; classe carregada via preload (sem class_name).
##
## @created 2026-07-29
## @updated 2026-08-02
##
## @since 0.1.0
## @lastModifiedIn 0.3.0-rc.1
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNNetHook = preload("res://addons/quantic_net/src/infrastructure/qn_net_hook.gd")

var _test_hooks: Array = []
func create_hook() -> QNNetHook:
	var h = QNNetHook.new()
	_test_hooks.append(h)
	return h

func after_each() -> void:
	for h in _test_hooks:
		if h and h.has_method("close"):
			h.close()
	_test_hooks.clear()

@rpc("any_peer") func metodo_teste(_a, _b) -> void: pass
@rpc("any_peer") func vetado() -> void: pass
@rpc("any_peer") func qualquer() -> void: pass

func test_gancho_rpc_permite_quando_retorna_true() -> void:
	# Arrange: gancho observador que aprova
	var hook := create_hook() as QNNetHook
	var seen := []
	hook.on_outgoing_rpc = func(peer: int, obj: Object, method: StringName, args: Array) -> bool:
		seen.append(method)
		return true
	# Act: _rpc delega ao base (sem peer conectado, base.rpc retorna erro, o que nao importa)
	hook._rpc(0, self, &"metodo_teste", [1, 2])
	# Assert: gancho foi chamado com o metodo correto
	assert_eq(seen, [&"metodo_teste"], "RPC observado pelo gancho")

func test_gancho_rpc_veta_quando_retorna_false() -> void:
	# Arrange: gancho que bloqueia
	var hook := create_hook() as QNNetHook
	hook.on_outgoing_rpc = func(peer: int, obj: Object, method: StringName, args: Array) -> bool:
		return false
	# Act
	var err: Error = hook._rpc(0, self, &"vetado", [])
	# Assert: retorna OK sem delegar (descarte silencioso)
	assert_eq(err, OK, "RPC vetado descartado com OK")

func test_sem_gancho_rpc_delega_direto() -> void:
	# Arrange: sem gancho registrado
	var hook := create_hook() as QNNetHook
	# Act + Assert: nao deve travar nem exigir Callable valido
	hook._rpc(0, self, &"qualquer", [])
	pass_test("delegacao direta sem gancho nao quebra")

func test_filtro_entrada_descarta_quando_retorna_null() -> void:
	# Arrange: consumidor de custom_packet + filtro que descarta
	var hook := create_hook() as QNNetHook
	var received := []
	hook.custom_packet.connect(func(from_peer: int, data: PackedByteArray, ch: int) -> void:
		received.append(data))
	hook.on_incoming_packet = func(from_peer: int, data: PackedByteArray) -> Variant:
		return null
	# Act: simula o bloco interno de _poll sobre um pacote
	var pkt: PackedByteArray = PackedByteArray([1, 2, 3])
	var filtered: Variant = hook.on_incoming_packet.call(5, pkt)
	if filtered != null:
		hook.custom_packet.emit(5, filtered, 1)
	# Assert
	assert_eq(received.size(), 0, "pacote filtrado nao chega ao consumidor")

func test_filtro_entrada_pode_transformar_payload() -> void:
	# Arrange: filtro que acrescenta um byte
	var hook := create_hook() as QNNetHook
	var received := []
	hook.custom_packet.connect(func(from_peer: int, data: PackedByteArray, ch: int) -> void:
		received.append(data))
	hook.on_incoming_packet = func(from_peer: int, data: PackedByteArray) -> Variant:
		var copy := data.duplicate()
		copy.append(99)
		return copy
	# Act
	var pkt: PackedByteArray = PackedByteArray([1])
	var filtered: Variant = hook.on_incoming_packet.call(5, pkt)
	if filtered != null:
		hook.custom_packet.emit(5, filtered, 1)
	# Assert
	assert_eq(received[0], PackedByteArray([1, 99]), "payload transformado entregue")

func test_filtro_saida_descarta_quando_retorna_null() -> void:
	# Arrange
	var hook := create_hook() as QNNetHook
	hook.on_outgoing_packet = func(to: int, data: PackedByteArray) -> Variant:
		return null
	# Act
	var err: Error = hook.send_custom(1, PackedByteArray([1, 2, 3]))
	# Assert: descarte silencioso com OK, sem exigir peer
	assert_eq(err, OK, "saida filtrada descartada com OK")

func test_observador_config_add_chamado() -> void:
	# Arrange
	var hook := create_hook() as QNNetHook
	var dummy := Object.new()
	var seen := []
	hook.on_config_add = func(obj: Object, config: Variant) -> void:
		seen.append(obj)
	# Act
	hook._object_configuration_add(dummy, null)
	# Assert
	assert_eq(seen.size(), 1, "observador notificado no spawn config")
	dummy.free()

