## @file qn_clock_sync.gd
## @path res://addons/quantic_net/src/domain/qn_clock_sync.gd
##
## @description
## Sincronização de relógio estilo NTP: estima offset e RTT usando
## janela de mínimo (10 amostras) + média móvel exponencial (EMA).
## Camada: Domain (regra pura — não conhece ENet, MultiplayerPeer nem SceneTree).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)



const SAMPLE_WINDOW := 10
const EMA_ALPHA := 0.2

var offset_ms: float = 0.0
var rtt_ms: float = 0.0
var jitter_ms: float = 0.0
var _samples: Array[float] = []
var _initialized := false

func on_pong(client_sent_time: int, server_time: int, client_now: int) -> void:
	var rtt: int = client_now - client_sent_time
	if rtt < 0 or rtt > 5000:
		return
	var sample: float = float(server_time) - (float(client_sent_time) + float(rtt) / 2.0)
	_samples.append(sample)
	if _samples.size() > SAMPLE_WINDOW:
		_samples.pop_front()
	var best: float = _samples[0]
	for s: float in _samples:
		best = minf(best, s)
	if not _initialized:
		offset_ms = best
		rtt_ms = float(rtt)
		jitter_ms = 0.0
		_initialized = true
	else:
		var current_jitter: float = absf(float(rtt) - rtt_ms)
		jitter_ms = lerpf(jitter_ms, current_jitter, EMA_ALPHA)
		offset_ms = lerpf(offset_ms, best, EMA_ALPHA)
		rtt_ms = lerpf(rtt_ms, float(rtt), EMA_ALPHA)

func server_time() -> int:
	return int(Time.get_ticks_msec() + offset_ms)

func is_synced() -> bool:
	return _initialized
