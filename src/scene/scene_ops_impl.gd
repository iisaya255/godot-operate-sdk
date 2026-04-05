@tool
extends RefCounted
## SceneOps module - scene creation, modification, and inspection

const Result = preload("../core/sdk_result.gd")
const PathUtils = preload("../core/sdk_path_utils.gd")
const FileWriter = preload("../core/sdk_file_writer.gd")
const TypeConverter = preload("../core/sdk_type_converter.gd")
const NodeRules = preload("./node_rules.gd")

# ---------------------------------------------------------------------------
# create_scene_from_json
# ---------------------------------------------------------------------------

static func create_scene_from_json(json: Dictionary) -> Dictionary:
	if not json.has("root"):
		return Result.err("Missing 'root' in json", "ERR_INVALID_INPUT")
	var root_data: Dictionary = json["root"]
	if not root_data.has("type") or root_data["type"] == "":
		return Result.err("root node must have a 'type'", "ERR_INVALID_INPUT")

	var scene_name: String = json.get("scene_name", root_data.get("name", "Scene"))
	var scene_path := PathUtils.normalize_res_path(scene_name)
	if not scene_path.ends_with(".tscn"):
		scene_path += ".tscn"

	var auto_completed := NodeRules.apply_rules_recursive(root_data)

	var build_result := _build_node(root_data)
	if not build_result.get("ok", false):
		return build_result
	var root_node: Node = build_result["node"]
	_set_owner_recursive(root_node, root_node)

	var write_result := FileWriter.write_scene(root_node, scene_path, true)
	root_node.free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Write failed"), "ERR_WRITE_FAILED")

	return Result.ok({"scene_path": scene_path, "auto_completed": auto_completed})

# ---------------------------------------------------------------------------
# scene_to_json
# ---------------------------------------------------------------------------

static func scene_to_json(scene_path: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	if not ResourceLoader.exists(scene_path):
		return Result.err("Scene not found: %s" % scene_path, "ERR_NOT_FOUND")

	var packed := load(scene_path) as PackedScene
	if packed == null:
		return Result.err("Failed to load scene: %s" % scene_path, "ERR_LOAD_FAILED")

	var state := packed.get_state()
	if state == null or state.get_node_count() == 0:
		return Result.err("Scene has no nodes", "ERR_EMPTY_SCENE")

	var root_json := _state_node_to_json(state, 0)
	var scene_name := scene_path.get_file().get_basename()
	return Result.ok({"scene_name": scene_name, "root": root_json})

# ---------------------------------------------------------------------------
# save_scene
# ---------------------------------------------------------------------------

static func save_scene(scene_path: String, new_path: String = "") -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	if not ResourceLoader.exists(scene_path):
		return Result.err("Scene not found: %s" % scene_path, "ERR_NOT_FOUND")

	var packed := load(scene_path) as PackedScene
	if packed == null:
		return Result.err("Failed to load scene: %s" % scene_path, "ERR_LOAD_FAILED")

	var root := packed.instantiate()
	if root == null:
		return Result.err("Failed to instantiate scene: %s" % scene_path, "ERR_INSTANTIATE_FAILED")

	var save_path := scene_path if new_path.is_empty() else PathUtils.normalize_res_path(new_path)
	_set_owner_recursive(root, root)

	var write_result := FileWriter.write_scene(root, save_path, true)
	root.free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Write failed"), "ERR_WRITE_FAILED")

	return Result.ok({"scene_path": scene_path, "save_path": save_path})

# ---------------------------------------------------------------------------
# resave_scene — re-load and re-serialize the scene file on disk.
# This does NOT save in-editor unsaved modifications; it re-packs the
# already-persisted data.  Useful after external edits to normalise the file.
# ---------------------------------------------------------------------------

static func resave_scene(scene_path: String) -> Dictionary:
	return save_scene(scene_path)

# ---------------------------------------------------------------------------
# add_node
# ---------------------------------------------------------------------------

static func add_node(scene_path: String, parent_path: String, node_json: Dictionary) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	var load_result := _load_and_instantiate(scene_path)
	if not load_result.get("ok", false):
		return load_result
	var root: Node = load_result["root"]

	var parent: Node = root if parent_path == "" or parent_path == "/" else root.get_node_or_null(parent_path)
	if parent == null:
		root.free()
		return Result.err("Parent node not found: %s" % parent_path, "ERR_NOT_FOUND")

	NodeRules.apply_rules_recursive(node_json)

	var build_result := _build_node(node_json)
	if not build_result.get("ok", false):
		root.free()
		return build_result
	var new_node: Node = build_result["node"]

	parent.add_child(new_node)
	_set_owner_recursive(new_node, root)

	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Write failed"), "ERR_WRITE_FAILED")

	return Result.ok({"scene_path": scene_path, "node_name": node_json.get("name", "")})

# ---------------------------------------------------------------------------
# remove_node
# ---------------------------------------------------------------------------

static func remove_node(scene_path: String, node_path: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	var load_result := _load_and_instantiate(scene_path)
	if not load_result.get("ok", false):
		return load_result
	var root: Node = load_result["root"]

	if node_path == "" or node_path == "/":
		root.free()
		return Result.err("Cannot remove root node", "ERR_INVALID_INPUT")

	var target: Node = root.get_node_or_null(node_path)
	if target == null:
		root.free()
		return Result.err("Node not found: %s" % node_path, "ERR_NOT_FOUND")

	if target == root:
		root.free()
		return Result.err("Cannot remove root node", "ERR_INVALID_INPUT")

	target.get_parent().remove_child(target)
	target.queue_free()

	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Write failed"), "ERR_WRITE_FAILED")

	return Result.ok({"scene_path": scene_path, "removed": node_path})

# ---------------------------------------------------------------------------
# update_node
# ---------------------------------------------------------------------------

static func update_node(scene_path: String, node_path: String, properties: Dictionary) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	var load_result := _load_and_instantiate(scene_path)
	if not load_result.get("ok", false):
		return load_result
	var root: Node = load_result["root"]

	var target: Node = root if node_path == "" or node_path == "/" else root.get_node_or_null(node_path)
	if target == null:
		root.free()
		return Result.err("Node not found: %s" % node_path, "ERR_NOT_FOUND")

	var apply_result := _apply_properties(target, properties)
	if not apply_result.get("ok", false):
		root.free()
		return apply_result

	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Write failed"), "ERR_WRITE_FAILED")

	return Result.ok({"scene_path": scene_path, "node_path": node_path})

# ---------------------------------------------------------------------------
# move_node
# ---------------------------------------------------------------------------

static func move_node(scene_path: String, node_path: String, new_parent: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	var load_result := _load_and_instantiate(scene_path)
	if not load_result.get("ok", false):
		return load_result
	var root: Node = load_result["root"]

	if node_path == "" or node_path == "/":
		root.free()
		return Result.err("Cannot move root node", "ERR_INVALID_INPUT")

	var target: Node = root.get_node_or_null(node_path)
	if target == null:
		root.free()
		return Result.err("Node not found: %s" % node_path, "ERR_NOT_FOUND")

	var parent_node: Node = root if new_parent == "" or new_parent == "/" else root.get_node_or_null(new_parent)
	if parent_node == null:
		root.free()
		return Result.err("New parent not found: %s" % new_parent, "ERR_NOT_FOUND")

	_clear_owner_recursive(target)
	target.reparent(parent_node)
	_set_owner_recursive(target, root)

	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Write failed"), "ERR_WRITE_FAILED")

	return Result.ok({"scene_path": scene_path, "node_path": node_path, "new_parent": new_parent})

# ---------------------------------------------------------------------------
# get_node_info
# ---------------------------------------------------------------------------

static func get_node_info(scene_path: String, node_path: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	var load_result := _load_and_instantiate(scene_path)
	if not load_result.get("ok", false):
		return load_result
	var root: Node = load_result["root"]

	var target: Node = root if node_path == "" or node_path == "/" else root.get_node_or_null(node_path)
	if target == null:
		root.free()
		return Result.err("Node not found: %s" % node_path, "ERR_NOT_FOUND")

	var info := _node_to_json(target)
	info["children_count"] = target.get_child_count()
	root.free()
	return Result.ok(info)

# ---------------------------------------------------------------------------
# list_nodes
# ---------------------------------------------------------------------------

static func list_nodes(scene_path: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	var load_result := _load_and_instantiate(scene_path)
	if not load_result.get("ok", false):
		return load_result
	var root: Node = load_result["root"]
	var tree := _build_tree_simple(root, "")
	root.free()
	return Result.ok({"tree": tree})

# ---------------------------------------------------------------------------
# find_nodes_by_type
# ---------------------------------------------------------------------------

static func find_nodes_by_type(scene_path: String, type_name: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	var load_result := _load_and_instantiate(scene_path)
	if not load_result.get("ok", false):
		return load_result
	var root: Node = load_result["root"]
	var found: Array = []
	_find_by_type_recursive(root, type_name, "", found)
	root.free()
	return Result.ok({"nodes": found})

# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

static func _load_and_instantiate(scene_path: String) -> Dictionary:
	if not ResourceLoader.exists(scene_path):
		return Result.err("Scene not found: %s" % scene_path, "ERR_NOT_FOUND")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return Result.err("Failed to load scene: %s" % scene_path, "ERR_LOAD_FAILED")
	var root := packed.instantiate()
	if root == null:
		return Result.err("Failed to instantiate scene: %s" % scene_path, "ERR_INSTANTIATE_FAILED")
	return {"ok": true, "root": root}

static func _get_script_by_name(type_name: String) -> Script:
	var normalized_path := PathUtils.normalize_res_path(type_name)
	if (PathUtils.is_resource_path(type_name) or type_name.ends_with(".gd")) and ResourceLoader.exists(normalized_path, "Script"):
		var direct_script = load(normalized_path)
		if direct_script is Script:
			return direct_script

	for global_class in ProjectSettings.get_global_class_list():
		if str(global_class.get("class", "")) != type_name:
			continue
		var script_path := str(global_class.get("path", ""))
		if script_path.is_empty():
			continue
		if not ResourceLoader.exists(script_path, "Script"):
			continue
		var script = load(script_path)
		if script is Script:
			return script

	return null

static func _instantiate_node_type(type_name: String) -> Dictionary:
	if type_name.is_empty():
		return Result.err("Node type cannot be empty", "ERR_INVALID_INPUT")

	if ClassDB.class_exists(type_name) and ClassDB.can_instantiate(type_name):
		var built_in = ClassDB.instantiate(type_name)
		if built_in is Node:
			return Result.ok({"node": built_in})

	var script := _get_script_by_name(type_name)
	if not (script is Script):
		return Result.err("Failed to instantiate node type: %s" % type_name, "ERR_INSTANTIATE_FAILED")

	var instance = script.new()
	if not (instance is Node):
		return Result.err("Script type is not a Node: %s" % type_name, "ERR_INSTANTIATE_FAILED")

	return Result.ok({"node": instance})

static func _build_node(node_data: Dictionary) -> Dictionary:
	var type_name: String = node_data.get("type", "Node")
	var instantiate_result := _instantiate_node_type(type_name)
	if not instantiate_result.get("ok", false):
		return instantiate_result
	var node: Node = instantiate_result["data"]["node"]

	var node_name: String = node_data.get("name", type_name)
	if not node_name.is_empty():
		node.name = node_name

	if node_data.has("script"):
		var script_path: String = node_data["script"]
		if not script_path.is_empty():
			script_path = PathUtils.normalize_res_path(script_path)
			if ResourceLoader.exists(script_path):
				node.set_script(load(script_path))

	if node_data.has("properties"):
		var apply_result := _apply_properties(node, node_data["properties"])
		if not apply_result.get("ok", false):
			node.free()
			return apply_result

	if node_data.has("groups"):
		for group in node_data["groups"]:
			node.add_to_group(str(group))

	if node_data.has("children"):
		for child_data in node_data["children"]:
			if child_data is Dictionary:
				var child_result := _build_node(child_data)
				if not child_result.get("ok", false):
					node.free()
					return child_result
				node.add_child(child_result["node"])

	return {"ok": true, "node": node}

static func _apply_properties(node: Node, properties: Dictionary) -> Dictionary:
	for prop in properties:
		var property_name := str(prop)
		if _get_property_info(node, property_name).is_empty():
			return Result.err(
				"Property not found on %s: %s" % [node.get_class(), property_name],
				"ERR_PROPERTY_NOT_FOUND",
				{"node_class": node.get_class(), "property": property_name}
			)
		var value = properties[prop]
		if value is Dictionary and value.has("_type"):
			var type_str: String = value["_type"]
			if type_str == "Enum":
				var int_val := TypeConverter.enum_string_to_int(node.get_class(), property_name, str(value.get("value", "")))
				node.set(property_name, int_val)
			else:
				node.set(property_name, TypeConverter.convert_typed_value(value))
		else:
			node.set(property_name, value)
	return Result.ok({})

static func _get_property_info(node: Node, property_name: String) -> Dictionary:
	for prop_info in node.get_property_list():
		if str(prop_info.name) == property_name:
			return prop_info
	return {}

static func _set_owner_recursive(node: Node, owner: Node) -> void:
	if node != owner and node.get_owner() != owner:
		node.set_owner(owner)
	for child in node.get_children():
		_set_owner_recursive(child, owner)

static func _clear_owner_recursive(node: Node) -> void:
	node.set_owner(null)
	for child in node.get_children():
		_clear_owner_recursive(child)

# --- scene_to_json helpers (SceneState-based) ---

static func _state_node_to_json(state: SceneState, idx: int) -> Dictionary:
	var node_json := {}
	node_json["name"] = state.get_node_name(idx)
	node_json["type"] = state.get_node_type(idx)

	# properties
	var props := {}
	for i in range(state.get_node_property_count(idx)):
		var pname: String = state.get_node_property_name(idx, i)
		var pval = state.get_node_property_value(idx, i)
		if pname == "script":
			if pval is Script:
				node_json["script"] = pval.resource_path
			continue
		var json_val = _value_to_json(pval)
		if json_val != null:
			props[pname] = json_val
	node_json["properties"] = props

	# groups
	var groups := []
	var raw_groups := state.get_node_groups(idx)
	for g in raw_groups:
		groups.append(str(g))
	node_json["groups"] = groups

	# children: find direct children by checking parent index
	var children := []
	var my_path := str(state.get_node_path(idx))
	for i in range(1, state.get_node_count()):
		# SceneState stores parent as a NodePath relative to root
		var parent_np := state.get_node_path(i)
		var parent_path_str := str(parent_np)
		# Direct child of root: path has no "/" (e.g. "Sprite2D")
		# Direct child of other: path is "Parent/Child" where parent part matches
		var slash_pos := parent_path_str.rfind("/")
		var parent_part := ""
		if slash_pos >= 0:
			parent_part = parent_path_str.substr(0, slash_pos)
		# For root node (idx 0), direct children have no "/" in their path
		if idx == 0:
			if slash_pos == -1:
				children.append(_state_node_to_json(state, i))
		else:
			if parent_part == my_path:
				children.append(_state_node_to_json(state, i))
	node_json["children"] = children

	return node_json

static func _value_to_json(value: Variant) -> Variant:
	if value is Resource:
		var res := value as Resource
		if res.resource_path != "":
			return {"_type": "Resource", "path": res.resource_path}
		# inline resource
		var res_json := {"_type": res.get_class()}
		for prop in res.get_property_list():
			if prop.usage & PROPERTY_USAGE_STORAGE == 0:
				continue
			var pname: String = prop.name
			if pname == "script" or pname == "resource_path" or pname == "resource_name":
				continue
			var pval = res.get(pname)
			var jval = _value_to_json(pval)
			if jval != null:
				res_json[pname] = jval
		return res_json
	return TypeConverter.value_to_typed_json(value)

# --- list_nodes helper ---

static func _build_tree_simple(node: Node, parent_path: String) -> Dictionary:
	var node_name: String = str(node.name)
	var path: String = parent_path + "/" + node_name if parent_path != "" else node_name
	var entry := {
		"name": node_name,
		"type": node.get_class(),
		"path": path,
		"children": []
	}
	for child in node.get_children():
		entry["children"].append(_build_tree_simple(child, path))
	return entry

# --- find_nodes_by_type helper ---

static func _find_by_type_recursive(node: Node, type_name: String, parent_path: String, result: Array) -> void:
	var node_name: String = str(node.name)
	var path: String = parent_path + "/" + node_name if parent_path != "" else node_name
	if node.is_class(type_name):
		result.append({"name": node_name, "path": path})
	for child in node.get_children():
		_find_by_type_recursive(child, type_name, path, result)

# --- get_node_info helper ---

static func _node_to_json(node: Node) -> Dictionary:
	var props := {}
	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		var pname: String = prop.name
		if pname == "script":
			continue
		var pval = node.get(pname)
		var jval = _value_to_json(pval)
		if jval != null:
			props[pname] = jval

	var script_path := ""
	if node.get_script() != null:
		script_path = (node.get_script() as Script).resource_path

	return {
		"name": node.name,
		"type": node.get_class(),
		"properties": props,
		"script": script_path,
		"groups": node.get_groups(),
	}
