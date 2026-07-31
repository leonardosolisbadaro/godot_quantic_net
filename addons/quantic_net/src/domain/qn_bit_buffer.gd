## @file qn_bit_buffer.gd
## @path res://addons/quantic_net/src/domain/qn_bit_buffer.gd
##
## @description
## Manipulação de bits sobre PackedByteArray (BitStream).
##
## @created 2026-07-31
## @updated 2026-07-31

extends RefCounted

var _buffer: PackedByteArray
var _bit_position: int = 0

func _init(buf: PackedByteArray = PackedByteArray()) -> void:
	_buffer = buf
	_bit_position = 0

func get_buffer() -> PackedByteArray:
	# Retorna apenas a parte válida (até o byte que contém o último bit escrito)
	var byte_count = (_bit_position + 7) / 8
	return _buffer.slice(0, byte_count)

func seek(pos: int) -> void:
	_bit_position = pos

func get_position() -> int:
	return _bit_position

func write_bool(b: bool) -> void:
	write_bits(1 if b else 0, 1)

func read_bool() -> bool:
	return read_bits(1) != 0

func write_bits(value: int, num_bits: int) -> void:
	var byte_idx = _bit_position / 8
	var bit_offset = _bit_position % 8
	
	# Expand buffer se necessário
	var required_bytes = (_bit_position + num_bits + 7) / 8
	if _buffer.size() < required_bytes:
		_buffer.resize(required_bytes)
		
	# Limpa bits espúrios acima do tamanho
	var mask = (1 << num_bits) - 1
	var val = value & mask
	
	var bits_written = 0
	while bits_written < num_bits:
		var bits_this_byte = 8 - bit_offset
		var bits_to_write = mini(bits_this_byte, num_bits - bits_written)
		
		var chunk_mask = (1 << bits_to_write) - 1
		var chunk = (val >> bits_written) & chunk_mask
		
		# Limpa a área e escreve o chunk
		_buffer[byte_idx] = _buffer[byte_idx] & ~(chunk_mask << bit_offset)
		_buffer[byte_idx] = _buffer[byte_idx] | (chunk << bit_offset)
		
		bits_written += bits_to_write
		_bit_position += bits_to_write
		byte_idx += 1
		bit_offset = 0

func read_bits(num_bits: int) -> int:
	var byte_idx = _bit_position / 8
	var bit_offset = _bit_position % 8
	
	var val = 0
	var bits_read = 0
	
	while bits_read < num_bits:
		if byte_idx >= _buffer.size():
			break
			
		var bits_this_byte = 8 - bit_offset
		var bits_to_read = mini(bits_this_byte, num_bits - bits_read)
		
		var chunk_mask = (1 << bits_to_read) - 1
		var chunk = (_buffer[byte_idx] >> bit_offset) & chunk_mask
		
		val = val | (chunk << bits_read)
		
		bits_read += bits_to_read
		_bit_position += bits_to_read
		byte_idx += 1
		bit_offset = 0
		
	return val

func write_float(val: float, min_val: float, max_val: float, precision_bits: int) -> void:
	var max_int = (1 << precision_bits) - 1
	var ratio = clampf((val - min_val) / (max_val - min_val), 0.0, 1.0)
	var int_val = roundi(ratio * max_int)
	write_bits(int_val, precision_bits)

func read_float(min_val: float, max_val: float, precision_bits: int) -> float:
	var max_int = (1 << precision_bits) - 1
	var int_val = read_bits(precision_bits)
	var ratio = float(int_val) / float(max_int)
	return min_val + ratio * (max_val - min_val)

func write_quaternion(q: Quaternion) -> void:
	var max_idx = 0
	var max_val = absf(q.x)
	if absf(q.y) > max_val: max_idx = 1; max_val = absf(q.y)
	if absf(q.z) > max_val: max_idx = 2; max_val = absf(q.z)
	if absf(q.w) > max_val: max_idx = 3; max_val = absf(q.w)
	
	var sign_val = 1.0
	match max_idx:
		0: sign_val = signf(q.x)
		1: sign_val = signf(q.y)
		2: sign_val = signf(q.z)
		3: sign_val = signf(q.w)
	if sign_val == 0.0: sign_val = 1.0
	
	var q_norm = Quaternion(q.x * sign_val, q.y * sign_val, q.z * sign_val, q.w * sign_val)
	
	write_bits(max_idx, 2)
	
	var min_comp = -0.707107
	var max_comp = 0.707107
	var precision = 10
	
	match max_idx:
		0:
			write_float(q_norm.y, min_comp, max_comp, precision)
			write_float(q_norm.z, min_comp, max_comp, precision)
			write_float(q_norm.w, min_comp, max_comp, precision)
		1:
			write_float(q_norm.x, min_comp, max_comp, precision)
			write_float(q_norm.z, min_comp, max_comp, precision)
			write_float(q_norm.w, min_comp, max_comp, precision)
		2:
			write_float(q_norm.x, min_comp, max_comp, precision)
			write_float(q_norm.y, min_comp, max_comp, precision)
			write_float(q_norm.w, min_comp, max_comp, precision)
		3:
			write_float(q_norm.x, min_comp, max_comp, precision)
			write_float(q_norm.y, min_comp, max_comp, precision)
			write_float(q_norm.z, min_comp, max_comp, precision)

func read_quaternion() -> Quaternion:
	var max_idx = read_bits(2)
	var min_comp = -0.707107
	var max_comp = 0.707107
	var precision = 10
	
	var a = read_float(min_comp, max_comp, precision)
	var b = read_float(min_comp, max_comp, precision)
	var c = read_float(min_comp, max_comp, precision)
	
	var missing = sqrt(maxf(0.0, 1.0 - a*a - b*b - c*c))
	
	var q = Quaternion()
	match max_idx:
		0: q = Quaternion(missing, a, b, c)
		1: q = Quaternion(a, missing, b, c)
		2: q = Quaternion(a, b, missing, c)
		3: q = Quaternion(a, b, c, missing)
		
	return q.normalized()
