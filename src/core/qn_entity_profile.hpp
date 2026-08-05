#ifndef QN_ENTITY_PROFILE_H
#define QN_ENTITY_PROFILE_H

#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {

class QNEntityProfile : public RefCounted {
	GDCLASS(QNEntityProfile, RefCounted)

protected:
	static void _bind_methods();

public:
	enum HitboxType {
		HITBOX_SPHERE = 0,
		HITBOX_AABB = 1
	};
	double tick_rate_hz;
	double base_priority;
	double spatial_culling_radius;
	
	HitboxType hitbox_type;
	Vector3 hitbox_extents;

	QNEntityProfile();
	~QNEntityProfile();

	void init(double p_tick_rate = 20.0, double p_base_priority = 1.0, double p_culling_radius = 50.0);

	double get_tick_rate_hz() const { return tick_rate_hz; }
	double get_base_priority() const { return base_priority; }
	double get_spatial_culling_radius() const { return spatial_culling_radius; }
	
	void set_hitbox_type(int type) { hitbox_type = (HitboxType)type; }
	int get_hitbox_type() const { return hitbox_type; }
	
	void set_hitbox_extents(const Vector3 &extents) { hitbox_extents = extents; }
	Vector3 get_hitbox_extents() const { return hitbox_extents; }

	static Ref<QNEntityProfile> preset_high_frequency();
	static Ref<QNEntityProfile> preset_standard();
	static Ref<QNEntityProfile> preset_low_frequency();
	static Ref<QNEntityProfile> preset_static();
};

} // namespace godot

VARIANT_ENUM_CAST(godot::QNEntityProfile::HitboxType);

#endif // QN_ENTITY_PROFILE_H
