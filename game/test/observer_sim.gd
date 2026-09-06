extends SceneTree
## OBS-01 观察模式集成测试。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/observer_sim.gd
## 覆盖：无 Player/三NPC 初始化、600 tick 自主到达、确定性（分块 step 等价 + 同 seed 重复）、
## 真实输入选择/取消、Esc 暂停冻结/恢复、重建无重复、HUD 夹具渲染与隔离。

var passed := 0
var failed := 0
var _started := false
var _finished := false
var _inst: Node = null
var _cached_600 := ""

func _initialize() -> void:
	print("OBS-01 observer harness: deferred to first frame")

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished

func _run() -> void:
	await _run_all_tests()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_finished = true
	quit(0 if failed == 0 else 1)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("PASS %s" % name)
	else:
		failed += 1
		print("FAIL %s  %s" % [name, detail])

func _steps(n: int) -> void:
	for i in n:
		await physics_frame

func _run_all_tests() -> void:
	# 巡航模式测试（故事模式由 story_causal/story_dynamic/story_save 覆盖）
	# 通过命令行 AIW_MODE=wander 环境变量控制；test 脚本内用 _force_wander 兜底
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		for n in ["observer_boots_three_npcs", "observer_no_player_nodes", "npc600_each_two_pois",
				"npc600_all_tiles_legal", "sim_deterministic_chunking", "sim_same_seed_repeatable",
				"real_input_selects_npc", "empty_click_deselects", "pause_freezes_sim",
				"esc_resumes_sim", "rebuild_single_set", "hud_fixture_render", "hud_isolation_from_sim"]:
			_check(n, false, "观察场景不可加载")
		return
	var had_mode := OS.has_environment("AIW_MODE")
	var previous_mode := OS.get_environment("AIW_MODE")
	OS.set_environment("AIW_MODE", "wander")
	_inst = ps.instantiate()
	root.add_child(_inst)
	await _steps(20)
	if had_mode:
		OS.set_environment("AIW_MODE", previous_mode)
	else:
		OS.unset_environment("AIW_MODE")

	var sim: SimulationCore = _inst.get_simulation()
	_check("observer_boots_three_npcs",
		sim != null and not _inst.has_error() and _inst.get_node("World/NpcRoot").get_child_count() == 3)
	_check("observer_no_player_nodes", not _tree_has_player(_inst))

	# —— 600 tick：每 NPC 至少到访 2 个不同 POI，全程合法格 ——
	var ctl = _inst.get_node("World/MapController")
	var all_legal := true
	for i in 600:
		sim.step()
		if i % 60 == 0:
			for id in sim.actors:
				var t: Vector2i = sim.get_actor(id)["tile"]
				if not ctl.is_walkable_tile(Vector3i(t.x, 0, t.y)):
					all_legal = false
	var min_pois := 999
	for id in sim.actors:
		min_pois = mini(min_pois, sim.get_actor(id)["visited_pois"].size())
	_check("npc600_each_two_pois", min_pois >= 2, "min_visited=%d" % min_pois)
	_check("npc600_all_tiles_legal", all_legal)
	print("OBS_SUMMARY ticks=600 events=%d min_pois=%d" % [sim.events.size(), min_pois])

	# —— 确定性：1×600 vs 86×7 分块 vs 另一次完整 600 ——
	var sim2 := _fresh_sim()
	for i in 600:
		sim2.step()
	var sim3 := _fresh_sim()
	for chunk in range(85): # 85*7+5 = 600，分块总数精确相等
		for k in 7:
			sim3.step()
	for k in 5:
		sim3.step()
	_check("sim_deterministic_chunking",
		sim2.event_summary() == sim3.event_summary()
		and JSON.stringify(sim2.get_snapshot()) == JSON.stringify(sim3.get_snapshot()))
	_check("sim_same_seed_repeatable", sim2.event_summary() == _fresh_sim_600_summary())

	# —— 真实输入选择 ——
	# 时序要点：先暂停模拟（插值冻结、视觉静止），再等帧同步、取样、点击，
	# 断言后恢复。用脚点取样消除斜视角射线的地面偏移。
	_inst.sim_paused = true
	await _steps(5)
	var npc_node: Node3D = _inst.get_node("World/NpcRoot").get_child(0)
	var sel_id := str(npc_node.get_meta("npc_id"))
	var cam: Camera3D = _inst.get_node("World/CameraRig/YawPivot/MainCamera")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	# headless 下 push_input/parse_input 会对 position 施加 final_transform 的逆变换
	# （实测 set(270,215)->收到(5400,4020)）；用正向变换预补偿还原成期望视口坐标
	var ft: Transform2D = root.get_final_transform()
	ev.position = ft * cam.unproject_position(npc_node.global_position + Vector3(0, 0.05, 0))
	Input.parse_input_event(ev)
	for i in 4:
		await process_frame # 鼠标事件在主循环输入段分发，等 process 帧而不是 physics 帧
	_check("real_input_selects_npc", _inst.selected_actor_id == sel_id,
		"want=%s got=%s" % [sel_id, _inst.selected_actor_id])
	var ev_empty := InputEventMouseButton.new()
	ev_empty.button_index = MOUSE_BUTTON_LEFT
	ev_empty.pressed = true
	ev_empty.position = ft * Vector2(16, 640) # 远离 NPC 的左下空白
	Input.parse_input_event(ev_empty)
	for i in 4:
		await process_frame
	_check("empty_click_deselects", _inst.selected_actor_id == "", "got=%s" % _inst.selected_actor_id)
	_inst.sim_paused = false

	# —— Esc 暂停冻结 / 恢复 ——
	var tick_before: int = sim.tick
	var esc := InputEventAction.new()
	esc.action = "cancel"
	esc.pressed = true
	Input.parse_input_event(esc)
	await _steps(2)
	var paused_ok: bool = _inst.sim_paused
	await _steps(60)
	_check("pause_freezes_sim", paused_ok and sim.tick == tick_before,
		"paused=%s tick=%d/%d" % [paused_ok, sim.tick, tick_before])
	Input.parse_input_event(esc)
	await _steps(5)
	_check("esc_resumes_sim", not _inst.sim_paused)

	# —— 重建 ——
	_inst.rebuild()
	await _steps(20)
	_check("rebuild_single_set",
		_inst.get_node("World/NpcRoot").get_child_count() == 3
		and _inst.get_simulation() != null and not _inst.has_error())

	root.remove_child(_inst)
	_inst.free()

	# —— HUD 夹具渲染 + 隔离（preview 场景，无模拟依赖）——
	var preview: PackedScene = load("res://scenes/ui/ui_preview.tscn")
	var pv = preview.instantiate()
	root.add_child(pv)
	await _steps(3)
	var hud = pv.get_node("ObserverHud")
	_check("hud_fixture_render",
		str(hud.sel_name.text).find("薇拉") != -1
		and str(hud.tick_label.text).find("2×") != -1
		and str(hud.events_label.get_parsed_text()).find("卡德加") != -1)
	var model: Dictionary = pv.fixture_model()
	model["selected_actor"]["display_name"] = "篡改"
	hud.render(pv.fixture_model())
	_check("hud_isolation_from_sim", str(hud.sel_name.text).find("篡改") == -1
		and str(hud.sel_name.text).find("薇拉") != -1)
	root.remove_child(pv)
	pv.free()

func _tree_has_player(node: Node) -> bool:
	if node is CharacterBody3D or str(node.name) == "Player":
		return true
	for c in node.get_children():
		if _tree_has_player(c):
			return true
	return false

func _fresh_sim() -> SimulationCore:
	var ctl = _inst.get_node("World/MapController")
	var ref: SimulationCore = _inst.get_simulation()
	var actors_config: Array = []
	for id in ref.actors:
		var a: Dictionary = ref.get_actor(id)
		actors_config.append({
			"id": id, "display_name": a["display_name"], "home": a["home"], "preferred": a["preferred"],
		})
	return SimulationCore.new(ctl, actors_config, ref.seed_value)

func _fresh_sim_600_summary() -> String:
	if _cached_600 != "":
		return _cached_600
	var s := _fresh_sim()
	for i in 600:
		s.step()
	_cached_600 = s.event_summary()
	return _cached_600
