import sys
import re

with open('src/session/qn_host_session.cpp', 'r', encoding='utf-8') as f:
    code = f.read()

# We need to replace the entire `void QNHostSession::tick_broadcast()` block.
# Let's find its start and end.
start_idx = code.find('void QNHostSession::tick_broadcast() {')
if start_idx == -1:
    print("Could not find tick_broadcast!")
    sys.exit(1)

# We know where it ends roughly, let's just replace everything from start_idx up to the next method.
next_method_idx = code.find('Dictionary QNHostSession::query_raycast', start_idx)

new_tick_broadcast = """void QNHostSession::tick_broadcast() {
	if (_registry.is_empty()) return;

	uint64_t now = Time::get_singleton()->get_ticks_msec();
	_server_seq++;
	
	Dictionary current_states;
	Array keys = _registry.keys();
	
	for (int i = 0; i < keys.size(); i++) {
		int id = keys[i];
		Dictionary st = _registry[id];
		
		int last_broadcast_ts = st.get("last_broadcast_ts", 0);
		bool should_broadcast = false;
		
		if (st.has("profile")) {
			Ref<QNEntityProfile> profile = st["profile"];
			if (profile.is_valid()) {
				int tick_rate = profile->get_tick_rate();
				if (tick_rate > 0) {
					int ticks_between = 1000 / tick_rate;
					if (now - last_broadcast_ts >= ticks_between) {
						should_broadcast = true;
					}
				}
			}
		} else {
			if (last_broadcast_ts == 0) {
				should_broadcast = true;
			}
		}
		
		if (should_broadcast) {
			Dictionary inner_clone = _get_pooled_dict();
			Dictionary orig = st; // _registry[id]
			Array orig_keys = orig.keys();
			for (int k = 0; k < orig_keys.size(); k++) {
				inner_clone[orig_keys[k]] = orig[orig_keys[k]];
			}
			current_states[id] = inner_clone;
		}
	}
	
	static Dictionary empty_dict;
	std::vector<int> candidates;
	candidates.reserve(128);
	std::vector<int> selected_states;
	selected_states.reserve(128);
	
	for (int i = 0; i < keys.size(); i++) {
		int id = keys[i];
		Dictionary st = _registry[id];
		if (!(bool)st.get("is_peer", false)) continue;
		
		int ack = st.get("ack", 0);
		Dictionary base_states;
		for (int k = 0; k < _world_history.size(); k++) {
			Dictionary hist = _world_history[k];
			if ((int)hist["seq"] == ack) {
				base_states = hist["states"];
				break;
			}
		}
		
		candidates.clear();
		selected_states.clear();
		
		_grid->get_entities_in_radius_internal(st["pos"], 250.0, candidates);
		
		// Filtra candidatos pela aura de existencia
		auto it = candidates.begin();
		while (it != candidates.end()) {
			int cid = *it;
			if (current_states.has(cid)) {
				double cid_aura = 250.0;
				if (_registry.has(cid)) {
					Dictionary reg_st = _registry[cid];
					Ref<QNEntityProfile> cid_profile = reg_st.get("profile", Variant());
					if (cid_profile.is_valid()) cid_aura = cid_profile->get_spatial_culling_radius();
				}
				
				Vector3 cid_pos = ((Dictionary)current_states[cid]).get("pos", Vector3());
				Vector3 my_pos = st["pos"];
				
				if (cid_pos.distance_to(my_pos) > cid_aura) {
					it = candidates.erase(it);
				} else {
					++it;
				}
			} else {
				it = candidates.erase(it);
			}
		}
		
		// Ensure peer itself is included
		if (current_states.has(id)) {
			if (std::find(candidates.begin(), candidates.end(), id) == candidates.end()) {
				candidates.push_back(id);
			}
		}
		
		_accumulator->select_entities(id, candidates, _registry, current_states, st["pos"], 1200, 19, selected_states);
		
		for (int j = 0; j < selected_states.size(); j++) {
			int selected_id = selected_states[j];
			if (_registry.has(selected_id)) {
				Dictionary sel_st = _registry[selected_id];
				sel_st["last_broadcast_ts"] = now;
			}
		}
		
		_stats["entities_total"] = _registry.size();
		_stats["entities_sent_this_tick"] = selected_states.size();
		int omitted_entities = _registry.size() - selected_states.size();
		_stats["bytes_saved_by_hybrid_ticking"] = (int)_stats["bytes_saved_by_hybrid_ticking"] + (omitted_entities * 19);
		_stats["ticks_since_log"] = (int)_stats["ticks_since_log"] + 1;
		
		if ((int)_stats["ticks_since_log"] >= 600) {
			UtilityFunctions::print(String("[QNHostSession] Bandwidth Stats (Peer ") + String::num_int64(id) + "): " + String::num_int64(selected_states.size()) + " entities sent out of " + String::num_int64(_registry.size()) + ". Savings so far: " + String::num_int64(_stats["bytes_saved_by_hybrid_ticking"]) + " bytes");
			_stats["ticks_since_log"] = 0;
		}
		
		Ref<QNBitBuffer> buf; buf.instantiate();
		buf->write_bits(_server_seq, 16);
		buf->write_bits(ack, 16);
		buf->write_bits(now & 0xFFFFFFFF, 32);
		buf->write_bits(selected_states.size(), 8);
		
		for (int j = 0; j < selected_states.size(); j++) {
			int entity_id = selected_states[j];
			buf->write_bits(entity_id, 32);
			
			const Dictionary *base_ptr = &empty_dict;
			if (base_states.has(entity_id)) {
				base_ptr = &((Dictionary)base_states[entity_id]);
				if (!base_ptr->is_empty()) {
					const Dictionary *peer_base_ptr = &empty_dict;
					if (base_states.has(id)) {
						peer_base_ptr = &((Dictionary)base_states[id]);
						if (!peer_base_ptr->is_empty()) {
							double cull_radius = 50.0;
							if (_registry.has(entity_id)) {
								Dictionary reg_st = _registry[entity_id];
								Ref<QNEntityProfile> p = reg_st.get("profile", Variant());
								if (p.is_valid()) cull_radius = p->get_spatial_culling_radius();
							}
							
							Vector3 pb_pos = peer_base_ptr->get("pos", Vector3());
							Vector3 b_pos = base_ptr->get("pos", Vector3());
							if (pb_pos.distance_to(b_pos) > cull_radius) {
								base_ptr = &empty_dict;
							}
						}
					}
				}
			}
			
			QNDeltaSerializer::encode_state(buf, *base_ptr, current_states[entity_id]);
		}
		
		emit_signal("packet_ready", id, buf->get_buffer());
	}
	
	_rewind_buffer->push_state(now, current_states);
}

"""

new_code = code[:start_idx] + new_tick_broadcast + code[next_method_idx:]
with open('src/session/qn_host_session.cpp', 'w', encoding='utf-8') as f:
    f.write(new_code)
