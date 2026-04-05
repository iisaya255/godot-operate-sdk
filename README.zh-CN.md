# godot-editor-ops-sdk

[English](./README.md) | [简体中文](./README.zh-CN.md)

这是一个用于二次开发的 Godot 编辑器专用 SDK，支持场景、脚本、资源和文件操作

该 SDK 并非独立可运行的程序，你可以将整个目录直接接入自己的项目中使用。内部依赖改为相对 `preload()` 路径，只要目录结构保持不变，就不需要再手动修改引用路径

支持版本：仅适用于 Godot 4.x。

不适用于无头模式(headless) - 所有文件系统刷新调用都通过 Engine.is_editor_hint() 进行保护

## 目录结构

```text
godot-editor-ops-sdk/
|- api/                        # 对外公开 API，供调用方依赖
|  |- godot_sdk.gd             # 统一入口（GodotSDK.scene、.fs 等）
|  |- scene_ops.gd             # 场景 CRUD、JSON 往返转换、保存/另存为
|  |- script_ops.gd            # 脚本 CRUD、挂载/卸载
|  |- resource_ops.gd          # 资源绑定/解绑、检查、MeshLibrary、UID
|  |- file_system.gd           # 文件/目录操作、grep
|  |- editor_ops.gd            # 运行/停止场景，打开场景/脚本
|  |- validation_ops.gd        # 场景、资源、脚本校验
|  `- project_config.gd        # 项目设置读写
`- src/                        # 内部实现，不要直接导入
   |- core/                    # Result、PathUtils、FileWriter、TypeConverter
   |- scene/                   # SceneOps 实现、NodeRules
   |- script/                  # ScriptOps 实现
   |- resource/                # ResourceOps 实现
   |- file/                    # FileSystem 实现
   |- editor/                  # EditorOps 实现
   |- validation/              # Validation 实现
   `- config/                  # ProjectConfig 实现
```

## 用法

```gdscript
# 通过统一入口
GodotSDK.scene.create_scene_from_json(json)
GodotSDK.scene.save_scene("res://scenes/main.tscn", "res://scenes/main_copy.tscn")
GodotSDK.fs.grep("player", "res://scripts")
GodotSDK.resource.export_mesh_library("res://scenes/tileset.tscn", "res://assets/tileset_mesh_library.tres")

# 或单独导入模块
SceneOps.add_node(scene_path, parent_path, node_json)
ScriptOps.create_script(path, content)
FileSystem.read_file(path)
```

所有 API 方法在成功时返回 `{ "ok": true, "data": { ... } }`，失败时返回 `{ "ok": false, "error": "...", "code": "ERR_..." }`。

当前 API 已覆盖场景保存/另存为、MeshLibrary 导出、UID 查询与更新，以及使用内置类、脚本路径或已注册全局脚本类作为节点类型的场景创建与加节点流程。

## 说明

- 调用方应依赖 `api/`。`src/` 应视为内部实现。
- 资源索引 / 搜索 / 解析器集成位于 `addons/godot-ai`。

## 许可证

MIT 详见 [LICENSE](./LICENSE)。
