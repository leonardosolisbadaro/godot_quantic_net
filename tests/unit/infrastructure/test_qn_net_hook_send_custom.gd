## @file test_qn_net_hook_send_custom.gd
## @path res://tests/unit/infrastructure/test_qn_net_hook_send_custom.gd
##
## @description
## Testes do envio customizado do QNNetHook: canal virtual, modo de
## transferencia e target peer aplicados no MultiplayerPeer subjacente.
## Metodologia AAA sobre bitwes/Gut; classe carregada via preload (sem class_name).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNNetHook = preload("res://addons/quantic_net/src/infrastructure/qn_net_hook.gd")

class FakeBase extends MultiplayerAPIExtension:
	var sent := []
	var last_channel := -1
	var last_mode := -1
	var last_target := -999
	
	func send_bytes(data: PackedByteArray, id: int = 0, mode: int = 2, channel: int = 0) -> Error:
		last_target = id
		last_mode = mode
		last_channel = channel
		sent.append(data)
		return OK
	

func _hook_com_fake() -> Array:
	var hook := autofree(QNNetHook.new()) as QNNetHook
	var fake_base = autofree(FakeBase.new())
	
	# Desconecta do base original
	hook.base.connected_to_server.disconnect(hook._on_connected_to_server)
	hook.base.connection_failed.disconnect(hook._on_connection_failed)
	hook.base.server_disconnected.disconnect(hook._on_server_disconnected)
	hook.base.peer_connected.disconnect(hook._on_peer_connected)
	hook.base.peer_disconnected.disconnect(hook._on_peer_disconnected)
	hook.base.peer_authenticating.disconnect(hook._on_peer_authenticating)
	hook.base.peer_packet.disconnect(hook._on_peer_packet)
	
	# Aplica fake
	hook.base = fake_base
	
	# Não precisamos reconectar os sinais se não formos testá-los nesta suite,
	# mas como é _hook_com_fake, pode ser seguro fazê-lo.
	
	return [hook, fake_base]

func test_send_custom_aplica_canal_modo_e_target() -> void:
	# Arrange
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake_base = pair[1]
	# Act
	hook.send_custom(3, PackedByteArray([9]), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	# Assert
	assert_eq(fake_base.last_target, 3, "target peer aplicado")
	assert_eq(fake_base.last_channel, 1, "canal virtual aplicado")
	assert_eq(fake_base.last_mode, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, "modo aplicado")
	assert_eq(fake_base.sent[0], PackedByteArray([9]), "payload entregue intacto")

func test_send_custom_broadcast_target_zero() -> void:
	# Arrange
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake_base = pair[1]
	# Act
	hook.send_custom(0, PackedByteArray([1]))
	# Assert
	assert_eq(fake_base.last_target, 0, "target 0 = broadcast")
	assert_eq(fake_base.sent.size(), 1)

func test_send_custom_filtro_transforma_antes_do_envio() -> void:
	# Arrange
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake_base = pair[1]
	hook.on_outgoing_packet = func(to: int, data: PackedByteArray) -> Variant:
		var copy := data.duplicate()
		copy.append(0xFF)
		return copy
	# Act
	hook.send_custom(1, PackedByteArray([1]))
	# Assert
	assert_eq(fake_base.sent[0], PackedByteArray([1, 0xFF]), "filtro aplicado antes do fio")
