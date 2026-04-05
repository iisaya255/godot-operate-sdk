@tool
extends RefCounted
## ScriptOps module internal implementation

const Result = preload("../core/sdk_result.gd")
const PathUtils = preload("../core/sdk_path_utils.gd")
const FileWriter = preload("../core/sdk_file_writer.gd")


static func create_script(path: String, content: String, base_type: String = "") -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	var final_content := content
	if not base_type.is_empty() and not content.begins_with("extends"):
		final_content = "extends %s\n\n%s" % [base_type, content]
	if not FileWriter.write_text(path, final_content):
		return Result.err("Failed to write script: %s" % path, "ERR_WRITE_FAILED")
	return Result.ok({"path": path})


static func read_script(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("Script not found: %s" % path, "ERR_SCRIPT_NOT_FOUND")
	var content := FileAccess.get_file_as_string(path)
	return Result.ok({"path": path, "content": content})


static func update_script(path: String, content: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("Script not found: %s" % path, "ERR_SCRIPT_NOT_FOUND")
	if not FileWriter.write_text(path, content):
		return Result.err("Failed to write script: %s" % path, "ERR_WRITE_FAILED")
	return Result.ok({"path": path})


static func delete_script(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("Script not found: %s" % path, "ERR_SCRIPT_NOT_FOUND")
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return Result.err("Failed to delete script: %s" % path, "ERR_DELETE_FAILED")
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return Result.ok({"path": path})


static func update_script_function(path: String, function_name: String, new_function_content: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("Script not found: %s" % path, "ERR_SCRIPT_NOT_FOUND")
	var content := FileAccess.get_file_as_string(path)
	var lines := content.split("\n")
	var start_line := -1
	for i in range(lines.size()):
		var line := lines[i]
		if line.begins_with("func %s" % function_name) or line.begins_with("static func %s" % function_name):
			start_line = i
			break
	if start_line == -1:
		return Result.err("Function not found: %s" % function_name, "ERR_FUNCTION_NOT_FOUND")
	var end_line := _find_function_end(lines, start_line)
	var new_lines: Array = []
	for i in range(start_line):
		new_lines.append(lines[i])
	new_lines.append_array(new_function_content.split("\n"))
	for i in range(end_line, lines.size()):
		new_lines.append(lines[i])
	if not FileWriter.write_text(path, "\n".join(new_lines)):
		return Result.err("Failed to write script: %s" % path, "ERR_WRITE_FAILED")
	return Result.ok({"path": path, "function": function_name, "start_line": start_line + 1, "end_line": end_line})


static func _find_function_end(lines: Array, start_line: int) -> int:
	var top_level_markers := ["func ", "static func ", "class ", "signal ", "var ", "const ", "@"]
	for i in range(start_line + 1, lines.size()):
		var line: String = lines[i]
		if line.strip_edges().is_empty() or line.strip_edges().begins_with("#"):
			continue
		for marker in top_level_markers:
			if line.begins_with(marker):
				return i
	return lines.size()


static func update_script_range(path: String, start_line: int, end_line: int, new_content: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("Script not found: %s" % path, "ERR_SCRIPT_NOT_FOUND")
	var content := FileAccess.get_file_as_string(path)
	var lines := content.split("\n")
	if start_line < 1 or end_line < start_line or end_line > lines.size():
		return Result.err("Invalid line range: %d-%d" % [start_line, end_line], "ERR_INVALID_RANGE")
	var new_lines: Array = []
	for i in range(start_line - 1):
		new_lines.append(lines[i])
	new_lines.append_array(new_content.split("\n"))
	for i in range(end_line, lines.size()):
		new_lines.append(lines[i])
	if not FileWriter.write_text(path, "\n".join(new_lines)):
		return Result.err("Failed to write script: %s" % path, "ERR_WRITE_FAILED")
	return Result.ok({"path": path, "start_line": start_line, "end_line": end_line})


static func attach_script(scene_path: String, node_path: String, script_path: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	script_path = PathUtils.normalize_res_path(script_path)
	if not ResourceLoader.exists(scene_path):
		return Result.err("Scene not found: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return Result.err("Failed to load scene: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var root := packed.instantiate()
	if root == null:
		return Result.err("Failed to instantiate scene: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var node := root.get_node_or_null(node_path)
	if node == null:
		root.queue_free()
		return Result.err("Node not found: %s" % node_path, "ERR_NODE_NOT_FOUND")
	if not ResourceLoader.exists(script_path):
		root.queue_free()
		return Result.err("Script not found: %s" % script_path, "ERR_SCRIPT_NOT_FOUND")
	var script := ResourceLoader.load(script_path) as Script
	if script == null:
		root.queue_free()
		return Result.err("Script not found: %s" % script_path, "ERR_SCRIPT_NOT_FOUND")
	node.set_script(script)
	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.queue_free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Save failed"), "ERR_WRITE_FAILED")
	return Result.ok({"scene_path": scene_path, "node_path": node_path, "script_path": script_path})


static func detach_script(scene_path: String, node_path: String) -> Dictionary:
	scene_path = PathUtils.normalize_res_path(scene_path)
	if not ResourceLoader.exists(scene_path):
		return Result.err("Scene not found: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var packed := ResourceLoader.load(scene_path) as PackedScene
	if packed == null:
		return Result.err("Failed to load scene: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var root := packed.instantiate()
	if root == null:
		return Result.err("Failed to instantiate scene: %s" % scene_path, "ERR_SCENE_LOAD_FAILED")
	var node := root.get_node_or_null(node_path)
	if node == null:
		root.queue_free()
		return Result.err("Node not found: %s" % node_path, "ERR_NODE_NOT_FOUND")
	node.set_script(null)
	var write_result := FileWriter.write_scene(root, scene_path, true)
	root.queue_free()
	if not write_result.get("ok", false):
		return Result.err(write_result.get("error", "Save failed"), "ERR_WRITE_FAILED")
	return Result.ok({"scene_path": scene_path, "node_path": node_path})


static func compile_check(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("Script not found: %s" % path, "ERR_SCRIPT_NOT_FOUND")
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	var err := script.reload()
	if err == OK:
		return Result.ok({"valid": true})
	return Result.ok({"valid": false, "errors": [{"line": 0, "column": 0, "message": "Compilation failed (error code: %d)" % err, "source": path}]})


static func get_script_structure(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("Script not found: %s" % path, "ERR_SCRIPT_NOT_FOUND")
	var content := FileAccess.get_file_as_string(path)
	var lines := content.split("\n")
	var extends_class := ""
	var variables: Array = []
	var signals: Array = []
	var functions: Array = []
	for i in range(lines.size()):
		var line: String = lines[i]
		var stripped := line.strip_edges()
		# extends
		if stripped.begins_with("extends "):
			extends_class = stripped.substr(8).strip_edges()
			continue
		# signals
		if stripped.begins_with("signal "):
			var sig_name := stripped.substr(7).split("(")[0].strip_edges()
			signals.append({"name": sig_name, "line": i + 1})
			continue
		# functions
		if line.begins_with("func ") or line.begins_with("static func "):
			var func_start := i
			var func_end := _find_function_end(lines, func_start)
			var func_name := _parse_function_name(line)
			functions.append({"name": func_name, "start_line": func_start + 1, "end_line": func_end})
			continue
		# variables (top-level only, not indented)
		if _is_variable_line(line):
			var var_info := _parse_variable_line(line, i + 1)
			if not var_info.is_empty():
				variables.append(var_info)
	return Result.ok({"extends": extends_class, "variables": variables, "signals": signals, "functions": functions})


static func _parse_function_name(line: String) -> String:
	var s := line.strip_edges()
	if s.begins_with("static func "):
		s = s.substr(12)
	elif s.begins_with("func "):
		s = s.substr(5)
	return s.split("(")[0].strip_edges()


static func _is_variable_line(line: String) -> bool:
	if line.begins_with("var ") or line.begins_with("@export var "):
		return true
	# handle other decorators like @onready, @export_range, etc.
	if line.begins_with("@") and " var " in line:
		return true
	return false


static func _parse_variable_line(line: String, line_num: int) -> Dictionary:
	# strip decorator prefix to get to "var ..."
	var var_part := line
	if line.begins_with("@"):
		var idx := line.find(" var ")
		if idx == -1:
			return {}
		var_part = line.substr(idx + 1)
	# var_part now starts with "var "
	var_part = var_part.strip_edges()
	if not var_part.begins_with("var "):
		return {}
	var rest := var_part.substr(4).strip_edges()
	# rest is like: speed: float = 200.0  or  speed = 200.0  or  speed: float
	var var_name := ""
	var var_type := ""
	if ":" in rest:
		var colon_idx := rest.find(":")
		var_name = rest.substr(0, colon_idx).strip_edges()
		var after_colon := rest.substr(colon_idx + 1).strip_edges()
		# type is up to "=" or end
		if "=" in after_colon:
			var eq_idx := after_colon.find("=")
			var_type = after_colon.substr(0, eq_idx).strip_edges()
		else:
			var_type = after_colon.strip_edges()
	elif "=" in rest:
		var eq_idx := rest.find("=")
		var_name = rest.substr(0, eq_idx).strip_edges()
	else:
		var_name = rest.strip_edges()
	if var_name.is_empty():
		return {}
	return {"name": var_name, "line": line_num, "type": var_type}
