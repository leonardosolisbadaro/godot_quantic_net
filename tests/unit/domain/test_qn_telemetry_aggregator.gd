## @file test_qn_telemetry_aggregator.gd
## @path res://tests/unit/domain/test_qn_telemetry_aggregator.gd
##
## @description
## Testes puros da matemÃ¡tica da janela deslizante do QNTelemetryAggregator.
## SUT: QNTelemetryAggregator
##
## @created 2026-08-04
## @updated 2026-08-08
##
## @since 0.4.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. BadarÃ³ (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

var SUT = preload("res://addons/quantic_net/src/domain/qn_telemetry_aggregator.gd")


func test_cold_start_retorna_zeros_sem_dividir_por_zero():
	var sut = SUT.new(5)
	assert_eq(sut.get_avg_rtt(), 0.0)
	assert_eq(sut.get_max_rtt(), 0.0)
	assert_eq(sut.get_min_rtt(), 0.0)
	assert_eq(sut.get_current_loss(), 0.0)
	assert_eq(sut.get_max_loss(), 0.0)


func test_janela_cheia_descarta_antigos_e_mantem_apenas_window_size():
	var sut = SUT.new(3)
	sut.push_rtt(100.0)
	sut.push_rtt(200.0)
	sut.push_rtt(300.0)
	sut.push_rtt(400.0) # 100 sai da janela
	sut.push_rtt(500.0) # 200 sai da janela

	# Janela deve conter [300, 400, 500]
	assert_eq(sut.get_avg_rtt(), 400.0)
	assert_eq(sut.get_max_rtt(), 500.0)
	assert_eq(sut.get_min_rtt(), 300.0)


func test_pico_registra_maximo_e_reseta_ao_sair_da_janela():
	var sut = SUT.new(3)
	sut.push_loss(0.0)
	sut.push_loss(50.0) # Pico!
	sut.push_loss(0.0)

	assert_eq(sut.get_max_loss(), 50.0)

	sut.push_loss(0.0) # 0.0 antigo sai da janela
	assert_eq(sut.get_max_loss(), 50.0) # 50.0 ainda tÃ¡ lÃ¡!
	sut.push_loss(0.0) # O 50.0 deve sair da janela agora!
	assert_eq(sut.get_max_loss(), 0.0) # Reseta para 0
