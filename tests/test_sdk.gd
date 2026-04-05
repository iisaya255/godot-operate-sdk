@tool
extends EditorScript
## godot-editor-ops-sdk contract test suite
##
## usage: Run in Godot
## Tests will create temporary files under res://_sdk_test/, which will be automatically cleaned up after completion

const TEST_DIR := "res://_sdk_test"
const TEST_SCENE := "res://_sdk_test/test_scene.tscn"
const TEST_SCRIPT_SCENE := "res://_sdk_test/script_test_scene.tscn"
const TEST_SCRIPT := "res://_sdk_test/test_player.gd"
const TEST_FILE := "res://_sdk_test/hello.txt"

var _pass_count := 0
var _fail_count := 0
var _current_group := ""


func _run() -> void:
	print("\n========== godot-editor-ops-sdk test suite ==========\n")
	_setup()

	_test_file_system()
	_test_scene_ops()
	_test_script_ops()
	_test_resource_ops()
	_test_validation_ops()
	_test_project_config()
	_test_editor_ops()
	_test_type_converter_round_trip()
	_test_error_semantics()

	_teardown()
	print("\n===================================================")
	print("  PASS: %d   FAIL: %d" % [_pass_count, _fail_count])
	print("===================================================\n")


func _supports_uids() -> bool:
	var version := Engine.get_version_info()
	var major := int(version.get("major", 0))
	var minor := int(version.get("minor", 0))
	return major > 4 or (major == 4 and minor >= 4)


# ===================================================================
# Setup / Teardown
# ===================================================================

func _setup() -> void:
	DirAccess.make_dir_recursive_absolute(TEST_DIR)


func _teardown() -> void:
	# Recursively remove the test directory
	_remove_dir_recursive(ProjectSettings.globalize_path(TEST_DIR))
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()


func _remove_dir_recursive(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while not fname.is_empty():
		var full := abs_path.path_join(fname)
		if dir.current_is_dir():
			_remove_dir_recursive(full)
		else:
			DirAccess.remove_absolute(full)
		fname = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_path)


# ===================================================================
# Assertions
# ===================================================================

func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass_count += 1
		print("  PASS  %s" % label)
	else:
		_fail_count += 1
		print("  FAIL  %s" % label)


func _assert_ok(result: Dictionary, label: String) -> void:
	_assert(result.get("ok", false), label)


func _assert_err(result: Dictionary, label: String, expected_code: String = "") -> void:
	var is_err: bool = not bool(result.get("ok", true))
	if not expected_code.is_empty():
		is_err = is_err and result.get("code", "") == expected_code
	_assert(is_err, label)


func _group(name: String) -> void:
	_current_group = name
	print("\n--- %s ---" % name)


# ===================================================================
# FileSystem
# ===================================================================

func _test_file_system() -> void:
	_group("FileSystem")

	# write_file
	var r := FileSystem.write_file(TEST_FILE, "hello sdk")
	_assert_ok(r, "write_file: create new file")

	# file_exists
	r = FileSystem.file_exists(TEST_FILE)
	_assert_ok(r, "file_exists: returns ok")
	_assert(r["data"]["exists"] == true, "file_exists: file exists")

	# read_file
	r = FileSystem.read_file(TEST_FILE)
	_assert_ok(r, "read_file: success")
	_assert(r["data"]["content"] == "hello sdk", "read_file: content matches")

	# get_file_info
	r = FileSystem.get_file_info(TEST_FILE)
	_assert_ok(r, "get_file_info: success")
	_assert(r["data"]["size"] > 0, "get_file_info: size > 0")
	_assert(r["data"]["type"] == "txt", "get_file_info: extension is txt")

	# copy_file
	var copy_path := TEST_DIR + "/hello_copy.txt"
	r = FileSystem.copy_file(TEST_FILE, copy_path)
	_assert_ok(r, "copy_file: success")
	r = FileSystem.file_exists(copy_path)
	_assert(r["data"]["exists"] == true, "copy_file: target exists")

	# move_file
	var moved_path := TEST_DIR + "/hello_moved.txt"
	r = FileSystem.move_file(copy_path, moved_path)
	_assert_ok(r, "move_file: success")
	r = FileSystem.file_exists(moved_path)
	_assert(r["data"]["exists"] == true, "move_file: target exists")
	r = FileSystem.file_exists(copy_path)
	_assert(r["data"]["exists"] == false, "move_file: source gone")

	# delete_file
	r = FileSystem.delete_file(moved_path)
	_assert_ok(r, "delete_file: success")
	r = FileSystem.file_exists(moved_path)
	_assert(r["data"]["exists"] == false, "delete_file: file gone")

	# dir_exists
	r = FileSystem.dir_exists(TEST_DIR)
	_assert_ok(r, "dir_exists: returns ok")
	_assert(r["data"]["exists"] == true, "dir_exists: dir exists")

	# list_files
	r = FileSystem.list_files(TEST_DIR, "*.txt")
	_assert_ok(r, "list_files: success")
	_assert(r["data"]["files"] is Array, "list_files: returns array")

	# get_directory_tree
	r = FileSystem.get_directory_tree(TEST_DIR, {"max_depth": 1})
	_assert_ok(r, "get_directory_tree: success")
	_assert(r["data"]["type"] == "directory", "get_directory_tree: root is directory")

	# grep — success path
	FileSystem.write_file(TEST_DIR + "/grep_target.gd", "extends Node\nvar speed := 100\nfunc _ready():\n\tpass\n")
	r = FileSystem.grep("speed", TEST_DIR, {"file_pattern": "*.gd"})
	_assert_ok(r, "grep: success with match")
	_assert(r["data"]["total_matches"] >= 1, "grep: found at least 1 match")

	# grep — regex
	r = FileSystem.grep("var\\s+\\w+", TEST_DIR, {"regex": true, "file_pattern": "*.gd"})
	_assert_ok(r, "grep: regex match")
	_assert(r["data"]["total_matches"] >= 1, "grep: regex found match")

	# grep — context_lines
	r = FileSystem.grep("speed", TEST_DIR, {"file_pattern": "*.gd", "context_lines": 1})
	_assert_ok(r, "grep: context_lines")
	if r["data"]["matches"].size() > 0:
		_assert(r["data"]["matches"][0].has("context_before"), "grep: has context_before")

	# grep — nonexistent path → error
	r = FileSystem.grep("x", "res://_sdk_test_nonexistent")
	_assert_err(r, "grep: nonexistent path returns error", "ERR_PATH_NOT_FOUND")

	# read_file — not found
	r = FileSystem.read_file("res://_sdk_test/nonexistent.txt")
	_assert_err(r, "read_file: missing file returns error")

	# delete_file — not found
	r = FileSystem.delete_file("res://_sdk_test/nonexistent.txt")
	_assert_err(r, "delete_file: missing file returns error")


# ===================================================================
# SceneOps
# ===================================================================

func _test_scene_ops() -> void:
	_group("SceneOps")

	# create_scene_from_json — basic scene with auto-completion
	var json := {
		"scene_name": "_sdk_test/test_scene",
		"root": {
			"name": "TestRoot",
			"type": "CharacterBody2D",
			"properties": {
				"position": {"_type": "Vector2", "x": 10, "y": 20}
			},
			"children": [
				{
					"name": "Sprite",
					"type": "Sprite2D",
					"properties": {}
				}
			]
		}
	}
	var r := SceneOps.create_scene_from_json(json)
	_assert_ok(r, "create_scene_from_json: success")
	_assert(r["data"]["auto_completed"] is Array, "create_scene_from_json: returns auto_completed")
	# CharacterBody2D should auto-get a CollisionShape2D
	_assert(r["data"]["auto_completed"].size() > 0, "create_scene_from_json: auto-completed CollisionShape2D")

	var scene_path: String = r["data"]["scene_path"]

	# scene_to_json
	r = SceneOps.scene_to_json(scene_path)
	_assert_ok(r, "scene_to_json: success")
	_assert(r["data"]["root"]["name"] == "TestRoot", "scene_to_json: root name matches")
	_assert(r["data"]["root"]["type"] == "CharacterBody2D", "scene_to_json: root type matches")

	# list_nodes
	r = SceneOps.list_nodes(scene_path)
	_assert_ok(r, "list_nodes: success")
	_assert(r["data"]["tree"]["name"] == "TestRoot", "list_nodes: tree root name")

	# get_node_info
	r = SceneOps.get_node_info(scene_path, "Sprite")
	_assert_ok(r, "get_node_info: success")
	_assert(r["data"]["type"] == "Sprite2D", "get_node_info: type is Sprite2D")

	# find_nodes_by_type
	r = SceneOps.find_nodes_by_type(scene_path, "Sprite2D")
	_assert_ok(r, "find_nodes_by_type: success")
	_assert(r["data"]["nodes"].size() >= 1, "find_nodes_by_type: found Sprite2D")

	# add_node
	r = SceneOps.add_node(scene_path, "", {
		"name": "Label",
		"type": "Label",
		"properties": {"text": "hello"}
	})
	_assert_ok(r, "add_node: success")

	# update_node
	r = SceneOps.update_node(scene_path, "Label", {"text": "updated"})
	_assert_ok(r, "update_node: success")

	# Verify update took effect
	r = SceneOps.get_node_info(scene_path, "Label")
	_assert_ok(r, "update_node: verify read back")
	_assert(r["data"]["properties"].get("text", "") == "updated", "update_node: property updated")

	r = SceneOps.update_node(scene_path, "Label", {"__sdk_missing_property": "value"})
	_assert_err(r, "update_node: invalid property returns error", "ERR_PROPERTY_NOT_FOUND")

	# move_node
	r = SceneOps.move_node(scene_path, "Label", "Sprite")
	_assert_ok(r, "move_node: success")
	# Verify it's now under Sprite
	r = SceneOps.get_node_info(scene_path, "Sprite/Label")
	_assert_ok(r, "move_node: node accessible at new path")

	# remove_node
	r = SceneOps.remove_node(scene_path, "Sprite/Label")
	_assert_ok(r, "remove_node: success")
	r = SceneOps.get_node_info(scene_path, "Sprite/Label")
	_assert_err(r, "remove_node: node is gone")

	# resave_scene
	r = SceneOps.resave_scene(scene_path)
	_assert_ok(r, "resave_scene: success")

	# save_scene with new_path
	var copy_scene := TEST_DIR + "/test_scene_copy.tscn"
	r = SceneOps.save_scene(scene_path, copy_scene)
	_assert_ok(r, "save_scene: save-as success")
	r = SceneOps.scene_to_json(copy_scene)
	_assert_ok(r, "save_scene: save-as can be loaded")
	_assert(r["data"]["root"]["name"] == "TestRoot", "save_scene: copied scene keeps root")

	# create_scene_from_json with custom script path as node type
	var custom_node_script := TEST_DIR + "/custom_node.gd"
	r = ScriptOps.create_script(custom_node_script, "@tool\nextends Node2D\n")
	_assert_ok(r, "create_scene_from_json: setup custom script node")
	r = SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/custom_script_scene",
		"root": {
			"name": "CustomRoot",
			"type": custom_node_script,
			"properties": {"position": {"_type": "Vector2", "x": 3, "y": 4}}
		}
	})
	_assert_ok(r, "create_scene_from_json: custom script path type")
	r = SceneOps.get_node_info("res://_sdk_test/custom_script_scene.tscn", "")
	_assert_ok(r, "create_scene_from_json: custom script scene info")
	_assert(r["data"]["script"] == custom_node_script, "create_scene_from_json: custom script attached")

	# Error paths
	r = SceneOps.scene_to_json("res://_sdk_test/nonexistent.tscn")
	_assert_err(r, "scene_to_json: missing scene returns error")

	r = SceneOps.create_scene_from_json({})
	_assert_err(r, "create_scene_from_json: missing root returns error")

	r = SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/invalid_property_scene",
		"root": {
			"name": "BrokenRoot",
			"type": "Node2D",
			"properties": {"__sdk_missing_property": 1}
		}
	})
	_assert_err(r, "create_scene_from_json: invalid property returns error", "ERR_PROPERTY_NOT_FOUND")

	r = SceneOps.remove_node(scene_path, "")
	_assert_err(r, "remove_node: empty path (root) returns error")

	r = SceneOps.add_node(scene_path, "NonexistentParent", {"name": "X", "type": "Node"})
	_assert_err(r, "add_node: nonexistent parent returns error")


# ===================================================================
# ScriptOps
# ===================================================================

func _test_script_ops() -> void:
	_group("ScriptOps")

	# create_script with base_type
	var r := ScriptOps.create_script(TEST_SCRIPT, "var speed := 200.0\n\nfunc _ready():\n\tpass\n\nfunc _process(delta):\n\tpass\n", "CharacterBody2D")
	_assert_ok(r, "create_script: success")

	# read_script
	r = ScriptOps.read_script(TEST_SCRIPT)
	_assert_ok(r, "read_script: success")
	_assert("extends CharacterBody2D" in r["data"]["content"], "create_script: auto-added extends")
	_assert("speed" in r["data"]["content"], "read_script: content has speed var")

	# get_script_structure
	r = ScriptOps.get_script_structure(TEST_SCRIPT)
	_assert_ok(r, "get_script_structure: success")
	_assert(r["data"]["extends"] == "CharacterBody2D", "get_script_structure: extends correct")
	_assert(r["data"]["variables"].size() >= 1, "get_script_structure: found variables")
	_assert(r["data"]["functions"].size() >= 2, "get_script_structure: found functions")

	# compile_check — valid
	r = ScriptOps.compile_check(TEST_SCRIPT)
	_assert_ok(r, "compile_check: returns ok")
	# Note: compile_check may not catch all errors without full editor context
	# The point is it returns ok:true with valid:true/false, not ok:false

	# update_script
	r = ScriptOps.update_script(TEST_SCRIPT, "extends CharacterBody2D\nvar speed := 300.0\n\nfunc _ready():\n\tprint(\"hello\")\n\nfunc _process(delta):\n\tpass\n")
	_assert_ok(r, "update_script: success")

	# update_script_function
	r = ScriptOps.update_script_function(TEST_SCRIPT, "_ready", "func _ready():\n\tprint(\"updated ready\")\n")
	_assert_ok(r, "update_script_function: success")
	r = ScriptOps.read_script(TEST_SCRIPT)
	_assert("updated ready" in r["data"]["content"], "update_script_function: content changed")

	# update_script_range
	r = ScriptOps.update_script_range(TEST_SCRIPT, 2, 2, "var speed := 999.0")
	_assert_ok(r, "update_script_range: success")
	r = ScriptOps.read_script(TEST_SCRIPT)
	_assert("999" in r["data"]["content"], "update_script_range: line replaced")

	# attach_script (use a dedicated scene so this test does not depend on SceneOps mutations)
	var scene_path := TEST_SCRIPT_SCENE
	r = SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/script_test_scene",
		"root": {"name": "TestRoot", "type": "Node2D", "children": [
			{"name": "Child", "type": "CharacterBody2D", "properties": {}}
		]}
	})
	_assert_ok(r, "attach_script: setup scene")
	r = ScriptOps.attach_script(scene_path, "Child", TEST_SCRIPT)
	_assert_ok(r, "attach_script: success")

	# detach_script
	r = ScriptOps.detach_script(scene_path, "Child")
	_assert_ok(r, "detach_script: success")

	# delete_script
	var temp_script := TEST_DIR + "/temp_delete.gd"
	ScriptOps.create_script(temp_script, "extends Node\n")
	r = ScriptOps.delete_script(temp_script)
	_assert_ok(r, "delete_script: success")
	r = ScriptOps.read_script(temp_script)
	_assert_err(r, "delete_script: file is gone", "ERR_SCRIPT_NOT_FOUND")

	# Error paths
	r = ScriptOps.read_script("res://_sdk_test/nonexistent.gd")
	_assert_err(r, "read_script: missing script returns error", "ERR_SCRIPT_NOT_FOUND")

	r = ScriptOps.update_script_function(TEST_SCRIPT, "nonexistent_func", "func x():\n\tpass\n")
	_assert_err(r, "update_script_function: missing function returns error", "ERR_FUNCTION_NOT_FOUND")

	r = ScriptOps.update_script_range(TEST_SCRIPT, 999, 1000, "x")
	_assert_err(r, "update_script_range: invalid range returns error", "ERR_INVALID_RANGE")

	r = ScriptOps.delete_script("res://_sdk_test/nonexistent.gd")
	_assert_err(r, "delete_script: missing file returns error", "ERR_SCRIPT_NOT_FOUND")


# ===================================================================
# ResourceOps
# ===================================================================

func _test_resource_ops() -> void:
	_group("ResourceOps")

	# Prepare a scene with a Sprite2D and a texture to bind
	var scene_path := TEST_DIR + "/res_test.tscn"
	SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/res_test",
		"root": {
			"name": "Root",
			"type": "Node2D",
			"children": [
				{"name": "Sprite", "type": "Sprite2D", "properties": {}},
				{"name": "Audio", "type": "AudioStreamPlayer", "properties": {}}
			]
		}
	})

	# Create a minimal resource file to bind (a .tres)
	var tex_path := TEST_DIR + "/test_tex.tres"
	var placeholder := PlaceholderTexture2D.new()
	placeholder.size = Vector2(64, 64)
	ResourceSaver.save(placeholder, tex_path)

	# bind_resource
	var r := ResourceOps.bind_resource(scene_path, "Sprite", "texture", tex_path)
	_assert_ok(r, "bind_resource: success")

	# get_node_resources
	r = ResourceOps.get_node_resources(scene_path, "Sprite")
	_assert_ok(r, "get_node_resources: success")
	var has_texture := false
	for res in r["data"]["resources"]:
		if res["property"] == "texture":
			has_texture = true
	_assert(has_texture, "get_node_resources: texture is bound")

	# get_scene_resources
	r = ResourceOps.get_scene_resources(scene_path)
	_assert_ok(r, "get_scene_resources: success")
	_assert(r["data"]["resources"] is Array, "get_scene_resources: returns array")

	# batch_bind
	r = ResourceOps.batch_bind(scene_path, [
		{"node_path": "Sprite", "property": "texture", "resource_path": tex_path},
	])
	_assert_ok(r, "batch_bind: success")
	_assert(r["data"]["bound"] >= 1, "batch_bind: bound count >= 1")

	# unbind_resource
	r = ResourceOps.unbind_resource(scene_path, "Sprite", "texture")
	_assert_ok(r, "unbind_resource: success")
	r = ResourceOps.get_node_resources(scene_path, "Sprite")
	var still_bound := false
	for res in r["data"]["resources"]:
		if res["property"] == "texture":
			still_bound = true
	_assert(not still_bound, "unbind_resource: texture is unbound")

	# Error paths
	r = ResourceOps.bind_resource(scene_path, "NonexistentNode", "texture", tex_path)
	_assert_err(r, "bind_resource: missing node returns error", "ERR_NODE_NOT_FOUND")

	r = ResourceOps.bind_resource(scene_path, "Sprite", "__sdk_missing_property", tex_path)
	_assert_err(r, "bind_resource: invalid property returns error", "ERR_PROPERTY_NOT_FOUND")

	r = ResourceOps.bind_resource(scene_path, "Sprite", "position", tex_path)
	_assert_err(r, "bind_resource: non-resource property returns error", "ERR_INVALID_PROPERTY")

	r = ResourceOps.batch_bind(scene_path, [
		{"node_path": "Sprite", "property": "__sdk_missing_property", "resource_path": tex_path},
	])
	_assert_ok(r, "batch_bind: invalid property still returns batch result")
	_assert(r["data"]["bound"] == 0, "batch_bind: invalid property does not bind")
	_assert(r["data"]["results"].size() == 1 and r["data"]["results"][0].get("code", "") == "ERR_PROPERTY_NOT_FOUND", "batch_bind: invalid property reports error code")

	r = ResourceOps.bind_resource(scene_path, "Sprite", "texture", "res://_sdk_test/nonexistent.tres")
	_assert_err(r, "bind_resource: missing resource returns error", "ERR_RESOURCE_NOT_FOUND")

	# export_mesh_library
	var mesh_scene := TEST_DIR + "/mesh_source.tscn"
	r = SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/mesh_source",
		"root": {
			"name": "MeshRoot",
			"type": "Node3D",
			"children": [
				{
					"name": "Wall",
					"type": "Node3D",
					"children": [
						{
							"name": "Mesh",
							"type": "MeshInstance3D",
							"properties": {
								"mesh": {
									"_type": "BoxMesh",
									"size": {"_type": "Vector3", "x": 2, "y": 1, "z": 1}
								}
							}
						},
						{
							"name": "Collision",
							"type": "CollisionShape3D",
							"properties": {
								"shape": {
									"_type": "BoxShape3D",
									"size": {"_type": "Vector3", "x": 2, "y": 1, "z": 1}
								}
							}
						}
					]
				}
			]
		}
	})
	_assert_ok(r, "export_mesh_library: setup mesh scene")
	var mesh_library_path := TEST_DIR + "/mesh_library.tres"
	r = ResourceOps.export_mesh_library(mesh_scene, mesh_library_path)
	_assert_ok(r, "export_mesh_library: success")
	_assert(FileAccess.file_exists(mesh_library_path), "export_mesh_library: file exists")
	var mesh_library = load(mesh_library_path)
	_assert(mesh_library is MeshLibrary, "export_mesh_library: loads as MeshLibrary")
	if mesh_library is MeshLibrary:
		_assert((mesh_library as MeshLibrary).get_item_list().size() >= 1, "export_mesh_library: contains items")

	# get_uid from existing sidecar file
	var uid_target := scene_path
	var uid_sidecar := uid_target + ".uid"
	var uid_file := FileAccess.open(uid_sidecar, FileAccess.WRITE)
	if uid_file != null:
		uid_file.store_string("uid://manual-test")
		uid_file.close()
	r = ResourceOps.get_uid(uid_target)
	_assert_ok(r, "get_uid: success")
	_assert(r["data"]["exists"] == true, "get_uid: sidecar detected")
	_assert(r["data"]["uid"] == "uid://manual-test", "get_uid: content matches")

	# update_project_uids
	var uid_scene := TEST_DIR + "/uid_scene.tscn"
	r = SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/uid_scene",
		"root": {"name": "UidRoot", "type": "Node2D"}
	})
	_assert_ok(r, "update_project_uids: setup scene")
	var uid_script := TEST_DIR + "/uid_target.gd"
	r = ScriptOps.create_script(uid_script, "extends Node\n")
	_assert_ok(r, "update_project_uids: setup script")
	var uid_script_sidecar_abs := ProjectSettings.globalize_path(uid_script + ".uid")
	if FileAccess.file_exists(uid_script + ".uid"):
		DirAccess.remove_absolute(uid_script_sidecar_abs)
	r = ResourceOps.update_project_uids(TEST_DIR)
	_assert_ok(r, "update_project_uids: success")
	_assert(r["data"]["scenes_processed"] >= 1, "update_project_uids: processed scenes")
	r = ResourceOps.get_uid(uid_script)
	_assert_ok(r, "update_project_uids: get_uid after refresh")
	if _supports_uids():
		_assert(r["data"]["exists"] == true, "update_project_uids: script UID generated on supported versions")
	else:
		_assert(r["data"].has("exists"), "update_project_uids: reports existence on older versions")


# ===================================================================
# ValidationOps
# ===================================================================

func _test_validation_ops() -> void:
	_group("ValidationOps")

	# Create a scene with known issues for validation
	var scene_path := TEST_DIR + "/validate_test.tscn"
	SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/validate_test",
		"root": {
			"name": "Root",
			"type": "Node2D",
			"children": [
				# CollisionShape2D without a parent body — valid node but orphan shape
				{"name": "Shape", "type": "CollisionShape2D", "properties": {}},
				{"name": "Sprite", "type": "Sprite2D", "properties": {}}
			]
		}
	})

	# validate_scene
	var r := ValidationOps.validate_scene(scene_path)
	_assert_ok(r, "validate_scene: returns ok")
	_assert(r["data"].has("valid"), "validate_scene: has valid field")
	_assert(r["data"].has("errors"), "validate_scene: has errors field")
	_assert(r["data"].has("warnings"), "validate_scene: has warnings field")
	# The CollisionShape2D has no shape, so there should be an error
	var has_missing_shape := false
	for err in r["data"]["errors"]:
		if err.get("code", "") == "MISSING_SHAPE":
			has_missing_shape = true
	_assert(has_missing_shape, "validate_scene: detected MISSING_SHAPE on CollisionShape2D")

	# validate_resources
	r = ValidationOps.validate_resources(scene_path)
	_assert_ok(r, "validate_resources: returns ok")
	_assert(r["data"].has("valid"), "validate_resources: has valid field")

	# validate_script_references
	r = ValidationOps.validate_script_references(scene_path)
	_assert_ok(r, "validate_script_references: returns ok")
	_assert(r["data"].has("valid"), "validate_script_references: has valid field")

	# validate_all
	r = ValidationOps.validate_all(scene_path)
	_assert_ok(r, "validate_all: returns ok")
	_assert(r["data"].has("scene"), "validate_all: has scene section")
	_assert(r["data"].has("resources"), "validate_all: has resources section")
	_assert(r["data"].has("scripts"), "validate_all: has scripts section")

	# Error paths
	r = ValidationOps.validate_scene("res://_sdk_test/nonexistent.tscn")
	_assert_err(r, "validate_scene: missing scene returns error")

	r = ValidationOps.validate_all("res://_sdk_test/nonexistent.tscn")
	_assert_err(r, "validate_all: missing scene returns error", "ERR_SCENE_LOAD_FAILED")

	# Create a scene with physics body missing collision shape (auto-complete disabled by
	# providing children list with a non-collision child) — validate should catch this
	var body_scene := TEST_DIR + "/body_test.tscn"
	# Build manually to bypass NodeRules auto-complete
	var body_root := CharacterBody2D.new()
	body_root.name = "Player"
	var label := Label.new()
	label.name = "HUD"
	body_root.add_child(label)
	label.set_owner(body_root)
	var packed := PackedScene.new()
	packed.pack(body_root)
	ResourceSaver.save(packed, body_scene)
	body_root.free()

	r = ValidationOps.validate_scene(body_scene)
	_assert_ok(r, "validate_scene: body without shape returns ok")
	var has_missing_collision := false
	for err in r["data"]["errors"]:
		if err.get("code", "") == "MISSING_COLLISION_SHAPE":
			has_missing_collision = true
	_assert(has_missing_collision, "validate_scene: detected MISSING_COLLISION_SHAPE on CharacterBody2D")


# ===================================================================
# ProjectConfig
# ===================================================================

func _test_project_config() -> void:
	_group("ProjectConfig")

	# set_setting / get_setting
	var r := ProjectConfig.set_setting("_sdk_test/custom_value", 42)
	_assert_ok(r, "set_setting: success")
	r = ProjectConfig.get_setting("_sdk_test/custom_value")
	_assert_ok(r, "get_setting: success")
	_assert(r["data"]["value"] == 42, "get_setting: value matches")

	# get_setting — not found
	r = ProjectConfig.get_setting("_sdk_test/nonexistent_key")
	_assert_err(r, "get_setting: missing key returns error", "ERR_SETTING_NOT_FOUND")

	# Clean up setting
	ProjectSettings.set("_sdk_test/custom_value", null)
	ProjectSettings.save()

	# add_input_action / get_input_actions / remove_input_action
	r = ProjectConfig.add_input_action("_sdk_test_jump", [
		{"type": "key", "keycode": "space"},
		{"type": "joypad_button", "button": 0}
	])
	_assert_ok(r, "add_input_action: success")
	_assert(r["data"]["event_count"] == 2, "add_input_action: 2 events bound")

	r = ProjectConfig.get_input_actions()
	_assert_ok(r, "get_input_actions: success")
	_assert(r["data"]["actions"].has("_sdk_test_jump"), "get_input_actions: has test action")

	r = ProjectConfig.remove_input_action("_sdk_test_jump")
	_assert_ok(r, "remove_input_action: success")

	r = ProjectConfig.remove_input_action("_sdk_test_nonexistent")
	_assert_err(r, "remove_input_action: missing action returns error", "ERR_SETTING_NOT_FOUND")

	# set_layer_name / get_layer_names
	r = ProjectConfig.set_layer_name("2d_physics", 1, "_sdk_test_player")
	_assert_ok(r, "set_layer_name: success")

	r = ProjectConfig.get_layer_names("2d_physics")
	_assert_ok(r, "get_layer_names: success")
	_assert(r["data"]["layers"].get("1", "") == "_sdk_test_player", "get_layer_names: name matches")

	# Clean up layer name
	ProjectSettings.set("layer_names/2d_physics/layer_1", "")
	ProjectSettings.save()

	# add_autoload / get_autoloads / remove_autoload
	# Create a dummy script for autoload
	var al_script := TEST_DIR + "/autoload_test.gd"
	ScriptOps.create_script(al_script, "extends Node\n")
	r = ProjectConfig.add_autoload("_SDKTestAutoload", al_script)
	_assert_ok(r, "add_autoload: success")

	# duplicate add should fail
	r = ProjectConfig.add_autoload("_SDKTestAutoload", al_script)
	_assert_err(r, "add_autoload: duplicate returns error", "ERR_AUTOLOAD_EXISTS")

	r = ProjectConfig.get_autoloads()
	_assert_ok(r, "get_autoloads: success")
	_assert(r["data"]["autoloads"].has("_SDKTestAutoload"), "get_autoloads: has test autoload")

	r = ProjectConfig.remove_autoload("_SDKTestAutoload")
	_assert_ok(r, "remove_autoload: success")

	r = ProjectConfig.remove_autoload("_SDKTestAutoload")
	_assert_err(r, "remove_autoload: missing returns error", "ERR_SETTING_NOT_FOUND")


# ===================================================================
# EditorOps
# ===================================================================

func _test_editor_ops() -> void:
	_group("EditorOps")

	# get_project_info
	var r := EditorOps.get_project_info()
	_assert_ok(r, "get_project_info: success")
	_assert(r["data"].has("name"), "get_project_info: has name")
	_assert(r["data"].has("godot_version"), "get_project_info: has godot_version")
	_assert(r["data"].has("project_path"), "get_project_info: has project_path")

	# get_open_scenes
	r = EditorOps.get_open_scenes()
	_assert_ok(r, "get_open_scenes: success")
	_assert(r["data"]["scenes"] is Array, "get_open_scenes: returns array")

	# get_log_timestamp
	r = EditorOps.get_log_timestamp()
	_assert_ok(r, "get_log_timestamp: success")
	_assert(r["data"]["timestamp"] > 0, "get_log_timestamp: timestamp > 0")

	# push_log + get_editor_logs (SDK internal buffer)
	var ts: float = r["data"]["timestamp"]
	# Small delay to ensure timestamps differ
	var Internal = preload("../src/editor/editor_ops_impl.gd")
	Internal.push_log("error", "test error message")
	Internal.push_log("warning", "test warning message")
	Internal.push_log("info", "test info message")

	r = EditorOps.get_editor_logs({"after_timestamp": ts})
	_assert_ok(r, "get_editor_logs: success")
	_assert(r["data"]["total"] >= 3, "get_editor_logs: got >= 3 entries after timestamp")

	# Filter by level
	r = EditorOps.get_editor_logs({"after_timestamp": ts, "level": "error"})
	_assert_ok(r, "get_editor_logs: level filter")
	for entry in r["data"]["logs"]:
		_assert(entry["level"] == "error", "get_editor_logs: filtered entry is error")

	# Limit
	r = EditorOps.get_editor_logs({"after_timestamp": ts, "limit": 1})
	_assert_ok(r, "get_editor_logs: limit")
	_assert(r["data"]["logs"].size() <= 1, "get_editor_logs: respects limit=1")

	# Engine log entries should be consumed once per read window.
	var old_log_path = ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")
	var temp_engine_log := TEST_DIR + "/editor_test.log"
	var temp_engine_log_abs := ProjectSettings.globalize_path(temp_engine_log)
	DirAccess.make_dir_recursive_absolute(temp_engine_log_abs.get_base_dir())
	var temp_log_file := FileAccess.open(temp_engine_log_abs, FileAccess.WRITE)
	if temp_log_file != null:
		temp_log_file.store_string("ERROR: engine replay check\n")
		temp_log_file.close()

	ProjectSettings.set("debug/file_logging/log_path", temp_engine_log)
	Internal._log_buffer.clear()
	Internal._engine_log_position = 0

	r = EditorOps.get_editor_logs({"level": "error"})
	_assert_ok(r, "get_editor_logs: engine log read succeeds")
	_assert(r["data"]["total"] == 1, "get_editor_logs: engine entry returned once")
	if r["data"]["logs"].size() > 0:
		_assert(r["data"]["logs"][0]["message"] == "engine replay check", "get_editor_logs: engine message parsed")
	else:
		_assert(false, "get_editor_logs: engine message parsed")

	r = EditorOps.get_editor_logs({"level": "error"})
	_assert_ok(r, "get_editor_logs: second engine read succeeds")
	_assert(r["data"]["total"] == 0, "get_editor_logs: engine entries are not replayed")

	ProjectSettings.set("debug/file_logging/log_path", old_log_path)
	Internal._engine_log_position = -1

	# refresh_filesystem
	r = EditorOps.refresh_filesystem()
	_assert_ok(r, "refresh_filesystem: success")

	# open_scene
	if ResourceLoader.exists(TEST_SCENE):
		r = EditorOps.open_scene(TEST_SCENE)
		_assert_ok(r, "open_scene: success")

	# open_scene — not found
	r = EditorOps.open_scene("res://_sdk_test/nonexistent.tscn")
	_assert_err(r, "open_scene: missing scene returns error")

	# open_script
	if FileAccess.file_exists(TEST_SCRIPT):
		r = EditorOps.open_script(TEST_SCRIPT, 1)
		_assert_ok(r, "open_script: success")

	# open_script — not found
	r = EditorOps.open_script("res://_sdk_test/nonexistent.gd")
	_assert_err(r, "open_script: missing script returns error")

	# Note: run_scene / stop_scene are not tested automatically because they
	# launch a child process.  They are verified manually.
	# We only assert the error path for non-editor context is unreachable here
	# (since this script IS running in the editor).


# ===================================================================
# TypeConverter round-trip
# ===================================================================

func _test_type_converter_round_trip() -> void:
	_group("TypeConverter round-trip")

	var TC = preload("../src/core/sdk_type_converter.gd")

	# Vector2 round-trip
	var v2 := Vector2(1.5, 2.5)
	var j: Dictionary = TC.value_to_typed_json(v2)
	_assert(j["_type"] == "Vector2", "Vector2: serializes as Vector2")
	var back: Variant = TC.convert_typed_value(j)
	_assert(back is Vector2, "Vector2: deserializes to Vector2")
	_assert(back == Vector2(1.5, 2.5), "Vector2: value preserved")

	# Vector2i round-trip
	var v2i := Vector2i(3, 4)
	j = TC.value_to_typed_json(v2i)
	_assert(j["_type"] == "Vector2i", "Vector2i: serializes as Vector2i (not Vector2)")
	back = TC.convert_typed_value(j)
	_assert(back is Vector2i, "Vector2i: deserializes to Vector2i")
	_assert(back == Vector2i(3, 4), "Vector2i: value preserved")

	# Vector3 round-trip
	var v3 := Vector3(1.0, 2.0, 3.0)
	j = TC.value_to_typed_json(v3)
	_assert(j["_type"] == "Vector3", "Vector3: serializes as Vector3")
	back = TC.convert_typed_value(j)
	_assert(back is Vector3, "Vector3: deserializes to Vector3")

	# Vector3i round-trip
	var v3i := Vector3i(5, 6, 7)
	j = TC.value_to_typed_json(v3i)
	_assert(j["_type"] == "Vector3i", "Vector3i: serializes as Vector3i (not Vector3)")
	back = TC.convert_typed_value(j)
	_assert(back is Vector3i, "Vector3i: deserializes to Vector3i")
	_assert(back == Vector3i(5, 6, 7), "Vector3i: value preserved")

	# Color round-trip
	var c := Color(1, 0, 0.5, 0.8)
	j = TC.value_to_typed_json(c)
	_assert(j["_type"] == "Color", "Color: serializes as Color")
	back = TC.convert_typed_value(j)
	_assert(back is Color, "Color: deserializes to Color")

	# Rect2 round-trip
	var rect := Rect2(10, 20, 30, 40)
	j = TC.value_to_typed_json(rect)
	_assert(j["_type"] == "Rect2", "Rect2: serializes as Rect2")
	back = TC.convert_typed_value(j)
	_assert(back is Rect2, "Rect2: deserializes to Rect2")

	# NodePath round-trip
	var np := NodePath("Parent/Child")
	j = TC.value_to_typed_json(np)
	_assert(j["_type"] == "NodePath", "NodePath: serializes as NodePath")
	back = TC.convert_typed_value(j)
	_assert(back is NodePath, "NodePath: deserializes to NodePath")
	_assert(str(back) == "Parent/Child", "NodePath: value preserved")

	# Enum round-trip
	var enum_json := {"_type": "Enum", "value": "keep_aspect"}
	back = TC.convert_typed_value(enum_json)
	_assert(back == "keep_aspect", "Enum: value passed through")

	# Inline resource — RectangleShape2D
	var shape_json := {"_type": "RectangleShape2D", "size": {"_type": "Vector2", "x": 32, "y": 32}}
	back = TC.convert_typed_value(shape_json)
	_assert(back is RectangleShape2D, "RectangleShape2D: created from JSON")
	_assert((back as RectangleShape2D).size == Vector2(32, 32), "RectangleShape2D: size correct")

	# Inline resource — CircleShape2D
	back = TC.convert_typed_value({"_type": "CircleShape2D", "radius": 16})
	_assert(back is CircleShape2D, "CircleShape2D: created from JSON")
	_assert((back as CircleShape2D).radius == 16.0, "CircleShape2D: radius correct")

	# Primitives pass through
	_assert(TC.value_to_typed_json(42) == 42, "int: pass-through")
	_assert(TC.value_to_typed_json("hello") == "hello", "string: pass-through")
	_assert(TC.value_to_typed_json(true) == true, "bool: pass-through")


# ===================================================================
# Error semantics consistency
# ===================================================================

func _test_error_semantics() -> void:
	_group("Error semantics")

	# validate_resources TYPE_MISMATCH should be an error (not warning),
	# consistent with bind_resource's ERR_TYPE_MISMATCH.
	# We can't easily forge a type mismatch in a saved scene without low-level
	# manipulation, so we verify the structural contract instead.
	var scene_path := TEST_DIR + "/error_test.tscn"
	SceneOps.create_scene_from_json({
		"scene_name": "_sdk_test/error_test",
		"root": {
			"name": "Root",
			"type": "Node2D",
			"children": [
				{"name": "Sprite", "type": "Sprite2D", "properties": {}}
			]
		}
	})

	# validate_resources returns correct structure
	var r := ValidationOps.validate_resources(scene_path)
	_assert_ok(r, "error_semantics: validate_resources returns ok")
	_assert(r["data"].has("valid"), "error_semantics: has valid")
	_assert(r["data"].has("errors"), "error_semantics: has errors (not just warnings)")

	# bind_resource type mismatch returns ERR_TYPE_MISMATCH
	# Create an audio stream resource and try to bind it as a texture
	var audio_path := TEST_DIR + "/test_audio.tres"
	var stream := AudioStreamGenerator.new()
	ResourceSaver.save(stream, audio_path)
	r = ResourceOps.bind_resource(scene_path, "Sprite", "texture", audio_path)
	_assert_err(r, "error_semantics: bind type mismatch returns error", "ERR_TYPE_MISMATCH")

	# Verify write operations propagate failures
	# attach_script to nonexistent scene
	r = ScriptOps.attach_script("res://_sdk_test/nonexistent.tscn", "X", TEST_SCRIPT)
	_assert_err(r, "error_semantics: attach_script missing scene returns error")

	# detach_script from nonexistent scene
	r = ScriptOps.detach_script("res://_sdk_test/nonexistent.tscn", "X")
	_assert_err(r, "error_semantics: detach_script missing scene returns error")
