@tool
class_name EditorOps
extends RefCounted

const Internal = preload("../src/editor/editor_ops_impl.gd")

static func get_editor_logs(options: Dictionary = {}) -> Dictionary:
	return Internal.get_editor_logs(options)

static func get_log_timestamp() -> Dictionary:
	return Internal.get_log_timestamp()

static func run_scene(scene_path: String = "") -> Dictionary:
	return Internal.run_scene(scene_path)

static func stop_scene() -> Dictionary:
	return Internal.stop_scene()

static func open_scene(scene_path: String) -> Dictionary:
	return Internal.open_scene(scene_path)

static func open_script(script_path: String, line: int = -1) -> Dictionary:
	return Internal.open_script(script_path, line)

static func refresh_filesystem() -> Dictionary:
	return Internal.refresh_filesystem()

static func get_open_scenes() -> Dictionary:
	return Internal.get_open_scenes()

static func get_project_info() -> Dictionary:
	return Internal.get_project_info()
