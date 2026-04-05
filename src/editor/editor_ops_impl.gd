@tool
extends RefCounted
## Editor operations implementation

const Result = preload("../core/sdk_result.gd")
const PathUtils = preload("../core/sdk_path_utils.gd")
const FileWriter = preload("../core/sdk_file_writer.gd")

# --- SDK internal log buffer ---
static var _log_buffer: Array = []
static var _log_counter: int = 0

# --- Engine log file tracking ---
# Position in the engine log file; -1 means "not yet marked".
static var _engine_log_position: int = -1


static func push_log(level: String, message: String) -> void:
	_log_buffer.append({
		"id": _log_counter,
		"level": level,
		"message": message,
		"timestamp": _now_timestamp(),
	})
	_log_counter += 1
	if _log_buffer.size() > 1000:
		_log_buffer.pop_front()


static func get_editor_logs(options: Dictionary = {}) -> Dictionary:
	var level_filter: String = options.get("level", "all")
	var limit: int = options.get("limit", 50)
	var after_timestamp: float = float(options.get("after_timestamp", 0))

	var filtered: Array = []

	# 1) SDK internal logs (timestamp-filtered)
	for entry in _log_buffer:
		if after_timestamp > 0 and float(entry.get("timestamp", 0)) <= after_timestamp:
			continue
		if level_filter != "all" and entry.get("level", "") != level_filter:
			continue
		filtered.append(entry)

	# 2) Engine log file (position-filtered)
	var engine_entries := _read_engine_logs()
	for entry in engine_entries:
		if level_filter != "all" and entry.get("level", "") != level_filter:
			continue
		filtered.append(entry)

	# Return the most recent `limit` entries
	if filtered.size() > limit:
		filtered = filtered.slice(filtered.size() - limit)

	return Result.ok({"logs": filtered, "total": filtered.size()})


static func get_log_timestamp() -> Dictionary:
	_mark_engine_log_position()
	return Result.ok({"timestamp": _now_timestamp()})


static func run_scene(scene_path: String = "") -> Dictionary:
	if not Engine.is_editor_hint():
		return Result.err("Not running in editor", "ERR_NOT_IN_EDITOR")
	_mark_engine_log_position()
	if scene_path.is_empty():
		EditorInterface.play_main_scene()
	else:
		scene_path = PathUtils.normalize_res_path(scene_path)
		EditorInterface.play_custom_scene(scene_path)
	return Result.ok({"scene": scene_path})


static func stop_scene() -> Dictionary:
	if not Engine.is_editor_hint():
		return Result.err("Not running in editor", "ERR_NOT_IN_EDITOR")
	EditorInterface.stop_playing_scene()
	return Result.ok({})


static func open_scene(scene_path: String) -> Dictionary:
	if not Engine.is_editor_hint():
		return Result.err("Not running in editor", "ERR_NOT_IN_EDITOR")
	scene_path = PathUtils.normalize_res_path(scene_path)
	if not ResourceLoader.exists(scene_path):
		return Result.err("Scene not found: %s" % scene_path, "ERR_FILE_NOT_FOUND")
	EditorInterface.open_scene_from_path(scene_path)
	return Result.ok({"scene": scene_path})


static func open_script(script_path: String, line: int = -1) -> Dictionary:
	if not Engine.is_editor_hint():
		return Result.err("Not running in editor", "ERR_NOT_IN_EDITOR")
	script_path = PathUtils.normalize_res_path(script_path)
	if not ResourceLoader.exists(script_path):
		return Result.err("Script not found: %s" % script_path, "ERR_FILE_NOT_FOUND")
	var script = load(script_path)
	if not (script is Script):
		return Result.err("Not a script: %s" % script_path, "ERR_FILE_NOT_FOUND")
	EditorInterface.edit_script(script, line)
	return Result.ok({"script": script_path, "line": line})


static func refresh_filesystem() -> Dictionary:
	if not Engine.is_editor_hint():
		return Result.err("Not running in editor", "ERR_NOT_IN_EDITOR")
	EditorInterface.get_resource_filesystem().scan()
	return Result.ok({})


static func get_open_scenes() -> Dictionary:
	if not Engine.is_editor_hint():
		return Result.err("Not running in editor", "ERR_NOT_IN_EDITOR")
	var scenes := Array(EditorInterface.get_open_scenes())
	return Result.ok({"scenes": scenes})


static func get_project_info() -> Dictionary:
	return Result.ok({
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"godot_version": Engine.get_version_info(),
		"project_path": ProjectSettings.globalize_path("res://"),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
	})


# ---------------------------------------------------------------------------
# Engine log file helpers
# ---------------------------------------------------------------------------

static func _get_engine_log_path() -> String:
	var log_path: String = ProjectSettings.get_setting(
		"debug/file_logging/log_path", "user://logs/godot.log")
	return ProjectSettings.globalize_path(log_path)


static func _mark_engine_log_position() -> void:
	var path := _get_engine_log_path()
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		file.seek_end()
		_engine_log_position = file.get_position()
		file.close()
	else:
		_engine_log_position = 0


static func _read_engine_logs() -> Array:
	if _engine_log_position < 0:
		return []
	var path := _get_engine_log_path()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var file_len := file.get_length()
	if file_len < _engine_log_position:
		_engine_log_position = 0
	if file_len <= _engine_log_position:
		file.close()
		return []
	file.seek(_engine_log_position)
	var new_bytes := file.get_buffer(file_len - _engine_log_position)
	_engine_log_position = file_len
	file.close()
	if new_bytes.size() == 0:
		return []
	var new_text := new_bytes.get_string_from_utf8()
	return _parse_engine_log_lines(new_text)


static func _parse_engine_log_lines(text: String) -> Array:
	var entries: Array = []
	var lines := text.split("\n")
	var ts := _now_timestamp()
	for line in lines:
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		var level := "info"
		var message := stripped
		if stripped.begins_with("ERROR: ") or stripped.begins_with("SCRIPT ERROR: "):
			level = "error"
			message = stripped.substr(stripped.find(": ") + 2)
		elif stripped.begins_with("WARNING: "):
			level = "warning"
			message = stripped.substr(9)
		elif stripped.begins_with("   at: "):
			# Continuation line from a previous error/warning — append to last entry
			if entries.size() > 0:
				entries[-1]["message"] += " | " + stripped.substr(7)
			continue
		else:
			# Regular print output — skip unless it looks like a runtime message
			if not stripped.begins_with("Godot Engine") and not stripped.begins_with("OpenGL") \
				and not stripped.begins_with("Vulkan") and not stripped.begins_with(" "):
				level = "info"
			else:
				continue
		entries.append({
			"level": level,
			"message": message,
			"timestamp": ts,
			"source": "engine",
		})
	return entries


static func _now_timestamp() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0
