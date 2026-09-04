extends Node
## 主场景控制（WP-02/R1 + WP-03）。
## 世界加载成功 -> MapController 构建地图并投影；失败 -> 隐藏并停用 World 子树，
## ErrorPanel 显示稳定错误码。F3 切换 DebugOverlay（含地图诊断字段）。
## autoload 一律通过 /root/... 动态获取：正常游戏时它们必然存在；独立实例化（测试）时安全降级。
## 节点引用使用显式相对路径（比 %UniqueName 在根脚本上更不依赖场景状态）。

const DEMO_SPEC_PATH := "res://data/demo_world/world_spec.json"

@onready var world_root: Node3D = $World
@onready var sun: DirectionalLight3D = $World/Sun
@onready var camera_rig: Node3D = $World/CameraRig
@onready var camera: Camera3D = $World/CameraRig/YawPivot/MainCamera
@onready var map_controller: Node = $World/MapController
@onready var title_label: Label = $Ui/Hud/TitleLabel
@onready var error_panel: Control = $Ui/ErrorPanel
@onready var error_code_label: Label = $Ui/ErrorPanel/ErrorBox/ErrorVBox/ErrorCodeLabel
@onready var error_message_label: Label = $Ui/ErrorPanel/ErrorBox/ErrorVBox/ErrorMessageLabel
@onready var debug_overlay: Control = $Ui/DebugOverlay
@onready var debug_world_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugWorldLabel
@onready var debug_schema_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugSchemaLabel
@onready var debug_seed_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugSeedLabel
@onready var debug_gen_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugGenLabel
@onready var debug_mode_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugModeLabel
@onready var debug_error_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugErrorLabel
@onready var debug_camera_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugCameraLabel
@onready var debug_map_hash_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugMapHashLabel
@onready var debug_map_ratio_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugMapRatioLabel
@onready var debug_map_cells_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugMapCellsLabel
@onready var debug_map_spawn_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugMapSpawnLabel

var _current_spec: Dictionary = {}
var _mode := "demo"
var _last_error_code := "-"
var _last_error_message := "-"

func _ready() -> void:
	sun.rotation_degrees = Vector3(-55, -35, 0)
	# 相机从 (12,12,12) 看向原点：45° 方位角、约 35.26° 俯角的正交等距画面。
	# 禁止自由俯仰；Q/R 旋转留到 WP-04。apply_world 成功后会把 rig 平移到地图中心。
	camera.look_at(Vector3.ZERO)

	var hub := get_node_or_null("/root/EventHub")
	if hub:
		hub.world_loaded.connect(_on_world_loaded)
		hub.world_load_failed.connect(_on_world_load_failed)

	var session := get_node_or_null("/root/GameSession")
	if session and not session.world.is_empty():
		apply_world(session.world)
	elif session and not session.world_error_code.is_empty():
		apply_error(session.world_error_code, session.world_error_message)
	else:
		var result := WorldSpecLoader.load_from_path(DEMO_SPEC_PATH)
		if result.ok:
			apply_world(result.data)
		else:
			apply_error(result.code, result.message)

func apply_world(spec: Dictionary) -> void:
	_current_spec = spec
	_last_error_code = "-" # 从错误状态恢复为合法世界时清掉旧错误（R1）
	_last_error_message = "-"
	var app_config := get_node_or_null("/root/AppConfig")
	_mode = str(app_config.mode) if app_config and not str(app_config.mode).is_empty() else "demo"

	# 地图构建（WP-03）：失败复用 ErrorPanel 并停用 World 子树
	var map_config: Dictionary = {}
	if app_config and typeof(app_config.raw) == TYPE_DICTIONARY:
		var raw_map = app_config.raw.get("map", {})
		if typeof(raw_map) == TYPE_DICTIONARY:
			map_config = raw_map
	var build_result: Dictionary = map_controller.build(spec, map_config)
	if not build_result.ok:
		apply_error(str(build_result.code), str(build_result.message))
		return

	world_root.visible = true
	world_root.process_mode = Node.PROCESS_MODE_INHERIT
	world_root.set_process(true)
	error_panel.visible = false
	title_label.text = "%s\nseed=%s · mode=%s · 世界已就绪 · %s" % [
		str(spec.get("title", "")), str(spec.get("seed", "-")), _mode, str(map_controller.get_map_debug().get("map_hash", "-")).substr(0, 20)]

	# 把正交等距视角对准地图中心
	if map_controller.has_map():
		var sz: Vector2i = map_controller.map_size()
		var center := Vector3(sz.x * 0.5, 0.0, sz.y * 0.5)
		camera_rig.position = center + Vector3(12, 12, 12)
		camera.look_at(center)
	_refresh_debug()

func apply_error(code: String, message: String) -> void:
	_last_error_code = code
	_last_error_message = message
	world_root.visible = false
	world_root.process_mode = Node.PROCESS_MODE_DISABLED # 停用整个 World 子树
	world_root.set_process(false)
	error_panel.visible = true
	error_code_label.text = code
	error_message_label.text = message
	title_label.text = "AIWorld Prototype"
	_refresh_debug()

func get_debug_info() -> Dictionary:
	var d := {
		"world_id": str(_current_spec.get("world_id", "-")),
		"schema_version": str(_current_spec.get("schema_version", "-")),
		"seed": str(_current_spec.get("seed", "-")),
		"generator_version": str(_current_spec.get("generator_version", "-")),
		"mode": _mode,
		"error": "%s: %s" % [_last_error_code, _last_error_message],
		"camera_projection": "orthogonal" if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "other",
		"camera_orthogonal_size": camera.size,
	}
	var m: Dictionary = map_controller.get_map_debug()
	for k in m:
		d[k] = m[k]
	return d

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible
		var hub := get_node_or_null("/root/EventHub")
		if hub:
			hub.debug_overlay_toggled.emit(debug_overlay.visible)
		_refresh_debug()

func _on_world_loaded(_ok: bool, _world_id: String) -> void:
	var session := get_node_or_null("/root/GameSession")
	if session and not session.world.is_empty():
		apply_world(session.world)

func _on_world_load_failed(code: String, message: String) -> void:
	apply_error(code, message)

func _refresh_debug() -> void:
	var d := get_debug_info()
	debug_world_label.text = "world_id: " + d["world_id"]
	debug_schema_label.text = "schema_version: " + d["schema_version"]
	debug_seed_label.text = "seed: " + d["seed"]
	debug_gen_label.text = "generator_version: " + d["generator_version"]
	debug_mode_label.text = "mode: " + d["mode"]
	debug_error_label.text = "error: " + d["error"]
	debug_camera_label.text = "camera: %s (size=%s)" % [d["camera_projection"], d["camera_orthogonal_size"]]
	debug_map_hash_label.text = "map: %s retry=%s" % [d.get("map_generator_version", "-"), d.get("map_retry_index", "-")]
	debug_map_hash_label.text += "\nhash: " + str(d.get("map_hash", "-"))
	debug_map_ratio_label.text = "size: %s | ratios: %s" % [d.get("map_size", "-"), d.get("map_ratios", "-")]
	debug_map_cells_label.text = "cells: %s | poi=%s" % [d.get("map_cells", "-"), d.get("poi_count", "-")]
	debug_map_spawn_label.text = "spawn: %s | err: %s" % [d.get("spawn_tile", "-"), d.get("map_error", "-")]
