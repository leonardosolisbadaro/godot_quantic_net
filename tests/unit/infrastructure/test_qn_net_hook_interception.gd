## @file test_qn_net_hook_interception.gd
## @path res://tests/unit/infrastructure/test_qn_net_hook_interception.gd
##
## @description
## Testes dos ganchos de interceptacao do QNNetHook: RPC de saida,
## pacotes customizados de entrada/saida e observador de configuracao.
## Metodologia AAA sobre bitwes/Gut.
## Testado via Black-Box utilizando a API publica do SceneMultiplayer.
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

class FakePeer extends MultiplayerPeerExtension:
	var sent := []
	var last_channel := -1
	var last_mode := -1
	var last_target := -999
	
	func _set_target_peer(p_peer: int) -> void: last_target = p_peer
	func _set_transfer_channel(p_channel: int) -> void: last_channel = p_channel
	func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void: last_mode = p_mode
	func _put_packet_script(p_buffer: PackedByteArray) -> Error:
		sent.append(p_buffer)
		return OK
		
	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus: return MultiplayerPeer.CONNECTION_CONNECTED
	func _get_packet_script() -> PackedByteArray: return PackedByteArray()
	func _get_available_packet_count() -> int: return 0
	func _get_max_packet_size() -> int: return 1024
	func _get_unique_id() -> int: return 1
	func _is_server() -> bool: return true
	func _get_packet_peer() -> int: return 0
	func _get_packet_channel() -> int: return 0
	func _get_packet_mode() -> MultiplayerPeer.TransferMode: return MultiplayerPeer.TRANSFER_MODE_RELIABLE
	func _poll() -> void: pass
	func _close() -> void: pass
	func _disconnect_peer(_p: int, _f: bool) -> void: pass

func create_hook() -> QNNetHook:
	var h = QNNetHook.new()
	var peer = FakePeer.new()
	h.get_base().multiplayer_peer = peer
	h.get_base().set_root_path(self.get_path())
	peer.peer_connected.emit(1)
	_test_hooks.append(h)
	return h

func after_each() -> void:
	for h in _test_hooks:
		if h and h.has_method("close"):
			h.close()
	_test_hooks.clear()


func test_filtro_entrada_descarta_quando_retorna_null() -> void:
	var hook := create_hook() as QNNetHook
	var received := []
	hook.custom_packet.connect(func(from_peer: int, data: PackedByteArray, ch: int) -> void:
		received.append(data))
		
	var incoming_cb := func(from_peer: int, data: PackedByteArray) -> Variant:
		return null
	hook.set_hooks(Callable(), incoming_cb, Callable(), Callable())
	
	# Act: Simular a emissão interna que o QNNetHook escuta do ENet
	hook.get_base().peer_packet.emit(5, PackedByteArray([1, 2, 3]))
	
	# Assert
	assert_eq(received.size(), 0, "pacote filtrado nao chega ao consumidor custom_packet")

func test_filtro_entrada_pode_transformar_payload() -> void:
	var hook := create_hook() as QNNetHook
	var received := []
	hook.custom_packet.connect(func(from_peer: int, data: PackedByteArray, ch: int) -> void:
		received.append(data))
		
	var incoming_cb := func(from_peer: int, data: PackedByteArray) -> Variant:
		var copy := data.duplicate()
		copy.append(99)
		return copy
	hook.set_hooks(Callable(), incoming_cb, Callable(), Callable())
	
	# Act
	hook.get_base().peer_packet.emit(5, PackedByteArray([1]))
	
	# Assert
	assert_eq(received[0], PackedByteArray([1, 99]), "payload transformado entregue")

func test_filtro_saida_descarta_quando_retorna_null() -> void:
	var hook := create_hook() as QNNetHook
	hook.set_hooks(Callable(), Callable(), func(to: int, data: PackedByteArray) -> Variant:
		return null
	, Callable())
	
	# Act
	var err: Error = hook.send_custom(1, PackedByteArray([1, 2, 3]))
	
	# Assert
	assert_eq(err, OK, "saida filtrada descartada com OK silencioso")
