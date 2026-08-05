#include "qn_entity_profile.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

QNEntityProfile::QNEntityProfile() {
	tick_rate_hz = 20.0;
	base_priority = 1.0;
	spatial_culling_radius = 50.0;
	hitbox_type = HITBOX_SPHERE;
	hitbox_extents = Vector3(1.0, 1.0, 1.0);
}

QNEntityProfile::~QNEntityProfile() {
}

void QNEntityProfile::_bind_methods() {
	ClassDB::bind_method(D_METHOD("init", "p_tick_rate", "p_base_priority", "p_culling_radius"), &QNEntityProfile::init, DEFVAL(20.0), DEFVAL(1.0), DEFVAL(50.0));
	
	ClassDB::bind_static_method("QNEntityProfile", D_METHOD("preset_high_frequency"), &QNEntityProfile::preset_high_frequency);
	ClassDB::bind_static_method("QNEntityProfile", D_METHOD("preset_standard"), &QNEntityProfile::preset_standard);
	ClassDB::bind_static_method("QNEntityProfile", D_METHOD("preset_low_frequency"), &QNEntityProfile::preset_low_frequency);
	ClassDB::bind_static_method("QNEntityProfile", D_METHOD("preset_static"), &QNEntityProfile::preset_static);
	
	ClassDB::bind_method(D_METHOD("get_tick_rate_hz"), &QNEntityProfile::get_tick_rate_hz);
	ClassDB::bind_method(D_METHOD("get_base_priority"), &QNEntityProfile::get_base_priority);
	ClassDB::bind_method(D_METHOD("get_spatial_culling_radius"), &QNEntityProfile::get_spatial_culling_radius);
	
	ClassDB::bind_method(D_METHOD("set_hitbox_type", "type"), &QNEntityProfile::set_hitbox_type);
	ClassDB::bind_method(D_METHOD("get_hitbox_type"), &QNEntityProfile::get_hitbox_type);
	
	ClassDB::bind_method(D_METHOD("set_hitbox_extents", "extents"), &QNEntityProfile::set_hitbox_extents);
	ClassDB::bind_method(D_METHOD("get_hitbox_extents"), &QNEntityProfile::get_hitbox_extents);
	
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "tick_rate_hz"), "", "get_tick_rate_hz");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "base_priority"), "", "get_base_priority");
	ADD_PROPERTY(PropertyInfo(Variant::FLOAT, "spatial_culling_radius"), "", "get_spatial_culling_radius");
	
	ADD_PROPERTY(PropertyInfo(Variant::INT, "hitbox_type"), "set_hitbox_type", "get_hitbox_type");
	ADD_PROPERTY(PropertyInfo(Variant::VECTOR3, "hitbox_extents"), "set_hitbox_extents", "get_hitbox_extents");
	
	BIND_ENUM_CONSTANT(HITBOX_SPHERE);
	BIND_ENUM_CONSTANT(HITBOX_AABB);
}

void QNEntityProfile::init(double p_tick_rate, double p_base_priority, double p_culling_radius) {
	tick_rate_hz = p_tick_rate;
	base_priority = p_base_priority;
	spatial_culling_radius = p_culling_radius;
}

Ref<QNEntityProfile> QNEntityProfile::preset_high_frequency() {
	Ref<QNEntityProfile> p; p.instantiate();
	p->init(60.0, 2.0, 100.0);
	return p;
}

Ref<QNEntityProfile> QNEntityProfile::preset_standard() {
	Ref<QNEntityProfile> p; p.instantiate();
	p->init(20.0, 1.0, 50.0);
	return p;
}

Ref<QNEntityProfile> QNEntityProfile::preset_low_frequency() {
	Ref<QNEntityProfile> p; p.instantiate();
	p->init(5.0, 0.5, 30.0);
	return p;
}

Ref<QNEntityProfile> QNEntityProfile::preset_static() {
	Ref<QNEntityProfile> p; p.instantiate();
	p->init(0.0, 0.0, 100.0);
	return p;
}
