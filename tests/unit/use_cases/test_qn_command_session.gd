## @file test_qn_command_session.gd
## @path res://tests/unit/use_cases/test_qn_command_session.gd
##
## @description
## Testes unitários do orquestrador QNCommandSession.
## Verifica a alocação dinâmica de buffers, roteamento de pacotes TYPE_INPUT
## e disparo determinístico do sinal de input_tick.
##
## @created 2026-08-08
## @updated 2026-08-08
##
## @since 0.7.0
## @lastModifiedIn 0.7.0
##
## @author Leonardo S. Badaró (with Gemini 3.1 Pro - High)

extends GutTest

const QNCommandSession = preload("res://addons/quantic_net/src/use_cases/qn_command_session.gd")

var _ticks_emitted := []


func before_each() -> void:
	_ticks_emitted.clear()


func _on_input_tick(peer_id: int, sequence: int, input_mask: int, look_dir: Vector2) -> void:
	_ticks_emitted.append(
		{
			"peer_id": peer_id,
			"seq": sequence,
			"mask": input_mask,
			"dir": look_dir,
		}
	)


func test_must_allocate_and_free_buffers_based_on_connection_lifecycle() -> void:
	# Arrange
	var sut = QNCommandSession.new()
	sut.init(func(_to, _data, _ch, _mode):
			pass, 50)
	sut.input_tick.connect(_on_input_tick)

	var pkt = PackedByteArray()
	pkt.resize(13)
	pkt.encode_u8(0, QNSerializer.TYPE_INPUT)
	pkt.encode_u16(1, 1)

	# Act 1: Sem autenticar (Ignora)
	sut.on_client_input(10, pkt, 1000)
	sut.tick_broadcast(2000)

	# Assert 1
	assert_eq(_ticks_emitted.size(), 0, "Nao deve processar input sem autenticar")

	# Act 2: Autenticado (Processa)
	sut.on_peer_authenticated(10)
	sut.on_client_input(10, pkt, 2000)
	sut.tick_broadcast(3000)

	# Assert 2
	assert_eq(_ticks_emitted.size(), 1, "Deve alocar buffer e processar input apos conectar")

	# Act 3: Desconectado (Descarta buffer)
	sut.on_peer_disconnected(10)
	sut.on_client_input(10, pkt, 3000)
	sut.tick_broadcast(4000)

	# Assert 3
	assert_eq(_ticks_emitted.size(), 1, "Deve desalocar o buffer e ignorar apos desconectar")


func test_must_parse_input_packet_and_emit_tick() -> void:
	# Arrange
	var sut = QNCommandSession.new()
	sut.init(func(_to, _data, _ch, _mode):
			pass, 50)
	sut.input_tick.connect(_on_input_tick)
	sut.on_peer_authenticated(42)

	var pkt = PackedByteArray()
	pkt.resize(13)
	pkt.encode_u8(0, QNSerializer.TYPE_INPUT)
	pkt.encode_u16(1, 100) # seq
	pkt.encode_u16(3, 5) # mask
	pkt.encode_float(5, 1.0) # dir_x
	pkt.encode_float(9, -1.0) # dir_y

	# Act
	sut.on_client_input(42, pkt, 1000)

	# Drena os ticks do buffer apos o delay (100ms default)
	sut.tick_broadcast(1100)

	# Assert
	assert_eq(_ticks_emitted.size(), 1, "Deve emitir exatamente um tick de input")
	var t = _ticks_emitted[0]
	assert_eq(t.peer_id, 42, "O peer ID deve bater")
	assert_eq(t.seq, 100, "Sequence decodada deve bater")
	assert_eq(t.mask, 5, "Mask decodada deve bater")
	assert_eq(t.dir.x, 1.0, "Dir X decodado deve bater")
	assert_eq(t.dir.y, -1.0, "Dir Y decodado deve bater")


func test_must_ignore_invalid_or_unregistered_packets() -> void:
	# Arrange
	var sut = QNCommandSession.new()
	sut.init(func(_to, _data, _ch, _mode):
			pass, 50)
	sut.input_tick.connect(_on_input_tick)
	sut.on_peer_authenticated(7)

	var bad_size_pkt = PackedByteArray([QNSerializer.TYPE_INPUT, 1, 2, 3]) # curto
	var bad_type_pkt = PackedByteArray()
	bad_type_pkt.resize(13)
	bad_type_pkt.encode_u8(0, 99) # Tipo invalido

	# Act
	sut.on_client_input(7, bad_size_pkt, 1000)
	sut.on_client_input(7, bad_type_pkt, 1000)
	sut.on_client_input(999, bad_type_pkt, 1000) # Peer desconhecido
	sut.tick_broadcast(2000)

	# Assert
	assert_eq(
		_ticks_emitted.size(),
		0,
		"Nenhum tick deve ser emitido para pacotes corrompidos ou orfaos",
	)
