## @file qn_telemetry_aggregator.gd
## @path res://addons/quantic_net/src/domain/qn_telemetry_aggregator.gd
##
## @description
## Agregador puramente matemático (Domain Layer) para cálculo de métricas de rede
## com janelas deslizantes (Sliding Window). Sem dependência da ENet ou Node.
##
## @created 2026-08-04
## @updated 2026-08-04
##
## @since 0.4.0
## @lastModifiedIn 0.4.0
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

class_name QNTelemetryAggregator
extends RefCounted

var _window_size: int
var _rtt_samples: Array[float] = []

var _rtt_min: float = INF
var _rtt_max: float = -INF

var _current_loss: float = 0.0
var _loss_samples: Array[float] = []
var _loss_max: float = -INF

func _init(window: int = 128) -> void:
	assert(window > 0, "O tamanho da janela deve ser maior que zero")
	_window_size = window

func push_rtt(ms: float) -> void:
	_rtt_samples.append(ms)
	if _rtt_samples.size() > _window_size:
		_rtt_samples.pop_front()
		
		# Recalculate min/max
		_rtt_min = INF
		_rtt_max = -INF
		for v in _rtt_samples:
			if v < _rtt_min: _rtt_min = v
			if v > _rtt_max: _rtt_max = v
	else:
		if ms < _rtt_min: _rtt_min = ms
		if ms > _rtt_max: _rtt_max = ms

func push_loss(pct: float) -> void:
	_current_loss = pct
	_loss_samples.append(pct)
	if _loss_samples.size() > _window_size:
		_loss_samples.pop_front()
		
		# Recalculate max
		_loss_max = -INF
		for v in _loss_samples:
			if v > _loss_max: _loss_max = v
	else:
		if pct > _loss_max: _loss_max = pct

func get_current_rtt() -> float:
	if _rtt_samples.is_empty(): return 0.0
	return _rtt_samples.back()

func get_avg_rtt() -> float:
	if _rtt_samples.is_empty(): return 0.0
	var sum := 0.0
	for v in _rtt_samples: sum += v
	return sum / float(_rtt_samples.size())

func get_max_rtt() -> float:
	if _rtt_samples.is_empty(): return 0.0
	return _rtt_max

func get_min_rtt() -> float:
	if _rtt_samples.is_empty(): return 0.0
	return _rtt_min

func get_current_loss() -> float:
	return _current_loss

func get_max_loss() -> float:
	if _loss_max == -INF: return 0.0
	return _loss_max

