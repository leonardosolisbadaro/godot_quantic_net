## @file test_qn_wire_peer_codec.gd
## @path res://tests/unit/adapters/test_qn_wire_peer_codec.gd
##
## @description
## Testes do codec versionado do QNWirePeer: header, ZSTD condicional,
## XOR e rejeicao de framing invalido.
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNWirePeer = preload("res://addons/quantic_net/src/adapters/qn_wire_peer.gd")

func _new_peer() -> MultiplayerPeerExtension:
	return QNWirePeer.new(ENetConnection.new())

func test_header_carrega_magic_versao_e_canal() -> void:
	# Arrange
	var peer := _new_peer()
	var payload := PackedByteArray([10, 20, 30])
	
	# Act
	var wire: PackedByteArray = peer._encode(QNWirePeer.CH_STATE, payload)
	
	# Assert
	assert_eq(wire.decode_u16(0), QNWirePeer.MAGIC, "magic no offset 0")
	assert_eq(wire.decode_u8(2), QNWirePeer.WIRE_VER, "versao do protocolo")
	assert_eq(wire.decode_u8(3), QNWirePeer.CH_STATE, "canal virtual preservado")

func test_encode_aplica_zstd_quando_util() -> void:
	# Arrange
	var peer := _new_peer()
	var payload := PackedByteArray()
	payload.resize(100)
	payload.fill(1) # Repetitivo para garantir taxa de compressão
	
	# Act
	var wire: PackedByteArray = peer._encode(QNWirePeer.CH_RELIABLE, payload)
	
	# Assert
	var flags = wire.decode_u8(4)
	assert_true(flags & QNWirePeer.FLAG_COMPRESS != 0, "deve ligar a flag de compressao")
	assert_lt(wire.size(), payload.size() + 5, "o pacote final deve ser menor que o original")

func test_encode_aplica_xor_com_mascara_correta() -> void:
	# Arrange
	var peer := _new_peer()
	peer.obfuscate = true
	var payload := PackedByteArray([1, 2, 3])
	
	# Act
	var wire: PackedByteArray = peer._encode(QNWirePeer.CH_CONTROL, payload)
	
	# Assert
	var flags = wire.decode_u8(4)
	assert_true(flags & QNWirePeer.FLAG_OBFUSCATE != 0, "deve ligar a flag XOR")
	assert_eq(wire[5], 1 ^ 0x5A, "byte 1 ofuscado")
	assert_eq(wire[6], 2 ^ 0x5A, "byte 2 ofuscado")
	assert_eq(wire[7], 3 ^ 0x5A, "byte 3 ofuscado")

func test_decode_rejeita_pacotes_invalidos() -> void:
	var peer := _new_peer()
	var r1 = peer._decode(PackedByteArray([1, 2, 3, 4]))
	assert_eq(r1.size(), 0, "pacote curto deve ser rejeitado")
	
	var wire = peer._encode(QNWirePeer.CH_CONTROL, PackedByteArray([1]))
	wire.encode_u16(0, 0xBAD0)
	var r2 = peer._decode(wire)
	assert_eq(r2.size(), 0, "magic invalido rejeitado")
	
	wire.encode_u16(0, QNWirePeer.MAGIC)
	wire.encode_u8(2, 99)
	var r3 = peer._decode(wire)
	assert_eq(r3.size(), 0, "versao errada rejeitada")

func test_decode_reconstroi_payload() -> void:
	var peer := _new_peer()
	peer.obfuscate = true
	var payload := PackedByteArray()
	payload.resize(100)
	payload.fill(42)
	
	var wire = peer._encode(QNWirePeer.CH_RELIABLE, payload)
	var decoded = peer._decode(wire)
	
	assert_eq(decoded, payload, "roundtrip com ZSTD e XOR deve ser bit-perfect")
