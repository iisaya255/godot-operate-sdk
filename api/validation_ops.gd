@tool
class_name ValidationOps
extends RefCounted

const Internal = preload("../src/validation/validation_ops_impl.gd")

static func validate_scene(scene_path: String) -> Dictionary:
	return Internal.validate_scene(scene_path)

static func validate_resources(scene_path: String) -> Dictionary:
	return Internal.validate_resources(scene_path)

static func validate_script_references(scene_path: String) -> Dictionary:
	return Internal.validate_script_references(scene_path)

static func validate_all(scene_path: String) -> Dictionary:
	return Internal.validate_all(scene_path)
