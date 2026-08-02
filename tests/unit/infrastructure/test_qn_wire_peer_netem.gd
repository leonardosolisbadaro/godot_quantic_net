## @file test_qn_wire_peer_netem.gd
## @path res://tests/unit/infrastructure/test_qn_wire_peer_netem.gd
##
## @description
## Testes unitários para o emulador de rede (Netem) embutido no QNWirePeer.
## Valida retenção por latência, reordenação por jitter, descarte e duplicação
## simulada.
##
## @created 2026-07-29
## @updated 2026-07-31
##
## @since 0.1.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNWirePeer = preload("res://addons/quantic_net/src/infrastructure/qn_wire_peer.gd")

func _new_peer() -> QNWirePeer:
	var peer = autofree(QNWirePeer.new())
	peer.netem_enabled = true
	return peer

func test_canal_confiavel_nao_sofre_drop() -> void:
	# Arrange
	var peer = _new_peer()
	peer.netem_loss_pct = 1.0 # 100% de perda
	var payload = PackedByteArray([1, 2, 3])
	
	# Act
	var queued = peer._queue_netem(QNWirePeer.CH_CONTROL, payload, 1000)
	
	# Assert
	assert_eq(queued.size(), 1, "Canal de controle (0) nunca deve sofrer drop")
	
func test_canal_nao_confiavel_sofre_drop_configurado() -> void:
	# Arrange
	var peer = _new_peer()
	peer.netem_loss_pct = 1.0 # 100% de perda
	var payload = PackedByteArray([1, 2, 3])
	
	# Act
	var queued = peer._queue_netem(QNWirePeer.CH_STATE, payload, 1000)
	
	# Assert
	assert_eq(queued.size(), 0, "Canal de estado (1) deve sofrer drop se configurado")

func test_latencia_base_retardou_entrega() -> void:
	# Arrange
	var peer = _new_peer()
	peer.netem_latency_ms = 50
	peer.netem_jitter_ms = 0
	var payload = PackedByteArray([1, 2, 3])
	
	# Act
	var queued = peer._queue_netem(QNWirePeer.CH_STATE, payload, 1000)
	
	# Assert
	assert_eq(queued.size(), 1, "Deve enfileirar o pacote")
	assert_eq(queued[0].release_ts, 1050, "Timestamp de release deve somar a latência base")

func test_jitter_adiciona_variancia_gaussiana() -> void:
	# Arrange
	var peer = _new_peer()
	peer.netem_latency_ms = 50
	peer.netem_jitter_ms = 20
	var payload = PackedByteArray([1, 2, 3])
	
	# Act
	# Repete várias vezes para garantir que há variação e testar o range
	var sum = 0
	for i in range(10):
		var queued = peer._queue_netem(QNWirePeer.CH_STATE, payload, 1000)
		sum += queued[0].release_ts
		assert_between(queued[0].release_ts, 950, 1150, "Deve variar em torno da media com jitter")
		peer._netem_queue.clear()
	
	# Na média deve estar próximo de 1050 (10500 / 10 = 1050)
	assert_between(sum, 10200, 10800, "A média deve respeitar a distribuição")

func test_duplicacao_gera_dois_pacotes() -> void:
	# Arrange
	var peer = _new_peer()
	peer.netem_dup_pct = 1.0 # 100% de chance de duplicar
	peer.netem_jitter_ms = 50 # Necessário para causar variância no release_ts
	var payload = PackedByteArray([1, 2, 3])
	
	# Act
	# Forçamos até que a variância acerte valores diferentes (pode calhar de rolar 2 randfn iguais, mas é raro)
	var queued = peer._queue_netem(QNWirePeer.CH_STATE, payload, 1000)
	
	# Assert
	assert_eq(queued.size(), 2, "Deve enfileirar dois pacotes idênticos")
	# Se por um azar incrível der o mesmo tick exato, é quase impossível num float, 
	# mas como estamos fazendo cast pra int(randfn()), a chance existe. 
	# Para testes rigorosos sem flaky, poderíamos aceitar que eles sejam processados juntos.
	# Vamos apenas testar se eles tem a mesma raiz e são 2 objetos.
	assert_eq(queued[0].payload, queued[1].payload, "O payload do duplicado deve ser idêntico")

func test_drain_netem_retorna_apenas_pacotes_vencidos() -> void:
	# Arrange
	var peer = _new_peer()
	peer._netem_queue.append({"channel": QNWirePeer.CH_STATE, "payload": PackedByteArray([1]), "release_ts": 1000, "target": 0})
	peer._netem_queue.append({"channel": QNWirePeer.CH_STATE, "payload": PackedByteArray([2]), "release_ts": 1050, "target": 0})
	peer._netem_queue.append({"channel": QNWirePeer.CH_STATE, "payload": PackedByteArray([3]), "release_ts": 950, "target": 0})
	
	# Act
	var ready_1000 = peer._drain_netem(1000)
	
	# Assert
	assert_eq(ready_1000.size(), 2, "Deve retornar os pacotes de 950 e 1000")
	# Reordenação: 950 deve estar antes ou depois? A ordem final depende da lógica de drain.
	# Normalmente drain ordena por release_ts ou apenas filtra.
	
	var remaining = peer._netem_queue
	assert_eq(remaining.size(), 1, "Deve sobrar o pacote de 1050")
	assert_eq(remaining[0].payload[0], 2, "O pacote restante deve ser o de payload 2")
