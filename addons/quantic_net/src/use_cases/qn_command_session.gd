## @file qn_command_session.gd
## @path res://addons/quantic_net/src/use_cases/qn_command_session.gd
##
## @description
## Sessão do servidor para o paradigma Command-Based. Mantém um JitterBuffer para cada cliente.
## Recebe TYPE_INPUT, enfileira, e efetua o pop determinístico durante o tick.
##
## @created 2026-08-08
## @updated 2026-08-08
##
## @since 0.7.0
## @lastModifiedIn 0.7.0
##
## @author Leonardo S. Badaró (with Gemini 3.1 Pro - High)
extends RefCounted

signal input_tick(peer_id: int, sequence: int, input_mask: int, look_dir: Vector2)
signal peer_rejected(peer_id: int, reason: String, strikes: int)

const TYPE_INPUT = 5

var _buffers := {} # peer_id -> QNServerJitterBuffer
var _send_cb: Callable
var _tick_rate_ms: int = 50

func init(send_callback: Callable, tick_rate_ms: int = 50) -> void:
	_send_cb = send_callback
	_tick_rate_ms = tick_rate_ms

func on_peer_authenticated(peer_id: int) -> void:
	var buf = QNServerJitterBuffer.new()
	buf.setup(_tick_rate_ms)
	buf.set_target_delay(100) # Default Jitter de 100ms
	_buffers[peer_id] = buf

func on_peer_disconnected(peer_id: int) -> void:
	if _buffers.has(peer_id):
		_buffers.erase(peer_id)

func set_jitter_delay(peer_id: int, delay_ms: int) -> void:
	if _buffers.has(peer_id):
		_buffers[peer_id].set_target_delay(delay_ms)

func on_client_input(peer_id: int, data: PackedByteArray, current_time: int) -> void:
	if not _buffers.has(peer_id):
		return
	
	if data.size() < 13:
		return
		
	var type = data.decode_u8(0)
	if type != TYPE_INPUT:
		return
		
	var seq = data.decode_u16(1)
	var mask = data.decode_u16(3)
	var dir_x = data.decode_float(5)
	var dir_y = data.decode_float(9)
	var dir = Vector2(dir_x, dir_y)
	
	_buffers[peer_id].push(seq, mask, dir, current_time)

func tick_broadcast(current_time: int) -> void:
	for peer_id: int in _buffers.keys():
		var buf = _buffers[peer_id]
		
		while true:
			var input = buf.pop(current_time)
			if input.is_empty():
				break
				
			input_tick.emit(peer_id, input.get("seq", 0), input.get("input_mask", 0), input.get("look_dir", Vector2.ZERO))
