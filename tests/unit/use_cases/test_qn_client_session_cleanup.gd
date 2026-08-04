## @file test_qn_client_session_cleanup.gd
## @path tests/unit/use_cases/test_qn_client_session_cleanup.gd
##
## @description
## Testes unitários para garantir que o cliente consiga limpar buffers antigos
## de interpolação e perda de pacotes quando uma entidade é desregistrada pelo servidor.
##
## @created 2026-08-04
## @updated 2026-08-04
##
## @since 0.3.0
## @lastModifiedIn 0.3.0-rc.3
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const QNClientSession = preload("res://addons/quantic_net/src/use_cases/qn_client_session.gd")

var sut: QNClientSession
var _submitted: Array

func _submit(to: int, pkt: PackedByteArray, ch: int, mode: int) -> void:
	_submitted.append({"to": to, "pkt": pkt, "ch": ch, "mode": mode})

func before_each():
	_submitted.clear()
	sut = QNClientSession.new(Callable(self, "_submit"))
	sut.set_local_id(2)

func _state_from(owner: int, seq: int, pos: Vector3, ts: int) -> PackedByteArray:
	var QNSerializer = preload("res://addons/quantic_net/src/domain/qn_serializer.gd")
	var pkt := PackedByteArray([QNSerializer.TYPE_STATE])
	pkt.resize(5)
	pkt.encode_u32(1, owner)
	pkt.append_array(QNSerializer.encode_state_seq(seq, pos, Vector3.ZERO, ts, 0))
	return pkt

func test_must_cleanup_entity_when_requested():
	# Arrange: Alimentar pacotes artificiais de um prop na sessão
	var owner = 1000
	var now = Time.get_ticks_msec()
	
	sut.handle_packet(_state_from(owner, 1, Vector3.ZERO, now - 100), now - 100)
	sut.handle_packet(_state_from(owner, 2, Vector3.ZERO, now), now)
	
	# Verify that the interpolator holds the state
	assert_true(sut._interp.has(owner), "A entidade deve ter sido alocada no dicionário.")
	
	# Act: Limpar a entidade
	sut.cleanup_entity(owner)
	
	# Assert: A entidade não deve mais existir na interpolação
	assert_false(sut._interp.has(owner), "A entidade deve ter sido apagada dos buffers.")
