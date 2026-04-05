@tool
class_name SDKTypeConverter
extends RefCounted

## property converter - deal _type format JSON to Godot type


const PathUtils = preload("./sdk_path_utils.gd")

static var _instance: SDKTypeConverter
static var _property_cache: Dictionary = {}

static func get_instance() -> SDKTypeConverter:
	if _instance == null:
		_instance = SDKTypeConverter.new()
	return _instance

## JSON -> Godot Type
## example: {"_type": "Vector2", "x": 100, "y": 200} -> Vector2(100, 200)
static func convert_typed_value(value: Variant) -> Variant:
	if not value is Dictionary:
		return value
	var dict: Dictionary = value
	if not dict.has("_type"):
		return value

	var type_name: String = dict["_type"]
	match type_name:
		"Vector2":
			return Vector2(dict.get("x", 0.0), dict.get("y", 0.0))
		"Vector2i":
			return Vector2i(int(dict.get("x", 0)), int(dict.get("y", 0)))
		"Vector3":
			return Vector3(dict.get("x", 0.0), dict.get("y", 0.0), dict.get("z", 0.0))
		"Vector3i":
			return Vector3i(int(dict.get("x", 0)), int(dict.get("y", 0)), int(dict.get("z", 0)))
		"Color":
			return Color(dict.get("r", 0.0), dict.get("g", 0.0), dict.get("b", 0.0), dict.get("a", 1.0))
		"Rect2":
			return Rect2(dict.get("x", 0.0), dict.get("y", 0.0), dict.get("w", 0.0), dict.get("h", 0.0))
		"Resource":
			var path: String = dict.get("path", "")
			if not path.is_empty():
				path = PathUtils.normalize_res_path(path)
				if ResourceLoader.exists(path):
					return load(path)
			return null
		"NodePath":
			return NodePath(dict.get("path", ""))
		"Enum":
			return dict.get("value", "")
		_:
			# inline resource type (RectangleShape2D, CircleShape2D, etc.)
			return _create_inline_resource(type_name, dict)

## create inline resource
static func _create_inline_resource(type_name: String, config: Dictionary) -> Resource:
	match type_name:
		"RectangleShape2D":
			var shape := RectangleShape2D.new()
			if config.has("size"):
				shape.size = convert_typed_value(config["size"]) if config["size"] is Dictionary else Vector2(32, 32)
			return shape
		"CircleShape2D":
			var shape := CircleShape2D.new()
			if config.has("radius"):
				shape.radius = float(config["radius"])
			return shape
		"CapsuleShape2D":
			var shape := CapsuleShape2D.new()
			if config.has("radius"):
				shape.radius = float(config["radius"])
			if config.has("height"):
				shape.height = float(config["height"])
			return shape
		"SegmentShape2D":
			var shape := SegmentShape2D.new()
			if config.has("a"):
				shape.a = convert_typed_value(config["a"]) if config["a"] is Dictionary else Vector2.ZERO
			if config.has("b"):
				shape.b = convert_typed_value(config["b"]) if config["b"] is Dictionary else Vector2(0, 32)
			return shape
		"BoxShape3D":
			var shape := BoxShape3D.new()
			if config.has("size"):
				shape.size = convert_typed_value(config["size"]) if config["size"] is Dictionary else Vector3(1, 1, 1)
			return shape
		"SphereShape3D":
			var shape := SphereShape3D.new()
			if config.has("radius"):
				shape.radius = float(config["radius"])
			return shape
		"CapsuleShape3D":
			var shape := CapsuleShape3D.new()
			if config.has("radius"):
				shape.radius = float(config["radius"])
			if config.has("height"):
				shape.height = float(config["height"])
			return shape
		"CylinderShape3D":
			var shape := CylinderShape3D.new()
			if config.has("radius"):
				shape.radius = float(config["radius"])
			if config.has("height"):
				shape.height = float(config["height"])
			return shape
		"StyleBoxFlat":
			var style := StyleBoxFlat.new()
			if config.has("bg_color"):
				style.bg_color = convert_typed_value(config["bg_color"])
			if config.has("border_color"):
				style.border_color = convert_typed_value(config["border_color"])
			return style
		"LabelSettings":
			var settings := LabelSettings.new()
			if config.has("font_size"):
				settings.font_size = int(config["font_size"])
			if config.has("font_color"):
				settings.font_color = convert_typed_value(config["font_color"])
			return settings
		"Gradient":
			var gradient := Gradient.new()
			if config.has("colors") and config["colors"] is Array:
				var colors := PackedColorArray()
				for c in config["colors"]:
					colors.append(convert_typed_value(c) if c is Dictionary else Color.WHITE)
				gradient.colors = colors
			return gradient
		_:
			# try to create instance from ClassDB 
			if ClassDB.class_exists(type_name) and ClassDB.is_parent_class(type_name, "Resource"):
				if ClassDB.can_instantiate(type_name):
					var res = ClassDB.instantiate(type_name)
					if res is Resource:
						_apply_resource_properties(res, config)
						return res
			return null

## set properties
static func _apply_resource_properties(res: Resource, config: Dictionary) -> void:
	for key in config:
		if key == "_type":
			continue
		var value = config[key]
		if value is Dictionary and value.has("_type"):
			value = convert_typed_value(value)
		res.set(key, value)

## get property from ClassDB
func get_property_type_info(node_class: String, property_name: String) -> Dictionary:
	var cache_key := "%s.%s" % [node_class, property_name]
	if _property_cache.has(cache_key):
		return _property_cache[cache_key]
	if not ClassDB.class_exists(node_class):
		return {}
	var property_list := ClassDB.class_get_property_list(node_class, true)
	for prop_info in property_list:
		if prop_info.name == property_name:
			var type_info := {
				"type": prop_info.type,
				"hint": prop_info.hint,
				"hint_string": prop_info.hint_string,
				"class_name": prop_info.get("class_name", ""),
			}
			_property_cache[cache_key] = type_info
			return type_info
	return {}

## Godot Type to JSON
static func value_to_typed_json(value: Variant) -> Variant:
	match typeof(value):
		TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return value
		TYPE_FLOAT:
			return snappedf(value, 0.0001)
		TYPE_VECTOR2:
			var v := value as Vector2
			return {"_type": "Vector2", "x": snappedf(v.x, 0.0001), "y": snappedf(v.y, 0.0001)}
		TYPE_VECTOR2I:
			var v := value as Vector2i
			return {"_type": "Vector2i", "x": v.x, "y": v.y}
		TYPE_VECTOR3:
			var v := value as Vector3
			return {"_type": "Vector3", "x": snappedf(v.x, 0.0001), "y": snappedf(v.y, 0.0001), "z": snappedf(v.z, 0.0001)}
		TYPE_VECTOR3I:
			var v := value as Vector3i
			return {"_type": "Vector3i", "x": v.x, "y": v.y, "z": v.z}
		TYPE_COLOR:
			var c := value as Color
			return {"_type": "Color", "r": snappedf(c.r, 0.0001), "g": snappedf(c.g, 0.0001), "b": snappedf(c.b, 0.0001), "a": snappedf(c.a, 0.0001)}
		TYPE_RECT2:
			var r := value as Rect2
			return {"_type": "Rect2", "x": snappedf(r.position.x, 0.0001), "y": snappedf(r.position.y, 0.0001), "w": snappedf(r.size.x, 0.0001), "h": snappedf(r.size.y, 0.0001)}
		TYPE_NODE_PATH:
			var np := value as NodePath
			if np.is_empty():
				return null
			return {"_type": "NodePath", "path": str(np)}
		TYPE_STRING_NAME:
			var sn := value as StringName
			return str(sn) if not sn.is_empty() else null
		TYPE_ARRAY:
			var arr := []
			for item in value:
				var json_item = value_to_typed_json(item)
				if json_item != null:
					arr.append(json_item)
			return arr
		TYPE_DICTIONARY:
			var dict := {}
			for key in (value as Dictionary).keys():
				var json_val = value_to_typed_json(value[key])
				if json_val != null:
					dict[str(key)] = json_val
			return dict
		_:
			return null

## Enum int to String
static func enum_int_to_string(node: Node, property_name: String, int_value: int) -> String:
	var property_list := node.get_property_list()
	for prop_info in property_list:
		if prop_info.name == property_name and prop_info.hint == PROPERTY_HINT_ENUM:
			var hint_string: String = prop_info.hint_string
			var options := hint_string.split(",")
			for option in options:
				var parts := option.split(":")
				var name := parts[0].strip_edges()
				var val := int(parts[1].strip_edges()) if parts.size() > 1 else options.find(option)
				if val == int_value:
					return name
	return str(int_value)

## Enum String to int
static func enum_string_to_int(node_class: String, property_name: String, string_value: String) -> int:
	if not ClassDB.class_exists(node_class):
		return 0
	var property_list := ClassDB.class_get_property_list(node_class, true)
	for prop_info in property_list:
		if prop_info.name == property_name and prop_info.hint == PROPERTY_HINT_ENUM:
			var hint_string: String = prop_info.hint_string
			var options := hint_string.split(",")
			for option in options:
				var parts := option.split(":")
				var name := parts[0].strip_edges()
				if name.to_lower() == string_value.to_lower() or name.to_snake_case() == string_value.to_snake_case():
					return int(parts[1].strip_edges()) if parts.size() > 1 else options.find(option)
	return 0
