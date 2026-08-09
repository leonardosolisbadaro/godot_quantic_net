## @file test_qn_delta_serializer.gd
## @path res://tests/unit/domain/test_qn_delta_serializer.gd
##
## @description
## TDD para QNDeltaSerializer (Delta Compression).
##
## @created 2026-07-31
## @updated 2026-08-08

extends "res://addons/gut/test.gd"


func test_encode_decode_iframe() -> void:
	var current = {
		"seq": 100,
		"pos": Vector3(10, 0, 10),
		"rot": Vector3(0, PI / 2, 0),
		"ts": 12345,
		"custom_id": 5,
	}

	var buf = QNBitBuffer.new()
	QNDeltaSerializer.encode_state(buf, { }, current)

	buf.seek(0)
	var decoded = QNDeltaSerializer.decode_state(buf, { })

	assert_eq(decoded.seq, 100)
	assert_almost_eq(decoded.pos.x, 10.0, 0.1)
	assert_almost_eq(decoded.pos.z, 10.0, 0.1)
	assert_eq(decoded.ts, 12345)
	assert_eq(decoded.custom_id, 5)


func test_encode_decode_pframe_no_change() -> void:
	var base = {
		"seq": 100,
		"pos": Vector3(10, 0, 10),
		"rot": Vector3(0, PI / 2, 0),
		"ts": 12345,
		"custom_id": 5,
	}
	var current = {
		"seq": 105,
		"pos": Vector3(10, 0, 10), # No change
		"rot": Vector3(0, PI / 2, 0), # No change
		"ts": 12400,
		"custom_id": 5, # No change
	}

	var buf = QNBitBuffer.new()
	QNDeltaSerializer.encode_state(buf, base, current)

	# The buffer should be VERY small (flags only, plus seq and ts)
	# seq (16) + ts (32) + pos_flag(1) + rot_flag(1) + custom_id_flag(1) = 51 bits
	assert_true(buf.get_position() < 64, "P-Frame with no changes should be extremely small")

	buf.seek(0)
	var decoded = QNDeltaSerializer.decode_state(buf, base)

	assert_eq(decoded.seq, 105)
	assert_almost_eq(decoded.pos.x, 10.0, 0.1)
	assert_almost_eq(decoded.rot.y, base.rot.y, 0.1)
	assert_eq(decoded.ts, 12400)
	assert_eq(decoded.custom_id, 5)


func test_encode_decode_pframe_partial_change() -> void:
	var base = {
		"seq": 100,
		"pos": Vector3(10, 0, 10),
		"rot": Vector3(0, PI / 2, 0),
		"ts": 12345,
		"custom_id": 5,
	}
	var current = {
		"seq": 105,
		"pos": Vector3(20, 0, 20), # Changed!
		"rot": Vector3(0, PI / 2, 0), # No change
		"ts": 12400,
		"custom_id": 5, # No change
	}

	var buf = QNBitBuffer.new()
	QNDeltaSerializer.encode_state(buf, base, current)

	buf.seek(0)
	var decoded = QNDeltaSerializer.decode_state(buf, base)

	assert_eq(decoded.seq, 105)
	assert_almost_eq(decoded.pos.x, 20.0, 0.1)
	assert_almost_eq(decoded.rot.y, base.rot.y, 0.1)
