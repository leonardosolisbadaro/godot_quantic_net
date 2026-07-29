## @file quantic_net_autoload.gd
## @path res://addons/quantic_net/src/infrastructure/quantic_net_autoload.gd
##
## @description
## Autoload principal (casca) do QuanticNet.
## Expõe a API pública do plugin (host, join, submit_state) 
## para integração plug and play com a Godot Engine.
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends Node

# Sinais públicos (API)
signal peer_joined(id: int)
signal peer_left(id: int)
signal state_received(owner: int, pos: Vector3, rot: Vector3, custom: int)
signal pong_received(rtt: float, offset: float)
signal snapback_received(seq: int, pos: Vector3, rot: Vector3)

func host(port: int, secret: String, bind_ip: String = "*", max_peers: int = 32) -> void:
	pass

func join(ip: String, port: int, secret: String, netem: bool = false) -> void:
	pass

func submit_state(pos: Vector3, rot: Vector3, custom: int, dt: float) -> void:
	pass

func remote_state(owner_id: int) -> Dictionary:
	return {}

func loss_of(owner_id: int) -> float:
	return 0.0

func kick(peer_id: int) -> void:
	pass

func toggle_netem() -> void:
	pass
