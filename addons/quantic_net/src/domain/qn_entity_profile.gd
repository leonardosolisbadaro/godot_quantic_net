## @file qn_entity_profile.gd
## @path res://addons/quantic_net/src/domain/qn_entity_profile.gd
##
## @description
## Classe de dados estritamente técnica, expondo os parâmetros de rede agnósticos
## que ditam a política de despacho das entidades no servidor (Tick Híbrido).
##
## @since 0.3.0
## @lastModifiedIn 0.4.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)
class_name QNEntityProfile
extends RefCounted

var tick_rate_hz: float = 20.0
var base_priority: float = 1.0
var spatial_culling_radius: float = 50.0

func _init(p_tick_rate: float = 20.0, p_base_priority: float = 1.0, p_culling_radius: float = 50.0) -> void:
	assert(p_tick_rate >= 0.0 and p_tick_rate <= 128.0, "tick_rate_hz fora do range valido (0 a 128)")
	tick_rate_hz = p_tick_rate
	base_priority = p_base_priority
	spatial_culling_radius = p_culling_radius

static func preset_high_frequency() -> RefCounted:
	return load("res://addons/quantic_net/src/domain/qn_entity_profile.gd").new(60.0, 2.0, 100.0)

static func preset_standard() -> RefCounted:
	return load("res://addons/quantic_net/src/domain/qn_entity_profile.gd").new(20.0, 1.0, 50.0)

static func preset_low_frequency() -> RefCounted:
	return load("res://addons/quantic_net/src/domain/qn_entity_profile.gd").new(5.0, 0.5, 30.0)

static func preset_static() -> RefCounted:
	return load("res://addons/quantic_net/src/domain/qn_entity_profile.gd").new(0.0, 0.0, 100.0)
