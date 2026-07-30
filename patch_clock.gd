extends SceneTree
func _init():
	var file = FileAccess.open(""res://addons/quantic_net/src/domain/qn_clock_sync.gd"", FileAccess.READ_WRITE)
	var text = file.get_as_text()
	text = text.replace(""func on_pong(client_sent_time: int, server_time: int, client_now: int) -> void:
	var rtt: int = client_now - client_sent_time"", ""func on_pong(client_sent_time: int, server_time: int, client_now: int) -> void:
	var rtt: int = client_now - client_sent_time
	print('ON_PONG sent=', client_sent_time, ' srv=', server_time, ' now=', client_now, ' rtt=', rtt)"")
	file.store_string(text)
	file.close()
	print(""Patched qn_clock_sync.gd!"")
	quit()
