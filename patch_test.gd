extends SceneTree
func _init():
	var file = FileAccess.open(""res://tests/integration/test_server_two_clients.gd"", FileAccess.READ_WRITE)
	var text = file.get_as_text()
	text = text.replace(""assert_true(dist2 < 2.0, \""cli2 no host converge para o esperado (dist=\"" + str(dist2) + \"")\"")"", ""print('CLI2 EXPECTED: ', pos_c2, ' SERVER: ', reg2.pos)
		assert_true(dist2 < 2.0, \""cli2 no host converge para o esperado (dist=\"" + str(dist2) + \"")\"")"")
	file.store_string(text)
	file.close()
	print(""Patched test!"")
	quit()
