## @file qn_loss_tracker.gd
## @path res://addons/quantic_net/src/domain/qn_loss_tracker.gd
##
## @description
## Medidor de perda de pacotes por gaps de sequência (wrap-aware 16bit),
## com janela deslizante de 128 amostras para percentual recente.
## Camada: Domain (regra pura — não conhece ENet, MultiplayerPeer nem SceneTree).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)



const WINDOW := 128

var last_seq := -1
var received := 0
var lost := 0
var recent: Array[bool] = []

func on_packet(seq: int) -> void:
	if last_seq == -1:
		last_seq = seq
		_record(true)
		received += 1
		return
	var gap: int = (seq - last_seq) & 0xFFFF
	if gap == 0 or gap > 32768:
		return
	for i: int in range(1, gap):
		_record(false)
		lost += 1
	_record(true)
	received += 1
	last_seq = seq

func _record(ok: bool) -> void:
	recent.append(ok)
	if recent.size() > WINDOW:
		recent.pop_front()

func loss_pct() -> float:
	if recent.is_empty():
		return 0.0
	return 100.0 * float(recent.count(false)) / float(recent.size())
