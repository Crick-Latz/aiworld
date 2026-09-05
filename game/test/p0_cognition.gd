extends SceneTree
## P0 核心闭环验收测试：验证"像人不像机器"的关键指标。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/p0_cognition.gd
## 覆盖 GPT 建议的 4 项关键测试 + Belief/Goal/LifeHistory/Trace 功能验证。

var passed := 0
var failed := 0
var _started := false
var _finished := false

func _initialize() -> void:
	print("P0 cognition harness: deferred")

func _process(_d: float) -> bool:
	if not _started:
		_started = true
		_run()
	return _finished

func _run() -> void:
	await _run_all_tests()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_finished = true
	quit(0 if failed == 0 else 1)

func _check(n: String, c: bool, d: String = "") -> void:
	if c: passed += 1; print("PASS %s" % n)
	else: failed += 1; print("FAIL %s  %s" % [n, d])

func _run_all_tests() -> void:
	var mq = await _make_map()
	if mq == null:
		for i in range(10): _check("p0_%d" % i, false, "地图不可用")
		return

	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var configs := _make_configs(mq, scenario)

	# ── 1. Same World / Different Character ──
	# 同一世界，三个角色行为分布必须不同
	var sim1 := IslandSimulation.new(mq, 20260906, configs)
	for i in 300: sim1.step()
	var activity_sets := {}
	for id in sim1.actors:
		var acts: Dictionary = {}
		for e in sim1.events:
			if e["actor_id"] == id:
				acts[str(e["type"])] = true
		activity_sets[id] = acts.keys()
	var w_acts: Array = activity_sets.get("npc_weila", [])
	var o_acts: Array = activity_sets.get("npc_oun", [])
	var k_acts: Array = activity_sets.get("npc_kadga", [])
	# 至少一对角色有显著不同的行为集
	var all_same := (w_acts == o_acts and o_acts == k_acts)
	_check("same_world_different_character", not all_same,
		"weila=%s oun=%s kadga=%s" % [w_acts, o_acts, k_acts])

	# ── 2. Same Character / Different Seed ──
	# 同一角色不同 seed 应产生不同路径
	var sim2 := IslandSimulation.new(mq, 999999, configs)
	for i in 300: sim2.step()
	var sim3 := IslandSimulation.new(mq, 888888, configs)
	for i in 300: sim3.step()
	var p1 := _event_pattern(sim2, "npc_weila")
	var p2 := _event_pattern(sim3, "npc_weila")
	_check("same_character_different_seed", p1 != p2,
		"pattern1=%d events pattern2=%d" % [p1.length(), p2.length()])

	# ── 3. Hidden Information Test ──
	# NPC 没看到的事件不得影响其信念
	var sim4 := IslandSimulation.new(mq, 20260906, configs)
	for i in 100: sim4.step()
	# 检查每个角色的记忆中只有其目击的事件
	var all_legal := true
	for id in sim4.actors:
		var mems: Array = sim4.actors[id]["memories"]
		for m in mems:
			var seq := int(m.get("seq", -1))
			if seq < 0: continue
			# 找到对应的原始事件
			for e in sim4.events:
				if int(e["seq"]) == seq:
					# 如果事件 actor 不是自己，且距离太远，不应该记住
					if str(e["actor_id"]) != id:
						var event_actor_tile: Vector2i = sim4.actors.get(str(e["actor_id"]), {}).get("tile", Vector2i(0,0))
						var my_tile: Vector2i = sim4.actors[id]["tile"]
						if absi(event_actor_tile.x - my_tile.x) + absi(event_actor_tile.y - my_tile.y) > 20:
							all_legal = false
					break
	_check("hidden_info_no_leak", all_legal, "远距离事件不应被记住")

	# ── 4. Intention Persistence Test ──
	# 不应频繁切换行动类型（action thrashing）
	var sim5 := IslandSimulation.new(mq, 20260906, configs)
	var action_changes := {"npc_weila": 0, "npc_oun": 0, "npc_kadga": 0}
	var last_types := {}
	for i in 200:
		sim5.step()
		for id in action_changes:
			var ca = sim5.actors[id].get("current_action", null)
			var act_type := ""
			if ca != null and typeof(ca) == TYPE_DICTIONARY:
				act_type = str(ca.get("action", ""))
			if act_type == "": continue  # 跳过 idle 间隙，只跟踪实际行动
			if last_types.has(id) and str(last_types[id]) != "" and str(last_types[id]) != act_type:
				action_changes[id] += 1
			if act_type != "":
				last_types[id] = act_type
	var max_changes := 0
	for id in action_changes:
		max_changes = maxi(max_changes, int(action_changes[id]))
	_check("intention_persistence", max_changes < 60,
		"max_action_type_changes=%d" % max_changes)

	# ── 5. GoalManager 功能 ──
	var gm := GoalManager.auto_generate(sim1.actors["npc_weila"])
	_check("goal_manager_generates", gm.goals.size() >= 1, "goals=%d" % gm.goals.size())

	# ── 6. LifeHistory 派生信念 ──
	var oun_life: LifeHistory = sim1.actors["npc_oun"]["life_history"]
	var beliefs := oun_life.derived_beliefs()
	_check("life_history_beliefs", beliefs.has("食物是命"), str(beliefs.keys()))
	var sens: Dictionary = sim1.actors["npc_oun"]["sensitivities"]
	_check("life_history_sensitivities", float(sens.get("food_loss_sensitivity", 0)) > 0.8,
		"sensitivity=%s" % str(sens.get("food_loss_sensitivity", "?")))

	# ── 7. DecisionTrace 完整性 ──
	var weila_trace: Dictionary = sim1.actors["npc_weila"]["last_decision_trace"]
	_check("decision_trace_has_reason", weila_trace.has("reason") or weila_trace.has("selected"),
		"trace_keys=%s" % str(weila_trace.keys()))

	# ── 8. BeliefStore 可用 ──
	var bs: BeliefStore = sim1.actors["npc_weila"]["beliefs"]
	bs.believe("测试信念", 0.8, "test", 1)
	_check("belief_store_works", bs.believes("测试信念"), "confidence=%s" % str(bs.confidence_of("测试信念")))

	print("P0_SUMMARY seeds=3 chars=3 ticks=600 events=%d" % sim1.events.size())

func _event_pattern(sim: IslandSimulation, id: String) -> String:
	var parts: Array = []
	for e in sim.events:
		if e["actor_id"] == id:
			parts.append(str(e["type"]))
	return ",".join(parts)

func _make_map():
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null: return null
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	return inst.get_node("World/MapController")

func _make_configs(mq, scenario: Dictionary) -> Array:
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]
	var configs: Array = []
	var idx := 0
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate()
		cfg["spawn"] = spots[idx % spots.size()]
		idx += 1
		configs.append(cfg)
	return configs
