## @file test_qn_net_profile.gd
## @path res://addons/quantic_net/tests/domain/test_qn_net_profile.gd
##
## @description
## Testes unitários para a classe de domínio QNNetProfile.
## Valida os presets e as propriedades que ditam a política de despache.
##
## @created 2026-08-01
## @updated 2026-08-01
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNNetProfile = preload("res://addons/quantic_net/src/domain/qn_net_profile.gd")

func test_must_create_default_profile():
	var profile = QNNetProfile.new()
	assert_eq(profile.tick_rate_hz, 20.0, "O padrão deve ser 20Hz")
	assert_eq(profile.base_priority, 1.0, "A prioridade base padrão deve ser 1.0")
	assert_eq(profile.spatial_culling_radius, 50.0, "O raio de cull padrão deve ser 50m")

func test_preset_high_frequency():
	var profile = QNNetProfile.preset_high_frequency()
	assert_eq(profile.tick_rate_hz, 60.0, "Alta frequência deve ser 60Hz")
	assert_eq(profile.base_priority, 2.0, "Alta frequência deve ter prioridade 2.0")

func test_preset_standard():
	var profile = QNNetProfile.preset_standard()
	assert_eq(profile.tick_rate_hz, 20.0, "Padrão deve ser 20Hz")
	assert_eq(profile.base_priority, 1.0, "Padrão deve ter prioridade 1.0")

func test_preset_low_frequency():
	var profile = QNNetProfile.preset_low_frequency()
	assert_eq(profile.tick_rate_hz, 5.0, "Baixa frequência deve ser 5Hz")
	assert_eq(profile.base_priority, 0.5, "Baixa frequência deve ter menor prioridade (0.5)")

func test_preset_static():
	var profile = QNNetProfile.preset_static()
	assert_eq(profile.tick_rate_hz, 0.0, "Estático não deve possuir envio temporal periódico")
	assert_eq(profile.base_priority, 0.0, "Estático tem prioridade mínima")
