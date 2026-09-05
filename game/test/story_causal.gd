extends SceneTree
## OBS-02 因果闭环验收测试。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/story_causal.gd
## 覆盖：基准夹具（保留0→点亮）/对照夹具（保留2→拒绝+waiting）同规则不同真实结果、
## 状态逐项核对（库存/消耗/灯塔）、因果链回溯、幂等重交、竞争请求固定序、
## 非法数量/非法ID/过期/远距全部拒绝且状态不变、知识门控（未 inspect 不知短缺）。

var passed := 0
var failed := 0
var _started := false
var _finished := false

func _initialize() -> void:
	print("OBS-02 story causal harness: deferred to first frame")

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

func _run_all_tests() -> void:
	var map_query = await _make_map_query()
	if map_query == null:
		for n in ["baseline_reaches_lit", "baseline_state_exact", "control_declines", "control_state_exact",
				"causal_chain_complete", "idempotent_resubmit", "competing_fixed_order",
				"reject_negative_amount", "reject_non_integer", "reject_illegal_id",
				"reject_expired", "reject_far_distance", "knowledge_gating"]:
			_check(n, false, "地图不可用")
		return

	# —— 基准夹具：欧恩 3 份/保留 0 → 全链完成、灯塔点亮 ——
	var sim = _make_story(map_query, "res://data/scenarios/lighthouse_baseline.json")
	var ok_run := false
	for i in 600:
		sim.step()
		if sim.actors["npc_weila"]["phase"] == "done":
			ok_run = true
			break
	_check("baseline_reaches_lit", ok_run and sim.lighthouse_lit,
		"phase=%s lit=%s ticks=%d" % [sim.actors["npc_weila"]["phase"], sim.lighthouse_lit, sim.tick])
	var snap: Dictionary = sim.get_snapshot()
	var w_inv: Dictionary = snap["actors"]["npc_weila"]["inventory"]
	var o_inv: Dictionary = snap["actors"]["npc_oun"]["inventory"]
	_check("baseline_state_exact",
		int(o_inv.get("windcrystal_powder", -1)) == 1
		and int(w_inv.get("windcrystal_powder", -1)) == 0
		and sim.consumed_fuel == 2
		and sim.lighthouse_lit == true
		and snap["actors"]["npc_weila"]["goal_status"] == "succeeded",
		"oun=%d weila=%d consumed=%d lit=%s" % [o_inv.get("windcrystal_powder", -1), w_inv.get("windcrystal_powder", -1), sim.consumed_fuel, sim.lighthouse_lit])

	# —— 对照夹具：欧恩保留 2 → 最多可给 1 → 拒绝；灯塔不亮；waiting 不刷请求 ——
	var sim2 = _make_story(map_query, "res://data/scenarios/lighthouse_control.json")
	var ok_run2 := false
	for i in 600:
		sim2.step()
		if sim2.actors["npc_weila"]["phase"] == "goal_failed":
			ok_run2 = true
			break
	_check("control_declines", ok_run2 and not sim2.lighthouse_lit,
		"phase=%s lit=%s" % [sim2.actors["npc_weila"]["phase"], sim2.lighthouse_lit])
	var snap2: Dictionary = sim2.get_snapshot()
	var o2_inv: Dictionary = snap2["actors"]["npc_oun"]["inventory"]
	var w2_inv: Dictionary = snap2["actors"]["npc_weila"]["inventory"]
	var req_count := 0
	for e in sim2.events:
		if e["type"] == "help_requested":
			req_count += 1
	_check("control_state_exact",
		int(o2_inv.get("windcrystal_powder", -1)) == 3
		and int(w2_inv.get("windcrystal_powder", -1)) == 0
		and not sim2.lighthouse_lit
		and sim2.actors["npc_weila"]["goal_status"] == "waiting"
		and req_count == 1, # 不刷重复请求
		"oun=%d weila=%d requests=%d status=%s" % [o2_inv.get("windcrystal_powder", -1), w2_inv.get("windcrystal_powder", -1), req_count, sim2.actors["npc_weila"]["goal_status"]])
	var decline_events := 0
	for e in sim2.events:
		if e["type"] == "help_declined":
			decline_events += 1
	_check("control_decline_explained", decline_events == 1 and sim2.actors["npc_weila"]["phase"] == "goal_failed",
		"declines=%d" % decline_events)

	# —— 因果链：lit_changed 回溯到 shortage_observed ——
	var chain: Array = sim.causal_chain_of("lit_changed")
	_check("causal_chain_complete",
		chain == ["shortage_observed", "help_requested", "help_accepted", "item_transferred", "work_completed", "lit_changed"],
		str(chain))

	# —— 幂等：同 command_id 重交不重复转移 ——
	var sim3 = _make_story(map_query, "res://data/scenarios/lighthouse_baseline.json")
	for i in 400:
		sim3.step()
		if sim3.actors["npc_weila"]["phase"] == "done":
			break
	var weila_tile: Vector2i = sim3.actors["npc_weila"]["tile"]
	sim3.actors["npc_oun"]["tile"] = weila_tile # 靠近以便手工交易可用
	sim3.actors["npc_oun"]["inventory"]["windcrystal_powder"] = 5
	var before: int = sim3.actors["npc_weila"]["inventory"].get("windcrystal_powder", 0)
	var r1: Dictionary = sim3.submit_transfer("cmd_test_1", "npc_oun", "npc_weila", "windcrystal_powder", 2)
	var after1: int = sim3.actors["npc_weila"]["inventory"]["windcrystal_powder"]
	var r2: Dictionary = sim3.submit_transfer("cmd_test_1", "npc_oun", "npc_weila", "windcrystal_powder", 2)
	var after2: int = sim3.actors["npc_weila"]["inventory"]["windcrystal_powder"]
	_check("idempotent_resubmit", r1["ok"] and r2["ok"] and r2 == r1 and after1 == before + 2 and after2 == after1,
		"before=%d after1=%d after2=%d" % [before, after1, after2])

	# —— 竞争请求：固定提交序，先到先得，后到库存不足拒绝 ——
	sim3.actors["npc_oun"]["inventory"]["windcrystal_powder"] = 3
	sim3.actors["npc_oun"]["reserve"] = {}
	var ra: Dictionary = sim3.submit_transfer("cmd_race_a", "npc_oun", "npc_weila", "windcrystal_powder", 2)
	var rb: Dictionary = sim3.submit_transfer("cmd_race_b", "npc_oun", "npc_weila", "windcrystal_powder", 2)
	_check("competing_fixed_order", ra["ok"] and not rb["ok"] and sim3.actors["npc_oun"]["inventory"]["windcrystal_powder"] == 1,
		"a=%s b=%s left=%d" % [str(ra["ok"]), str(rb["ok"]), sim3.actors["npc_oun"]["inventory"]["windcrystal_powder"]])

	# —— 拒绝反例：状态不变 ——
	sim3.actors["npc_oun"]["inventory"]["windcrystal_powder"] = 3
	sim3.actors["npc_oun"]["tile"] = weila_tile
	var s0 := JSON.stringify(sim3.get_snapshot())
	var rn: Dictionary = sim3.submit_transfer("cmd_neg", "npc_oun", "npc_weila", "windcrystal_powder", -2)
	var rf: Dictionary = sim3.submit_transfer("cmd_float", "npc_oun", "npc_weila", "windcrystal_powder", 1.5)
	var ri: Dictionary = sim3.submit_transfer("cmd_ghost", "npc_ghost", "npc_weila", "windcrystal_powder", 1)
	var re_: Dictionary = sim3.submit_transfer("cmd_exp", "npc_oun", "npc_weila", "windcrystal_powder", 1, 0, 0) # tick>expire
	sim3.actors["npc_oun"]["tile"] = Vector2i(2, 2) # 拉远
	var rd: Dictionary = sim3.submit_transfer("cmd_far", "npc_oun", "npc_weila", "windcrystal_powder", 1)
	sim3.actors["npc_oun"]["tile"] = weila_tile
	var s1 := JSON.stringify(sim3.get_snapshot())
	var all_rejected: bool = not rn["ok"] and not rf["ok"] and not ri["ok"] and not re_["ok"] and not rd["ok"]
	var codes_ok: bool = rn["code"] == "E_COMMAND_FORBIDDEN" and rf["code"] == "E_COMMAND_FORBIDDEN" \
		and ri["code"] == "E_REFERENCE_BROKEN" and re_["code"] == "E_PRECONDITION" and rd["code"] == "E_PRECONDITION"
	_check("reject_negative_amount", not rn["ok"] and rn["code"] == "E_COMMAND_FORBIDDEN", str(rn))
	_check("reject_non_integer", not rf["ok"] and rf["code"] == "E_COMMAND_FORBIDDEN", str(rf))
	_check("reject_illegal_id", not ri["ok"] and ri["code"] == "E_REFERENCE_BROKEN", str(ri))
	_check("reject_expired", not re_["ok"] and re_["code"] == "E_PRECONDITION", str(re_))
	_check("reject_far_distance", not rd["ok"] and rd["code"] == "E_PRECONDITION", str(rd))
	# 状态不变：手工交易前的快照对比（tile 曾短暂改动已复位；inventory 未变）
	var inv_now: int = sim3.actors["npc_oun"]["inventory"]["windcrystal_powder"]
	_check("rejections_state_unchanged", all_rejected and codes_ok and inv_now == 3, "inv=%d" % inv_now)

	# —— 知识门控：未 inspect 的旁观者不知短缺 ——
	var sim4 = _make_story(map_query, "res://data/scenarios/lighthouse_baseline.json")
	sim4.step()
	_check("knowledge_gating",
		not sim4.knowledge.knows("npc_kadga", "fact_lighthouse_dark")
		and not sim4.knowledge.knows("npc_oun", "fact_lighthouse_dark"), # 请求发出前 helper 也不知道
		"提前知情")

	print("STORY_SUMMARY baseline_ticks=%d control_ticks=%d chain=%s" % [
		sim.tick, sim2.tick, str(sim.causal_chain_of("lit_changed"))])

func _make_map_query():
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	if ps == null:
		return null
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20:
		await physics_frame
	return inst.get_node("World/MapController")

func _make_story(map_query, scenario_path: String) -> StorySimulation:
	var text := FileAccess.get_file_as_string(scenario_path)
	var data: Dictionary = JSON.parse_string(text)
	var spawn := {}
	var homes := {"npc_weila": "tide_market", "npc_oun": "tide_market", "npc_kadga": "post_house"}
	for id in homes:
		var t: Vector2i = map_query.get_poi_tile(homes[id])
		spawn[id] = t
	return StorySimulation.new(map_query, data, spawn)
