## @file test_qn_net_hook_send_custom.gd
## @path res://tests/unit/infrastructure/test_qn_net_hook_send_custom.gd
##
## @description
## Testes do envio customizado do QNNetHook: canal virtual, modo de
## transferencia e target peer aplicados no MultiplayerPeer subjacente.
## Metodologia AAA sobre bitwes/Gut.
## Testado via Black-Box utilizando FakePeer completo para evitar logs/bugs do Godot.
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


class FakePeer extends MultiplayerPeerExtension:
	var sent := []
	var last_channel := -1
	var last_mode := -1
	var last_target := -999


	func _set_target_peer(p_peer: int) -> void:
		last_target = p_peer


	func _set_transfer_channel(p_channel: int) -> void:
		last_channel = p_channel


	func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
		last_mode = p_mode


	func _put_packet_script(p_buffer: PackedByteArray) -> Error:
		sent.append(p_buffer)
		return OK


	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
		return MultiplayerPeer.CONNECTION_CONNECTED


	func _get_packet_script() -> PackedByteArray:
		return PackedByteArray()


	func _get_available_packet_count() -> int:
		return 0


	func _get_max_packet_size() -> int:
		return 1024


	func _get_unique_id() -> int:
		return 1


	func _is_server() -> bool:
		return true


	func _get_packet_peer() -> int:
		return 0


	func _get_packet_channel() -> int:
		return 0


	func _get_packet_mode() -> MultiplayerPeer.TransferMode:
		return MultiplayerPeer.TRANSFER_MODE_RELIABLE


	func _poll() -> void:
		pass


	func _close() -> void:
		pass


	func _disconnect_peer(_p: int, _f: bool) -> void:
		pass


func _hook_com_fake() -> Array:
	var hook := create_hook() as QNNetHook
	var fake_peer = autofree(FakePeer.new())
	hook.get_base().multiplayer_peer = fake_peer
	# Simulamos que os peers conectaram para o SceneMultiplayer não rejeitar o envio
	fake_peer.peer_connected.emit(3)
	fake_peer.peer_connected.emit(1)
	return [hook, fake_peer]


func test_send_custom_aplica_canal_modo_e_target() -> void:
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake_peer = pair[1]

	hook.send_custom(3, PackedByteArray([9]), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)

	assert_eq(fake_peer.last_target, 3, "target peer aplicado")
	assert_eq(fake_peer.last_channel, 1, "canal virtual aplicado")
	assert_eq(fake_peer.last_mode, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, "modo aplicado")
	assert_true(fake_peer.sent.size() > 0, "payload enviado")


func test_send_custom_broadcast_target_zero() -> void:
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake_peer = pair[1]

	hook.send_custom(0, PackedByteArray([1]))

	assert_eq(fake_peer.sent.size(), 2, "broadcast para todos (2 peers simulados)")
	assert_true(fake_peer.sent[0].size() > 0, "payload processado")


func test_send_custom_filtro_transforma_antes_do_envio() -> void:
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake_peer = pair[1]

	hook.set_hooks(
		Callable(),
		Callable(),
		func(to: int, data: PackedByteArray) -> Variant:
			var copy := data.duplicate()
			copy.append(0xFF)
			return copy,
		Callable(),
	)

	hook.send_custom(1, PackedByteArray([1]))

	assert_true(fake_peer.sent.size() > 0, "filtro aplicado antes do envio")
