## @file qn_server_validator.gd
## @path res://addons/quantic_net/src/domain/qn_server_validator.gd
##
## @description
## Validador autoritativo anti-teleporte e anti-speedhack: 3 zonas de tolerância (accept/clamp/reject),
## restrições de limites de mundo (world bounds) e sistema de strikes com expulsão.
## Camada: Domain (regra pura — não conhece ENet, MultiplayerPeer nem SceneTree).
##
## @created 2026-07-29
## @updated 2026-07-31
##
## @since 0.1.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)



signal peer_rejected(id: int, reason: String, strikes: int)

var max_speed := 6.0
var hard_cap := 20.0
var world_bounds := 60.0
var max_strikes := 5

func configure(config: Dictionary) -> void:
	max_speed = config.get("max_speed", 6.0)
	hard_cap = config.get("hard_cap", 20.0)
	world_bounds = config.get("world_bounds", 60.0)
	max_strikes = config.get("max_strikes", 5)

class PeerState:
	var pos: Vector3
	var rot: Vector3
	var last_ts: int
	var strikes: int = 0
	var seq: int = 0

var peers := {}

func peer_left(id: int) -> void:
	peers.erase(id)

func validate(id: int, pos: Vector3, rot: Vector3, now: int) -> Dictionary:
	# print("[VALIDATOR] Validate called with pos: ", pos)
	if absf(pos.x) > world_bounds or absf(pos.z) > world_bounds or pos.y < -2.0 or pos.y > 50.0:
		return _reject(id, peers.get(id), "fora do mundo")
		
	if not peers.has(id):
		var st := PeerState.new()
		st.pos = pos
		st.rot = rot
		st.last_ts = now
		peers[id] = st
		return {"action": "accept", "pos": pos, "rot": rot}
		
	var st: PeerState = peers[id]
	var dt: float = float(now - st.last_ts) / 1000.0
	if dt <= 0.0:
		dt = 0.001
		
	var dist: float = pos.distance_to(st.pos)
	var effective_dt: float = maxf(dt, 0.05)
	var speed: float = dist / effective_dt
	
	if speed <= max_speed:
		st.pos = pos
		st.rot = rot
		st.last_ts = now
		st.strikes = maxi(0, st.strikes - 1)
		return {"action": "accept", "pos": pos, "rot": rot}
		
	if speed <= hard_cap:
		var dir: Vector3 = pos - st.pos
		var clamped: Vector3 = st.pos + dir.normalized() * minf(dist, max_speed * dt)
		clamped.y = pos.y
		st.pos = clamped
		st.rot = rot
		st.last_ts = now
		return {"action": "clamp", "pos": clamped, "rot": rot}
		
	return _reject(id, st, "speed=%.1f m/s" % speed)

func _reject(id: int, st: PeerState, reason: String) -> Dictionary:
	if st:
		st.strikes += 1
		peer_rejected.emit(id, reason, st.strikes)
		return {"action": "reject", "pos": st.pos, "rot": st.rot, "strikes": st.strikes}
	peer_rejected.emit(id, reason, 0)
	return {"action": "reject", "pos": Vector3.ZERO, "rot": Vector3.ZERO, "strikes": 0}

func should_kick(id: int) -> bool:
	return peers.has(id) and peers[id].strikes >= max_strikes
