@tool
class_name FileSystem
extends RefCounted

const Internal = preload("../src/file/file_system_impl.gd")

static func get_directory_tree(path: String, options: Dictionary = {}) -> Dictionary:
	return Internal.get_directory_tree(path, options)

static func read_file(path: String) -> Dictionary:
	return Internal.read_file(path)

static func write_file(path: String, content: String) -> Dictionary:
	return Internal.write_file(path, content)

static func file_exists(path: String) -> Dictionary:
	return Internal.file_exists(path)

static func dir_exists(path: String) -> Dictionary:
	return Internal.dir_exists(path)

static func list_files(path: String, pattern: String = "") -> Dictionary:
	return Internal.list_files(path, pattern)

static func get_file_info(path: String) -> Dictionary:
	return Internal.get_file_info(path)

static func copy_file(from: String, to: String) -> Dictionary:
	return Internal.copy_file(from, to)

static func move_file(from: String, to: String) -> Dictionary:
	return Internal.move_file(from, to)

static func delete_file(path: String) -> Dictionary:
	return Internal.delete_file(path)

static func grep(pattern: String, path: String, options: Dictionary = {}) -> Dictionary:
	return Internal.grep(pattern, path, options)
