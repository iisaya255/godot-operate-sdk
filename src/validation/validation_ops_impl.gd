@tool
extends RefCounted

const Result = preload("../core/sdk_result.gd")
const PathUtils = preload("../core/sdk_path_utils.gd")
const FileWriter = preload("../core/sdk_file_writer.gd")
const NodeRules = preload("../scene/node_rules.gd")


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


static func _walk_nodes(node: Node, parent_path: String, out: Array) -> void:
	var node_name: String = str(node.name)
	var node_path: String = node_name if parent_path.is_empty() else parent_path + "/" + node_name
	out.append({"node": node, "path": node_path})
	for i in node.get_child_count():
		_walk_nodes(node.get_child(i), node_path, out)


static func validate_scene(scene_path: String) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var errors: Array = []
	var warnings: Array = []
	var all_nodes: Array = []
	_walk_nodes(root, "", all_nodes)

	for entry in all_nodes:
		var node: Node = entry["node"]
		var node_class := node.get_class()
		var node_path: String = entry["path"]

		# CollisionShape2D without a shape assigned
		if node_class == "CollisionShape2D":
			if node.shape == null:
				errors.append({
					"node": node_path,
					"code": "MISSING_SHAPE",
					"message": "CollisionShape2D has no shape assigned",
				})

		# CollisionShape3D without a shape assigned
		if node_class == "CollisionShape3D":
			if node.shape == null:
				errors.append({
					"node": node_path,
					"code": "MISSING_SHAPE",
					"message": "CollisionShape3D has no shape assigned",
				})

		# Physics bodies that need a CollisionShape child
		if node_class in NodeRules.PHYSICS_BODY_2D_TYPES:
			var has_shape := false
			for i in node.get_child_count():
				if node.get_child(i) is CollisionShape2D:
					has_shape = true
					break
			if not has_shape:
				errors.append({
					"node": node_path,
					"code": "MISSING_COLLISION_SHAPE",
					"message": "%s has no CollisionShape2D child" % node_class,
				})

		if node_class in NodeRules.PHYSICS_BODY_3D_TYPES:
			var has_shape := false
			for i in node.get_child_count():
				if node.get_child(i) is CollisionShape3D:
					has_shape = true
					break
			if not has_shape:
				errors.append({
					"node": node_path,
					"code": "MISSING_COLLISION_SHAPE",
					"message": "%s has no CollisionShape3D child" % node_class,
				})

		# Warn-only rules from NodeRules
		for warn in NodeRules.get_warnings(node_class):
			var prop_val = node.get(warn["property"])
			if prop_val == null:
				warnings.append({
					"node": node_path,
					"code": "MISSING_RESOURCE",
					"message": warn["message"],
					"property": warn["property"],
				})

	root.queue_free()
	return Result.ok({
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	})


static func validate_resources(scene_path: String) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var errors: Array = []
	var warnings: Array = []
	var all_nodes: Array = []
	_walk_nodes(root, "", all_nodes)

	for entry in all_nodes:
		var node: Node = entry["node"]
		var node_path: String = entry["path"]
		for prop in node.get_property_list():
			if prop.type != TYPE_OBJECT or prop.hint != PROPERTY_HINT_RESOURCE_TYPE:
				continue
			var val = node.get(prop.name)
			if not (val is Resource):
				continue
			var rpath: String = val.resource_path
			# Inline resources have no path — skip existence check
			if rpath.is_empty():
				continue
			if not FileAccess.file_exists(rpath) and not ResourceLoader.exists(rpath):
				errors.append({
					"node": node_path,
					"property": prop.name,
					"code": "MISSING_RESOURCE_FILE",
					"message": "Resource file not found: %s" % rpath,
					"resource_path": rpath,
				})
			else:
				# Type compatibility check
				var expected_type: String = prop.get("hint_string", "")
				if not expected_type.is_empty() and ClassDB.class_exists(expected_type):
					if not val.is_class(expected_type) and not ClassDB.is_parent_class(val.get_class(), expected_type):
						errors.append({
							"node": node_path,
							"property": prop.name,
							"code": "TYPE_MISMATCH",
							"message": "Expected %s, got %s" % [expected_type, val.get_class()],
						})

	root.queue_free()
	return Result.ok({
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	})


static func validate_script_references(scene_path: String) -> Dictionary:
	var root = _load_scene(scene_path)
	if root is Dictionary:
		return root

	var errors: Array = []
	var warnings: Array = []
	var all_nodes: Array = []
	_walk_nodes(root, "", all_nodes)

	for entry in all_nodes:
		var node: Node = entry["node"]
		var node_path: String = entry["path"]
		var script = node.get_script()
		if not (script is Script):
			continue

		var script_path: String = script.resource_path

		# Check script file exists
		if not script_path.is_empty() and not FileAccess.file_exists(script_path):
			errors.append({
				"node": node_path,
				"code": "MISSING_SCRIPT_FILE",
				"message": "Script file not found: %s" % script_path,
				"script": script_path,
			})
			continue

		# Check extends matches node class
		var source: String = script.source_code
		if not source.is_empty():
			var node_class := node.get_class()
			# Look for "extends ClassName" in the first non-empty lines
			for line in source.split("\n"):
				line = line.strip_edges()
				if line.begins_with("extends "):
					var extends_class := line.substr(8).strip_edges().trim_suffix("\"").trim_prefix("\"")
					# Allow if extends_class is the node class or a parent of it
					if extends_class != node_class and not ClassDB.is_parent_class(node_class, extends_class):
						warnings.append({
							"node": node_path,
							"code": "EXTENDS_MISMATCH",
							"message": "Script extends '%s' but node is '%s'" % [extends_class, node_class],
							"script": script_path,
							"extends": extends_class,
							"node_class": node_class,
						})
					break

	root.queue_free()
	return Result.ok({
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	})


static func validate_all(scene_path: String) -> Dictionary:
	var scene_result := validate_scene(scene_path)
	if not scene_result.get("ok", false):
		return scene_result

	var resources_result := validate_resources(scene_path)
	if not resources_result.get("ok", false):
		return resources_result

	var scripts_result := validate_script_references(scene_path)
	if not scripts_result.get("ok", false):
		return scripts_result

	var scene_data: Dictionary = scene_result.get("data", {})
	var resources_data: Dictionary = resources_result.get("data", {})
	var scripts_data: Dictionary = scripts_result.get("data", {})

	var all_valid: bool = (
		bool(scene_data.get("valid", false)) and
		bool(resources_data.get("valid", false)) and
		bool(scripts_data.get("valid", false))
	)

	return Result.ok({
		"valid": all_valid,
		"scene": scene_data,
		"resources": resources_data,
		"scripts": scripts_data,
	})
