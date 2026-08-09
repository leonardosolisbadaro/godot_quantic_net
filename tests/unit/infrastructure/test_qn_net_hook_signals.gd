## @file test_qn_net_hook_signals.gd
## @path res://tests/unit/infrastructure/test_qn_net_hook_signals.gd
##
## @description
## Testes de reemissao de sinais do QNNetHook: os eventos do
## SceneMultiplayer encapsulado devem chegar ao consumidor do hook.
## Metodologia AAA sobre bitwes/Gut.
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest


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

func test_sinais_de_conexao_sao_reemitidos() -> void:
	# Arrange: hook e coletores de sinais
	var hook := create_hook() as QNNetHook
	var fired := []
	hook.connected_to_server.connect(func() -> void: fired.append("connected"))
	hook.connection_failed.connect(func() -> void: fired.append("failed"))
	hook.server_disconnected.connect(func() -> void: fired.append("disconnected"))
	# Act: emite os sinais correspondentes no SceneMultiplayer interno
	hook.get_base().connected_to_server.emit()
	hook.get_base().connection_failed.emit()
	hook.get_base().server_disconnected.emit()
	# Assert: consumidor do hook recebeu todos, na ordem
	assert_eq(fired, ["connected", "failed", "disconnected"],
		"sinais de conexao reemitidos na ordem")

func test_sinais_de_peer_sao_reemitidos_com_id() -> void:
	# Arrange
	var hook := create_hook() as QNNetHook
	var joined := []
	var left := []
	hook.peer_connected.connect(func(id: int) -> void: joined.append(id))
	hook.peer_disconnected.connect(func(id: int) -> void: left.append(id))
	# Act
	hook.get_base().peer_connected.emit(42)
	hook.get_base().peer_disconnected.emit(42)
	# Assert
	assert_eq(joined, [42], "peer_connected propaga o id")
	assert_eq(left, [42], "peer_disconnected propaga o id")

func test_sinal_peer_authenticating_reemitido() -> void:
	# Arrange
	var hook := create_hook() as QNNetHook
	var auth := []
	hook.peer_authenticating.connect(func(id: int) -> void: auth.append(id))
	# Act
	hook.get_base().peer_authenticating.emit(7)
	# Assert
	assert_eq(auth, [7], "handshake de auth chega ao consumidor")

func test_hook_e_multiplayer_api_valida_sem_peer() -> void:
	# Arrange + Act + Assert: sem peer configurado, estado consistente
	var hook := create_hook() as QNNetHook
	assert_eq(hook.get_peers().size(), 0, "nenhum peer antes de conectar")
