@tool
extends RefCounted
## FileSystem Module Implementation

const Result = preload("../core/sdk_result.gd")
const PathUtils = preload("../core/sdk_path_utils.gd")
const FileWriter = preload("../core/sdk_file_writer.gd")

static func get_directory_tree(path: String, options: Dictionary = {}) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not DirAccess.dir_exists_absolute(path):
		return Result.err("Directory not found: %s" % path, "ERR_DIR_NOT_FOUND")
	var max_depth: int = options.get("max_depth", -1)
	var include_pattern: String = options.get("include_pattern", "")
	var exclude_dirs: Array = options.get("exclude_dirs", [".godot", ".git"])
	var tree := _build_tree(path, path.get_file(), max_depth, 0, include_pattern, exclude_dirs)
	return Result.ok(tree)

static func _build_tree(path: String, name: String, max_depth: int, depth: int, include_pattern: String, exclude_dirs: Array) -> Dictionary:
	var entry := {"path": path, "name": name, "type": "directory", "children": []}
	if max_depth >= 0 and depth >= max_depth:
		return entry
	var dir := DirAccess.open(path)
	if dir == null:
		return entry
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not fname.begins_with(".") or not fname in [".godot", ".git"]:
			var full_path := path.path_join(fname)
			if dir.current_is_dir():
				if fname not in exclude_dirs:
					entry["children"].append(_build_tree(full_path, fname, max_depth, depth + 1, include_pattern, exclude_dirs))
			else:
				if include_pattern.is_empty() or fname.matchn(include_pattern):
					entry["children"].append({"path": full_path, "name": fname, "type": "file"})
		fname = dir.get_next()
	dir.list_dir_end()
	return entry

static func read_file(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	var content := FileAccess.get_file_as_string(path)
	if content == "" and FileAccess.get_open_error() != OK:
		return Result.err("File not found: %s" % path, "ERR_FILE_NOT_FOUND")
	return Result.ok({"path": path, "content": content})

static func write_file(path: String, content: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if FileWriter.write_text(path, content):
		return Result.ok({"path": path})
	return Result.err("Failed to write file: %s" % path, "ERR_WRITE_FAILED")

static func file_exists(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	return Result.ok({"exists": FileAccess.file_exists(path)})

static func dir_exists(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	return Result.ok({"exists": DirAccess.dir_exists_absolute(path)})

static func list_files(path: String, pattern: String = "") -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not DirAccess.dir_exists_absolute(path):
		return Result.err("Directory not found: %s" % path, "ERR_DIR_NOT_FOUND")
	var files: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return Result.err("Cannot open directory: %s" % path, "ERR_READ_FAILED")
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not dir.current_is_dir() and not fname.begins_with("."):
			if pattern.is_empty() or fname.matchn(pattern):
				files.append(path.path_join(fname))
		fname = dir.get_next()
	dir.list_dir_end()
	return Result.ok({"files": files})

static func get_file_info(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("File not found: %s" % path, "ERR_FILE_NOT_FOUND")
	var file := FileAccess.open(path, FileAccess.READ)
	var size := 0
	if file:
		size = file.get_length()
		file.close()
	return Result.ok({
		"path": path,
		"size": size,
		"modified_time": FileAccess.get_modified_time(path),
		"type": path.get_extension().to_lower()
	})

static func copy_file(from: String, to: String) -> Dictionary:
	from = PathUtils.normalize_res_path(from)
	to = PathUtils.normalize_res_path(to)
	if not FileAccess.file_exists(from):
		return Result.err("Source file not found: %s" % from, "ERR_FILE_NOT_FOUND")
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var err := DirAccess.copy_absolute(from, to)
	if err != OK:
		return Result.err("Copy failed: %s" % from, "ERR_WRITE_FAILED")
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return Result.ok({"from": from, "to": to})

static func move_file(from: String, to: String) -> Dictionary:
	from = PathUtils.normalize_res_path(from)
	to = PathUtils.normalize_res_path(to)
	if not FileAccess.file_exists(from):
		return Result.err("Source file not found: %s" % from, "ERR_FILE_NOT_FOUND")
	DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	var err := DirAccess.rename_absolute(from, to)
	if err != OK:
		return Result.err("Move failed: %s" % from, "ERR_WRITE_FAILED")
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return Result.ok({"from": from, "to": to})

static func delete_file(path: String) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path):
		return Result.err("File not found: %s" % path, "ERR_FILE_NOT_FOUND")
	var err := DirAccess.remove_absolute(path)
	if err != OK:
		return Result.err("Delete failed: %s" % path, "ERR_WRITE_FAILED")
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	return Result.ok({"path": path})

static func grep(pattern: String, path: String, options: Dictionary = {}) -> Dictionary:
	path = PathUtils.normalize_res_path(path)
	if not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(path):
		return Result.err("Path not found: %s" % path, "ERR_PATH_NOT_FOUND")
	var is_regex: bool = options.get("regex", false)
	var context_lines: int = options.get("context_lines", 0)
	var max_results: int = options.get("max_results", 100)
	var file_pattern: String = options.get("file_pattern", "")

	var matches: Array = []
	var files_to_search: Array = []
	_collect_files_recursive(path, file_pattern, files_to_search)

	var regex: RegEx = null
	if is_regex:
		regex = RegEx.new()
		var compile_err := regex.compile(pattern)
		if compile_err != OK:
			return Result.err("Invalid regex pattern: %s" % pattern, "ERR_INVALID_PATH")

	for file_path in files_to_search:
		if matches.size() >= max_results:
			break
		var content := FileAccess.get_file_as_string(file_path)
		if content.is_empty():
			continue
		var lines := content.split("\n")
		for i in range(lines.size()):
			if matches.size() >= max_results:
				break
			var line: String = lines[i]
			var found := false
			if is_regex and regex:
				found = regex.search(line) != null
			else:
				found = pattern in line
			if found:
				var match_entry := {
					"file": file_path,
					"line": i + 1,
					"content": line,
				}
				if context_lines > 0:
					var before: Array = []
					var after: Array = []
					for j in range(max(0, i - context_lines), i):
						before.append(lines[j])
					for j in range(i + 1, min(lines.size(), i + 1 + context_lines)):
						after.append(lines[j])
					match_entry["context_before"] = before
					match_entry["context_after"] = after
				matches.append(match_entry)

	return Result.ok({"matches": matches, "total_matches": matches.size()})

static func _collect_files_recursive(path: String, file_pattern: String, result: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		# 可能是单个文件
		if FileAccess.file_exists(path):
			result.append(path)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		if not fname.begins_with("."):
			var full_path := path.path_join(fname)
			if dir.current_is_dir():
				_collect_files_recursive(full_path, file_pattern, result)
			else:
				if file_pattern.is_empty() or fname.matchn(file_pattern):
					result.append(full_path)
		fname = dir.get_next()
	dir.list_dir_end()
