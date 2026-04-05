@tool
extends RefCounted
## Project config operations implementation

const Result = preload("../core/sdk_result.gd")
const PathUtils = preload("../core/sdk_path_utils.gd")
const FileWriter = preload("../core/sdk_file_writer.gd")


static func _make_input_event(event_def: Dictionary) -> InputEvent:
	var type: String = event_def.get("type", "")
	match type:
		"key":
			var ev := InputEventKey.new()
			var keycode_str: String = event_def.get("keycode", "")
			if not keycode_str.is_empty():
				ev.keycode = OS.find_keycode_from_string(keycode_str)
			return ev
		"joypad_button":
			var ev := InputEventJoypadButton.new()
			ev.button_index = int(event_def.get("button", 0))
			return ev
		"mouse_button":
			var ev := InputEventMouseButton.new()
			var btn = event_def.get("button", "left")
			if btn is int:
				ev.button_index = btn
			else:
				match str(btn).to_lower():
					"left":   ev.button_index = MOUSE_BUTTON_LEFT
					"right":  ev.button_index = MOUSE_BUTTON_RIGHT
					"middle": ev.button_index = MOUSE_BUTTON_MIDDLE
					_:        ev.button_index = MOUSE_BUTTON_LEFT
			return ev
	return null


static func _event_to_dict(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "keycode": OS.get_keycode_string(ev.keycode)}
	if ev is InputEventJoypadButton:
		return {"type": "joypad_button", "button": ev.button_index}
	if ev is InputEventMouseButton:
		var btn_name := "left"
		match ev.button_index:
			MOUSE_BUTTON_RIGHT:  btn_name = "right"
			MOUSE_BUTTON_MIDDLE: btn_name = "middle"
		return {"type": "mouse_button", "button": btn_name}
	return {"type": "unknown"}


static func add_input_action(action_name: String, events: Array) -> Dictionary:
	var events_array: Array = []
	for event_def in events:
		var ev := _make_input_event(event_def)
		if ev != null:
			events_array.append(ev)

	ProjectSettings.set("input/" + action_name, {"deadzone": 0.5, "events": events_array})
	ProjectSettings.save()
	return Result.ok({"action": action_name, "event_count": events_array.size()})


static func remove_input_action(action_name: String) -> Dictionary:
	var key := "input/" + action_name
	if not ProjectSettings.has_setting(key):
		return Result.err("Action not found: %s" % action_name, "ERR_SETTING_NOT_FOUND")
	ProjectSettings.set(key, null)
	ProjectSettings.save()
	return Result.ok({"action": action_name})


static func get_input_actions() -> Dictionary:
	var actions: Dictionary = {}
	var all_props := ProjectSettings.get_property_list()
	for prop in all_props:
		var pname: String = prop.name
		if not pname.begins_with("input/"):
			continue
		var action_name := pname.substr(6)
		var value = ProjectSettings.get_setting(pname)
		if value is Dictionary and value.has("events"):
			var ev_list: Array = []
			for ev in value["events"]:
				if ev is InputEvent:
					ev_list.append(_event_to_dict(ev))
			actions[action_name] = ev_list
	return Result.ok({"actions": actions})


static func set_layer_name(layer_type: String, layer_number: int, name: String) -> Dictionary:
	var key := "layer_names/%s/layer_%d" % [layer_type, layer_number]
	ProjectSettings.set(key, name)
	ProjectSettings.save()
	return Result.ok({"layer_type": layer_type, "layer_number": layer_number, "name": name})


static func get_layer_names(layer_type: String) -> Dictionary:
	var layers: Dictionary = {}
	for i in range(1, 33):
		var key := "layer_names/%s/layer_%d" % [layer_type, i]
		if ProjectSettings.has_setting(key):
			var val: String = ProjectSettings.get_setting(key)
			if not val.is_empty():
				layers[str(i)] = val
	return Result.ok({"layers": layers})


static func add_autoload(name: String, path: String) -> Dictionary:
	var key := "autoload/" + name
	if ProjectSettings.has_setting(key):
		return Result.err("Autoload already exists: %s" % name, "ERR_AUTOLOAD_EXISTS")
	path = PathUtils.normalize_res_path(path)
	ProjectSettings.set(key, "*" + path)
	ProjectSettings.save()
	return Result.ok({"name": name, "path": path})


static func remove_autoload(name: String) -> Dictionary:
	var key := "autoload/" + name
	if not ProjectSettings.has_setting(key):
		return Result.err("Autoload not found: %s" % name, "ERR_SETTING_NOT_FOUND")
	ProjectSettings.set(key, null)
	ProjectSettings.save()
	return Result.ok({"name": name})


static func get_autoloads() -> Dictionary:
	var autoloads: Dictionary = {}
	var all_props := ProjectSettings.get_property_list()
	for prop in all_props:
		var pname: String = prop.name
		if not pname.begins_with("autoload/"):
			continue
		var al_name := pname.substr(9)
		var val: String = ProjectSettings.get_setting(pname)
		# Strip leading "*" singleton marker
		if val.begins_with("*"):
			val = val.substr(1)
		autoloads[al_name] = val
	return Result.ok({"autoloads": autoloads})


static func set_setting(key: String, value: Variant) -> Dictionary:
	ProjectSettings.set(key, value)
	ProjectSettings.save()
	return Result.ok({"key": key, "value": value})


static func get_setting(key: String) -> Dictionary:
	if not ProjectSettings.has_setting(key):
		return Result.err("Setting not found: %s" % key, "ERR_SETTING_NOT_FOUND")
	return Result.ok({"key": key, "value": ProjectSettings.get_setting(key)})
