## @file qn_host_session.gd
## @path res://addons/quantic_net/src/use_cases/qn_host_session.gd
##
## @description
## Orquestração da sessão do servidor autoritativo. Processa autenticação,
## validação de movimento, propagação e registro de entidades.
##
## @created 2026-07-30
## @updated 2026-07-30
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends RefCounted

signal snapback_requested(peer_id: int, pkt: PackedByteArray)
signal peer_rejected(peer_id: int, reason: String, strikes: int)
signal broadcast_ready(states: Array)

const SNAPBACK_REASON_CLAMP = 1
const SNAPBACK_REASON_REJECT = 2

var _registry := {}
const QNSerializer = preload("res://addons/quantic_net/src/domain/qn_serializer.gd")

var validator: RefCounted:
	set(v):
		if validator and validator.has_signal("peer_rejected"):
			validator.peer_rejected.disconnect(_on_validator_peer_rejected)
		validator = v
		if validator and validator.has_signal("peer_rejected"):
			validator.peer_rejected.connect(_on_validator_peer_rejected)

func _on_validator_peer_rejected(id: int, reason: String, strikes: int) -> void:
	peer_rejected.emit(id, reason, strikes)

func on_peer_authenticated(peer_id: int) -> void:
	_registry[peer_id] = {
		"id": peer_id,
		"pos": Vector3.ZERO,
		"rot": Vector3.ZERO,
		"profile": "MMO"
	}

func on_client_snapshot(peer_id: int, data: PackedByteArray, now: int) -> void:
	if not _registry.has(peer_id) or not validator:
		return
		
	var decoded = QNSerializer.decode_state_seq(data)
	if decoded.is_empty():
		return
		
	var pos: Vector3 = decoded.get("pos", Vector3.ZERO)
	var rot: Vector3 = decoded.get("rot", Vector3.ZERO)
	var seq: int = decoded.get("seq", 0)
	
	var result: Dictionary = validator.validate(peer_id, pos, rot, now)
	var action: String = result.get("action", "")
	
	if action == "accept":
		_registry[peer_id].pos = result.pos
		_registry[peer_id].rot = result.rot
	elif action == "clamp":
		_registry[peer_id].pos = result.pos
		_registry[peer_id].rot = result.rot
		var snap = QNSerializer.encode_snapback(seq, result.pos, result.rot, now, SNAPBACK_REASON_CLAMP)
		snapback_requested.emit(peer_id, snap)
	elif action == "reject":
		var snap = QNSerializer.encode_snapback(seq, result.pos, result.rot, now, SNAPBACK_REASON_REJECT)
		snapback_requested.emit(peer_id, snap)

func tick_broadcast(now: int) -> void:
	var states := []
	for id in _registry:
		states.append(_registry[id])
	broadcast_ready.emit(states)

func get_registry() -> Dictionary:
	return _registry
