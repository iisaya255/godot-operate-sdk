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
