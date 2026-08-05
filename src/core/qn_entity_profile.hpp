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
	double tick_rate_hz;
	double base_priority;
	double spatial_culling_radius;

	QNEntityProfile();
	~QNEntityProfile();

	void init(double p_tick_rate = 20.0, double p_base_priority = 1.0, double p_culling_radius = 50.0);

	double get_tick_rate_hz() const { return tick_rate_hz; }
	double get_base_priority() const { return base_priority; }
	double get_spatial_culling_radius() const { return spatial_culling_radius; }

	static Ref<QNEntityProfile> preset_high_frequency();
	static Ref<QNEntityProfile> preset_standard();
	static Ref<QNEntityProfile> preset_low_frequency();
	static Ref<QNEntityProfile> preset_static();
};

} // namespace godot

#endif // QN_ENTITY_PROFILE_H
