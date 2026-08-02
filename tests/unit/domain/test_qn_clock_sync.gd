## @file test_qn_clock_sync.gd
## @path res://tests/unit/domain/test_qn_clock_sync.gd
##
## @description
## Testes unitários do QNClockSync utilizando metodologia AAA e framework bitwes/Gut.
## Focado em garantir o cálculo correto de offset de tempo de servidor, estimativa
## de RTT (Round Trip Time) através de janelas móveis (EMA), isolado da engine.
##
## @created 2026-07-29
## @updated 2026-08-01
##
## @since 0.1.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNClockSync = preload("res://addons/quantic_net/src/domain/qn_clock_sync.gd")

func test_converge_para_offset_real_com_jitter() -> void:
	# Arrange (Preparação): Instancia o sincronizador e define um offset alvo de 500ms simulando latência com jitter
	var cs := QNClockSync.new()
	var real_offset := 500.0
	
	# Act (Ação): Alimenta a janela de amostras com pongs artificiais contendo instabilidade de rede
	for i: int in 60:
		var jitter: float = randf_range(0, 40.0)
		var rtt: float = 80.0 + jitter
		var client_sent: int = 100000 + i * 50
		var client_now: int = int(client_sent + rtt)
		# O tempo do servidor quando ele processa o ping (assumindo simetria) é client_sent + offset + rtt/2
		var server_time: int = int(client_sent + real_offset + rtt / 2.0)
		cs.on_pong(client_sent, server_time, client_now)
	
	# Assert (Verificação): Após as amostras preencherem a janela, a estimativa do offset deve estar próxima ao alvo real
	assert_true(cs.is_synced(), "Deve ser considerado sincronizado apos receber amostras validas")
	assert_almost_eq(cs.offset_ms, real_offset, 30.0, "O offset estimado com filtro EMA deve absorver grande parte do jitter da rede")

func test_descarta_rtt_absurdo() -> void:
	# Arrange (Preparação): Um relógio novo e uma situação de lag spike maciça
	var cs := QNClockSync.new()
	
	# Act (Ação): Recebe um pong acusando 6000ms de rtt (enviado em 1000, recebido em 7000)
	cs.on_pong(1000, 1000, 7000)
	
	# Assert (Verificação): A amostra discrepante não deve sequer inicializar o relógio
	assert_false(cs.is_synced(), "Um RTT gigante (>5000ms) deve ser completamente ignorado para proteger a integridade do offset")

func test_server_time_aplica_offset() -> void:
	# Arrange (Preparação): Inicializa um clock sync
	var cs := QNClockSync.new()
	
	# Act (Ação): Alimenta uma primeira amostra. RTT de 80ms, servidor diz que é tempo 5000
	cs.on_pong(1000, 5000, 1080)
	
	# Assert (Verificação): O método server_time deve retornar o ticks_msec atual somado ao offset calculado
	assert_eq(cs.server_time(), int(Time.get_ticks_msec() + cs.offset_ms), "O tempo calculado do servidor deve ser o uptime local mais a defasagem (offset)")

func test_primeiro_pong_inicializa_sem_ema() -> void:
	# Arrange (Preparação): Um novo relógio pronto para o primeiro pacote
	var cs := QNClockSync.new()
	
	# Act (Ação): Recebe o primeiro pacote
	cs.on_pong(1000, 5000, 1080)
	
	# Assert (Verificação): A Média Móvel Exponencial não se aplica na primeira amostra (que é adotada como verdade absoluta momentânea)
	assert_eq(cs.rtt_ms, 80.0, "O primeiro RTT da conexao deve ser adotado diretamente sem suavizacao EMA")

func test_calcula_jitter_baseado_na_variancia_do_rtt() -> void:
	# Arrange (Preparação): Relógio sincronizado com 100ms de RTT inicial
	var cs := QNClockSync.new()
	cs.on_pong(1000, 5000, 1100) # RTT = 100ms
	assert_eq(cs.jitter_ms, 0.0, "O primeiro pacote nao tem variancia anterior, jitter deve ser 0")
	
	# Act (Ação): Simulando um pulo (spike) para RTT = 200ms
	# current_jitter seria |200 - 100| = 100
	# jitter_ms passa a ser lerp(0, 100, 0.2) = 20.0
	cs.on_pong(2000, 5000, 2200)
	
	# Assert (Verificação): O Jitter deve absorver a variação do RTT gradualmente
	assert_almost_eq(cs.jitter_ms, 20.0, 0.1, "O Jitter deve refletir a variancia do RTT utilizando EMA")
