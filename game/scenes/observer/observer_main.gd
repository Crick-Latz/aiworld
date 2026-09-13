extends Node
## 观察模式装配根（OBS-01，M01）：只负责创建模块、注入端口、连接信号与销毁。
## 不在此计算 NPC 目标、拼每条事件文案；无 Player、无自动驾驶、无整树暂停。
## 模拟暂停与相机/UI 解耦：Simulation 停 tick，视觉插值冻结，相机/按钮仍可用。
## UI-R1：island 默认模式切 2D 像素表现（World2D 子树）；wander/story 演示模式保留 3D。

const DEMO_SPEC_PATH := "res://data/demo_world/world_spec.json"
const NPC_SCENE := preload("res://scenes/actors/npc.tscn")
const NPC2D_SCENE := preload("res://scenes/observer/npc_2d.tscn")
# UI-R1 2D 模式的环境底色（暖色深水），进入 3D 演示模式时还原
const ISLAND_BG_COLOR := Color8(38, 96, 132)
const STORY_SCENARIOS := {
	"baseline": "res://data/scenarios/lighthouse_baseline.json",
	"control": "res://data/scenarios/lighthouse_control.json",
}
var current_scenario := "baseline"

# authored profiles（OBS-01 任务书：每人两个合法地点偏好）
const NPC_PROFILES := {
	"npc_kadga": {"color": [63, 127, 191], "preferred": ["post_house", "tide_market"]},
	"npc_weila": {"color": [56, 178, 168], "preferred": ["old_lighthouse", "tide_market"]},
	"npc_oun": {"color": [143, 107, 196], "preferred": ["tide_market", "post_house"]},
}
const MAX_TICKS_PER_FRAME := 8
const MAX_EVENTS_PANEL := 100

var sim: SimulationCore = null
var story_sim: StorySimulation = null
var story_mode := true # 默认展示因果闭环；AIW_MODE=wander 切巡航
var sim_paused := false
var speed_multiplier := 1
var selected_actor_id := ""
var _acc := 0.0
var _frame_tick_count := 0
var _npc_visuals: Dictionary = {} # id -> Node3D（wander/story 3D 表现）
var _npc_visuals_2d: Dictionary = {} # id -> Npc2D（island 2D 像素表现，UI-R1）
var _warning := ""
var _hud_event_cursor := 0
var _lighthouse_lit := false

@onready var world_root: Node3D = $World
@onready var map_controller: Node = $World/MapController
@onready var npc_root: Node3D = $World/NpcRoot
@onready var camera_rig: ObserverCamera = $World/CameraRig
@onready var camera: Camera3D = $World/CameraRig/YawPivot/MainCamera
@onready var world_env: WorldEnvironment = $World/Environment
@onready var hud: CanvasLayer = $ObserverHud
@onready var world2d: Node2D = $World2D
@onready var ground_layer: TileMapLayer = $World2D/GroundTerrain
@onready var props_root_2d: Node2D = $World2D/PropsRoot
@onready var npc_root_2d: Node2D = $World2D/NpcRoot2D
@onready var selection_ring: Sprite2D = $World2D/SelectionMarkers/SelectionRing
@onready var camera_2d: ObserverCamera2D = $World2D/Camera2D

var _hud_refresh_acc := 0.0

const ISLAND_SCENARIO := "res://data/scenarios/deserted_island.json"
var island_sim: IslandSimulation = null

# UI-R1 小地图原型：观察模式 island 世界收窄为 48x36（六分区舞台）。
# 只覆盖本次 build 的尺寸参数——game/config 与地图生成器/模拟代码零改动；
# AIW_UI_MAP=full 可退回 64x64 全图。巡航/故事演示模式不受影响。
const UI_MAP_SMALL := Vector2i(48, 36)

func _ready() -> void:
	# UI-R1：观察线内部渲染 480x270（16px tile 的 16:9 像素画布），窗口整倍放大。
	# 工程默认视口保持 1280x720 不变——遗留 main.tscn 玩家原型与其布局测试不受影响。
	get_tree().root.content_scale_size = Vector2i(480, 270)
	var requested_mode := OS.get_environment("AIW_MODE")
	story_mode = requested_mode != "wander"
	hud.pause_requested.connect(_toggle_pause)
	hud.speed_requested.connect(_set_speed)
	hud.save_requested.connect(_do_save)
	hud.scenario_requested.connect(switch_scenario)
	# 默认进入当前认知岛模拟；旧巡航/灯塔故事只在显式测试或演示模式启动。
	if requested_mode == "wander" or requested_mode == "story":
		_boot()
	else:
		_boot_island()

func _boot() -> void:
	_warning = ""
	var spec_result: Dictionary = WorldSpecLoader.load_from_path(DEMO_SPEC_PATH)
	if not spec_result.ok:
		_apply_error("E_DATA_MISSING", str(spec_result.message))
		return
	var spec: Dictionary = spec_result.data
	var app_config := get_node_or_null("/root/AppConfig")
	var map_config: Dictionary = {}
	if app_config and typeof(app_config.raw) == TYPE_DICTIONARY and typeof(app_config.raw.get("map")) == TYPE_DICTIONARY:
		map_config = app_config.raw.get("map")
	var build: Dictionary = map_controller.build(spec, map_config)
	if not build.ok:
		_apply_error(str(build.code), str(build.message))
		return

	for c in npc_root.get_children():
		npc_root.remove_child(c)
		c.free()
	_npc_visuals.clear()
	_hud_event_cursor = 0
	selected_actor_id = ""
	sim_paused = false
	speed_multiplier = 1
	_acc = 0.0

	var actors_config: Array = []
	for ch in spec["characters"]:
		var id := str(ch["id"])
		if not NPC_PROFILES.has(id):
			continue
		var home_poi := str(ch["home_poi_id"])
		var home := _find_spawn_near(home_poi)
		if home.x < 0:
			_apply_error("E_SCHEMA_INVALID", "角色 %s 的出生点 %s 附近没有可行走格" % [id, home_poi])
			return
		actors_config.append({
			"id": id,
			"display_name": str(ch["name"]),
			"home": home,
			"preferred": NPC_PROFILES[id]["preferred"],
		})
		var visual = NPC_SCENE.instantiate()
		npc_root.add_child(visual)
		var rgb: Array = NPC_PROFILES[id]["color"]
		visual.setup(id, str(ch["name"]), Color8(rgb[0], rgb[1], rgb[2]))
		visual.update_position(home, home, 0.0)
		_npc_visuals[id] = visual
	if story_mode and FileAccess.file_exists(STORY_SCENARIOS.get(current_scenario, "")):
		_boot_story_mode()
	else:
		sim = SimulationCore.new(map_controller, actors_config, int(spec.get("seed", 0)))
	camera_rig.center_on(Vector3(map_controller.map_size().x * 0.5, 0.0, map_controller.map_size().y * 0.5))
	_enter_3d_mode()
	_refresh_hud()

func _boot_story_mode() -> void:
	var scenario_path: String = STORY_SCENARIOS.get(current_scenario, "")
	var scenario_text := FileAccess.get_file_as_string(scenario_path)
	var scenario_data: Dictionary = JSON.parse_string(scenario_text)
	var spawn_tiles := {}
	for id in _npc_visuals:
		spawn_tiles[id] = _npc_visuals[id].global_position
		# 从 visual 世界坐标反推逻辑格
		var wp: Vector3 = _npc_visuals[id].global_position
		spawn_tiles[id] = Vector2i(int(wp.x - 0.5), int(wp.z - 0.5))
	story_sim = StorySimulation.new(map_controller, scenario_data, spawn_tiles)

func _boot_island() -> void:
	_warning = ""
	var spec_result: Dictionary = WorldSpecLoader.load_from_path(DEMO_SPEC_PATH)
	if not spec_result.ok:
		_apply_error("E_DATA_MISSING", str(spec_result.message))
		return
	var spec: Dictionary = spec_result.data
	var app_config := get_node_or_null("/root/AppConfig")
	var map_config: Dictionary = {}
	if app_config and typeof(app_config.raw) == TYPE_DICTIONARY and typeof(app_config.raw.get("map")) == TYPE_DICTIONARY:
		map_config = (app_config.raw.get("map") as Dictionary).duplicate()
	if OS.get_environment("AIW_UI_MAP") != "full":
		map_config["width_tiles"] = UI_MAP_SMALL.x
		map_config["depth_tiles"] = UI_MAP_SMALL.y
	var build: Dictionary = map_controller.build(spec, map_config)
	if not build.ok:
		_apply_error(str(build.code), str(build.message))
		return
	for c in npc_root.get_children():
		npc_root.remove_child(c)
		c.free()
	for c in npc_root_2d.get_children():
		npc_root_2d.remove_child(c)
		c.free()
	_npc_visuals.clear()
	_npc_visuals_2d.clear()
	selected_actor_id = ""
	sim_paused = false
	speed_multiplier = 1
	_acc = 0.0
	_lighthouse_lit = false
	var scenario_text := FileAccess.get_file_as_string(ISLAND_SCENARIO)
	var scenario: Dictionary = JSON.parse_string(scenario_text)
	var actor_configs: Array = []
	var spawn_spots := [
		map_controller.get_poi_tile("post_house"),
		map_controller.get_poi_tile("tide_market"),
		map_controller.get_poi_tile("old_lighthouse"),
	]
	var idx := 0
	for ac in scenario.get("actors", []):
		var spawn: Vector2i = spawn_spots[idx % spawn_spots.size()]
		idx += 1
		var cfg = ac.duplicate()
		cfg["spawn"] = spawn
		actor_configs.append(cfg)
		# UI-R1：island 模式的 NPC 用 2D 像素表现（Npc2D），不再创建 3D visual
		var visual = NPC2D_SCENE.instantiate()
		npc_root_2d.add_child(visual)
		var id := str(cfg["id"])
		var colors := {"npc_weila": [56, 178, 168], "npc_oun": [143, 107, 196], "npc_kadga": [63, 127, 191]}
		var rgb: Array = colors.get(id, [128, 128, 128])
		visual.setup(id, str(cfg.get("name", id)), Color8(rgb[0], rgb[1], rgb[2]))
		visual.update_position(spawn, spawn, 0.0)
		_npc_visuals_2d[id] = visual
	island_sim = IslandSimulation.new(map_controller, int(scenario.get("seed", 20260905)), actor_configs)
	# Assembly only: the observer uses the same explicit profile as headless runs.
	var profile := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--simulation-profile="): profile = arg.trim_prefix("--simulation-profile=")
	var configured := SimulationBootstrap.configure(island_sim, profile)
	if not configured.get("ok", false):
		push_error("SIMULATION_PROFILE_FAILED: " + str(configured))
		get_tree().quit(1)
		return
	_enter_2d_mode()
	_refresh_hud()

## UI-R1：island 默认模式切 2D 像素表现（隐藏 3D 子树，投影地形，启用 Camera2D）。
func _enter_2d_mode() -> void:
	world_root.visible = false
	camera.current = false
	world2d.visible = true
	World2DProjector.project(map_controller, ground_layer, props_root_2d)
	camera_2d.enabled = true
	camera_2d.make_current()
	var map_px: Vector2i = map_controller.map_size() * 16
	camera_2d.limit_left = 0
	camera_2d.limit_top = 0
	camera_2d.limit_right = map_px.x
	camera_2d.limit_bottom = map_px.y
	camera_2d.center_on(Vector2(map_px) * 0.5)
	if world_env.environment != null:
		world_env.environment.background_color = ISLAND_BG_COLOR
	selection_ring.visible = false

## 回到 3D 演示模式（wander/story）：还原环境与相机，收起 2D 子树。
func _enter_3d_mode() -> void:
	world2d.visible = false
	camera_2d.enabled = false
	world_root.visible = true
	camera.current = true
	if world_env.environment != null:
		world_env.environment.background_color = Color(0.58, 0.66, 0.78, 1)
	selection_ring.visible = false

func _process_island(delta: float) -> void:
	if not sim_paused:
		_acc += delta * speed_multiplier
		_frame_tick_count = 0
		while _acc >= 1.0 and _frame_tick_count < MAX_TICKS_PER_FRAME:
			island_sim.step()
			_acc -= 1.0
			_frame_tick_count += 1
	var alpha := clampf(_acc, 0.0, 1.0)
	var running := speed_multiplier >= 4
	for id in _npc_visuals_2d:
		if island_sim.actors.has(id):
			var a: Dictionary = island_sim.actors[id]
			(_npc_visuals_2d[id] as Npc2D).update_position(a["prev_tile"], a["tile"], alpha, running)
	if selected_actor_id != "" and _npc_visuals_2d.has(selected_actor_id):
		selection_ring.visible = true
		selection_ring.global_position = (_npc_visuals_2d[selected_actor_id] as Npc2D).global_position - Vector2(0, 2)
	else:
		selection_ring.visible = false
	_hud_refresh_acc += delta
	if _hud_refresh_acc >= 0.25:
		_hud_refresh_acc = 0.0
		_refresh_hud()

func _process(delta: float) -> void:
	if island_sim != null:
		_process_island(delta)
		return
	if story_sim != null:
		_process_story(delta)
		return
	if sim == null:
		return
	if not sim_paused:
		_acc += delta * speed_multiplier
		_frame_tick_count = 0
		while _acc >= 1.0 and _frame_tick_count < MAX_TICKS_PER_FRAME:
			sim.step()
			_acc -= 1.0
			_frame_tick_count += 1
		if _frame_tick_count >= MAX_TICKS_PER_FRAME and _acc >= 1.0:
			pass # 欠账保留在 _acc，HUD 显示 lag，不丢 tick
	# 视觉插值（暂停时 alpha 冻结，位置不动）
	var alpha := clampf(_acc, 0.0, 1.0)
	for id in _npc_visuals:
		var a: Dictionary = sim.get_actor(id)
		(_npc_visuals[id] as Node3D).update_position(a["prev_tile"], a["tile"], alpha)
	_hud_refresh_acc += delta
	if _hud_refresh_acc >= 0.25:
		_hud_refresh_acc = 0.0
		_refresh_hud()

## P4.3：LLM 线程渲染（fire-and-forget 协程；失败只影响显示，不影响模拟/线程结构）
func _p43_render_llm_threads(te, thread_irs: Array, ev_lookup: Dictionary) -> void:
	var config: Dictionary = LlmNarrativeRenderer.load_config()
	if config.is_empty():
		set_meta("_p43_busy", false)
		return
	var count := 0
	for tir in thread_irs:
		if count >= 3:
			break
		var thread = te.engine.thread_by_id(str(tir.get("thread_id", "")))
		if thread == null:
			continue
		var render_ir: Dictionary = LlmThreadRenderer.build_render_ir(island_sim, thread)
		var out_title: Dictionary = await LlmThreadRenderer.render(config, render_ir, "TITLE", ev_lookup)
		tir["_llm_title"] = str(out_title.get("text", ""))
		var out_sum: Dictionary = await LlmThreadRenderer.render(config, render_ir, "SUMMARY", ev_lookup)
		tir["_llm_summary"] = str(out_sum.get("text", ""))
		tir["_llm_renderer"] = str(out_sum.get("renderer", ""))
		tir["_llm_drilldown"] = out_sum.get("sentences", [])
		count += 1
	set_meta("_p43_busy", false)

func _process_story(delta: float) -> void:
	if not sim_paused:
		_acc += delta * speed_multiplier
		_frame_tick_count = 0
		while _acc >= 1.0 and _frame_tick_count < MAX_TICKS_PER_FRAME:
			var new_events: Array = story_sim.step()
			for e in new_events:
				if e["type"] == "lit_changed":
					_on_lighthouse_lit()
			_acc -= 1.0
			_frame_tick_count += 1
	var alpha := clampf(_acc, 0.0, 1.0)
	for id in _npc_visuals:
		if story_sim.actors.has(id):
			var a: Dictionary = story_sim.actors[id]
			(_npc_visuals[id] as Node3D).update_position(a["prev_tile"], a["tile"], alpha)
	_hud_refresh_acc += delta
	if _hud_refresh_acc >= 0.25:
		_hud_refresh_acc = 0.0
		_refresh_hud()

func _on_lighthouse_lit() -> void:
	if _lighthouse_lit:
		return
	_lighthouse_lit = true
	# 找到旧灯塔 POI marker 并改为发光材质
	var poi_root := get_node("World/PoiRoot")
	if poi_root:
		for c in poi_root.get_children():
			if str(c.get_meta("target_id", "")) == "old_lighthouse":
				var marker: MeshInstance3D = c.get_node_or_null("MarkerMesh")
				if marker != null and marker.mesh != null:
					var mat := StandardMaterial3D.new()
					mat.albedo_color = Color8(255, 240, 120)
					mat.emission_enabled = true
					mat.emission = Color8(255, 220, 80)
					mat.emission_energy_multiplier = 2.0
					marke_mesh_swap(marker, mat)

func marke_mesh_swap(marker: MeshInstance3D, mat: StandardMaterial3D) -> void:
	marker.material_override = mat

func _do_save() -> void:
	if story_sim == null:
		_warning = "存档仅支持故事模式"
		_refresh_hud()
		return
	var store := StorySaveStore.new("user://saves")
	var r: Dictionary = store.save_timeline(story_sim, DEMO_SPEC_PATH, "runtime")
	if r.ok:
		_warning = ""
	else:
		_warning = "保存失败：%s" % str(r.get("message", "?"))
	_refresh_hud()

func _unhandled_input(event: InputEvent) -> void:
	# island 2D 模式（UI-R1）：Esc 暂停 + 左键点选 NPC；空白点击取消选择
	if island_sim != null:
		if event.is_action_pressed("cancel"):
			_toggle_pause()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
				and (event as InputEventMouseButton).pressed:
			var world_pos: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * (event as InputEventMouseButton).position
			var best := ""
			var best_d := 18.0
			for id in _npc_visuals_2d:
				var d: float = (_npc_visuals_2d[id] as Npc2D).global_position.distance_to(world_pos)
				if d < best_d:
					best_d = d
					best = id
			select_actor(best)
			get_viewport().set_input_as_handled()
		return
	if story_sim == null and sim == null:
		return
	if event.is_action_pressed("cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
			and (event as InputEventMouseButton).pressed:
		var gp := camera_rig.ground_point((event as InputEventMouseButton).position)
		var best := ""
		var best_d := 1.5
		for id in _npc_visuals:
			var d: float = (_npc_visuals[id] as Node3D).global_position.distance_to(gp)
			if d < best_d:
				best_d = d
				best = id
		selected_actor_id = best # 空白点击取消选择
		for id in _npc_visuals:
			(_npc_visuals[id] as Node3D).set_selected(id == selected_actor_id)
		_refresh_hud()
		get_viewport().set_input_as_handled()

## UI-R1：island 2D 选中入口（预览/截图工具也用它）；空串取消选择。
func select_actor(actor_id: String) -> void:
	selected_actor_id = actor_id
	for id in _npc_visuals_2d:
		(_npc_visuals_2d[id] as Npc2D).set_selected(id == selected_actor_id)
	_refresh_hud()

func rebuild() -> void:
	_lighthouse_lit = false
	_boot()

func switch_scenario(scenario_name: String) -> void:
	if not STORY_SCENARIOS.has(scenario_name):
		return
	current_scenario = scenario_name
	_lighthouse_lit = false
	story_sim = null
	sim = null
	island_sim = null # UI-R1：离开 island 2D 模式，回到 3D 演示路径
	_boot()

func get_current_scenario() -> String:
	return current_scenario

func get_simulation() -> SimulationCore:
	return sim

func has_error() -> bool:
	return _warning != ""

func _toggle_pause() -> void:
	sim_paused = not sim_paused
	_refresh_hud()

func _set_speed(mult: int) -> void:
	speed_multiplier = mult
	_refresh_hud()

func _apply_error(code: String, message: String) -> void:
	_warning = "%s: %s" % [code, message]
	sim = null
	_refresh_hud()

# home POI 附近的确定性可行走出生格（BFS，先近后远，同环内按 x/z 稳定序）
func _find_spawn_near(poi_id: String) -> Vector2i:
	var poi_tile: Vector2i = map_controller.get_poi_tile(poi_id)
	if poi_tile.x < 0:
		return Vector2i(-1, -1)
	if map_controller.is_walkable_tile(Vector3i(poi_tile.x, 0, poi_tile.y)):
		return poi_tile
	var visited := {poi_tile: true}
	var queue: Array = [poi_tile]
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var sz: Vector2i = map_controller.map_size()
	while queue.size() > 0:
		var c: Vector2i = queue.pop_front()
		for d in dirs:
			var n := Vector2i(c.x + d.x, c.y + d.y)
			if n.x < 0 or n.y < 0 or n.x >= sz.x or n.y >= sz.y or visited.has(n):
				continue
			visited[n] = true
			queue.append(n)
			if map_controller.is_walkable_tile(Vector3i(n.x, 0, n.y)):
				return n
	return Vector2i(-1, -1)

func _refresh_hud() -> void:
	var model := {
		"view_schema_version": "0.2",
		"state_revision": island_sim.tick if island_sim != null else 0,
		"paused": sim_paused,
		"speed_multiplier": speed_multiplier,
		"lag_ticks": int(_acc) if island_sim != null else 0,
		"warning_text": _warning,
	}
	if island_sim != null:
		model["world_name"] = "荒岛 · 观察模式"
		model["time_label"] = "第 %d 天 %02d:00" % [island_sim.world_time["day"], island_sim.world_time["hour"]]
		var sel = null
		if selected_actor_id != "" and island_sim.actors.has(selected_actor_id):
			sel = _build_island_selected(island_sim.actors[selected_actor_id])
		model["selected_actor"] = sel
		var recent: Array = []
		var all: Array = island_sim.events
		for i in range(maxi(0, all.size() - MAX_EVENTS_PANEL), all.size()):
			recent.append(all[i])
		model["recent_events"] = recent
		model["causal_chains"] = _build_causal_chains(recent)
		# P4-3: 故事线——ThreadEngine 识别跨天线程
		if island_sim != null and island_sim.tick % 30 == 0:
			if not has_meta("_thread_engine"):
				set_meta("_thread_engine", ThreadEngine.new())
			var _te = get_meta("_thread_engine")
			_te.process(island_sim)
			var thread_irs: Array = []
			var ev_lookup := ThreadSummaryRenderer.build_event_lookup(island_sim)
			for th in _te.engine.threads:
				var tir = _te.build_thread_ir(island_sim, th)
				tir["_summary"] = ThreadSummaryRenderer.render_summary(tir, ev_lookup)
				tir["_title"] = ThreadSummaryRenderer.render_title(tir)
				thread_irs.append(tir)
			model["story_threads"] = thread_irs
			# P4.3（§20）：LLM 线程渲染——AIWORLD_THREAD_LLM=1 时，对前 3 条线程
			# 追加 _llm_title/_llm_summary + debug 回溯（sentence→claim_ids→sources）。
			# 防重入：上一次渲染未完成就跳过；任何失败静默走模板（面板仍有 _summary）。
			if OS.get_environment("AIWORLD_THREAD_LLM") == "1" and not get_meta("_p43_busy", false):
				set_meta("_p43_busy", true)
				_p43_render_llm_threads(_te, thread_irs, ev_lookup)
		# P3b-5: 对话转录——从最近社会事件提取 SpeechAct → 模板台词
		if island_sim != null:
			var dialogue_lines: Array = []
			var recent_dlg: Array = island_sim.events.slice(maxi(0, island_sim.events.size() - 20), island_sim.events.size())
			for e in recent_dlg:
				var speaker_id := str(e.get("actor_id", ""))
				if speaker_id == "" or not island_sim.actors.has(speaker_id):
					continue
				var sa := SpeechAct.from_event(e, island_sim.actors[speaker_id])
				if sa.is_empty():
					continue
				var utter: Dictionary = TemplateDialogueRenderer.render(sa, str(island_sim.actors[speaker_id]["display_name"]))
				if bool(utter.get("ok", false)):
					dialogue_lines.append({"day": int(e.get("day", 1)), "speaker": str(island_sim.actors[speaker_id]["display_name"]), "text": str(utter.get("text", "")), "act": str(sa.get("act_type", "")), "seq": int(e.get("seq", 0))})
			model["dialogue_transcript"] = dialogue_lines
		# P3a-2: 句子级编年史（claim-first）+ 证据面板数据
		if island_sim != null:
			var n_ir: Dictionary = NarrativeIR.build_ir(island_sim, "OBJECTIVE", "", 6)
			# P3a-3: LLM 渲染器优先（ai.local.json 或环境变量配置存在时）；否则 template（零网络）
			var llm_cfg: Dictionary = LlmNarrativeRenderer.load_config()
			var provider: Dictionary
			if llm_cfg.is_empty():
				provider = {"render": func(ir, st, la, ln): return TemplateNarrativeRenderer.render(ir, st, la, ln)}
			else:
				provider = LlmNarrativeRenderer.make_provider(llm_cfg)
			var n_out: Dictionary = await NarrativeRenderer.render(provider, n_ir)
			model["narrative_sentences"] = n_out.get("sentences", [])
			model["narrative_ir_claims"] = n_ir.get("claims", [])
		# P2: 编年史——最近两天的日记（金色，与原始事件流区分）
		var chron_lines: Array = []
		var chronicles: Array = island_sim.chronicles
		for i in range(maxi(0, chronicles.size() - 2), chronicles.size()):
			chron_lines.append("[color=#e8c170]%s[/color]" % str(chronicles[i]["text"]))
		model["chronicle_text"] = "\n".join(chron_lines)
	elif story_sim != null:
		model["world_name"] = "灰雾港 · 故事模式"
		var t: int = story_sim.tick
		model["time_label"] = "第 %d 天 %02d:%02d%s" % [t / 1440 + 1, (t % 1440) / 60, t % 60,
			" · 灯塔已点亮 ✨" if story_sim.lighthouse_lit else " · 灯塔未点亮"]
		model["world_facts_text"] = "灯塔：%s" % ("已点亮" if story_sim.lighthouse_lit else "未点亮")
	elif sim != null:
		model["world_name"] = "灰雾港 · 巡航模式"
		var t2: int = sim.tick
		model["time_label"] = "第 %d 天 %02d:%02d" % [t2 / 1440 + 1, (t2 % 1440) / 60, t2 % 60]
	else:
		model["world_name"] = "灰雾港 · 观察模式"
		model["time_label"] = "-"
	var sel = null
	if story_sim != null:
		if selected_actor_id != "" and story_sim.actors.has(selected_actor_id):
			var a: Dictionary = story_sim.actors[selected_actor_id]
			sel = {
				"id": selected_actor_id,
				"display_name": a["display_name"],
				"activity_text": str(a["activity"]),
				"goal_text": str(a["goal"]) if str(a["goal"]) != "" else "无",
				"location_text": "(%d, %d)" % [a["tile"].x, a["tile"].y],
				"inventory_text": _inv_text(a["inventory"]),
			}
		model["selected_actor"] = sel
		var recent: Array = []
		var all: Array = story_sim.events
		for i in range(maxi(0, all.size() - MAX_EVENTS_PANEL), all.size()):
			recent.append(all[i])
		model["recent_events"] = recent
	elif sim != null:
		if selected_actor_id != "" and sim.actors.has(selected_actor_id):
			var a: Dictionary = sim.get_actor(selected_actor_id)
			var goal := "前往 %s" % a["target_poi"] if str(a["target_poi"]) != "" else "待定"
			sel = {
				"id": selected_actor_id,
				"display_name": a["display_name"],
				"activity_text": _activity_text(a),
				"goal_text": goal,
				"location_text": "(%d, %d)" % [a["tile"].x, a["tile"].y],
			}
		model["selected_actor"] = sel
		var recent2: Array = []
		var all2: Array = sim.events
		for i in range(maxi(0, all2.size() - MAX_EVENTS_PANEL), all2.size()):
			recent2.append(all2[i])
		model["recent_events"] = recent2
	else:
		if island_sim == null: # island 分支已组装 selected_actor，不得被演示模式兜底覆盖
			model["selected_actor"] = null
			model["recent_events"] = []
	hud.render(model)

func _island_goal_text(a: Dictionary) -> String:
	var intentions: IntentionManager = a.get("intentions", null)
	if intentions != null and intentions.has_intention():
		return str(intentions.current_intention.get("desc", ""))
	return "思考中..."

## UI-R1：island 选中角色的结构化 ViewModel（presentation adapter 组装，HUD 只渲染）。
## 字段定义见 docs/ui/OBSERVER_VIEW_MODEL.md（view_schema_version 0.2）。
const TRAIT_LABELS := {
	"resilience": "韧性", "curiosity": "好奇", "action_bias": "行动", "caution": "谨慎",
	"empathy": "共情", "sociability": "社交", "altruism": "利他", "expressiveness": "表达",
	"conflict_avoidance": "避冲突", "pragmatism": "务实",
}

func _build_island_selected(a: Dictionary) -> Dictionary:
	var p: PersonalityProfile = a["personality"]
	var trace: Dictionary = a.get("last_decision_trace", {})
	var needs: Dictionary = a["needs"]
	var intentions: IntentionManager = a.get("intentions", null)
	var intention: Dictionary = intentions.current_intention if intentions != null and intentions.has_intention() else {}
	var sel := {
		"id": selected_actor_id,
		"display_name": a["display_name"],
		"status_text": str(a["activity"]),
		"activity_text": str(a["activity"]),
		"goal_text": _island_goal_text(a),
		"location_text": "(%d, %d)" % [a["tile"].x, a["tile"].y],
		"inventory_text": _inv_text(a["inventory"]),
		"needs_text": "饿%d/渴%d/累%d/孤独%d" % [
			int(needs.get("hunger", 0)), int(needs.get("thirst", 0)),
			1000 - int(needs.get("energy", 1000)), int(needs.get("social", 0)),
		],
	}
	var inv_items: Array = []
	for item in a["inventory"]:
		var n: int = int(a["inventory"][item])
		if n > 0:
			inv_items.append({"id": str(item), "count": n})
	sel["inventory_items"] = inv_items
	var reason := str(trace.get("reason", ""))
	sel["decision_text"] = reason
	sel["decision"] = {
		"plan": str(intention.get("desc", _island_goal_text(a))),
		"step": str(a["activity"]),
		"reason": reason if reason != "" else "—",
		"blocker": str(trace.get("blocker", "无")),
		"next_step": str(intention.get("desc", "—")) if not intention.is_empty() else "—",
	}
	var memory_items: Array = []
	for m in a.get("memories", []):
		memory_items.append({
			"day": int(m.get("day", 0)), "tick": int(m.get("tick", 0)),
			"text": str(m.get("text", "")), "type": str(m.get("type", "")),
			"counterpart": str(m.get("counterpart_id", "")),
			"importance": float(m.get("appraisal_goal_congruence", 0.0)),
		})
	sel["memory_items"] = memory_items
	var traits: Array = []
	for key in TRAIT_LABELS:
		traits.append({"key": key, "label": TRAIT_LABELS[key], "value": float(p.traits.get(key, 0.5))})
	var emotions: Array = []
	for key in ["joy", "fear", "anger", "sadness", "guilt"]:
		var v: float = p.emotions.get(key, 0.0)
		if absf(v) > 0.05:
			emotions.append({"key": key, "value": v})
	var beliefs: Array = []
	for text in p.beliefs:
		beliefs.append({"text": str(text), "weight": float(p.beliefs[text]["weight"])})
	sel["personality"] = {"traits": traits, "emotions": emotions, "beliefs": beliefs}
	var rel_rows: Array = []
	var tom: TheoryOfMind = a.get("tom", null)
	for oid in island_sim.actors:
		if oid == selected_actor_id:
			continue
		var row := {
			"other_id": oid,
			"other_name": str(island_sim.actors[oid]["display_name"]),
			"trust": int(island_sim.relationships.get_trust(selected_actor_id, oid)),
		}
		if tom != null:
			var m: Dictionary = tom.model_of(oid)
			row["tom"] = {
				"has_food": float(m.get("has_food", 0.0)),
				"generous": float(m.get("generous", 0.0)),
				"reliable": float(m.get("reliable", 0.0)),
			}
			row["benevolence"] = float(m.get("generous", 0.0))
			row["reliability"] = float(m.get("reliable", 0.0))
		rel_rows.append(row)
	sel["relationship_rows"] = rel_rows
	var hist: Array = []
	var hist_by_seq := {}
	for i in range(island_sim.events.size() - 1, -1, -1):
		var e: Dictionary = island_sim.events[i]
		if str(e.get("actor_id", "")) == selected_actor_id or selected_actor_id in (e.get("actor_ids", []) as Array):
			hist.append({"day": int(e.get("day", 0)), "seq": int(e.get("seq", 0)), "text": str(e.get("text", ""))})
			hist_by_seq[int(e.get("seq", 0))] = e
			if hist.size() >= 12:
				break
	sel["history_rows"] = hist
	var display_name := str(a["display_name"])
	var hist_dialogue: Array = []
	for dl in _last_dialogue(6):
		if str(dl.get("speaker", "")) == display_name:
			hist_dialogue.append(dl)
	sel["history_dialogue_rows"] = hist_dialogue
	sel["history_chain_rows"] = _actor_chain_rows(hist_by_seq)
	return sel

## History 页第三段：该角色自身带 cause_seq 事件的因果步（无则空，占位由 HUD 显示）。
func _actor_chain_rows(hist_by_seq: Dictionary) -> Array:
	var steps: Array = []
	for seq in hist_by_seq:
		var e: Dictionary = hist_by_seq[seq]
		var cause := int(e.get("cause_seq", 0))
		if cause <= 0 or not hist_by_seq.has(cause):
			continue
		var ce: Dictionary = hist_by_seq[cause]
		steps.append("E%d %s → E%d %s" % [cause, str(ce.get("text", "")), seq, str(e.get("text", ""))])
	return steps

## 最近 N 条对话转录（与底部对话页同源的轻量复取，不新建状态）。
func _last_dialogue(n: int) -> Array:
	var out: Array = []
	var recent_dlg: Array = island_sim.events.slice(maxi(0, island_sim.events.size() - 30), island_sim.events.size())
	for e in recent_dlg:
		var speaker_id := str(e.get("actor_id", ""))
		if speaker_id == "" or not island_sim.actors.has(speaker_id):
			continue
		var sa := SpeechAct.from_event(e, island_sim.actors[speaker_id])
		if sa.is_empty():
			continue
		var utter: Dictionary = TemplateDialogueRenderer.render(sa, str(island_sim.actors[speaker_id]["display_name"]))
		if bool(utter.get("ok", false)):
			out.append({"day": int(e.get("day", 1)), "speaker": str(island_sim.actors[speaker_id]["display_name"]), "text": str(utter.get("text", "")), "act": str(sa.get("act_type", "")), "seq": int(e.get("seq", 0))})
	return out.slice(maxi(0, out.size() - n), out.size())

## 由最近事件的 cause_seq 派生因果链视图（只读展示派生，不改模拟事件）。
func _build_causal_chains(events: Array) -> Array:
	var by_seq := {}
	for e in events:
		by_seq[int(e.get("seq", 0))] = e
	var chains: Array = []
	var used := {}
	for e in events:
		var seq := int(e.get("seq", 0))
		var cause := int(e.get("cause_seq", 0))
		if cause <= 0 or used.has(seq) or not by_seq.has(cause):
			continue
		var steps: Array = []
		var cur: Dictionary = e
		var guard := 0
		while not cur.is_empty() and guard < 5:
			steps.push_front("E%d %s" % [int(cur.get("seq", 0)), str(cur.get("text", ""))])
			used[int(cur.get("seq", 0))] = true
			var next_cause := int(cur.get("cause_seq", 0))
			cur = by_seq.get(next_cause, {}) if next_cause > 0 else {}
			guard += 1
		chains.append({"title": "E%d 事件链" % seq, "steps": steps})
		if chains.size() >= 4:
			break
	return chains

func _inv_text(inv: Dictionary) -> String:
	var parts: Array = []
	for item in inv:
		var n: int = int(inv[item])
		if n > 0:
			var display: String = {"windcrystal_powder": "风晶粉末"}.get(item, item)
			parts.append("%s×%d" % [display, n])
	if parts.is_empty():
		return "（空）"
	return "、".join(parts)

func _activity_text(a: Dictionary) -> String:
	match a["activity"]:
		"idle": return "思考下一步"
		"moving": return "赶路中"
		"inspecting": return "观察 %s" % a["target_poi"]
		"waiting": return "停留休息"
		"blocked": return "受阻等待改派"
	return str(a["activity"])
