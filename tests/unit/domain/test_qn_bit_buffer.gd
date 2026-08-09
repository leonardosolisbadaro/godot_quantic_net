## @file test_qn_bit_buffer.gd
## @path res://tests/unit/domain/test_qn_bit_buffer.gd
##
## @description
## TDD para QNBitBuffer (escrita e leitura de bits).
## Verifica endianness, carry over e leitura de dados compactados (Boolean, Int, Float).
##
## @created 2026-07-31
## @updated 2026-08-08

extends "res://addons/gut/test.gd"



func test_write_read_bool() -> void:
	var buf = QNBitBuffer.new()
	buf.write_bool(true)
	buf.write_bool(false)
	buf.write_bool(true)
	
	buf.seek(0)
	assert_true(buf.read_bool(), "Bit 0 should be true")
	assert_false(buf.read_bool(), "Bit 1 should be false")
	assert_true(buf.read_bool(), "Bit 2 should be true")

func test_write_read_bits() -> void:
	var buf = QNBitBuffer.new()
	buf.write_bits(0x5, 3) # 101 in binary (value 5)
	buf.write_bits(0xA, 4) # 1010 in binary (value 10)
	buf.write_bits(0xFF, 8) # 255
	
	buf.seek(0)
	assert_eq(buf.read_bits(3), 0x5)
	assert_eq(buf.read_bits(4), 0xA)
	assert_eq(buf.read_bits(8), 0xFF)

func test_write_read_float() -> void:
	var buf = QNBitBuffer.new()
	# range 0..100 with 10 bits precision
	buf.write_float(50.0, 0.0, 100.0, 10)
	buf.write_float(-25.5, -50.0, 50.0, 12)
	
	buf.seek(0)
	var f1 = buf.read_float(0.0, 100.0, 10)
	var f2 = buf.read_float(-50.0, 50.0, 12)
	
	assert_almost_eq(f1, 50.0, 0.1)
	assert_almost_eq(f2, -25.5, 0.1)

func test_write_read_across_byte_boundary() -> void:
	var buf = QNBitBuffer.new()
	# Write 15 bits, spanning 2 bytes
	buf.write_bits(0x7FFF, 15)
	
	buf.seek(0)
	assert_eq(buf.read_bits(15), 0x7FFF)

func test_write_read_quaternion() -> void:
	var buf = QNBitBuffer.new()
	# A normalized quaternion: (0.0, 0.7071, 0.0, 0.7071)
	var q = Quaternion(0.0, 0.707106, 0.0, 0.707106).normalized()
	buf.write_quaternion(q)
	
	buf.seek(0)
	var q2 = buf.read_quaternion()
	assert_almost_eq(q2.x, q.x, 0.05)
	assert_almost_eq(q2.y, q.y, 0.05)
	assert_almost_eq(q2.z, q.z, 0.05)
	assert_almost_eq(q2.w, q.w, 0.05)
