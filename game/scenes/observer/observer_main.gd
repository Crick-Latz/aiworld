extends Node
## 观察模式装配根（OBS-01，M01）：只负责创建模块、注入端口、连接信号与销毁。
## 不在此计算 NPC 目标、拼每条事件文案；无 Player、无自动驾驶、无整树暂停。
## 模拟暂停与相机/UI 解耦：Simulation 停 tick，视觉插值冻结，相机/按钮仍可用。

const DEMO_SPEC_PATH := "res://data/demo_world/world_spec.json"
const NPC_SCENE := preload("res://scenes/actors/npc.tscn")
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
var _npc_visuals: Dictionary = {} # id -> Node3D
var _warning := ""
var _hud_event_cursor := 0
var _lighthouse_lit := false

@onready var world_root: Node3D = $World
@onready var map_controller: Node = $World/MapController
@onready var npc_root: Node3D = $World/NpcRoot
@onready var camera_rig: ObserverCamera = $World/CameraRig
@onready var camera: Camera3D = $World/CameraRig/YawPivot/MainCamera
@onready var hud: CanvasLayer = $ObserverHud

var _hud_refresh_acc := 0.0

const ISLAND_SCENARIO := "res://data/scenarios/deserted_island.json"
var island_sim: IslandSimulation = null

func _ready() -> void:
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
		map_config = app_config.raw.get("map")
	var build: Dictionary = map_controller.build(spec, map_config)
	if not build.ok:
		_apply_error(str(build.code), str(build.message))
		return
	for c in npc_root.get_children():
		npc_root.remove_child(c)
		c.free()
	_npc_visuals.clear()
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
		var visual = NPC_SCENE.instantiate()
		npc_root.add_child(visual)
		var id := str(cfg["id"])
		var colors := {"npc_weila": [56, 178, 168], "npc_oun": [143, 107, 196], "npc_kadga": [63, 127, 191]}
		var rgb: Array = colors.get(id, [128, 128, 128])
		visual.setup(id, str(cfg.get("name", id)), Color8(rgb[0], rgb[1], rgb[2]))
		visual.update_position(spawn, spawn, 0.0)
		_npc_visuals[id] = visual
	island_sim = IslandSimulation.new(map_controller, int(scenario.get("seed", 20260905)), actor_configs)
	camera_rig.center_on(Vector3(map_controller.map_size().x * 0.5, 0.0, map_controller.map_size().y * 0.5))
	_refresh_hud()

func _process_island(delta: float) -> void:
	if not sim_paused:
		_acc += delta * speed_multiplier
		_frame_tick_count = 0
		while _acc >= 1.0 and _frame_tick_count < MAX_TICKS_PER_FRAME:
			island_sim.step()
			_acc -= 1.0
			_frame_tick_count += 1
	var alpha := clampf(_acc, 0.0, 1.0)
	for id in _npc_visuals:
		if island_sim.actors.has(id):
			var a: Dictionary = island_sim.actors[id]
			(_npc_visuals[id] as Node3D).update_position(a["prev_tile"], a["tile"], alpha)
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
		"view_schema_version": "0.1",
		"state_revision": island_sim.tick if island_sim != null else 0,
		"paused": sim_paused,
		"speed_multiplier": speed_multiplier,
		"lag_ticks": int(_acc) if island_sim != null else 0,
		"warning_text": _warning,
	}
	if island_sim != null:
		model["time_label"] = "第 %d 天 %02d:00" % [island_sim.world_time["day"], island_sim.world_time["hour"]]
		var sel = null
		if selected_actor_id != "" and island_sim.actors.has(selected_actor_id):
			var a: Dictionary = island_sim.actors[selected_actor_id]
			var p: PersonalityProfile = a["personality"]
			var trace: Dictionary = a.get("last_decision_trace", {})
			sel = {
				"id": selected_actor_id,
				"display_name": a["display_name"],
				"activity_text": str(a["activity"]),
				"goal_text": _island_goal_text(a),
				"location_text": "(%d, %d)" % [a["tile"].x, a["tile"].y],
				"inventory_text": _inv_text(a["inventory"]),
			}
			# 情绪和决策原因附加到活动文本
			var emotions: Array = []
			for key in ["joy", "fear", "anger", "sadness", "guilt"]:
				var v: float = p.emotions.get(key, 0.0)
				if absf(v) > 0.1:
					var names := {"joy": "开心", "fear": "恐惧", "anger": "愤怒", "sadness": "悲伤", "guilt": "内疚"}
					emotions.append("%s%.0f%%" % [names[key], v * 100])
			if not emotions.is_empty():
				sel["activity_text"] += "\n情绪：" + "、".join(emotions)
			if trace.has("reason"):
				sel["activity_text"] += "\n原因：" + str(trace["reason"])
			var needs: Dictionary = a["needs"]
			sel["activity_text"] += "\n需求：饿%d/渴%d/累%d/孤独%d" % [
				int(needs.get("hunger", 0)), int(needs.get("thirst", 0)),
				1000 - int(needs.get("energy", 1000)), int(needs.get("social", 0)),
			]
			# P1: 一阶心智——"他以为别人是什么样的人"（可能是错的，这正是看点）
			var tom: TheoryOfMind = a.get("tom", null)
			if tom != null:
				var tom_parts: Array = []
				for oid in island_sim.actors:
					if oid == selected_actor_id:
						continue
					var m: Dictionary = tom.model_of(oid)
					if float(m["has_food"]) != 0.0 or float(m["generous"]) != 0.0 or float(m["reliable"]) != 0.0:
						tom_parts.append("%s(食%+.1f 慷%+.1f 靠%+.1f)" % [
							island_sim.actors[oid]["display_name"],
							m["has_food"], m["generous"], m["reliable"]])
				if not tom_parts.is_empty():
					sel["activity_text"] += "\n心智：" + " ".join(tom_parts)
			# P1: 有向信任——"我信谁多少"（对方未必同样信我）
			var trust_parts: Array = []
			for oid in island_sim.actors:
				if oid == selected_actor_id:
					continue
				var t_val: int = island_sim.relationships.get_trust(selected_actor_id, oid)
				if t_val != 0:
					trust_parts.append("%s%+d" % [island_sim.actors[oid]["display_name"], t_val])
			if not trust_parts.is_empty():
				sel["activity_text"] += "\n信任：" + " ".join(trust_parts)
			# P1: 最近的记忆（受助/被拒/受伤这些塑造关系的时刻）
			var mems: Array = a.get("memories", [])
			if not mems.is_empty():
				var last_mem: Dictionary = mems[mems.size() - 1]
				sel["activity_text"] += "\n记忆：" + str(last_mem.get("text", "")).substr(0, 40)
		model["selected_actor"] = sel
		var recent: Array = []
		var all: Array = island_sim.events
		for i in range(maxi(0, all.size() - MAX_EVENTS_PANEL), all.size()):
			recent.append(all[i])
		model["recent_events"] = recent
		# P3a-2: 句子级编年史（claim-first）+ 证据面板数据
		if island_sim != null:
			var n_ir: Dictionary = NarrativeIR.build_ir(island_sim, "OBJECTIVE", "", 6)
			var n_out: Dictionary = NarrativeRenderer.render({"render": func(ir, st, la, ln): return TemplateNarrativeRenderer.render(ir, st, la, ln)}, n_ir)
			model["narrative_sentences"] = n_out.get("sentences", [])
			model["narrative_ir_claims"] = n_ir.get("claims", [])
		# P2: 编年史——最近两天的日记（金色，与原始事件流区分）
		var chron_lines: Array = []
		var chronicles: Array = island_sim.chronicles
		for i in range(maxi(0, chronicles.size() - 2), chronicles.size()):
			chron_lines.append("[color=#e8c170]%s[/color]" % str(chronicles[i]["text"]))
		model["chronicle_text"] = "\n".join(chron_lines)
	elif story_sim != null:
		var t: int = story_sim.tick
		model["time_label"] = "第 %d 天 %02d:%02d%s" % [t / 1440 + 1, (t % 1440) / 60, t % 60,
			" · 灯塔已点亮 ✨" if story_sim.lighthouse_lit else " · 灯塔未点亮"]
		model["world_facts_text"] = "灯塔：%s" % ("已点亮" if story_sim.lighthouse_lit else "未点亮")
	elif sim != null:
		var t2: int = sim.tick
		model["time_label"] = "第 %d 天 %02d:%02d" % [t2 / 1440 + 1, (t2 % 1440) / 60, t2 % 60]
	else:
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
		model["selected_actor"] = null
		model["recent_events"] = []
	hud.render(model)

func _island_goal_text(a: Dictionary) -> String:
	var intentions: IntentionManager = a.get("intentions", null)
	if intentions != null and intentions.has_intention():
		return str(intentions.current_intention.get("desc", ""))
	return "思考中..."

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
