#include "qn_interp_buffer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/core/math.hpp>

using namespace godot;

QNInterpBuffer::QNInterpBuffer() {
	_last_sample_now = 0;
	_was_extrapolating = false;
	_target_delay_ms = (double)BASE_DELAY_MS;
	_current_delay_ms = (double)BASE_DELAY_MS;
	render_delay_ms = BASE_DELAY_MS;
	
	_cached_state["pos"] = Vector3();
	_cached_state["rot"] = Vector3();
}

QNInterpBuffer::~QNInterpBuffer() {
}

void QNInterpBuffer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("update_jitter", "jitter_ms"), &QNInterpBuffer::update_jitter);
	ClassDB::bind_method(D_METHOD("push", "ts", "pos", "rot"), &QNInterpBuffer::push);
	ClassDB::bind_method(D_METHOD("sample", "now"), &QNInterpBuffer::sample);
}

void QNInterpBuffer::update_jitter(double jitter_ms) {
	_target_delay_ms = UtilityFunctions::clamp(BASE_DELAY_MS + (jitter_ms * 2.0), (double)BASE_DELAY_MS, (double)MAX_DELAY_MS);
}

void QNInterpBuffer::push(int ts, const Vector3 &pos, const Vector3 &rot) {
	if (snaps.size() > 0) {
		Dictionary last_snap = snaps[snaps.size() - 1];
		int last_ts = last_snap["ts"];
		
		if (ts - last_ts > 300) {
			snaps.clear();
			_error_pos = Vector3();
			_error_rot = Vector3();
			_was_extrapolating = false;
		}
		
		if (snaps.size() > 0) {
			Dictionary new_last_snap = snaps[snaps.size() - 1];
			if (ts <= (int)new_last_snap["ts"]) {
				return;
			}
		}
	}
	
	Dictionary d;
	d["ts"] = ts;
	d["pos"] = pos;
	d["rot"] = rot;
	snaps.push_back(d);
	
	if (snaps.size() > MAX_SNAPSHOTS) {
		snaps.pop_front();
	}
}

Dictionary QNInterpBuffer::sample(int now) {
	if (snaps.is_empty()) {
		return _empty_state;
	}
		
	double dt = (_last_sample_now == 0) ? 0.0 : (double)(now - _last_sample_now) / 1000.0;
	_last_sample_now = now;
	
	if (_target_delay_ms > _current_delay_ms) {
		_current_delay_ms = UtilityFunctions::lerp(_current_delay_ms, _target_delay_ms, UtilityFunctions::min(1.0, dt * 10.0));
	} else {
		_current_delay_ms = UtilityFunctions::lerp(_current_delay_ms, _target_delay_ms, UtilityFunctions::min(1.0, dt * 0.5));
	}
		
	render_delay_ms = (int)_current_delay_ms;
	int render_ts = now - render_delay_ms;
	
	Vector3 out_pos;
	Vector3 out_rot;
	bool is_extrapolating = false;
	bool found = false;
	
	Dictionary first_snap = snaps[0];
	if (render_ts <= (int)first_snap["ts"]) {
		out_pos = first_snap["pos"];
		out_rot = first_snap["rot"];
		found = true;
	} else {
		for (int i = 0; i < snaps.size() - 1; i++) {
			Dictionary a = snaps[i];
			Dictionary b = snaps[i + 1];
			int ts_a = a["ts"];
			int ts_b = b["ts"];
			
			if (render_ts >= ts_a && render_ts <= ts_b) {
				double span = (double)(ts_b - ts_a);
				double t = (span <= 0.0) ? 0.0 : (double)(render_ts - ts_a) / span;
				
				Vector3 pos_a = a["pos"];
				Vector3 pos_b = b["pos"];
				out_pos = pos_a.lerp(pos_b, t);
				
				Vector3 rot_a = a["rot"];
				Vector3 rot_b = b["rot"];
				out_rot = _lerp_angle_vec(rot_a, rot_b, t);
				
				found = true;
				break;
			}
		}
	}
				
	if (!found) {
		if (snaps.size() == 1) {
			Dictionary snap = snaps[0];
			out_pos = snap["pos"];
			out_rot = snap["rot"];
		} else if (snaps.size() >= 2) {
			Dictionary a = snaps[snaps.size() - 2];
			Dictionary b = snaps[snaps.size() - 1];
			int ts_a = a["ts"];
			int ts_b = b["ts"];
			double span = (double)(ts_b - ts_a);
			
			if (span > 0.0) {
				int over = UtilityFunctions::mini(render_ts - ts_b, EXTRAPOLATION_LIMIT_MS);
				double safe_span = UtilityFunctions::max(span, 25.0); 
				double t = 1.0 + (double)over / safe_span;
				
				Vector3 pos_a = a["pos"];
				Vector3 pos_b = b["pos"];
				out_pos = pos_a.lerp(pos_b, t);
				
				Vector3 rot_a = a["rot"];
				Vector3 rot_b = b["rot"];
				out_rot = _lerp_angle_vec(rot_a, rot_b, t);
				
				is_extrapolating = true;
			}
			found = true;
		}
	}
			
	if (!found) {
		Dictionary last_snap = snaps[snaps.size() - 1];
		out_pos = last_snap["pos"];
		out_rot = last_snap["rot"];
	}
		
	if (_was_extrapolating && !is_extrapolating) {
		_error_pos = _last_sample_pos - out_pos;
		_error_rot = _last_sample_rot - out_rot;
	}
		
	if (_error_pos.length_squared() > 0.0001) {
		double t = UtilityFunctions::min(1.0, dt * ERROR_BLEND_SPEED);
		_error_pos = _error_pos.lerp(Vector3(), t);
		_error_rot = _error_rot.lerp(Vector3(), t);
	} else {
		_error_pos = Vector3();
		_error_rot = Vector3();
	}
		
	_was_extrapolating = is_extrapolating;
	
	out_pos += _error_pos;
	out_rot += _error_rot;
	
	_last_sample_pos = out_pos;
	_last_sample_rot = out_rot;
	
	_cached_state["pos"] = out_pos;
	_cached_state["rot"] = out_rot;
	return _cached_state;
}

Vector3 QNInterpBuffer::_lerp_angle_vec(const Vector3 &a, const Vector3 &b, double t) {
	return Vector3(
		Math::lerp_angle(a.x, b.x, t),
		Math::lerp_angle(a.y, b.y, t),
		Math::lerp_angle(a.z, b.z, t)
	);
}
