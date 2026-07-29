@tool
extends EditorPlugin

const AUTOLOAD_NAME = "QuanticNet"
const AUTOLOAD_PATH = "res://addons/quantic_net/src/infrastructure/quantic_net_autoload.gd"

func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)
