import re

with open("addons/quantic_net/demo/demo_main.gd", "r", encoding="utf-8") as f:
    content = f.read()
    
# Normalize line endings
content = content.replace("\r\n", "\n")

# Fix 1: FPS History logic
content = content.replace("""	# Histórico de FPS
	var current_fps = Engine.get_frames_per_second()
	# if current_fps > 0:
	#	_frames_per_second_history.append(current_fps)
	#	if _frames_per_second_history.size() > FPS_HISTORY_MAX:
	#		_frames_per_second_history.pop_front()
	if current_fps < _frames_per_second_minimum:
		_frames_per_second_minimum = current_fps
	if current_fps > _frames_per_second_maximum:
		_frames_per_second_maximum = current_fps""",
"""	# Histórico de FPS
	var current_fps = Engine.get_frames_per_second()
	if current_fps > 0:
		_frames_per_second_history.append(current_fps)
		if _frames_per_second_history.size() > FPS_HISTORY_MAX:
			_frames_per_second_history.pop_front()
		if current_fps < _frames_per_second_minimum:
			_frames_per_second_minimum = current_fps
		if current_fps > _frames_per_second_maximum:
			_frames_per_second_maximum = current_fps""")

# Fix 2: RTT History logic
content = content.replace("""	_round_trip_time_history.append(rtt)
	if _round_trip_time_history.size() > RTT_HISTORY_MAX:
		_round_trip_time_history.pop_front()

	if rtt < _round_trip_time_minimum:
		_round_trip_time_minimum = rtt
	if rtt > _round_trip_time_maximum:
		_round_trip_time_maximum = rtt""",
"""	if rtt > 0:
		_round_trip_time_history.append(rtt)
		if _round_trip_time_history.size() > RTT_HISTORY_MAX:
			_round_trip_time_history.pop_front()

		if rtt < _round_trip_time_minimum:
			_round_trip_time_minimum = rtt
		if rtt > _round_trip_time_maximum:
			_round_trip_time_maximum = rtt""")

# Fix 3: UI Strings (FPS)
content = content.replace("""		_ui_diagnostic_label_fps.text = "FPS: %d | Avg: %d | Min: %d | Max: %d | 1%% Low: %d" % [
			current_fps,
			fps_avg,
			_frames_per_second_minimum,
			_frames_per_second_maximum,
			fps_1_low,
		]""",
"""		var fps_win = _frames_per_second_history.size()
		_ui_diagnostic_label_fps.text = "FPS: %d | Avg(%d): %d | Min: %d | Max: %d | 1%% Low: %d" % [
			current_fps,
			fps_win,
			fps_avg,
			_frames_per_second_minimum if _frames_per_second_minimum != SENTINEL_MAX_INT else 0,
			_frames_per_second_maximum,
			fps_1_low,
		]""")

# Fix 4: UI Strings (Frame Time)
content = content.replace("""		_ui_diagnostic_label_frametime.text = "Frame Time: %.2f ms | Avg: %.2f | Min: %.2f | Max: %.2f" % [
			frame_ms,
			frame_avg,
			frame_min_disp,
			_frame_time_maximum,
		]""",
"""		var f_win = _frame_time_history.size()
		_ui_diagnostic_label_frametime.text = "Frame Time: %.2f ms | Avg(%d): %.2f | Min: %.2f | Max: %.2f" % [
			frame_ms,
			f_win,
			frame_avg,
			frame_min_disp,
			_frame_time_maximum,
		]""")

# Fix 5: UI Strings (Physics Time)
content = content.replace("""		_ui_diagnostic_label_phys.text = "Physics Time: %.2f ms | Avg: %.2f | Min: %.2f | Max: %.2f" % [
			phys_ms,
			phys_avg,
			phys_min_disp,
			_physics_time_maximum,
		]""",
"""		var p_win = _physics_time_history.size()
		_ui_diagnostic_label_phys.text = "Physics Time: %.2f ms | Avg(%d): %.2f | Min: %.2f | Max: %.2f" % [
			phys_ms,
			p_win,
			phys_avg,
			phys_min_disp,
			_physics_time_maximum,
		]""")

# Fix 6: UI Strings (RTT and Loss)
content = content.replace("""			_ui_diagnostic_label_rtt.text = "RTT (ms): %.0f | Avg: %.0f | Min: %.0f | Max: %.0f" % [
				_network_round_trip_time,
				rtt_avg,
				rtt_min_disp,
				_round_trip_time_maximum,
			]
			_ui_diagnostic_label_loss.text = "Packet Loss: %.1f%% | Avg: %.1f%% | Min: %.1f%% | Max: %.1f%%" % [
				current_loss,
				loss_avg,
				loss_min_disp,
				_packet_loss_maximum,
			]""",
"""			var rtt_win = _round_trip_time_history.size()
			_ui_diagnostic_label_rtt.text = "RTT (ms): %.0f | Avg(%d): %.0f | Min: %.0f | Max: %.0f" % [
				_network_round_trip_time,
				rtt_win,
				rtt_avg,
				rtt_min_disp,
				_round_trip_time_maximum,
			]
			var l_win = _packet_loss_history.size()
			_ui_diagnostic_label_loss.text = "Packet Loss: %.1f%% | Avg(%d): %.1f%% | Min: %.1f%% | Max: %.1f%%" % [
				current_loss,
				l_win,
				loss_avg,
				loss_min_disp,
				_packet_loss_maximum,
			]""")

with open("addons/quantic_net/demo/demo_main.gd", "w", encoding="utf-8") as f:
    f.write(content)
