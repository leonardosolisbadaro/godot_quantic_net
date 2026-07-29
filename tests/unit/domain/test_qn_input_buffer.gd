## @file test_qn_input_buffer.gd
## @path res://tests/unit/domain/test_qn_input_buffer.gd
##
## @description
## Testes unitários do QNInputBuffer utilizando metodologia AAA e framework bitwes/Gut.
## Focado em garantir o armazenamento seguro de inputs locais e a drenagem (reconciliação)
## a partir de confirmações do servidor, suportando wrap-around de 16-bits.
##
## @created 2026-07-29
## @updated 2026-07-29
##
## @since 0.1.0
## @lastModifiedIn 0.1.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNInputBuffer = preload("res://addons/quantic_net/src/domain/qn_input_buffer.gd")

func test_drain_remove_confirmados_e_retorna_pendentes() -> void:
	# Arrange (Preparação): Instancia o buffer
	var buf := QNInputBuffer.new()
	
	# Act (Ação): Alimenta com 5 inputs locais (seq 0 a 4)
	for seq: int in 5:
		buf.record(seq, Vector2.ONE, 0.0, 0.05)
	
	# Simula que o servidor confirmou (snapback) até a sequence 2. Drena o buffer a partir dela.
	var replay: Array[Dictionary] = buf.drain_after(2)
	
	# Assert (Verificação): O buffer deve limpar do 0 ao 2, restando apenas o 3 e 4 para re-predição
	assert_eq(replay.size(), 2, "Devem sobrar apenas as sequencias 3 e 4 para repredicao")
	assert_eq(buf.size(), 2, "O tamanho do buffer interno deve estar sincronizado")
	assert_eq(replay[0]["seq"], 3, "O primeiro pendente obrigatoriamente e o logo apos o confirmado")
	assert_eq(replay[1]["seq"], 4, "A ordem cronologica deve ser respeitada")

func test_drain_com_wrap_around_limpa_corretamente() -> void:
	# Arrange (Preparação): Instancia o buffer na virada do uint16 (wrap-around)
	var buf := QNInputBuffer.new()
	
	# Act (Ação): Adiciona as sequências do fim e do reinício do contador
	buf.record(65534, Vector2.ZERO, 0.0, 0.05)
	buf.record(65535, Vector2.ZERO, 0.0, 0.05)
	buf.record(0, Vector2.ZERO, 0.0, 0.05)
	buf.record(1, Vector2.ZERO, 0.0, 0.05)
	
	# O servidor confirma ter recebido até a seq 0.
	var replay: Array[Dictionary] = buf.drain_after(0)
	
	# Assert (Verificação): Deve drenar 65534, 65535 e 0. Restando apenas a 1.
	assert_eq(replay.size(), 1, "Wrap-around (65535 -> 0) deve ser tolerado matematicamente na comparacao")
	assert_eq(replay[0]["seq"], 1, "Somente a sequence 1 eh estritamente posterior a 0 no wrap-around")

func test_drain_com_seq_alem_de_todos_esvazia() -> void:
	# Arrange (Preparação): Instancia buffer com dois pacotes antigos
	var buf := QNInputBuffer.new()
	buf.record(1, Vector2.ZERO, 0.0, 0.05)
	buf.record(2, Vector2.ZERO, 0.0, 0.05)
	
	# Act (Ação): O servidor confirma uma seq absurda lá no futuro
	var replay: Array[Dictionary] = buf.drain_after(99)
	
	# Assert (Verificação): A lista de pendentes devolvida deve ser vazia e o buffer resetado
	assert_eq(replay.size(), 0, "Nenhum pendente sobrevive se o servidor confirmar pacote futuro")
	assert_eq(buf.size(), 0, "O buffer de inputs interno deve estar zerado")

func test_cap_descarta_mais_antigos() -> void:
	# Arrange (Preparação): Instancia buffer e tenta sobrecarregar sua memória
	var buf := QNInputBuffer.new()
	
	# Act (Ação): Injeta 10 pacotes acima do limite máximo permitido
	for seq: int in (QNInputBuffer.MAX_PENDING + 10):
		buf.record(seq, Vector2.ZERO, 0.0, 0.05)
		
	# Assert (Verificação): O tamanho precisa travar no MAX_PENDING, dropando os velhos em favor dos novos
	assert_eq(buf.size(), QNInputBuffer.MAX_PENDING, "Nao deve exceder o limite de alocação de memória")
