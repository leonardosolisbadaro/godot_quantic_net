## @file qn_net_hook.gd
## @path res://addons/quantic_net/src/infrastructure/qn_net_hook.gd
##
## @description
## Hook de interceptacao sobre MultiplayerAPIExtension: encapsula um
## SceneMultiplayer real e expõe ganchos (Callables) para observar/filtrar
## RPCs de saida, pacotes customizados e configuracao de objetos (spawner).
## Camada: Infrastructure (acoplamento direto a APIs Godot permitido apenas aqui).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends MultiplayerAPIExtension

signal peer_authenticating(id: int)
signal peer_authentication_failed(id: int)

## Pacote customizado decodificado, fora do pipeline RPC.
signal custom_packet(from_peer: int, data: PackedByteArray, channel: int)

## Implementacao real encapsulada (fachada de delegacao).
var base: MultiplayerAPI = SceneMultiplayer.new()

## Ganchos opcionais (Callables). Retornar false/null cancela a operacao:
## on_outgoing_rpc(peer, object, method, args) -> bool (false = descarta)
## on_incoming_packet(from, data) -> PackedByteArray (null = descarta)
## on_outgoing_packet(to, data) -> PackedByteArray (null = descarta)
## on_config_add(object, config) -> void (observador)
var on_outgoing_rpc: Callable
var on_incoming_packet: Callable
var on_outgoing_packet: Callable
var on_config_add: Callable

func _init() -> void:
	base.connected_to_server.connect(_on_connected_to_server)
	base.connection_failed.connect(_on_connection_failed)
	base.server_disconnected.connect(_on_server_disconnected)
	base.peer_connected.connect(_on_peer_connected)
	base.peer_disconnected.connect(_on_peer_disconnected)
	base.peer_authenticating.connect(_on_peer_authenticating)
	base.peer_packet.connect(_on_peer_packet)

func _on_connected_to_server() -> void:
	print("QNNETHOOK: _on_connected_to_server called!")
	connected_to_server.emit()
func _on_connection_failed() -> void: connection_failed.emit()
func _on_server_disconnected() -> void: server_disconnected.emit()
func _on_peer_connected(id: int) -> void: peer_connected.emit(id)
func _on_peer_disconnected(id: int) -> void: peer_disconnected.emit(id)
func _on_peer_authenticating(id: int) -> void: peer_authenticating.emit(id)
func _on_peer_packet(id: int, data: PackedByteArray) -> void:
	if on_incoming_packet.is_valid():
		var filtered = on_incoming_packet.call(id, data)
		if filtered == null: return
		data = filtered
	custom_packet.emit(id, data, 1) # Note: we lose the original channel from Godot 4.3's peer_packet signal, but we can assume 1 (STATE) for now or get it from base.multiplayer_peer.get_packet_channel()

# Dummies/Wrappers obrigatorios da MultiplayerAPIExtension
func _poll() -> Error:
	var err: Error = base.poll()

	return err

func _rpc(peer: int, object: Object, method: StringName, args: Array) -> Error:
	if on_outgoing_rpc.is_valid() and not bool(on_outgoing_rpc.call(peer, object, method, args)):
		return OK
	return base.rpc(peer, object, method, args)

func _object_configuration_add(object: Object, config: Variant) -> Error:
	if on_config_add.is_valid():
		on_config_add.call(object, config)
	return base.object_configuration_add(object, config)

func _object_configuration_remove(object: Object, config: Variant) -> Error:
	return base.object_configuration_remove(object, config)

## Envia pacote customizado fora do pipeline RPC (apos codec do WirePeer).
## to_peer: id alvo (0 = broadcast). channel: canal virtual. mode: transfer.
func send_custom(to_peer: int, data: PackedByteArray, channel: int = 1,
		mode: int = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE) -> Error:
	if on_outgoing_packet.is_valid():
		var filtered: Variant = on_outgoing_packet.call(to_peer, data)
		if filtered == null:
			return OK
		data = filtered
	return base.send_bytes(data, to_peer, mode, channel)

func _set_multiplayer_peer(p_peer: MultiplayerPeer) -> void:
	base.multiplayer_peer = p_peer

func _get_multiplayer_peer() -> MultiplayerPeer:
	return base.multiplayer_peer

func _get_unique_id() -> int:
	return base.get_unique_id()

func _get_remote_sender_id() -> int:
	return base.get_remote_sender_id()

func _get_peer_ids() -> PackedInt32Array:
	return base.get_peers()
