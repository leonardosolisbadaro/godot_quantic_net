## @file test_qn_wire_peer_wrappers.gd
## @path res://tests/unit/infrastructure/test_qn_wire_peer_wrappers.gd
##
## @description
## Testes unitários para os wrappers do QNWirePeer obrigatórios pela
## Godot Engine (MultiplayerPeerExtension).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNWirePeer = preload("res://addons/quantic_net/src/infrastructure/qn_wire_peer.gd")

func test_wrappers_de_estado_armazenam_valores() -> void:
	# Arrange
	var peer = autofree(QNWirePeer.new())
	
	# Act
	peer._set_target_peer(42)
	peer._set_transfer_channel(1)
	peer._set_transfer_mode(MultiplayerPeer.TRANSFER_MODE_RELIABLE)
	peer._set_refuse_new_connections(true)
	
	# Assert
	assert_eq(peer._target_peer, 42, "Deve armazenar target_peer")
	assert_eq(peer._get_transfer_channel(), 1, "Deve retornar o channel correto")
	assert_eq(peer._get_transfer_mode(), MultiplayerPeer.TRANSFER_MODE_RELIABLE, "Deve retornar mode correto")
	assert_true(peer._is_refusing_new_connections(), "Deve refletir recusa de conexoes")

func test_put_packet_redireciona_ao_netem() -> void:
	# Arrange
	var peer = autofree(QNWirePeer.new())
	peer.netem_enabled = true
	peer.netem_latency_ms = 100
	peer._set_transfer_channel(QNWirePeer.CH_STATE)
	var payload = PackedByteArray([1, 2, 3])
	
	# Act
	var err = peer._put_packet_script(payload)
	
	# Assert
	assert_eq(err, OK, "Deve retornar OK")
	assert_eq(peer._netem_queue.size(), 1, "O pacote de saida deve ter ido para a fila do netem")
