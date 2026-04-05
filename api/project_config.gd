@tool
class_name ProjectConfig
extends RefCounted

const Internal = preload("../src/config/project_config_impl.gd")

static func add_input_action(action_name: String, events: Array) -> Dictionary:
	return Internal.add_input_action(action_name, events)

static func remove_input_action(action_name: String) -> Dictionary:
	return Internal.remove_input_action(action_name)

static func get_input_actions() -> Dictionary:
	return Internal.get_input_actions()

static func set_layer_name(layer_type: String, layer_number: int, name: String) -> Dictionary:
	return Internal.set_layer_name(layer_type, layer_number, name)

static func get_layer_names(layer_type: String) -> Dictionary:
	return Internal.get_layer_names(layer_type)

static func add_autoload(name: String, path: String) -> Dictionary:
	return Internal.add_autoload(name, path)

static func remove_autoload(name: String) -> Dictionary:
	return Internal.remove_autoload(name)

static func get_autoloads() -> Dictionary:
	return Internal.get_autoloads()

static func set_setting(key: String, value: Variant) -> Dictionary:
	return Internal.set_setting(key, value)

static func get_setting(key: String) -> Dictionary:
	return Internal.get_setting(key)
