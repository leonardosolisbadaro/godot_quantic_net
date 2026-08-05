## @file test_qn_world_history_buffer.gd
## @path res://tests/unit/test_qn_world_history_buffer.gd
##
## @description
## Testes unitários para QNWorldHistoryBuffer validando o armazenamento de
## posições passadas e a precisão do raycast temporal (Lag Compensation).
##
## @created 2026-08-05
## @updated 2026-08-05
##
## @since 0.6.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

var buffer: QNWorldHistoryBuffer

func before_each():
	buffer = QNWorldHistoryBuffer.new()

func after_each():
	buffer = null

func test_must_store_and_retrieve_past_states():
	# Arrange: Mover uma entidade ao longo do tempo (1 tick por 10ms)
	for i in range(10):
		var snapshot = {
			101: {"pos": Vector3(i, 0, 0), "radius": 1.0}
		}
		buffer.push_state(i * 10, snapshot)
	
	# Act: Fazer raycast mirando em Vector3(5, 0, 0) no timestamp 50
	# No timestamp 50 (i=5), a entidade estava em X=5.
	var origin = Vector3(5, 0, 10)
	var direction = Vector3(0, 0, -1) # Aponta pro Norte
	var hit = buffer.raycast_past(origin, direction, 50)
	
	# Assert
	assert_true(hit.has("entity_id"), "O tiro deve acertar a entidade 101 no passado")
	assert_eq(hit.get("entity_id", 0), 101, "O ID atingido deve ser o 101")

func test_must_miss_if_timestamp_is_wrong():
	# Arrange
	for i in range(10):
		var snapshot = {
			101: {"pos": Vector3(i, 0, 0), "radius": 1.0}
		}
		buffer.push_state(i * 10, snapshot)
	
	# Act: Atira na posicao 5 (onde ele esteve em ts=50), mas passando ts=90
	var origin = Vector3(5, 0, 10)
	var direction = Vector3(0, 0, -1)
	var hit = buffer.raycast_past(origin, direction, 90)
	
	# Assert
	assert_false(hit.has("entity_id"), "O tiro DEVE FALHAR porque em ts=90 o alvo ja estava na posicao X=9")

func test_must_interpolate_between_ticks():
	# Se atirarmos no tempo 55, o buffer deve saber que a entidade estava
	# entre X=5 e X=6 (X=5.5).
	for i in range(10):
		var snapshot = {
			101: {"pos": Vector3(i, 0, 0), "radius": 1.0}
		}
		buffer.push_state(i * 10, snapshot)
	
	var origin = Vector3(5.5, 0, 10)
	var direction = Vector3(0, 0, -1)
	var hit = buffer.raycast_past(origin, direction, 55)
	
	assert_true(hit.has("entity_id"), "O tiro deve acertar a entidade 101 interpolada no ts=55")
