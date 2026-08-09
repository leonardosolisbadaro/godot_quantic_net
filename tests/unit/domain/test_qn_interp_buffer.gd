## @file test_qn_interp_buffer.gd
## @path res://tests/unit/domain/test_qn_interp_buffer.gd
##
## @description
## Testes unitários do QNInterpBuffer utilizando metodologia AAA e framework bitwes/Gut.
## Focado em garantir que a amostragem do buffer circular retorne posições e rotações
## interpoladas corretamente no passado remoto, incluindo tratamento seguro de extrapolação.
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest


func test_sample_vazio_retorna_dicionario_vazio() -> void:
	# Arrange (Preparação): Instancia o buffer completamente vazio
	var buf := QNInterpBuffer.new()

	# Act (Ação): Tenta amostrar um tempo qualquer
	var result: Dictionary = buf.sample(1000)

	# Assert (Verificação): Deve falhar de forma limpa, retornando dicionário vazio
	assert_eq(result.size(), 0, "Buffer vazio nao deve quebrar e sim retornar vazio")


func test_interpolacao_linear_entre_snapshots() -> void:
	# Arrange (Preparação): Instancia o buffer e insere dois snapshots separados por 100ms
	var buf := QNInterpBuffer.new()
	var t := 10000
	buf.push(t, Vector3.ZERO, Vector3.ZERO)
	buf.push(t + 100, Vector3(1.0, 0.0, 0.0), Vector3.ZERO)

	# Act (Ação): Requisita amostragem exatamente no meio lógico entre os dois snapshots,
	# compensando o RENDER_DELAY interno (que joga o tempo pro passado)
	var sample_time: int = t + 50 + buf.render_delay_ms
	var s: Dictionary = buf.sample(sample_time)

	# Assert (Verificação): O resultado da posição deve ser 0.5 no eixo X (fator t=0.5)
	assert_almost_eq(
		s.get("pos", Vector3.ZERO).x,
		0.5,
		0.01,
		"A posicao deve ser perfeitamente interpolada na metade do caminho",
	)


func test_rotacao_usa_caminho_curto_do_angulo() -> void:
	# Arrange (Preparação): Dois snapshots onde o Euler Y cruza o ponto zero de Euler
	var buf := QNInterpBuffer.new()
	var t := 10000
	buf.push(t, Vector3.ZERO, Vector3(0.0, 0.1, 0.0))
	buf.push(t + 100, Vector3.ZERO, Vector3(0.0, TAU - 0.1, 0.0))

	# Act (Ação): Amostra o exato meio termo
	var s: Dictionary = buf.sample(t + 50 + buf.render_delay_ms)

	# Assert (Verificação): O angulo nao pode girar pelo caminho longo (quase TAU/2), e sim pelo mais curto ao redor do zero
	assert_true(
		absf(s.get("rot", Vector3.ZERO).y) < 0.3,
		"Rotacao interpolada deve utilizar o caminho mais curto no circulo",
	)


func test_pacote_atrasado_descartado() -> void:
	# Arrange (Preparação): Um buffer com dois snapshots
	var buf := QNInterpBuffer.new()
	var t := 10000

	# Act (Ação): Envia o primeiro, envia o SEGUNDO (+200ms) e tenta inserir um intermediário atrasado (+100ms)
	buf.push(t, Vector3.ZERO, Vector3.ZERO)
	buf.push(t + 200, Vector3.ONE, Vector3.ZERO)
	buf.push(t + 100, Vector3(0.5, 0.0, 0.0), Vector3.ZERO) # Descartado

	# Assert (Verificação): O pacote atrasado é ignorado para manter a integridade temporal do buffer
	assert_eq(
		buf.get_snaps_size(),
		2,
		"Pacotes com timestamp <= ao ultimo cabecalho registrado devem ser dropados sumariamente",
	)


func test_gap_longo_extrapola_limitado() -> void:
	# Arrange (Preparação): Simula perda de pacotes (gap) que faz o playhead ultrapassar o último pacote
	var buf := QNInterpBuffer.new()
	var t := 10000
	buf.push(t, Vector3.ZERO, Vector3.ZERO)
	buf.push(t + 50, Vector3(0.075, 0.0, 0.0), Vector3.ZERO)

	# Act (Ação): O playhead (render_ts) ultrapassa o último snapshot em 195ms.
	var target_render_ts := t + 50 + 195
	var now: int = target_render_ts + buf.render_delay_ms
	var s: Dictionary = buf.sample(now)

	# Assert (Verificação): 195ms < 250ms (limite de extrapolação). O alvo prevê velocidade constante de 0.0015u/ms.
	# Total = 0.075 + (195 * 0.0015) = 0.3675
	assert_almost_eq(
		s.get("pos", Vector3.ZERO).x,
		0.3675,
		0.001,
		"Extrapolacao com base no playhead (render_ts) deve ser linear no limite seguro",
	)


func test_extrapolacao_trava_no_limite_de_seguranca() -> void:
	# Arrange (Preparação): Simula uma enorme ausência de rede (desconexão ou lag brutal de mais de meio segundo)
	var buf := QNInterpBuffer.new()
	var t := 10000
	buf.push(t, Vector3.ZERO, Vector3.ZERO)
	buf.push(t + 50, Vector3(0.075, 0.0, 0.0), Vector3.ZERO)

	# Act (Ação): Playhead (render_ts) ultrapassa 500ms do último pacote
	var target_render_ts := t + 50 + 500
	var now: int = target_render_ts + buf.render_delay_ms
	var s: Dictionary = buf.sample(now)

	# Assert (Verificação): A extrapolação deve travar no hard limit da engine (250ms).
	# Total = 0.075 + (250 * 0.0015) = 0.450
	assert_almost_eq(
		s.get("pos", Vector3.ZERO).x,
		0.450,
		0.001,
		"Extrapolacao alem de 250ms deve ser clampada duramente (hard-stop) para evitar dead-reckoning voador",
	)


func test_dynamic_jitter_expands_delay() -> void:
	# Arrange (Preparação): Instancia o buffer
	var buf := QNInterpBuffer.new()
	assert_eq(buf.get_target_delay_ms(), 60.0, "Buffer inicializa com delay base otimista de 60ms")

	# Act (Ação): Reporta um jitter agressivo (ex: 80ms de variancia)
	# Formula: BASE (60) + (80 * 2.0) = 220ms
	buf.update_jitter(80.0)

	# Assert (Verificação): O delay de renderização deve dilatar para proteger contra o jitter
	assert_eq(
		buf.get_target_delay_ms(),
		220.0,
		"O delay deve dilatar proporcionalmente ao Jitter recebido",
	)

	# Act 2 (Ação): Jitter catastrofico de 500ms
	buf.update_jitter(500.0)

	# Assert 2 (Verificação): Não pode dilatar infinitamente
	assert_eq(
		buf.get_target_delay_ms(),
		250.0,
		"O delay nao pode ultrapassar o teto maximo de seguranca de 250ms",
	)


func test_error_blending_amortece_pulo_visual() -> void:
	# Arrange (Preparação): Um buffer simulando Extrapolação seguida de Interpolação
	var buf := QNInterpBuffer.new()
	var t := 10000
	buf.push(t, Vector3.ZERO, Vector3.ZERO)
	buf.push(t + 50, Vector3(0.075, 0.0, 0.0), Vector3.ZERO)

	# Act 1 (Ação): Dispara extrapolação forçada (Renderizamos +100ms ALÉM do último pacote)
	var extrapolate_now: int = t + 50 + 100 + buf.render_delay_ms
	var ext_s: Dictionary = buf.sample(extrapolate_now)
	# Velocidade era de 0.0015u/ms. Extrapolou 100ms -> 0.075 + 0.150 = 0.225
	assert_almost_eq(
		ext_s.get("pos", Vector3.ZERO).x,
		0.225,
		0.001,
		"Pre-condicao: Ocorreu extrapolacao",
	)

	# Act 2 (Ação): Finalmente chega o pacote verdadeiro (o pacote real não andou tanto)
	buf.push(t + 100, Vector3(0.1, 0.0, 0.0), Vector3.ZERO) # Pacote diz que ele só estava em 0.1
	buf.push(t + 250, Vector3(0.1, 0.0, 0.0), Vector3.ZERO) # Outro pacote futuro longo

	# Amostra avançando no tempo 30ms APÓS o sample anterior
	var now_2: int = extrapolate_now + 30
	var interp_s: Dictionary = buf.sample(now_2)

	assert_true(
		interp_s.get("pos", Vector3.ZERO).x > 0.101,
		"Error Blending deve evitar que a posicao real (0.1) seja aplicada bruscamente",
	)
	assert_true(
		interp_s.get("pos", Vector3.ZERO).x < 0.225,
		"Error Blending deve decair o erro antigo",
	)
