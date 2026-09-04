extends Node
## GameSession：会话状态（WP-02 / R1）。只加载公开 WorldSpec——绝不读取
## director_secrets.json / last_failure_report.json / config.json / 任何密钥。
## R1：AppConfig 失败必须阻断世界加载——复制稳定错误码/消息、world 保持为空、
## 发 world_load_failed，并且不再读取/发布 WorldSpec。
## autoload 通过 /root/... 动态获取，保证注册顺序解耦与可测试性。

const DEMO_SPEC_PATH := "res://data/demo_world/world_spec.json"

var world: Dictionary = {}
var world_error_code := ""
var world_error_message := ""
var mode := "demo"

func _ready() -> void:
	var app_config := get_node_or_null("/root/AppConfig")
	if app_config and not str(app_config.mode).is_empty():
		mode = str(app_config.mode)

	var hub := get_node_or_null("/root/EventHub")

	if app_config and not str(app_config.last_error_code).is_empty():
		world_error_code = str(app_config.last_error_code)
		world_error_message = str(app_config.last_error_message)
		world = {}
		print("GameSession: 配置失败，已阻断世界加载：%s: %s" % [world_error_code, world_error_message])
		if hub:
			hub.world_load_failed.emit(world_error_code, world_error_message)
		return

	var result := WorldSpecLoader.load_from_path(DEMO_SPEC_PATH)
	if result.ok:
		world = result.data
		if hub:
			hub.world_loaded.emit(true, str(world.get("world_id", "")))
	else:
		world_error_code = str(result.code)
		world_error_message = str(result.message)
		print("GameSession: %s: %s" % [world_error_code, world_error_message])
		if hub:
			hub.world_load_failed.emit(world_error_code, world_error_message)
