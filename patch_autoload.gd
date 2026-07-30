extends SceneTree
func _init():
	var file = FileAccess.open(""res://addons/quantic_net/src/infrastructure/quantic_net_autoload.gd"", FileAccess.READ_WRITE)
	var text = file.get_as_text()
	text = text.replace(""func _on_custom_packet(peer_id: int, data: PackedByteArray, _channel: int = 1) -> void:
	if _is_server:"", ""func _on_custom_packet(peer_id: int, data: PackedByteArray, _channel: int = 1) -> void:
	print('ON CUSTOM PACKET: ', peer_id, ' size: ', data.size(), ' data: ', data.hex_encode())
	if _is_server:"")
	file.store_string(text)
	file.close()
	print(""Patched quantic_net_autoload.gd!"")
	quit()
