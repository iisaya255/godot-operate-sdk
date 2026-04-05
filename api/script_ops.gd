@tool
class_name ScriptOps
extends RefCounted

const Internal = preload("../src/script/script_ops_impl.gd")

static func create_script(path: String, content: String, base_type: String = "") -> Dictionary:
	return Internal.create_script(path, content, base_type)

static func read_script(path: String) -> Dictionary:
	return Internal.read_script(path)

static func update_script(path: String, content: String) -> Dictionary:
	return Internal.update_script(path, content)

static func delete_script(path: String) -> Dictionary:
	return Internal.delete_script(path)

static func update_script_function(path: String, function_name: String, new_function_content: String) -> Dictionary:
	return Internal.update_script_function(path, function_name, new_function_content)

static func update_script_range(path: String, start_line: int, end_line: int, new_content: String) -> Dictionary:
	return Internal.update_script_range(path, start_line, end_line, new_content)

static func attach_script(scene_path: String, node_path: String, script_path: String) -> Dictionary:
	return Internal.attach_script(scene_path, node_path, script_path)

static func detach_script(scene_path: String, node_path: String) -> Dictionary:
	return Internal.detach_script(scene_path, node_path)

static func compile_check(path: String) -> Dictionary:
	return Internal.compile_check(path)

static func get_script_structure(path: String) -> Dictionary:
	return Internal.get_script_structure(path)
