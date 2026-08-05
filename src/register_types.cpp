#include "register_types.hpp"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "core/qn_bit_buffer.hpp"
#include "core/qn_serializer.hpp"
#include "core/qn_delta_serializer.hpp"
#include "core/qn_interp_buffer.hpp"
#include "core/qn_input_buffer.hpp"

#include "net/qn_wire_peer.hpp"
#include "net/qn_dtls_bootstrap.hpp"
#include "net/qn_net_hook.hpp"

#include "core/qn_clock_sync.hpp"
#include "core/qn_entity_profile.hpp"
#include "core/qn_priority_accumulator.hpp"
#include "core/qn_spatial_grid.hpp"
#include "core/qn_world_history_buffer.hpp"
#include "session/qn_loss_tracker.hpp"
#include "session/qn_host_session.hpp"
#include "session/qn_client_session.hpp"

using namespace godot;

void initialize_quantic_net_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	GDREGISTER_CLASS(QNBitBuffer);
	GDREGISTER_CLASS(QNSerializer);
	GDREGISTER_CLASS(QNDeltaSerializer);
	GDREGISTER_CLASS(QNInterpBuffer);
	GDREGISTER_CLASS(QNInputBuffer);

	GDREGISTER_CLASS(QNWirePeer);
	GDREGISTER_CLASS(QNDTLSBootstrap);
	GDREGISTER_CLASS(QNNetHook);

	GDREGISTER_CLASS(QNClockSync);
	GDREGISTER_CLASS(QNEntityProfile);
	GDREGISTER_CLASS(QNPriorityAccumulator);
	GDREGISTER_CLASS(QNSpatialGrid);
	GDREGISTER_CLASS(QNWorldHistoryBuffer);
	GDREGISTER_CLASS(QNLossTracker);
	GDREGISTER_CLASS(QNHostSession);
	GDREGISTER_CLASS(QNClientSession);
}

void uninitialize_quantic_net_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
// Initialization.
GDExtensionBool GDE_EXPORT quantic_net_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, const GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_quantic_net_module);
	init_obj.register_terminator(uninitialize_quantic_net_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}
