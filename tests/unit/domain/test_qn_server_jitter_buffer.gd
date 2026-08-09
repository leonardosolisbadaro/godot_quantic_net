## @file test_qn_server_jitter_buffer.gd
## @path res://tests/unit/domain/test_qn_server_jitter_buffer.gd
##
## @description
## Testes unitÃ¡rios do QNServerJitterBuffer (Command-Based) utilizando framework bitwes/Gut.
## Focado em garantir ordenaÃ§Ã£o de sequÃªncia, wrap-around, e tempo de playout determinÃ­stico.
##
## @created 2026-08-08
## @updated 2026-08-08
##
## @since 0.7.0
## @lastModifiedIn 0.7.0
##
## @author Leonardo S. BadarÃ³ (with Gemini 3.1 Pro - High)

extends GutTest


func test_must_pop_ordered_inputs_after_delay() -> void:
	# Arrange
	var buf = QNServerJitterBuffer.new()
	buf.setup(50) # Tick rate de 50ms
	buf.set_target_delay(100) # Jitter delay de 100ms

	# Act
	# Recebe seq 10 no tempo 1000
	buf.push(10, 1, Vector2.ZERO, 1000)

	# Assert
	# No tempo 1050, o delay (100ms) ainda nÃ£o passou. NÃ£o deve retornar nada.
	var res1 = buf.pop(1050)
	assert_true(res1.is_empty(), "O input nao deve ser liberado antes do jitter delay")

	# No tempo 1100 (1000 + 100 delay), a seq 10 deve ser liberada
	var res2 = buf.pop(1100)
	assert_false(res2.is_empty(), "O input deve ser liberado apos o delay")
	assert_eq(res2.get("seq", -1), 10, "A sequence correta deve ser retornada")


func test_must_order_out_of_order_packets() -> void:
	# Arrange
	var buf = QNServerJitterBuffer.new()
	buf.setup(50)
	buf.set_target_delay(100)

	# Act - Chegam fora de ordem
	buf.push(11, 2, Vector2.ZERO, 1000) # Seq 11 chega primeiro
	buf.push(10, 1, Vector2.ZERO, 1020) # Seq 10 chega depois

	# Assert
	var res1 = buf.pop(2000) # Tempo no futuro pra forÃ§ar o Catch-up
	var res2 = buf.pop(2000)

	assert_eq(res1.get("seq", -1), 10, "O pacote 10 deve sair primeiro, mesmo chegando depois")
	assert_eq(res2.get("seq", -1), 11, "O pacote 11 deve sair em segundo")


func test_catch_up_drains_multiple_packets() -> void:
	# Arrange
	var buf = QNServerJitterBuffer.new()
	buf.setup(50)
	buf.set_target_delay(100)

	# Act - Chegam 3 pacotes juntos (pico de latÃªncia)
	buf.push(10, 1, Vector2.ZERO, 1000)
	buf.push(11, 2, Vector2.ZERO, 1010)
	buf.push(12, 3, Vector2.ZERO, 1020)

	# Assert
	# No tempo 1200 (bem no futuro), todos devem estar prontos
	assert_false(buf.pop(1200).is_empty(), "Deve drenar seq 10")
	assert_false(buf.pop(1200).is_empty(), "Deve drenar seq 11")
	assert_false(buf.pop(1200).is_empty(), "Deve drenar seq 12")
	assert_true(buf.pop(1200).is_empty(), "O buffer deve estar vazio")


func test_wrap_around_uint16() -> void:
	# Arrange
	var buf = QNServerJitterBuffer.new()
	buf.setup(50)

	# Act
	buf.push(0, 2, Vector2.ZERO, 1000)
	buf.push(65535, 1, Vector2.ZERO, 1000)

	# Assert - Deve ordenar 65535 antes do 0
	var res1 = buf.pop(2000)
	var res2 = buf.pop(2000)

	assert_eq(res1.get("seq", -1), 65535, "Wrap-around deve priorizar 65535 antes do 0")
	assert_eq(res2.get("seq", -1), 0, "0 deve vir apos 65535")
