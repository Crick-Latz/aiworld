extends Node
## 主场景控制（WP-02）：WorldSpec 加载成功→显示世界标题与状态；失败→隐藏 World、
## 停止其处理并显示 ErrorPanel（稳定错误码+简短消息，不含堆栈/密钥/私密内容）；F3 切换 DebugOverlay。
## autoload 一律通过 /root/... 动态获取：正常游戏时它们必然存在；独立实例化（测试）时安全降级。
## 节点引用使用显式相对路径（比 %UniqueName 在根脚本上更不依赖场景状态）。

const DEMO_SPEC_PATH := "res://data/demo_world/world_spec.json"

@onready var world_root: Node3D = $World
@onready var sun: DirectionalLight3D = $World/Sun
@onready var camera: Camera3D = $World/CameraRig/YawPivot/MainCamera
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

var _current_spec: Dictionary = {}
var _mode := "demo"
var _last_error_code := "-"
var _last_error_message := "-"

func _ready() -> void:
	sun.rotation_degrees = Vector3(-55, -35, 0)
	# 相机从 (12,12,12) 看向原点：45° 方位角、约 35.26° 俯角的正交等距画面。
	# 不注册任何俯仰/旋转输入——自由俯仰被禁止，Q/R 旋转留到后续纵切（WP-04）。
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
	var app_config := get_node_or_null("/root/AppConfig")
	_mode = str(app_config.mode) if app_config and not str(app_config.mode).is_empty() else "demo"
	world_root.visible = true
	world_root.process_mode = Node.PROCESS_MODE_INHERIT
	world_root.set_process(true)
	error_panel.visible = false
	title_label.text = "%s\nseed=%s · mode=%s · 世界已就绪" % [str(spec.get("title", "")), str(spec.get("seed", "-")), _mode]
	_refresh_debug()

func apply_error(code: String, message: String) -> void:
	_last_error_code = code
	_last_error_message = message
	world_root.visible = false
	world_root.process_mode = Node.PROCESS_MODE_DISABLED # 停用整个 World 子树，子节点不再处理
	world_root.set_process(false)
	error_panel.visible = true
	error_code_label.text = code
	error_message_label.text = message
	title_label.text = "AIWorld Prototype"
	_refresh_debug()

func get_debug_info() -> Dictionary:
	return {
		"world_id": str(_current_spec.get("world_id", "-")),
		"schema_version": str(_current_spec.get("schema_version", "-")),
		"seed": str(_current_spec.get("seed", "-")),
		"generator_version": str(_current_spec.get("generator_version", "-")),
		"mode": _mode,
		"error": "%s: %s" % [_last_error_code, _last_error_message],
		"camera_projection": "orthogonal" if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else "other",
		"camera_orthogonal_size": camera.size,
	}

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
