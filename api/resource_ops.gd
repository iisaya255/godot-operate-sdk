@tool
class_name ResourceOps
extends RefCounted

const Internal = preload("../src/resource/resource_ops_impl.gd")

static func bind_resource(scene_path: String, node_path: String, property: String, resource_path: String) -> Dictionary:
	return Internal.bind_resource(scene_path, node_path, property, resource_path)

static func unbind_resource(scene_path: String, node_path: String, property: String) -> Dictionary:
	return Internal.unbind_resource(scene_path, node_path, property)

static func batch_bind(scene_path: String, bindings: Array) -> Dictionary:
	return Internal.batch_bind(scene_path, bindings)

static func export_mesh_library(scene_path: String, output_path: String, mesh_item_names: Array = []) -> Dictionary:
	return Internal.export_mesh_library(scene_path, output_path, mesh_item_names)

static func get_node_resources(scene_path: String, node_path: String) -> Dictionary:
	return Internal.get_node_resources(scene_path, node_path)

static func get_scene_resources(scene_path: String) -> Dictionary:
	return Internal.get_scene_resources(scene_path)

static func get_uid(file_path: String) -> Dictionary:
	return Internal.get_uid(file_path)

static func update_project_uids(project_path: String = "res://") -> Dictionary:
	return Internal.update_project_uids(project_path)
