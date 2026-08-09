## @file test_qn_entity_profile.gd
## @path res://tests/unit/domain/test_qn_entity_profile.gd
##
## @description
## Testes puros do contrato e Value Object imutÃ¡vel QNEntityProfile.
## SUT: QNEntityProfile
##
## @created 2026-08-04
## @updated 2026-08-08
##
## @since 0.4.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. BadarÃ³ (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

var sut_class = QNEntityProfile


func test_construtor_atribui_valores_corretamente():
	var sut = sut_class.new()
	sut.init(60.0, 2.5, 100.0)
	assert_eq(sut.get_tick_rate_hz(), 60.0)
	assert_eq(sut.get_base_priority(), 2.5)
	assert_eq(sut.get_spatial_culling_radius(), 100.0)


func test_presets_retornam_instancias_validas():
	var p_high = sut_class.preset_high_frequency()
	assert_eq(p_high.get_tick_rate_hz(), 60.0)

	var p_std = sut_class.preset_standard()
	assert_eq(p_std.get_tick_rate_hz(), 20.0)

	var p_low = sut_class.preset_low_frequency()
	assert_eq(p_low.get_tick_rate_hz(), 5.0)

	var p_static = sut_class.preset_static()
	assert_eq(p_static.get_tick_rate_hz(), 0.0)

# O `assert` de range falharÃ¡ a execuÃ§Ã£o do jogo em runtime, o que Ã© o comportamento desejado.
# Como o Gut captura falhas de assert de forma especial, omitiremos testes de erro intencional
# para nÃ£o poluir o console com falhas crÃ­ticas da engine durante o CI,
# mas sabemos que o Value Object valida (0 a 128) no _init.
