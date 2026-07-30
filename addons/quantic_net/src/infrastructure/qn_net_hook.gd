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

## Pacote customizado decodificado, fora do pipeline RPC.
signal custom_packet(from_peer: int, data: PackedByteArray, channel: int)

## Implementacao real encapsulada (fachada de delegacao).
var base := SceneMultiplayer.new()

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

func _on_connected_to_server() -> void: emit_signal("connected_to_server")
func _on_connection_failed() -> void: emit_signal("connection_failed")
func _on_server_disconnected() -> void: emit_signal("server_disconnected")
func _on_peer_connected(id: int) -> void: emit_signal("peer_connected", id)
func _on_peer_disconnected(id: int) -> void: emit_signal("peer_disconnected", id)
func _on_peer_authenticating(id: int) -> void: emit_signal("peer_authenticating", id)

# Dummies/Wrappers obrigatorios da MultiplayerAPIExtension
func _poll() -> Error:
	var err: Error = base.poll()
	var peer: MultiplayerPeer = base.multiplayer_peer
	if peer and peer.get_available_packet_count() > 0:
		while peer.get_available_packet_count() > 0:
			var pkt: PackedByteArray = peer.get_packet()
			var from: int = peer.get_packet_peer()
			var channel: int = peer.get_packet_channel()
			if on_incoming_packet.is_valid():
				var filtered: Variant = on_incoming_packet.call(from, pkt)
				if filtered == null:
					continue
				pkt = filtered
			emit_signal("custom_packet", from, pkt, channel)
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
	var peer: MultiplayerPeer = base.multiplayer_peer
	if not peer:
		return ERR_UNCONFIGURED
	peer.transfer_channel = channel
	peer.transfer_mode = mode
	peer.set_target_peer(to_peer)
	return peer.put_packet(data)

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
