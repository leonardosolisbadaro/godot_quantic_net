## @file test_qn_host_session.gd
## @path res://addons/quantic_net/tests/use_cases/test_qn_host_session.gd
##
## @description
## Testes para QNHostSession focados em Hybrid Ticking.
##
## @created 2026-08-01
## @updated 2026-08-01
##
## @since 0.1.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNHostSession = preload("res://addons/quantic_net/src/use_cases/qn_host_session.gd")
const QNNetProfile = preload("res://addons/quantic_net/src/domain/qn_net_profile.gd")
const QNBitBuffer = preload("res://addons/quantic_net/src/domain/qn_bit_buffer.gd")

func test_hybrid_ticking_rates():
	var host = QNHostSession.new()
	var emitted_packets = []
	host.packet_ready.connect(func(id: int, data: PackedByteArray) -> void: emitted_packets.append({"id": id, "data": data}))
	
	# Jogador a 60Hz (a cada ~16ms)
	host.register_entity(1, true, true, QNNetProfile.preset_high_frequency()) 
	
	# Prop a 5Hz (a cada 200ms)
	host.register_entity(2, false, true, QNNetProfile.preset_low_frequency())
	
	# Tick 0
	emitted_packets.clear()
	host.tick_broadcast(0)
	
	# Deve conter ambas entidades no pacote para o peer 1
	assert_eq(emitted_packets.size(), 1, "Apenas o peer 1 deve receber pacote")
	var buf = QNBitBuffer.new(emitted_packets[0]["data"])
	buf.read_bits(16) # seq
	buf.read_bits(16) # ack
	buf.read_bits(32) # now
	var count = buf.read_bits(8)
	assert_eq(count, 2, "No tick 0, ambas entidades devem ser enviadas")
	
	# Tick 16 (16ms depois)
	emitted_packets.clear()
	host.tick_broadcast(16)
	assert_eq(emitted_packets.size(), 1)
	buf = QNBitBuffer.new(emitted_packets[0]["data"])
	buf.read_bits(16)
	buf.read_bits(16)
	buf.read_bits(32)
	count = buf.read_bits(8)
	assert_eq(count, 1, "No tick 16ms, apenas o Player (60Hz) deve ser enviado")
	
	# Tick 200 (200ms depois do tick 0)
	emitted_packets.clear()
	host.tick_broadcast(200)
	assert_eq(emitted_packets.size(), 1)
	buf = QNBitBuffer.new(emitted_packets[0]["data"])
	buf.read_bits(16)
	buf.read_bits(16)
	buf.read_bits(32)
	count = buf.read_bits(8)
	assert_eq(count, 2, "No tick 200ms, o Prop (5Hz) deve voltar a ser enviado")
