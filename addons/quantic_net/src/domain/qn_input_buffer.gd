## @file qn_input_buffer.gd
## @path res://addons/quantic_net/src/domain/qn_input_buffer.gd
##
## @description
## Buffer de inputs locais para Client-Side Prediction: drena inputs confirmados
## pelo servidor autoritativo (snapback) e devolve a lista de pendentes para re-predição,
## suportando wrap-around contínuo de 16-bits para as sequências lógicas.
## Camada: Domain (regra pura — não conhece ENet, MultiplayerPeer nem SceneTree).
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)



const MAX_PENDING := 256

var pending: Array[Dictionary] = []

func record(seq: int, move: Vector2, rot_delta: float, dt: float, sent_ts: int = 0) -> void:
	pending.append({"seq": seq, "move": move, "rot_delta": rot_delta, "dt": dt, "sent_ts": sent_ts})
	if pending.size() > MAX_PENDING:
		pending.pop_front()

func get_sent_ts(seq: int) -> int:
	for e: Dictionary in pending:
		if e["seq"] == seq:
			return e.get("sent_ts", 0)
	return 0

func drain_after(confirmed_seq: int) -> Array[Dictionary]:
	var replay: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	
	for e: Dictionary in pending:
		# Lógica matemática para wrap-around:
		# Se (confirmed_seq - seq) mod 65536 for menor que a metade (32768),
		# significa que confirmed_seq está "à frente" ou é "igual" a seq.
		# Logo, seq é mais antiga e deve ser drenada.
		var diff: int = (confirmed_seq - e["seq"]) & 0xFFFF
		if diff < 32768:
			continue # descarta os velhos ou confirmados
			
		replay.append(e)
		keep.append(e)
		
	pending = keep
	return replay

func size() -> int:
	return pending.size()
