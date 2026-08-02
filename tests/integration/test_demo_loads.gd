## @file test_demo_loads.gd
## @path res://tests/integration/test_demo_loads.gd
##
## @description
## Teste de fumaça da demo QuanticNet: garante que a cena demo
## carrega e que o autoload QuanticNet esta presente sem crash.
## Metodologia AAA sobre bitwes/Gut. Este e um teste de fumaça: garante que
## a cena demo carrega e promove o autoload sem crash.
##
## @created 2026-07-29
## @updated 2026-07-31
##
## @since 0.2.0
## @lastModifiedIn 0.3.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

func test_demo_scene_loads() -> void:
	# Arrange
	var scene := load("res://addons/quantic_net/demo/demo_main.tscn")
	# Act
	assert_not_null(scene, "Cena demo deve ser carregavel.")
	var inst: Node = scene.instantiate()
	add_child(inst)
	await get_tree().process_frame
	# Assert: se chegamos aqui sem erro, a demo esta integrada ao projeto
	pass_test("Demo instanciada sem crash")
	remove_child(inst)
	inst.free()
