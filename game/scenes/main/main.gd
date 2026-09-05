extends Node
## 主场景控制（WP-02/R1 + WP-03 + WP-04 玩家纵切）。
## 世界加载成功 -> 地图 build -> 四面边界 -> 唯一 Player（spawn tile 出生，注入相机与
## actor 配置）-> CameraRig 立即绑定玩家 -> 清旧交互 UI -> 显示世界与操作提示。
## 任一步失败 -> apply_error：删 Player、清边界、解绑相机、清交互、隐藏并停用 World。
## autoload 经 /root/... 动态获取；节点引用用显式路径。

const DEMO_SPEC_PATH := "res://data/demo_world/world_spec.json"
const PLAYER_SCENE := preload("res://scenes/actors/player.tscn")
const CONTROL_HINT := "WASD/方向键移动 · Q/R旋转 · 滚轮缩放 · E/空格交互 · Esc暂停"

@onready var world_root: Node3D = $World
@onready var sun: DirectionalLight3D = $World/Sun
@onready var actor_root: Node3D = $World/ActorRoot
@onready var boundary_root: Node3D = $World/BoundaryRoot
@onready var camera: Camera3D = $World/CameraRig/YawPivot/MainCamera
@onready var camera_ctl: IsometricCameraController = $World/CameraRig
@onready var map_controller: Node = $World/MapController
@onready var pause_controller: Node = $Ui/PauseController
@onready var title_label: Label = $Ui/Hud/TitleLabel
@onready var control_hint_label: Label = $Ui/Hud/ControlHintLabel
@onready var interaction_prompt: Label = $Ui/Hud/InteractionPrompt
@onready var toast_label: Label = $Ui/Hud/ToastLabel
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
@onready var debug_player_state_label: Label = $Ui/DebugOverlay/DebugPanel/DebugVBox/DebugPlayerStateLabel

var _current_spec: Dictionary = {}
var _mode := "demo"
var _last_error_code := "-"
var _last_error_message := "-"
var _player: PlayerController = null
var _toast_token := 0

func _ready() -> void:
	sun.rotation_degrees = Vector3(-55, -35, 0)
	pause_controller.setup($Ui/PauseMenu)
	pause_controller.set_world_active(false)

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
	_last_error_code = "-"
	_last_error_message = "-"
	var app_config := get_node_or_null("/root/AppConfig")
	_mode = str(app_config.mode) if app_config and not str(app_config.mode).is_empty() else "demo"

	var map_config: Dictionary = {}
	var raw_cfg: Dictionary = app_config.raw if app_config and typeof(app_config.raw) == TYPE_DICTIONARY else {}
	var raw_map = raw_cfg.get("map", {})
	if typeof(raw_map) == TYPE_DICTIONARY:
		map_config = raw_map

	var build_result: Dictionary = map_controller.build(spec, map_config)
	if not build_result.ok:
		apply_error(str(build_result.code), str(build_result.message))
		return

	var sz: Vector2i = map_controller.map_size()
	MapBoundaryBuilder.build(boundary_root, sz.x, sz.y)
	_spawn_player(raw_cfg)
	_bind_camera(raw_cfg)

	world_root.visible = true
	world_root.process_mode = Node.PROCESS_MODE_INHERIT
	world_root.set_process(true)
	error_panel.visible = false
	pause_controller.set_world_active(true)
	title_label.text = "%s\nseed=%s · mode=%s · 世界已就绪" % [
		str(spec.get("title", "")), str(spec.get("seed", "-")), _mode]
	control_hint_label.text = CONTROL_HINT
	interaction_prompt.visible = false
	toast_label.visible = false
	_refresh_debug()
	if OS.get_environment("AIW_SCREENSHOT_AUTOPILOT") == "1":
		_start_screenshot_autopilot()

func apply_error(code: String, message: String) -> void:
	_last_error_code = code
	_last_error_message = message
	_cleanup_runtime()
	world_root.visible = false
	world_root.process_mode = Node.PROCESS_MODE_DISABLED
	world_root.set_process(false)
	error_panel.visible = true
	error_code_label.text = code
	error_message_label.text = message
	title_label.text = "AIWorld Prototype"
	control_hint_label.text = ""
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
	if _player != null and is_instance_valid(_player):
		var ps: Dictionary = _player.get_debug_state()
		var world_pos: Vector3 = ps["world"]
		d["player_tile"] = "(%d, %d, %d)" % [ps["tile"].x, ps["tile"].z, ps["tile"].y]
		d["player_world"] = "(%.2f, %.2f, %.2f)" % [world_pos.x, world_pos.y, world_pos.z]
		d["player_floor"] = str(ps["on_floor"])
		d["player_speed"] = "%.2f" % float(ps["speed"])
		d["fall_recoveries"] = str(ps["fall_recoveries"])
		var interactor = _player.get_node_or_null("InteractionArea")
		d["interaction_target"] = str(interactor.current_target_id) if interactor else "-"
	else:
		d["player_tile"] = "-"
		d["player_world"] = "-"
		d["player_floor"] = "-"
		d["player_speed"] = "-"
		d["fall_recoveries"] = "-"
		d["interaction_target"] = "-"
	var cam_d: Dictionary = camera_ctl.get_debug_state()
	d["camera_yaw"] = str(cam_d.get("yaw", "-"))
	d["camera_size"] = str(cam_d.get("size", "-"))
	return d

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		debug_overlay.visible = not debug_overlay.visible
		var hub := get_node_or_null("/root/EventHub")
		if hub:
			hub.debug_overlay_toggled.emit(debug_overlay.visible)
		_refresh_debug()
	elif event.is_action_pressed("interact"):
		if _player != null and is_instance_valid(_player):
			var interactor = _player.get_node_or_null("InteractionArea")
			if interactor:
				interactor.try_interact()

func _spawn_player(raw_cfg: Dictionary) -> void:
	for c in actor_root.get_children():
		actor_root.remove_child(c)
		c.free()
	var player: PlayerController = PLAYER_SCENE.instantiate()
	actor_root.add_child(player)
	var actor_cfg = raw_cfg.get("actors", {})
	if typeof(actor_cfg) != TYPE_DICTIONARY:
		actor_cfg = {}
	player.configure(camera, map_controller.get_spawn_tile(), map_controller.map_size(), actor_cfg)
	player.tile_changed.connect(_on_player_tile_changed)
	player.fell_and_recovered.connect(_on_player_fell)
	var interactor: PlayerInteractor = player.get_node("InteractionArea")
	interactor.player = player
	interactor.camera = camera
	interactor.target_changed.connect(_on_target_changed)
	interactor.interaction_requested.connect(_on_interaction_requested)
	_player = player

func _bind_camera(raw_cfg: Dictionary) -> void:
	var cam_cfg = raw_cfg.get("camera", {})
	if typeof(cam_cfg) != TYPE_DICTIONARY:
		cam_cfg = {}
	camera_ctl.configure(cam_cfg)
	camera_ctl.kill_tween()
	camera_ctl.bind_target(_player, true)

func _cleanup_runtime() -> void:
	if _player != null and is_instance_valid(_player):
		actor_root.remove_child(_player)
		_player.free()
	_player = null
	MapBoundaryBuilder.clear(boundary_root)
	camera_ctl.clear_target()
	camera_ctl.kill_tween()
	interaction_prompt.visible = false
	toast_label.visible = false
	pause_controller.set_world_active(false)

func _on_player_tile_changed(actor_id: String, tile: Vector3i) -> void:
	var hub := get_node_or_null("/root/EventHub")
	if hub:
		hub.player_tile_changed.emit(actor_id, tile)

func _on_player_fell(_from_position: Vector3, to_tile: Vector3i) -> void:
	print("Main: 玩家安全恢复到 last_safe_tile %s" % str(to_tile))

func _on_target_changed(target_id: String, display_name: String) -> void:
	if target_id.is_empty():
		interaction_prompt.visible = false
	else:
		interaction_prompt.text = "E / 空格：查看「%s」" % display_name
		interaction_prompt.visible = true

func _on_interaction_requested(target_id: String, display_name: String) -> void:
	var hub := get_node_or_null("/root/EventHub")
	if hub:
		hub.player_interacted.emit(target_id, display_name)
	toast_label.text = "已到达：" + display_name
	toast_label.visible = true
	_toast_token += 1
	var token := _toast_token
	await get_tree().create_timer(2.0).timeout
	if token == _toast_token:
		toast_label.visible = false

# —— 截图专用自动驾驶（默认关闭；仅 AIW_SCREENSHOT_AUTOPILOT=1 时把玩家带到最近 POI）——
func _start_screenshot_autopilot() -> void:
	if _player == null or not map_controller.has_map():
		return
	var pois: Dictionary = map_controller.get_poi_tiles()
	if pois.is_empty():
		return
	var nearest := Vector3i.ZERO
	var best_d := 1 << 30
	for pid in pois:
		var t: Vector3i = pois[pid]
		var dist := absi(t.x - _player.get_current_tile().x) + absi(t.z - _player.get_current_tile().z)
		if dist < best_d:
			best_d = dist
			nearest = t
	var path: Array = map_controller.find_walk_path(_player.get_current_tile(), nearest)
	# 截图专用（R1）：走到 POI 相邻格后，在 ≤1.75m 的可行走候选中选屏幕投影
	# 与 marker 分离最明显的位置，保证玩家不被 POI 柱/标签遮挡。
	var stop_tile := _pick_screenshot_stop(nearest, path)
	var walk_path: Array = map_controller.find_walk_path(_player.get_current_tile(), stop_tile)
	if walk_path.is_empty():
		walk_path = path.slice(0, maxi(path.size() - 1, 1))
	for cell in walk_path:
		var target := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
		var guard := 0
		while guard < 240:
			var to := target - _player.global_position
			to.y = 0.0
			if to.length() < 0.15:
				break
			_player.set_test_world_direction(to.normalized())
			await get_tree().physics_frame
			guard += 1
		if _player == null or not is_instance_valid(_player):
			return
	_player.clear_test_input()

# 在 POI 四邻/两格内的可行走候选中，选与 marker 屏幕投影距离最大的候选（不站 marker 格）
func _pick_screenshot_stop(poi_tile: Vector3i, fallback_path: Array) -> Vector3i:
	if camera == null:
		return fallback_path[maxi(fallback_path.size() - 2, 0)] if fallback_path.size() >= 2 else poi_tile
	var marker_world := GridCoord.tile_to_world(poi_tile)
	var best_tile := poi_tile
	var best_sep := -1.0
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		var cand := Vector3i(poi_tile.x + int(d.x), 0, poi_tile.z + int(d.y))
		if cand == poi_tile or not map_controller.is_walkable_tile(cand):
			continue
		var cw := GridCoord.tile_to_world(cand)
		if Vector2(cw.x - marker_world.x, cw.z - marker_world.z).length() > 1.7:
			continue
		var s_marker: Vector2 = camera.unproject_position(marker_world + Vector3(0, 1.0, 0))
		var s_cand: Vector2 = camera.unproject_position(cw + Vector3(0, 0.8, 0))
		var sep := s_marker.distance_to(s_cand)
		if sep > best_sep:
			best_sep = sep
			best_tile = cand
	if best_tile == poi_tile and fallback_path.size() >= 2:
		best_tile = fallback_path[fallback_path.size() - 2]
	return best_tile

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
	debug_player_state_label.text = "player: %s %s floor=%s spd=%s\ncam: yaw=%s size=%s | target=%s | falls=%s" % [
		d.get("player_tile", "-"), d.get("player_world", "-"), d.get("player_floor", "-"),
		d.get("player_speed", "-"), d.get("camera_yaw", "-"), d.get("camera_size", "-"),
		d.get("interaction_target", "-"), d.get("fall_recoveries", "-")]
