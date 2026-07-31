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
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)



const RENDER_DELAY_MS := 120
const MAX_SNAPSHOTS := 16
const EXTRAPOLATION_LIMIT_MS := 250

var snaps: Array[Dictionary] = []

func push(ts: int, pos: Vector3, rot: Vector3) -> void:
	if not snaps.is_empty() and ts <= snaps[-1]["ts"]:
		return
	snaps.append({"ts": ts, "pos": pos, "rot": rot})
	if snaps.size() > MAX_SNAPSHOTS:
		snaps.pop_front()

func sample(now: int) -> Dictionary:
	if snaps.is_empty():
		return {}
		
	var render_ts: int = now - RENDER_DELAY_MS
	
	if render_ts <= snaps[0]["ts"]:
		return {"pos": snaps[0]["pos"], "rot": snaps[0]["rot"]}
		
	for i: int in range(snaps.size() - 1):
		var a: Dictionary = snaps[i]
		var b: Dictionary = snaps[i + 1]
		if render_ts >= a["ts"] and render_ts <= b["ts"]:
			var span: float = float(b["ts"] - a["ts"])
			var t: float = 0.0 if span <= 0.0 else float(render_ts - a["ts"]) / span
			return {"pos": a["pos"].lerp(b["pos"], t), "rot": _lerp_angle_vec(a["rot"], b["rot"], t)}
			
	if snaps.size() >= 2:
		var a: Dictionary = snaps[-2]
		var b: Dictionary = snaps[-1]
		var span: float = float(b["ts"] - a["ts"])
		if span > 0.0:
			# Correção de TDD: Extrapolar usando render_ts no lugar do now,
			# pois a "cabeça de leitura" temporal (playhead) reside no render_ts.
			var over: int = mini(render_ts - b["ts"], EXTRAPOLATION_LIMIT_MS)
			var t: float = 1.0 + float(over) / span
			return {"pos": a["pos"].lerp(b["pos"], t), "rot": _lerp_angle_vec(a["rot"], b["rot"], t)}
			
	return {"pos": snaps[-1]["pos"], "rot": snaps[-1]["rot"]}

static func _lerp_angle_vec(a: Vector3, b: Vector3, t: float) -> Vector3:
	return Vector3(
		lerp_angle(a.x, b.x, t),
		lerp_angle(a.y, b.y, t),
		lerp_angle(a.z, b.z, t)
	)
