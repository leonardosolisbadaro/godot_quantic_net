## @file qn_integration_base.gd
## @path res://tests/integration/helpers/qn_integration_base.gd
##
## @description
## Classe base para testes de integracao do QuanticNet.
## Prove bootstrapping seguro de Autoloads, manipulacao de portas
## e limpeza de estado para evitar vazamentos entre testes (SO_LINGER).
## Nao possui o prefixo 'test_' para nao ser coletada pelo GUT.
##
## @created 2026-07-30
## @updated 2026-07-30
##
## @since 0.2.0
## @lastModifiedIn 0.2.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

const AutoloadScript = preload("res://addons/quantic_net/src/infrastructure/quantic_net_autoload.gd")
const SECRET := "tok-integracao"

var _autoloads := []
static var _port_counter := 47900

func _next_test_port() -> int:
	_port_counter += 1
	return _port_counter

func after_each() -> void:
	for a in _autoloads:
		if is_instance_valid(a):
			# Forca teardown do netem caso algum assert tenha quebrado no meio do teste
			if a._wire:
				a._wire.netem_enabled = false
			remove_child(a)
			a.free()
	_autoloads.clear()
	_cleanup_certs()

func _spawn_autoload() -> Node:
	var a: Node = AutoloadScript.new()
	add_child(a)
	_autoloads.append(a)
	return a

func _cleanup_certs() -> void:
	for p in ["user://qnet_cert.crt", "user://qnet_cert.key"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
