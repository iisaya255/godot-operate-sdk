# godot-editor-ops-sdk

[English](./README.md) | [简体中文](./README.zh-CN.md)

Godot editor-only SDK for secondary development, supporting scene, script, resource, and file operations.
It is not a standalone runnable SDK; you can directly integrate the folder into your own project. Internal imports use relative `preload()` paths, so the SDK can live under any project path as long as the folder structure stays intact.

Not headless-safe — all file-system refresh calls are guarded by `Engine.is_editor_hint()`.

## Layout

```text
godot-editor-ops-sdk/
|- api/                        # Public API — depend on these
|  |- godot_sdk.gd             # Unified entry (GodotSDK.scene, .fs, …)
|  |- scene_ops.gd             # Scene CRUD, JSON round-trip
|  |- script_ops.gd            # Script CRUD, attach/detach
|  |- resource_ops.gd          # Resource bind/unbind, inspection
|  |- file_system.gd           # File/dir ops, grep
|  |- editor_ops.gd            # Run/stop scene, open scene/script
|  |- validation_ops.gd        # Scene, resource, script validation
|  `- project_config.gd        # Project settings read/write
`- src/                        # Internal implementation — do not import
   |- core/                    # Result, PathUtils, FileWriter, TypeConverter
   |- scene/                   # SceneOps impl, NodeRules
   |- script/                  # ScriptOps impl
   |- resource/                # ResourceOps impl
   |- file/                    # FileSystem impl
   |- editor/                  # EditorOps impl
   |- validation/              # Validation impl
   `- config/                  # ProjectConfig impl
```

## Usage

```gdscript
# Via unified entry
GodotSDK.scene.create_scene_from_json(json)
GodotSDK.fs.grep("player", "res://scripts")

# Or import individual modules
SceneOps.add_node(scene_path, parent_path, node_json)
ScriptOps.create_script(path, content)
FileSystem.read_file(path)
```

All API methods return `{ "ok": true, "data": { ... } }` on success or `{ "ok": false, "error": "...", "code": "ERR_..." }` on failure.

## Notes

- Depend on `api/` from consumers. Treat `src/` as internal.
- Asset indexing / search / parser integration lives in `addons/godot-ai`.

## License

MIT, See [LICENSE](./LICENSE).
