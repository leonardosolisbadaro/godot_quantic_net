## @file qn_interp_buffer.gd
## @path res://addons/quantic_net/src/domain/qn_interp_buffer.gd
##
## @description
## Buffer de snapshots para interpolação de peers remotos: renderiza
## 120ms no passado, com lerp_angle contínuo na rotação e extrapolação 
## limitada a um teto seguro para amenizar stutters em lag spikes.
## Camada: Domain (regra pura — não conhece ENet, MultiplayerPeer nem SceneTree).
##
## @created 2026-07-29
## @updated 2026-08-01
##
## @since 0.1.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)


const BASE_DELAY_MS := 60
const MAX_DELAY_MS := 250
const MAX_SNAPSHOTS = 20
const EXTRAPOLATION_LIMIT_MS = 250 # Restaurado para 250ms para evitar stuttering em props de 5Hz (200ms)
const ERROR_BLEND_SPEED := 5.0 # Fator de decaimento por segundo

var render_delay_ms: int = 60
var snaps: Array[Dictionary] = []
var _cached_state := {"pos": Vector3.ZERO, "rot": Vector3.ZERO}
var _empty_state := {}

var _last_sample_now: int = 0
var _last_sample_pos: Vector3 = Vector3.ZERO
var _last_sample_rot: Vector3 = Vector3.ZERO
var _was_extrapolating: bool = false
var _error_pos: Vector3 = Vector3.ZERO
var _error_rot: Vector3 = Vector3.ZERO

var _target_delay_ms: float = float(BASE_DELAY_MS)
var _current_delay_ms: float = float(BASE_DELAY_MS)

func update_jitter(jitter_ms: float) -> void:
	_target_delay_ms = clampf(BASE_DELAY_MS + (jitter_ms * 2.0), float(BASE_DELAY_MS), float(MAX_DELAY_MS))


func push(ts: int, pos: Vector3, rot: Vector3) -> void:
	if not snaps.is_empty() and ts - snaps[-1]["ts"] > 300:
		# Se houve um hiato (>300ms), a entidade provavelmente saiu e voltou
		# da Area of Interest (AoI) ou sofreu um packet loss. 
		# Limpamos o buffer para forçar um Hard-Snap e evitar "patinação" (deslize).
		snaps.clear()
		_error_pos = Vector3.ZERO
		_error_rot = Vector3.ZERO
		_was_extrapolating = false
		
	if not snaps.is_empty() and ts <= snaps[-1]["ts"]:
		return
	snaps.append({"ts": ts, "pos": pos, "rot": rot})
	if snaps.size() > MAX_SNAPSHOTS:
		snaps.pop_front()

func sample(now: int) -> Dictionary:
	if snaps.is_empty():
		return _empty_state
		
	var dt: float = 0.0 if _last_sample_now == 0 else float(now - _last_sample_now) / 1000.0
	_last_sample_now = now
	
	if _target_delay_ms > _current_delay_ms:
		_current_delay_ms = lerpf(_current_delay_ms, _target_delay_ms, minf(1.0, dt * 10.0))
	else:
		_current_delay_ms = lerpf(_current_delay_ms, _target_delay_ms, minf(1.0, dt * 0.5))
		
	render_delay_ms = int(_current_delay_ms)
	var render_ts: int = now - render_delay_ms
	
	var out_pos := Vector3.ZERO
	var out_rot := Vector3.ZERO
	var is_extrapolating := false
	var found := false
	
	if render_ts <= snaps[0]["ts"]:
		out_pos = snaps[0]["pos"]
		out_rot = snaps[0]["rot"]
		found = true
	else:
		for i: int in range(snaps.size() - 1):
			var a: Dictionary = snaps[i]
			var b: Dictionary = snaps[i + 1]
			if render_ts >= a["ts"] and render_ts <= b["ts"]:
				var span: float = float(b["ts"] - a["ts"])
				var t: float = 0.0 if span <= 0.0 else float(render_ts - a["ts"]) / span
				out_pos = a["pos"].lerp(b["pos"], t)
				out_rot = _lerp_angle_vec(a["rot"], b["rot"], t)
				found = true
				break
				
	if not found:
		if snaps.size() == 1:
			out_pos = snaps[0]["pos"]
			out_rot = snaps[0]["rot"]
		elif snaps.size() >= 2:
			var a: Dictionary = snaps[-2]
			var b: Dictionary = snaps[-1]
			var span: float = float(b["ts"] - a["ts"])
			if span > 0.0:
				var over: int = mini(render_ts - b["ts"], EXTRAPOLATION_LIMIT_MS)
				# Proteção contra spans anomalamente pequenos (ex: jitter de clock) que explodiriam o t
				var safe_span: float = maxf(span, 25.0) 
				var t: float = 1.0 + float(over) / safe_span
				out_pos = a["pos"].lerp(b["pos"], t)
				out_rot = _lerp_angle_vec(a["rot"], b["rot"], t)
				is_extrapolating = true
			found = true
			
	if not found:
		out_pos = snaps[-1]["pos"]
		out_rot = snaps[-1]["rot"]
		
	# MÁQUINA DE ESTADOS DO ERROR BLENDING
	if _was_extrapolating and not is_extrapolating:
		# Acabou de retornar da extrapolação! Captura o erro.
		_error_pos = _last_sample_pos - out_pos
		# Simplificacao do erro rotacional via euler pra demo
		_error_rot = _last_sample_rot - out_rot
		
	if _error_pos.length_squared() > 0.0001:
		_error_pos = _error_pos.lerp(Vector3.ZERO, minf(1.0, dt * ERROR_BLEND_SPEED))
		_error_rot = _error_rot.lerp(Vector3.ZERO, minf(1.0, dt * ERROR_BLEND_SPEED))
	else:
		_error_pos = Vector3.ZERO
		_error_rot = Vector3.ZERO
		
	_was_extrapolating = is_extrapolating
	
	out_pos += _error_pos
	out_rot += _error_rot
	
	_last_sample_pos = out_pos
	_last_sample_rot = out_rot
	
	_cached_state.pos = out_pos
	_cached_state.rot = out_rot
	return _cached_state

static func _lerp_angle_vec(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(
		lerp_angle(a.x, b.x, t),
		lerp_angle(a.y, b.y, t),
		lerp_angle(a.z, b.z, t)
	)
