@tool
class_name SceneOps
extends RefCounted

const Internal = preload("../src/scene/scene_ops_impl.gd")

static func create_scene_from_json(json: Dictionary) -> Dictionary:
	return Internal.create_scene_from_json(json)

static func scene_to_json(scene_path: String) -> Dictionary:
	return Internal.scene_to_json(scene_path)

static func resave_scene(scene_path: String) -> Dictionary:
	return Internal.resave_scene(scene_path)

static func add_node(scene_path: String, parent_path: String, node_json: Dictionary) -> Dictionary:
	return Internal.add_node(scene_path, parent_path, node_json)

static func remove_node(scene_path: String, node_path: String) -> Dictionary:
	return Internal.remove_node(scene_path, node_path)

static func update_node(scene_path: String, node_path: String, properties: Dictionary) -> Dictionary:
	return Internal.update_node(scene_path, node_path, properties)

static func move_node(scene_path: String, node_path: String, new_parent: String) -> Dictionary:
	return Internal.move_node(scene_path, node_path, new_parent)

static func get_node_info(scene_path: String, node_path: String) -> Dictionary:
	return Internal.get_node_info(scene_path, node_path)

static func list_nodes(scene_path: String) -> Dictionary:
	return Internal.list_nodes(scene_path)

static func find_nodes_by_type(scene_path: String, type_name: String) -> Dictionary:
	return Internal.find_nodes_by_type(scene_path, type_name)
