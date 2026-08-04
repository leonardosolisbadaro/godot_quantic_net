## @file test_qn_entity_profile.gd
## @path res://tests/unit/domain/test_qn_entity_profile.gd
##
## @description
## Testes puros do contrato e Value Object imutável QNEntityProfile.
## SUT: QNEntityProfile
##
## @created 2026-08-04
## @updated 2026-08-04
##
## @since 0.4.0
## @lastModifiedIn 0.4.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

var SUT = preload("res://addons/quantic_net/src/domain/qn_entity_profile.gd")

func test_construtor_atribui_valores_corretamente():
	var sut = SUT.new(60.0, 2.5, 100.0)
	assert_eq(sut.tick_rate_hz, 60.0)
	assert_eq(sut.base_priority, 2.5)
	assert_eq(sut.spatial_culling_radius, 100.0)

func test_presets_retornam_instancias_validas():
	var p_high = SUT.preset_high_frequency()
	assert_eq(p_high.tick_rate_hz, 60.0)
	
	var p_std = SUT.preset_standard()
	assert_eq(p_std.tick_rate_hz, 20.0)
	
	var p_low = SUT.preset_low_frequency()
	assert_eq(p_low.tick_rate_hz, 5.0)
	
	var p_static = SUT.preset_static()
	assert_eq(p_static.tick_rate_hz, 0.0)

# O `assert` de range falhará a execução do jogo em runtime, o que é o comportamento desejado.
# Como o Gut captura falhas de assert de forma especial, omitiremos testes de erro intencional
# para não poluir o console com falhas críticas da engine durante o CI,
# mas sabemos que o Value Object valida (0 a 128) no _init.
