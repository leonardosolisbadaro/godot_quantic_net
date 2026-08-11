## @file test_qn_server_validator.gd
## @path res://tests/unit/domain/test_qn_server_validator.gd
##
## @description
## Testes unitários do QNServerValidator utilizando metodologia AAA e framework bitwes/Gut.
## Focado em garantir a segurança do servidor contra speedhacks, teletransportes
## e posições inválidas (out-of-bounds), aplicando tolerâncias (clamps) ou rejeições.
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends GutTest

const QNServerValidator = preload("res://addons/quantic_net/src/domain/qn_server_validator.gd")


func test_movimento_legitimo_aceito() -> void:
	# Arrange (Preparação): Instancia o validador e inicializa um jogador
	var v := QNServerValidator.new()
	var pos := Vector3.ZERO
	var dt_ms := 50 # 20 ticks por segundo
	var player_id := 7
	v.validate(player_id, pos, Vector3.ZERO, 0)

	# Act (Ação) & Assert (Verificação): Movimenta de forma consistente a 1.5 m/s (abaixo do MAX_SPEED)
	for i: int in range(1, 11):
		pos.x += 1.5 * (dt_ms / 1000.0) # 1.5 m/s
		var r: Dictionary = v.validate(player_id, pos, Vector3.ZERO, i * dt_ms)
		assert_eq(r["action"], "accept", "Movimento dentro da velocidade limite deve ser aceito")


func test_jitter_de_dt_nao_rejeita_movimento_legitimo() -> void:
	# Arrange (Preparação): Validador e tempos variáveis (simulando jitter de rede real)
	var v := QNServerValidator.new()
	var pos := Vector3.ZERO
	var now := 0
	var rejects := 0
	var player_id := 7
	v.validate(player_id, pos, Vector3.ZERO, 0)

	# Act (Ação): Alimenta com pacotes irregulares em tempo, mas coerentes com a velocidade (1.5 m/s)
	for i: int in 100:
		var dt_ms: int = [20, 80, 35, 60, 45][i % 5]
		now += dt_ms
		pos.x += 1.5 * (dt_ms / 1000.0)
		if v.validate(player_id, pos, Vector3.ZERO, now)["action"] == "reject":
			rejects += 1

	# Assert (Verificação): O validador de velocidade tem que ser estritamente baseado no d/t real
	assert_eq(rejects, 0, "Deltas variáveis nao devem causar rejeicao se a velocidade for legítima")


func test_speed_hack_gera_reject_e_conserva_posicao() -> void:
	# Arrange (Preparação): Jogador na origem
	var v := QNServerValidator.new()
	var player_id := 7
	v.validate(player_id, Vector3.ZERO, Vector3.ZERO, 0)

	# Act (Ação): Tenta mover 50 metros em apenas 50ms (teletransporte / hack massivo)
	var r: Dictionary = v.validate(player_id, Vector3(50, 0, 0), Vector3.ZERO, 50)

	# Assert (Verificação): Deve rejeitar e devolver a última posição segura conhecida (ZERO)
	assert_eq(r["action"], "reject", "Velocidade absurda (> HARD_CAP) deve gerar reject")
	assert_eq(r["pos"], Vector3.ZERO, "O servidor deve forçar o estado seguro (ZERO) como resposta")


func test_excesso_moderado_gera_clamp() -> void:
	# Arrange (Preparação): Jogador na origem
	var v := QNServerValidator.new()
	var player_id := 7
	v.validate(player_id, Vector3.ZERO, Vector3.ZERO, 0)

	# Act (Ação): Tenta mover 0.5 metros em 50ms (10 m/s). MAX_SPEED é 6.0, HARD_CAP é 20.0. Logo (6 < 10 < 20).
	var r: Dictionary = v.validate(player_id, Vector3(0.5, 0, 0), Vector3.ZERO, 50)

	# Assert (Verificação): Deve clambar o vetor para o equivalente a 6.0 m/s naquele delta.
	# 6.0 m/s * 0.05s = 0.3 metros máximos permitidos.
	assert_eq(r["action"], "clamp", "Excesso moderado (acima do MAX e abaixo do HARD) gera clamp")
	assert_almost_eq(
		r["pos"].x,
		0.3,
		0.001,
		"O servidor deve cortar o vetor excedente pelo limite do MAX_SPEED",
	)


func test_fora_do_mundo_rejeitado() -> void:
	# Arrange (Preparação): Validador limpo
	var v := QNServerValidator.new()

	# Act (Ação): Cliente recém-conectado tenta nascer diretamente fora dos limites (WORLD_BOUNDS=60)
	var r: Dictionary = v.validate(7, Vector3(999, 0, 0), Vector3.ZERO, 0)

	# Assert (Verificação): Rejeição imediata sem registrar o state
	assert_eq(
		r["action"],
		"reject",
		"Posicao out-of-bounds tem que gerar reject independentemente da velocidade",
	)


func test_strikes_acumulam_ate_kick() -> void:
	# Arrange (Preparação): Jogador no centro
	var v := QNServerValidator.new()
	var player_id := 7
	v.validate(player_id, Vector3.ZERO, Vector3.ZERO, 0)

	# Act (Ação): O jogador insiste num teletransporte repetidas vezes
	for i: int in v.max_strikes:
		v.validate(player_id, Vector3(50, 0, 0), Vector3.ZERO, 50 + i * 50)

	# Assert (Verificação): A quantidade de strikes deve acionar o flag de ban/kick do servidor
	assert_true(
		v.should_kick(player_id),
		"Estourar o MAX_STRIKES de rejeições deve acionar o should_kick",
	)


func test_accept_reduz_strikes() -> void:
	# Arrange (Preparação): Jogador no centro comete uma infração
	var v := QNServerValidator.new()
	var player_id := 7
	v.validate(player_id, Vector3.ZERO, Vector3.ZERO, 0)
	v.validate(player_id, Vector3(50, 0, 0), Vector3.ZERO, 50) # 1 strike (reject)

	# Act (Ação): Jogador envia um movimento legítimo (0.1m em 50ms)
	v.validate(player_id, Vector3(0.1, 0, 0), Vector3.ZERO, 100) # accept

	# Assert (Verificação): O movimento correto "perdoa" parcialmente os strikes
	assert_false(v.should_kick(player_id), "Um movimento legítimo deve abater o strike negativo")


func test_rejeicao_emite_sinal_com_razao_e_strikes() -> void:
	# Arrange
	var v := QNServerValidator.new()
	watch_signals(v)
	v.validate(7, Vector3.ZERO, Vector3.ZERO, 0)

	# Act
	v.validate(7, Vector3(50, 0, 0), Vector3.ZERO, 50)

	# Assert
	assert_signal_emitted_with_parameters(v, "peer_rejected", [7, "speed=1000.0 m/s", 1])
