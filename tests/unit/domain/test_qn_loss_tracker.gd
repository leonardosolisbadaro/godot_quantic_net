## @file test_qn_loss_tracker.gd
## @path res://tests/unit/domain/test_qn_loss_tracker.gd
##
## @description
## Testes unitários do QNLossTracker utilizando metodologia AAA e framework bitwes/Gut.
## Focado em garantir a detecção precisa de perda de pacotes por gaps de sequência,
## suportando wrap-around de 16-bits e calculando média móvel de perda recente.
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends GutTest


func test_sem_gaps_reporta_zero_perda() -> void:
	# Arrange (Preparação): Instancia um novo medidor de perda
	var t := QNLossTracker.new()

	# Act (Ação): Alimenta o tracker com 50 pacotes perfeitamente sequenciais
	for i: int in 50:
		t.on_packet(i)

	# Assert (Verificação): O percentual de perda deve ser 0% e o contador de recebidos exato
	assert_eq(t.loss_pct(), 0.0, "Sequencia perfeita deve resultar em 0% de perda")
	assert_eq(
		t.received,
		50,
		"Todos os pacotes sequenciais devem ser contabilizados como recebidos",
	)


func test_gap_conta_perdidos() -> void:
	# Arrange (Preparação): Inicializa o tracker
	var t := QNLossTracker.new()

	# Act (Ação): Simula o recebimento do pacote 0, sofre perda massiva de rede, e recebe o pacote 5
	t.on_packet(0)
	t.on_packet(5)

	# Assert (Verificação): O pulo de 0 para 5 significa que os pacotes 1, 2, 3 e 4 (total 4) foram perdidos
	assert_eq(t.lost, 4, "Um salto de 0 para 5 deve inferir 4 pacotes perdidos")
	assert_eq(t.received, 2, "Apenas os 2 pacotes que chegaram de fato contam como recebidos")


func test_pacote_duplicado_ou_atrasado_ignorado() -> void:
	# Arrange (Preparação): Inicializa o tracker
	var t := QNLossTracker.new()

	# Act (Ação): Recebe o pacote 10. Em seguida, recebe outro 10 (duplicado) e um 5 (atrasado)
	t.on_packet(10)
	t.on_packet(10)
	t.on_packet(5)

	# Assert (Verificação): Pacotes antigos ou duplicados devem ser descartados sem interferir nos contadores
	assert_eq(
		t.received,
		1,
		"Pacotes duplicados e atrasados nao contabilizam como novos recebimentos",
	)
	assert_eq(t.lost, 0, "Pacotes atrasados nao devem incrementar perdas retroativas")


func test_wrap_16bit_nao_conta_perda_falsa() -> void:
	# Arrange (Preparação): Tracker rodando próximo ao limite do uint16
	var t := QNLossTracker.new()

	# Act (Ação): Envia pacotes no limite e logo após o overflow
	t.on_packet(65534)
	t.on_packet(65535)
	t.on_packet(0)

	# Assert (Verificação): O tracker deve reconhecer que o 0 vem logicamente depois do 65535 em 16 bits sem inferir perdas irreais
	assert_eq(
		t.lost,
		0,
		"O wrap-around de 16-bits (65535 -> 0) nao pode ser tratado como perda ou atraso",
	)
	assert_eq(t.received, 3, "Os pacotes da virada devem ser recebidos normalmente")


func test_loss_pct_reflete_janela_recente() -> void:
	# Arrange (Preparação): Tracker zerado
	var t := QNLossTracker.new()

	# Act (Ação): Recebe o 0 e salta para o 4. Isso preenche a janela com: [True, False, False, False, True]
	t.on_packet(0)
	t.on_packet(4)

	# Assert (Verificação): (3 perdas / 5 amostras totais) * 100 = 60%
	var pct: float = t.loss_pct()
	assert_almost_eq(
		pct,
		60.0,
		0.1,
		"3 pacotes perdidos em um total de 5 pacotes na janela significa 60% de perda",
	)
