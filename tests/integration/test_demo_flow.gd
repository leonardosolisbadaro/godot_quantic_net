## @file test_demo_flow.gd
## @path tests/integration/test_demo_flow.gd
##
## @description
## Teste de integração E2E verificando a instanciação Code-First da cena de demonstração.
## O System Under Test (SUT) é o main.gd que levanta a UI, os jogadores e a comunicação com QuanticNet.
##
## @created 2026-07-30
## @updated 2026-07-30
##
## @since 0.2.0
## @lastModifiedIn 0.2.0
##
## @author Leonardo S. Badaró (with Kimi k3 - Thinking & Gemini 3.1 Pro - High)

extends GutTest

var _sut: Node

func before_each() -> void:
	# Limpa instâncias QuanticNet
	if QuanticNet.has_node("QNNetHook"):
		QuanticNet.get_node("QNNetHook").queue_free()
	
	# Reset MultiplayerAPI
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()

	# Arrange
	# Instancia o SUT diretamente do script
	_sut = preload("res://demo/main.gd").new()
	_sut.name = "DemoMain"
	add_child(_sut)

func after_each() -> void:
	if is_instance_valid(_sut):
		_sut.queue_free()
	
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
	
	await wait_frames(2)

func test_must_build_ui_and_world_procedurally() -> void:
	# Act (O _ready já foi chamado ao ser adicionado à arvore)
	
	# Assert: Garante que os canvas e botões foram gerados via código
	var ui = _sut.get_node_or_null("UI/VBoxContainer")
	assert_not_null(ui, "SUT deveria ter gerado a UI via Code-First")
	
	var host_btn = ui.get_node_or_null("HostButton")
	assert_not_null(host_btn, "SUT deveria ter gerado o botão de Host")
	
	var join_btn = ui.get_node_or_null("JoinButton")
	assert_not_null(join_btn, "SUT deveria ter gerado o botão de Join")
	
	var world = _sut.get_node_or_null("World")
	assert_not_null(world, "SUT deveria ter gerado o Node3D do Mundo")
	
	var ground = world.get_node_or_null("Ground")
	assert_not_null(ground, "SUT deveria ter gerado a malha de chão (Ground)")

func test_must_spawn_local_player_when_hosting() -> void:
	# Arrange
	var ui = _sut.get_node("UI/VBoxContainer")
	var host_btn = ui.get_node("HostButton")
	_sut.PORT = 9991
	
	# Act
	host_btn.pressed.emit()
	
	# Assert
	var local_id = multiplayer.get_unique_id()
	var player = _sut.get_node_or_null("World/" + str(local_id))
	assert_not_null(player, "Deve instanciar um player local com o nome igual ao peer id")
	assert_true(player is CharacterBody3D, "O player local deve ser um CharacterBody3D para colisão/predição")
	
	# Cleanup
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()

func test_must_spawn_remote_player_on_peer_connected_signal() -> void:
	# Arrange: Host simulado
	var ui = _sut.get_node("UI/VBoxContainer")
	var host_btn = ui.get_node("HostButton")
	_sut.PORT = 9992
	host_btn.pressed.emit()
	
	var fake_remote_id = 12345
	
	# Act: Simular que um peer distante conectou disparando o sinal global do Singleton
	QuanticNet.peer_joined.emit(fake_remote_id)
	
	# Assert
	var remote_player = _sut.get_node_or_null("World/" + str(fake_remote_id))
	assert_not_null(remote_player, "Deve instanciar um remote player quando o sinal peer_joined for emitido")
	
	get_tree().get_multiplayer().multiplayer_peer = OfflineMultiplayerPeer.new()
