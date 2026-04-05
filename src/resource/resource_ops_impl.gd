@tool
extends RefCounted
## Resource operations implementation

const Result = preload("../core/sdk_result.gd")
const PathUtils = preload("../core/sdk_path_utils.gd")
const FileWriter = preload("../core/sdk_file_writer.gd")


static func _load_scene(scene_path: String) -> Variant:
	scene_path = PathUtils.normalize_res_path(scene_path)
	if not ResourceLoader.exists(scene_path):
		return Result.err("Scene not found: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var packed = load(scene_path)
	if not (packed is PackedScene):
		return Result.err("Not a PackedScene: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var root = packed.instantiate()
	if root == null:
		return Result.err("Failed to instantiate scene: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	return root


static func _find_node(root: Node, node_path: String) -> Node:
	if node_path == "." or node_path == "":
		return root
	return root.get_node_or_null(node_path)


static func _get_property_info(node: Node, property: String) -> Dictionary:
	for prop_info in node.get_property_list():
		if str(prop_info.name) == property:
			return prop_info
	return {}


static func _get_expected_resource_type(prop_info: Dictionary) -> String:
	var expected_type := str(prop_info.get("class_name", ""))
	if expected_type.is_empty() and int(prop_info.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_RESOURCE_TYPE:
		expected_type = str(prop_info.get("hint_string", ""))
	return expected_type


static func _validate_resource_property(node: Node, property: String) -> Dictionary:
	var prop_info := _get_property_info(node, property)
	if prop_info.is_empty():
		return Result.err(
			"Property not found on %s: %s" % [node.get_class(), property],
			"ERR_PROPERTY_NOT_FOUND",
			{"node_class": node.get_class(), "property": property}
		)

	if int(prop_info.get("type", TYPE_NIL)) != TYPE_OBJECT:
		return Result.err(
			"Property '%s' on %s does not accept resources" % [property, node.get_class()],
			"ERR_INVALID_PROPERTY",
			{"node_class": node.get_class(), "property": property}
		)

	var expected_type := _get_expected_resource_type(prop_info)
	if not expected_type.is_empty() and expected_type != "Resource" and ClassDB.class_exists(expected_type):
		if not ClassDB.is_parent_class(expected_type, "Resource"):
			return Result.err(
				"Property '%s' on %s does not accept resources" % [property, node.get_class()],
				"ERR_INVALID_PROPERTY",
				{"node_class": node.get_class(), "property": property}
			)

	return Result.ok({"expected_type": expected_type})


static func _check_type_compatibility(expected_type: String, resource: Resource) -> bool:
	if expected_type.is_empty() or expected_type == "Resource":
		return true
	if resource.is_class(expected_type):
		return true
	if ClassDB.class_exists(expected_type):
		return ClassDB.is_parent_class(resource.get_class(), expected_type)
	return true


static func _collect_resource_props(node: Node) -> Array:
	var results: Array = []
	for prop in node.get_property_list():
		if prop.type == TYPE_OBJECT and prop.hint == PROPERTY_HINT_RESOURCE_TYPE:
			var val = node.get(prop.name)
			if val is Resource:
				var rpath: String = val.resource_path
				results.append({
					"property": prop.name,
					"resource_path": rpath,
					"resource_type": val.get_class(),
				})
	return results


static func _collect_scene_resources_recursive(node: Node, parent_path: String, results: Array) -> void:
	var node_path: String = node.name if parent_path.is_empty() else parent_path + "/" + node.name
	for prop in node.get_property_list():
		if prop.type == TYPE_OBJECT and prop.hint == PROPERTY_HINT_RESOURCE_TYPE:
			var val = node.get(prop.name)
			if val is Resource:
				var rpath: String = val.resource_path
				results.append({
					"node": node_path,
					"property": prop.name,
					"resource_path": rpath,
					"resource_type": val.get_class(),
					"inline": rpath.is_empty(),
				})
	for i in node.get_child_count():
		_collect_scene_resources_recursive(node.get_child(i), node_path, results)


static func bind_resource(scene_path: String, node_path: String, property: String, resource_path: String) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var node: Node = _find_node(root, node_path)
	if node == null:
		root.queue_free()
		return Result.err("Node not found: %s" % node_path, "ERR_NODE_NOT_FOUND")

	resource_path = PathUtils.normalize_res_path(resource_path)
	if not ResourceLoader.exists(resource_path):
		root.queue_free()
		return Result.err("Resource not found: %s" % resource_path, "ERR_RESOURCE_NOT_FOUND")

	var resource = load(resource_path)
	if resource == null:
		root.queue_free()
		return Result.err("Failed to load resource: %s" % resource_path, "ERR_RESOURCE_NOT_FOUND")

	var property_result := _validate_resource_property(node, property)
	if not property_result.get("ok", false):
		root.queue_free()
		return property_result

	var expected_type: String = property_result.get("data", {}).get("expected_type", "")
	if not _check_type_compatibility(expected_type, resource):
		root.queue_free()
		return Result.err(
			"Type mismatch: %s is not compatible with property '%s'" % [resource.get_class(), property],
			"ERR_TYPE_MISMATCH",
			{"node": node.name, "property": property, "resource_type": resource.get_class(), "expected_type": expected_type}
		)

	node.set(property, resource)
	var node_name: String = node.name
	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.queue_free()

	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Save failed"), "ERR_SCENE_LOAD_FAILED")

	return Result.ok({"node": node_name, "property": property, "resource": resource_path})


static func unbind_resource(scene_path: String, node_path: String, property: String) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var node: Node = _find_node(root, node_path)
	if node == null:
		root.queue_free()
		return Result.err("Node not found: %s" % node_path, "ERR_NODE_NOT_FOUND")

	var property_result := _validate_resource_property(node, property)
	if not property_result.get("ok", false):
		root.queue_free()
		return property_result

	node.set(property, null)
	var node_name: String = node.name
	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.queue_free()

	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Save failed"), "ERR_SCENE_LOAD_FAILED")

	return Result.ok({"node": node_name, "property": property})


static func batch_bind(scene_path: String, bindings: Array) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var bound_count := 0
	var results: Array = []

	for binding in bindings:
		var np: String = binding.get("node_path", ".")
		var prop: String = binding.get("property", "")
		var rpath: String = PathUtils.normalize_res_path(binding.get("resource_path", ""))

		var node: Node = _find_node(root, np)
		if node == null:
			results.append({"node_path": np, "property": prop, "ok": false, "error": "Node not found"})
			continue

		if not ResourceLoader.exists(rpath):
			results.append({"node_path": np, "property": prop, "ok": false, "error": "Resource not found"})
			continue

		var resource = load(rpath)
		if resource == null:
			results.append({"node_path": np, "property": prop, "ok": false, "error": "Failed to load resource"})
			continue

		var property_result := _validate_resource_property(node, prop)
		if not property_result.get("ok", false):
			results.append({
				"node_path": np,
				"property": prop,
				"ok": false,
				"error": property_result.get("error", "Invalid property"),
				"code": property_result.get("code", "")
			})
			continue

		var expected_type: String = property_result.get("data", {}).get("expected_type", "")
		if not _check_type_compatibility(expected_type, resource):
			results.append({"node_path": np, "property": prop, "ok": false, "error": "Type mismatch", "code": "ERR_TYPE_MISMATCH"})
			continue

		node.set(prop, resource)
		bound_count += 1
		results.append({"node_path": np, "property": prop, "ok": true})

	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.queue_free()

	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Save failed"), "ERR_SCENE_LOAD_FAILED")

	return Result.ok({"bound": bound_count, "results": results})


static func export_mesh_library(scene_path: String, output_path: String, mesh_item_names: Array = []) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	scene_path = PathUtils.normalize_res_path(scene_path)
	output_path = PathUtils.normalize_res_path(output_path)

	var mesh_library := MeshLibrary.new()
	var use_specific_items := mesh_item_names.size() > 0
	var item_count := 0

	for child in root.get_children():
		var item_name := str(child.name)
		if use_specific_items and not (item_name in mesh_item_names):
			continue

		var mesh_data := _find_first_mesh_instance(child)
		if mesh_data.is_empty():
			continue

		var mesh_instance: MeshInstance3D = mesh_data["node"]
		if mesh_instance.mesh == null:
			continue

		mesh_library.create_item(item_count)
		mesh_library.set_item_name(item_count, item_name)
		mesh_library.set_item_mesh(item_count, mesh_instance.mesh)

		var mesh_transform: Transform3D = mesh_data.get("transform", Transform3D.IDENTITY)
		if mesh_transform != Transform3D.IDENTITY:
			mesh_library.set_item_mesh_transform(item_count, mesh_transform)

		var collision_shapes := _collect_collision_shapes(child)
		if collision_shapes.size() > 0:
			mesh_library.set_item_shapes(item_count, collision_shapes)

		item_count += 1

	root.queue_free()

	if item_count == 0:
		return Result.err("No valid meshes found in scene: %s" % scene_path, "ERR_NOT_FOUND")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var err := ResourceSaver.save(mesh_library, output_path)
	if err != OK:
		return Result.err("Failed to save MeshLibrary: %d" % err, "ERR_WRITE_FAILED")

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(output_path)
		EditorInterface.get_resource_filesystem().scan()

	return Result.ok({
		"scene_path": scene_path,
		"output_path": output_path,
		"item_count": item_count,
	})


static func get_node_resources(scene_path: String, node_path: String) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var node: Node = _find_node(root, node_path)
	if node == null:
		root.queue_free()
		return Result.err("Node not found: %s" % node_path, "ERR_NODE_NOT_FOUND")

	var node_name: String = node.name
	var resources := _collect_resource_props(node)
	root.queue_free()

	return Result.ok({"node": node_name, "resources": resources})


static func get_scene_resources(scene_path: String) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var resources: Array = []
	_collect_scene_resources_recursive(root, "", resources)
	root.queue_free()

	return Result.ok({"resources": resources})


static func get_uid(file_path: String) -> Dictionary:
	file_path = PathUtils.normalize_res_path(file_path)
	if not FileAccess.file_exists(file_path):
		return Result.err("File not found: %s" % file_path, "ERR_FILE_NOT_FOUND")

	var uid_path := file_path + ".uid"
	var absolute_path := ProjectSettings.globalize_path(file_path)

	if not FileAccess.file_exists(uid_path):
		return Result.ok({
			"file": file_path,
			"absolute_path": absolute_path,
			"exists": false,
			"message": "UID file does not exist for this file. Use update_project_uids to generate UIDs.",
		})

	var file := FileAccess.open(uid_path, FileAccess.READ)
	if file == null:
		return Result.err("Failed to read UID file: %s" % uid_path, "ERR_READ_FAILED")

	var uid_value := file.get_as_text().strip_edges()
	file.close()

	return Result.ok({
		"file": file_path,
		"absolute_path": absolute_path,
		"uid": uid_value,
		"exists": true,
	})


static func update_project_uids(project_path: String = "res://") -> Dictionary:
	project_path = PathUtils.normalize_res_path(project_path)
	var scenes: Array = []
	var scripts: Array = []
	var errors: Array = []

	_collect_files_recursive(project_path, [".tscn"], scenes)
	_collect_files_recursive(project_path, [".gd", ".shader", ".gdshader"], scripts)

	var scenes_saved := 0
	var scene_errors := 0
	for raw_scene_path in scenes:
		var scene_path: String = str(raw_scene_path)
		var scene_resource = load(scene_path)
		if scene_resource == null:
			scene_errors += 1
			errors.append({"path": scene_path, "code": "ERR_LOAD_FAILED", "message": "Failed to load resource"})
			continue

		var scene_err := ResourceSaver.save(scene_resource, scene_path)
		if scene_err != OK:
			scene_errors += 1
			errors.append({"path": scene_path, "code": "ERR_WRITE_FAILED", "message": "Failed to save resource: %d" % scene_err})
			continue

		var scene_uid_result := _ensure_uid_file(scene_path)
		if not scene_uid_result.get("ok", false):
			errors.append({
				"path": scene_path,
				"code": scene_uid_result.get("code", "ERR_UID_GENERATION_FAILED"),
				"message": scene_uid_result.get("error", "Failed to ensure UID"),
			})

		scenes_saved += 1

	var missing_uids := 0
	var generated_uids := 0
	for raw_script_path in scripts:
		var script_path: String = str(raw_script_path)
		var uid_path: String = script_path + ".uid"
		if FileAccess.file_exists(uid_path):
			continue

		missing_uids += 1
		var script_resource = load(script_path)
		if script_resource == null:
			errors.append({"path": script_path, "code": "ERR_LOAD_FAILED", "message": "Failed to load resource"})
			continue

		var script_err := ResourceSaver.save(script_resource, script_path)
		if script_err != OK:
			errors.append({"path": script_path, "code": "ERR_WRITE_FAILED", "message": "Failed to save resource: %d" % script_err})
			continue

		var script_uid_result := _ensure_uid_file(script_path)
		if not script_uid_result.get("ok", false):
			errors.append({
				"path": script_path,
				"code": script_uid_result.get("code", "ERR_UID_GENERATION_FAILED"),
				"message": script_uid_result.get("error", "Failed to ensure UID"),
			})
			continue

		if FileAccess.file_exists(uid_path):
			generated_uids += 1

	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()

	return Result.ok({
		"project_path": project_path,
		"scenes_processed": scenes.size(),
		"scenes_saved": scenes_saved,
		"scene_errors": scene_errors,
		"resources_checked": scripts.size(),
		"missing_uids": missing_uids,
		"generated_uids": generated_uids,
		"errors": errors,
	})


static func _ensure_uid_file(resource_path: String) -> Dictionary:
	resource_path = PathUtils.normalize_res_path(resource_path)
	var uid_path: String = resource_path + ".uid"
	if FileAccess.file_exists(uid_path):
		return Result.ok({"path": resource_path, "uid_path": uid_path, "exists": true})

	var resource_id: int = ResourceSaver.get_resource_id_for_path(resource_path, true)
	if resource_id == ResourceUID.INVALID_ID:
		return Result.err("Failed to allocate resource UID: %s" % resource_path, "ERR_UID_GENERATION_FAILED")

	var uid_text: String = _get_uid_text(resource_path, resource_id)

	if uid_text.is_empty():
		return Result.err("Failed to resolve UID text: %s" % resource_path, "ERR_UID_GENERATION_FAILED")

	if ResourceSaver.has_method("set_uid"):
		var set_uid_result: Variant = ResourceSaver.call("set_uid", resource_path, resource_id)
		if typeof(set_uid_result) == TYPE_INT and int(set_uid_result) != OK and not _resource_uses_uid_sidecar(resource_path):
			return Result.err(
				"Failed to assign resource UID: %s (%d)" % [resource_path, int(set_uid_result)],
				"ERR_UID_GENERATION_FAILED"
			)

	if not FileAccess.file_exists(uid_path) and _resource_uses_uid_sidecar(resource_path):
		if not FileWriter.write_text(uid_path, uid_text):
			return Result.err("Failed to write UID file: %s" % uid_path, "ERR_WRITE_FAILED")

	return Result.ok({
		"path": resource_path,
		"uid_path": uid_path,
		"uid": uid_text,
		"exists": FileAccess.file_exists(uid_path),
	})


static func _get_uid_text(resource_path: String, resource_id: int) -> String:
	var uid_text := ""
	if ResourceUID.has_method("id_to_text"):
		uid_text = str(ResourceUID.call("id_to_text", resource_id)).strip_edges()
	if uid_text.begins_with("uid://"):
		return uid_text

	if ResourceUID.has_method("path_to_uid"):
		var path_uid := str(ResourceUID.call("path_to_uid", resource_path)).strip_edges()
		if path_uid.begins_with("uid://"):
			return path_uid

	return ""


static func _resource_uses_uid_sidecar(resource_path: String) -> bool:
	return (
		resource_path.ends_with(".gd")
		or resource_path.ends_with(".shader")
		or resource_path.ends_with(".gdshader")
	)


static func _find_first_mesh_instance(node: Node, relative_transform: Transform3D = Transform3D.IDENTITY) -> Dictionary:
	if node is MeshInstance3D and node.mesh != null:
		return {"node": node, "transform": relative_transform}

	for child in node.get_children():
		var child_transform := relative_transform
		if child is Node3D:
			child_transform = relative_transform * child.transform
		var result := _find_first_mesh_instance(child, child_transform)
		if not result.is_empty():
			return result

	return {}


static func _collect_collision_shapes(node: Node, relative_transform: Transform3D = Transform3D.IDENTITY) -> Array:
	var results: Array = []

	for child in node.get_children():
		var child_transform := relative_transform
		if child is Node3D:
			child_transform = relative_transform * child.transform

		if child is CollisionShape3D and child.shape != null:
			results.append(child.shape)
			results.append(child_transform)

		results.append_array(_collect_collision_shapes(child, child_transform))

	return results


static func _collect_files_recursive(path: String, extensions: Array, result: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		if FileAccess.file_exists(path):
			for ext in extensions:
				if path.ends_with(ext):
					result.append(path)
					return
		return

	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not fname.begins_with("."):
			var full_path := path.path_join(fname)
			if dir.current_is_dir():
				_collect_files_recursive(full_path, extensions, result)
			else:
				for ext in extensions:
					if fname.ends_with(ext):
						result.append(full_path)
						break
		fname = dir.get_next()
	dir.list_dir_end()
