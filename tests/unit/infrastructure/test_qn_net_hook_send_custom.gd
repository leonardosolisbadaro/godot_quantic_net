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

class FakePeer:
	extends MultiplayerPeerExtension
	var sent := []
	var last_channel := -1
	var last_mode := -1
	var last_target := -999
	func _set_transfer_channel(ch: int) -> void: last_channel = ch
	func _set_transfer_mode(mode: int) -> void: last_mode = mode
	func _set_target_peer(p: int) -> void: last_target = p
	func _put_packet_script(buffer: PackedByteArray) -> Error:
		sent.append(buffer)
		return OK
	func _get_available_packet_count() -> int: return 0
	func _get_packet_script() -> PackedByteArray: return PackedByteArray()
	func _get_packet_channel() -> int: return 0
	func _get_packet_mode() -> int: return 0
	func _get_packet_peer() -> int: return 0
	func _close() -> void: pass
	func _disconnect_peer(_p: int, _f: bool) -> void: pass
	func _get_unique_id() -> int: return 1
	func _is_server() -> bool: return true
	func _is_refusing_new_connections() -> bool: return false
	func _is_server_relay_supported() -> bool: return false
	func _get_connection_status() -> int: return MultiplayerPeer.CONNECTION_CONNECTED
	func _get_transfer_channel() -> int: return last_channel
	func _get_transfer_mode() -> int: return last_mode
	func _get_max_packet_size() -> int: return 1400

func _hook_com_fake() -> Array:
	var hook := autofree(QNNetHook.new()) as QNNetHook
	var fake := autofree(FakePeer.new()) as FakePeer
	hook.base.multiplayer_peer = fake
	return [hook, fake]

func test_send_custom_aplica_canal_modo_e_target() -> void:
	# Arrange
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake = pair[1]
	# Act
	hook.send_custom(3, PackedByteArray([9]), 1, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE)
	# Assert
	assert_eq(fake.last_target, 3, "target peer aplicado")
	assert_eq(fake.last_channel, 1, "canal virtual aplicado")
	assert_eq(fake.last_mode, MultiplayerPeer.TRANSFER_MODE_UNRELIABLE, "modo aplicado")
	assert_eq(fake.sent[0], PackedByteArray([9]), "payload entregue intacto")

func test_send_custom_broadcast_target_zero() -> void:
	# Arrange
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake = pair[1]
	# Act
	hook.send_custom(0, PackedByteArray([1]))
	# Assert
	assert_eq(fake.last_target, 0, "target 0 = broadcast")
	assert_eq(fake.sent.size(), 1)

func test_send_custom_filtro_transforma_antes_do_envio() -> void:
	# Arrange
	var pair := _hook_com_fake()
	var hook = pair[0]
	var fake = pair[1]
	hook.on_outgoing_packet = func(to: int, data: PackedByteArray) -> Variant:
		var copy := data.duplicate()
		copy.append(0xFF)
		return copy
	# Act
	hook.send_custom(1, PackedByteArray([1]))
	# Assert
	assert_eq(fake.sent[0], PackedByteArray([1, 0xFF]), "filtro aplicado antes do fio")
