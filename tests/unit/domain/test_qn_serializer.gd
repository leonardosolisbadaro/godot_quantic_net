## @file test_qn_serializer.gd
## @path res://tests/unit/domain/test_qn_serializer.gd
##
## @description
## Testes unitários do QNSerializer utilizando metodologia AAA e framework bitwes/Gut.
## Focado em garantir a quantização de dados em 19 Bytes (Posição, Rotação, Timestamp, etc).
##
## @created 2026-07-29
## @updated 2026-08-08
##
## @since 0.1.0
## @lastModifiedIn 0.6.0
##
## @author Leonardo S. Badaró (Gemini 3.1 Pro - High)

extends GutTest


func test_roundtrip_preserva_valores_dentro_da_precisao() -> void:
	# Arrange (Preparação): Dados de posição e rotação simulados, e a classe alvo
	var pos := Vector3(12.345, 0.5, -45.678)
	var rot := Vector3(0.1, 1.57, -0.5)
	var expected_ts := 987654
	var expected_custom_id := 7
	var seq := 1234

	# Act (Ação): Realiza o encode para bytes e o decode de volta para dicionário
	var b: PackedByteArray = QNSerializer.encode_state_seq(
		seq,
		pos,
		rot,
		expected_ts,
		expected_custom_id,
	)
	var d: Dictionary = QNSerializer.decode_state_seq(b)

	# Assert (Verificação): Valida o tamanho do pacote e a perda aceitável na quantização
	assert_eq(b.size(), 17, "O payload final deve ter exatamente 17 bytes para economia de banda")
	assert_eq(d.get("seq", 0), seq, "A sequencia deve ser mantida")
	assert_almost_eq(
		d.get("pos", Vector3.ZERO).x,
		pos.x,
		0.002,
		"Eixo X da posicao deve estar dentro da margem de erro de quantizacao",
	)
	assert_almost_eq(
		d.get("pos", Vector3.ZERO).y,
		pos.y,
		0.002,
		"Eixo Y da posicao deve estar dentro da margem de erro",
	)
	assert_almost_eq(
		d.get("pos", Vector3.ZERO).z,
		pos.z,
		0.002,
		"Eixo Z da posicao deve estar dentro da margem de erro",
	)
	assert_almost_eq(
		d.get("rot", Vector3.ZERO).y,
		rot.y,
		0.01,
		"Rotacao no eixo Y deve estar preservada com alta precisao via Smallest Three",
	)
	assert_eq(d.get("ts", 0), expected_ts, "O timestamp de envio deve ser integro")
	assert_eq(
		d.get("custom_id", 0),
		expected_custom_id,
		"O identificador customizado deve ser integro",
	)


func test_posicao_fora_do_range_satura_nos_limites() -> void:
	# Arrange (Preparação): Uma posição muito além dos limites suportados pelo quantizador (ex: -64 a 64)
	var pos_out_of_bounds := Vector3(999.0, 0.0, -999.0)

	# Act (Ação): Serializa e deserializa
	var b: PackedByteArray = QNSerializer.encode_state_seq(1, pos_out_of_bounds, Vector3.ZERO, 0, 0)
	var d: Dictionary = QNSerializer.decode_state_seq(b)

	# Assert (Verificação): Os valores devem ser grampeados (clamped) aos extremos permitidos
	assert_almost_eq(
		d.get("pos", Vector3.ZERO).x,
		64.0,
		0.01,
		"Posicao X excedente deve saturar no limite superior",
	)
	assert_almost_eq(
		d.get("pos", Vector3.ZERO).z,
		-64.0,
		0.01,
		"Posicao Z excedente deve saturar no limite inferior",
	)


func test_seq_faz_wrap_em_16_bits() -> void:
	# Arrange (Preparação): Uma sequência acima do limite de 16 bits (65535)
	var high_seq := 65537

	# Act (Ação): Codifica com o overflow
	var b: PackedByteArray = QNSerializer.encode_state_seq(
		high_seq,
		Vector3.ZERO,
		Vector3.ZERO,
		0,
		0,
	)
	var d: Dictionary = QNSerializer.decode_state_seq(b)

	# Assert (Verificação): 65537 em 16 bits deve fazer wrap e virar 1
	assert_eq(d.get("seq", 0), 1, "A sequencia deve sofrer wrap silencioso em limites de 16 bits")


func test_decode_rejeita_payload_curto() -> void:
	# Arrange (Preparação): Um pacote malformado e curto
	var bad_packet := PackedByteArray([1, 2, 3])

	# Act (Ação): Tenta decodificar
	var result: Dictionary = QNSerializer.decode_state_seq(bad_packet)

	# Assert (Verificação): Deve retornar um dicionário vazio falhando silenciosamente
	assert_eq(result.size(), 0, "Dicionario deve ser vazio em caso de payload corrompido")


func test_snapback_usa_mesmo_formato_com_reason_no_custom_id() -> void:
	# Arrange (Preparação): Parametros mock de um snapback (correcao autoritativa do servidor)
	var expected_reason := 2

	# Act (Ação): Faz encode usando a variante especifica de snapback
	var b: PackedByteArray = QNSerializer.encode_snapback(
		9,
		Vector3.ONE,
		Vector3.ZERO,
		42,
		expected_reason,
	)
	var d: Dictionary = QNSerializer.decode_state_seq(b)

	# Assert (Verificação): O reason de snapback transita exatamente no mesmo campo "custom_id"
	assert_eq(
		d.get("custom_id", 0),
		expected_reason,
		"A razao do snapback deve viajar acoplada no campo custom_id",
	)
