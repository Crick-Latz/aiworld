extends SceneTree
## P6.3B-1 — 第一条可执行计划链（A-R 门）
## A 开关关闭不变性 · B SHADOW 不执行 · C ACQUIRE 匹配真实候选 · D 隐藏来源不匹配 ·
## E 未知配方/能力不足不能制作 · F 足量材料跳过 ACQUIRE · G 缺口vs最终需求 ·
## H 被选中未完成不推进 · I 制作后能力出现+恢复原目标 · J 制作失败不推进 ·
## K 重复通知幂等 · L 他人事件不推进 · M 旧 run 不影响新计划 · N 材料被耗重查 ·
## O 暂停恢复同一 run · P 无进展超时不因重规划续期 · Q 双跑一致 · R 完整真实链
var _f := false
var _s := false
var _pass := 0
var _fail := 0
func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f
func _check(name: String, ok: bool, info: String = "") -> void:
	if ok: _pass += 1; print("PASS " + name)
	else: _fail += 1; print("FAIL " + name + "  " + info)

func _run() -> void:
	var items := ItemCatalog.load_default()
	var recipes := RecipeCatalog.load_default(items)
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var mq = null
	var scenario_actors: Array = []
	if ps != null:
		var inst = ps.instantiate()
		root.add_child(inst)
		for i in 20: await physics_frame
		mq = inst.get_node("World/MapController")
		var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
		scenario_actors = scenario.get("actors", [])
		inst.queue_free()

	# ── A：开关关闭 → 与旧基线行为/RNG 一致（OFF vs OFF+enabled；LIVE vs LIVE+enabled=false）──
	if mq != null:
		var a_off := IslandSimulation.new(mq, 30014, scenario_actors)
		var a_off_en := IslandSimulation.new(mq, 30014, scenario_actors)
		a_off_en.agency_plan_execution_enabled = true
		var a_live := IslandSimulation.new(mq, 30014, scenario_actors)
		a_live.agency_mode = "LIVE_BRIDGE"
		var a_live_en := IslandSimulation.new(mq, 30014, scenario_actors)
		a_live_en.agency_mode = "LIVE_BRIDGE"
		a_live_en.agency_plan_execution_enabled = false
		for i in 200:
			a_off.step(); a_off_en.step(); a_live.step(); a_live_en.step()
		var a_ok := AgencyMeasure.canonical_behavior_digest(a_off) == AgencyMeasure.canonical_behavior_digest(a_off_en) \
			and AgencyMeasure.canonical_behavior_digest(a_live) == AgencyMeasure.canonical_behavior_digest(a_live_en)
		for id in a_off.actors:
			a_ok = a_ok and InventoryOps.canonical_hash(a_off.actors[id]["inventory"]) == InventoryOps.canonical_hash(a_off_en.actors[id]["inventory"])
		_check("a_switch_off_invariance", a_ok, "")
	else:
		_check("a_switch_off_invariance", false, "no map")

	# ── B：SHADOW 只观察不执行（无执行 trace，行为与开关关闭一致）──
	if mq != null:
		var b_sh := IslandSimulation.new(mq, 30014, scenario_actors)
		b_sh.agency_mode = "SHADOW"
		b_sh.agency_plan_execution_enabled = true
		var b_base := IslandSimulation.new(mq, 30014, scenario_actors)
		b_base.agency_mode = "SHADOW"
		for i in 200:
			b_sh.step(); b_base.step()
		var b_ok := AgencyMeasure.canonical_behavior_digest(b_sh) == AgencyMeasure.canonical_behavior_digest(b_base) \
			and b_sh.agency_execution_trace().is_empty()
		_check("b_shadow_observe_only", b_ok, "trace=%d" % b_sh.agency_execution_trace().size())
	else:
		_check("b_shadow_observe_only", false, "no map")

	# ── C：当前 ACQUIRE 步骤匹配真实 Registry 合法候选（目标 ∈ 主观已知来源）──
	var c_step := PlanStepSpec.make("ACQUIRE", "ACQUIRE:item:wood", "PENDING", "", "wood", 1, "", "", ["wood"], [], [], [], "get")
	var c_actor := {"id": "u", "personality": PersonalityProfile.new({"pragmatism": 0.8, "curiosity": 0.2}, {}),
		"needs": {"hunger": 700, "energy": 1000, "thirst": 0, "social": 0}, "physical": {}, "inventory": {},
		"tile": Vector2i(3, 3), "known_resources": {"trees": [Vector2i(4, 4)]}, "visited_tiles": {},
		"others_visible": [], "open_questions": [], "my_obligations": [], "institutional_goals": []}
	var c_actions: Array = ActionRegistry.get_available_actions(c_actor, {"tick": 1})
	var c_ctx := _ctx({"wood": 0}, [], ["WOOD"], [{"tag": "WOOD", "source_id": "tree|4,4", "belief_ref": "known_source:t1", "last_seen_tick": 1, "confidence": 1.0}], ["recipe_fish_spear"])
	var c_match: Dictionary = PlanStepActionAdapter.match_candidates(c_step, c_actions, c_ctx, recipes, items)
	var c_real := false
	var has_gather := false
	for ca in c_actions:
		if str((ca as Dictionary).get("action", "")) == "gather_wood":
			has_gather = true
	for cd in c_match.get("candidates", []):
		if str((cd as Dictionary).get("action", "")) == "gather_wood" and (cd as Dictionary).get("target", null) == Vector2i(4, 4):
			c_real = true
	_check("c_acquire_matches_real_candidate", has_gather and c_real and str(c_match.get("blocker_reason", "?")) == "",
		"registry_has_gather=%s matched=%s reason=%s" % [str(has_gather), str(c_real), str(c_match.get("blocker_reason", "?"))])

	# ── D：隐藏来源（不知道树在哪）→ 无候选 + 明确 blocker ──
	var d_actor := c_actor.duplicate(true)
	d_actor["known_resources"] = {}
	var d_actions: Array = ActionRegistry.get_available_actions(d_actor, {"tick": 1})
	var d_ctx := _ctx({"wood": 0}, [], [], [], ["recipe_fish_spear"])
	var d_match: Dictionary = PlanStepActionAdapter.match_candidates(c_step, d_actions, d_ctx, recipes, items)
	var d_no_gather := true
	for da in d_actions:
		if str((da as Dictionary).get("action", "")) == "gather_wood":
			d_no_gather = false
	_check("d_hidden_source_no_match", d_no_gather and (d_match.get("candidates", []) as Array).is_empty()
		and str(d_match.get("blocker_reason", "")) == "NO_KNOWN_SOURCE",
		"reason=%s" % str(d_match.get("blocker_reason", "?")))

	# ── E：未知配方 / 个人未知 / 能力不足 / 材料不足 → CRAFT blocker ──
	var e_items := ItemCatalog.load_default()
	var e_recipes := RecipeCatalog.new(e_items)
	e_recipes._register({"recipe_id": "recipe_cap_test", "ingredients": {"wood": 1},
		"outputs": {"fish_spear": 1}, "knowledge_refs": [], "required_capabilities": ["PIERCE"],
		"duration_ticks": 1})
	var e_step_unknown := PlanStepSpec.make("CRAFT", "CRAFT:recipe:no_such", "PENDING", "", "fish_spear", 1, "no_such", "FISH", [], ["FISH"], [], [], "c")
	var e_unknown: Dictionary = PlanStepActionAdapter.match_candidates(e_step_unknown, [], _ctx({}, [], [], [], []), e_recipes, e_items)
	var e_step_fish := PlanStepSpec.make("CRAFT", "CRAFT:recipe:recipe_fish_spear", "PENDING", "", "fish_spear", 1, "recipe_fish_spear", "FISH", [], ["FISH"], [], [], "c")
	var e_not_known: Dictionary = PlanStepActionAdapter.match_candidates(e_step_fish, [], _ctx({}, [], [], [], []), recipes, items)
	var e_step_cap := PlanStepSpec.make("CRAFT", "CRAFT:recipe:recipe_cap_test", "PENDING", "", "fish_spear", 1, "recipe_cap_test", "FISH", [], ["FISH"], [], [], "c")
	var e_caps: Array = ["recipe_cap_test"]
	var e_no_cap: Dictionary = PlanStepActionAdapter.match_candidates(e_step_cap, [], _ctx({}, [], [], [], e_caps), e_recipes, e_items)
	var e_with_cap := _ctx({}, [], [], [], e_caps)
	e_with_cap["possessed_capabilities"] = ["PIERCE"]
	var e_mats: Dictionary = PlanStepActionAdapter.match_candidates(e_step_cap, [], e_with_cap, e_recipes, e_items)
	_check("e_craft_blockers", str(e_unknown.get("blocker_reason", "")) == "UNKNOWN_RECIPE"
		and str(e_not_known.get("blocker_reason", "")) == "RECIPE_NOT_KNOWN"
		and str(e_no_cap.get("blocker_reason", "")) == "MISSING_CAPABILITY_FOR_CRAFT"
		and str(e_mats.get("blocker_reason", "")) == "MATERIALS_MISSING",
		"%s/%s/%s/%s" % [str(e_unknown.get("blocker_reason", "?")), str(e_not_known.get("blocker_reason", "?")),
			str(e_no_cap.get("blocker_reason", "?")), str(e_mats.get("blocker_reason", "?"))])

	# ── F：已有足量材料 → 无 ACQUIRE，首步 CRAFT（真实 planner）──
	var store := KnowledgePack.load_island_pack()
	var f_ctx := _ctx({"wood": 1, "shells": 1}, [], ["WOOD", "SHELL", "FISH"],
		[{"tag": "WOOD", "source_id": "tree|1,1", "belief_ref": "k1", "last_seen_tick": 1, "confidence": 1.0},
			{"tag": "SHELL", "source_id": "shell|2,2", "belief_ref": "k2", "last_seen_tick": 1, "confidence": 1.0},
			{"tag": "FISH", "source_id": "fish|3,3", "belief_ref": "k3", "last_seen_tick": 1, "confidence": 1.0}],
		["recipe_fish_spear"])
	var f_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, f_ctx, recipes, items)
	var f_kinds: Array = []
	for plan in f_plans:
		if str(plan.get("via_rule", "")) == "fish_food":
			for st in plan.get("steps", []):
				f_kinds.append(str((st as Dictionary).get("kind", "")))
	_check("f_materials_ok_skip_acquire", f_kinds.size() == 2 and f_kinds[0] == "CRAFT" and f_kinds[1] == "MAIN",
		"kinds=" + str(f_kinds))

	# ── G：缺口量 vs 最终需求量（需3/有1/缺2：拥有2未满足，3 才完成）──
	var g_tracker := PlanExecutionTracker.new()
	var g_plan := _fish_plan(2)
	var g_ctx1 := _ctx({"wood": 1}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"])
	g_tracker.prepare_decision("u", [g_plan], g_ctx1, 1)
	var g_key := "gather_wood@4,4"
	var g_ident: Dictionary = _decide(g_tracker, "u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		{"step_id": "ACQUIRE:item:wood", "selected": true, "candidate_key": g_key, "blocker_reason": ""}, 1)
	var g_r2: Dictionary = g_tracker.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(1, "gathered_wood", "u")], {"wood": 2}, 2, g_ident)
	g_ident = _decide(g_tracker, "u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		{"step_id": "ACQUIRE:item:wood", "selected": true, "candidate_key": g_key}, 3)
	var g_r3: Dictionary = g_tracker.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(2, "gathered_wood", "u")], {"wood": 3}, 3, g_ident)
	_check("g_gap_vs_required", not bool(g_r2.get("advanced", true)) and bool(g_r3.get("advanced", false)),
		"have2=%s have3=%s" % [str(g_r2), str(g_r3)])

	# ── H：被选择但未完成 → 步骤不推进（选中只挂 pending）──
	var h_tracker := PlanExecutionTracker.new()
	var h_plan := _fish_plan(1)
	h_tracker.prepare_decision("u", [h_plan], _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 1)
	_decide(h_tracker, "u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		{"step_id": "ACQUIRE:item:wood", "selected": true, "candidate_key": "gather_wood@4,4", "blocker_reason": ""}, 1)
	var h_run: Dictionary = h_tracker.runs["u"]
	_check("h_selected_not_completed", str(h_run.get("current_step_id", "")) == "ACQUIRE:item:wood"
		and str(h_run.get("state", "")) == "ACTIVE" and not (h_run.get("completion_event_refs", []) as Array).size() > 0, "")

	# ── I：成功制作后能力出现 + 恢复原捕鱼目标（首步 CRAFT 的短链）──
	if mq != null:
		var i_sim := _chain_sim(mq, true, "LIVE_BRIDGE", 30031, {"wood": 1, "shells": 1})
		var i_crafted := -1
		for i in 60:
			i_sim.step()
			if i_crafted < 0:
				for e in i_sim.events:
					if str(e.get("type", "")) == "crafted":
						i_crafted = int(e.get("tick", -1))
		var i_run: Dictionary = i_sim.agency_plan_run("npc_chain")
		var i_caps: Array = InventoryOps.capabilities_of_inventory(i_sim.actors["npc_chain"]["inventory"], items)
		# 制作后该 run 恢复 MAIN（R1：经 trace 判定，最终 run 可能是重启后的新周期）
		var i_at_main := false
		var i_craft_run := ""
		for tr in i_sim.agency_execution_trace():
			var td: Dictionary = tr
			if str(td.get("event", "")) == "STEP_COMPLETED" and str(td.get("step_id", "")) == "CRAFT:recipe:recipe_fish_spear":
				i_craft_run = str(td.get("run_id", ""))
			if str(td.get("run_id", "")) == i_craft_run and i_craft_run != "" \
					and (str(td.get("event", "")) == "STEP_ADVANCED" or str(td.get("event", "")) == "STEP_COMPLETED") \
					and str(td.get("step_id", "")) == "MAIN:rule:fish_food":
				i_at_main = true
		_check("i_craft_then_capability_and_main", i_crafted > 0 and i_caps.has("FISH")
			and i_at_main and str(i_run.get("root_goal", "")) == "HUNGER",
			"crafted_tick=%d caps=%s main_after_craft=%s goal=%s" % [i_crafted, str(i_caps), str(i_at_main), str(i_run.get("root_goal", "?"))])
	else:
		_check("i_craft_then_capability_and_main", false, "no map")

	# ── J：制作失败（无 crafted 事件/事务未产出）→ 不推进、不改状态 ──
	var j_tracker := PlanExecutionTracker.new()
	var j_plan := _fish_plan(1)
	var j_ctx := _ctx({"wood": 0, "shells": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"])
	j_tracker.prepare_decision("u", [j_plan], j_ctx, 1)
	# 直接推进到 CRAFT 步（材料经库存达标自动跳过 ACQUIRE）
	var j_ctx2 := _ctx({"wood": 1, "shells": 1}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"])
	j_tracker.prepare_decision("u", [j_plan], j_ctx2, 2)
	var j_ident: Dictionary = _decide(j_tracker, "u", {"action": "craft_fish_spear", "target": Vector2i(3, 3)},
		{"step_id": "CRAFT:recipe:recipe_fish_spear", "selected": true, "candidate_key": "craft_fish_spear@3,3", "blocker_reason": ""}, 2)
	var j_r: Dictionary = j_tracker.on_action_complete("u", {"action": "craft_fish_spear", "target": Vector2i(3, 3)},
		[_ev(9, "gathered_wood", "u")], {"wood": 1, "shells": 1}, 3, j_ident)
	var j_run: Dictionary = j_tracker.runs["u"]
	_check("j_failed_craft_no_advance", not bool(j_r.get("advanced", true))
		and str(j_run.get("current_step_id", "")) == "CRAFT:recipe:recipe_fish_spear"
		and str(j_run.get("state", "")) == "ACTIVE", "r=%s step=%s" % [str(j_r), str(j_run.get("current_step_id", "?"))])

	# ── K：重复完成通知幂等（同一步不二次推进）──
	var k_tracker := PlanExecutionTracker.new()
	var k_plan := _fish_plan(1)
	k_tracker.prepare_decision("u", [k_plan], _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 1)
	var k_ident: Dictionary = _decide(k_tracker, "u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		{"step_id": "ACQUIRE:item:wood", "selected": true, "candidate_key": "gather_wood@4,4", "blocker_reason": ""}, 1)
	var k_first: Dictionary = k_tracker.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(1, "gathered_wood", "u")], {"wood": 1}, 2, k_ident)
	var k_second: Dictionary = k_tracker.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(2, "gathered_wood", "u")], {"wood": 1}, 2, k_ident)
	var k_run: Dictionary = k_tracker.runs["u"]
	_check("k_duplicate_notify_idempotent", bool(k_first.get("advanced", false)) and k_second.is_empty()
		and str(k_run.get("current_step_id", "")) == "ACQUIRE:item:shells",
		"first=%s second=%s step=%s" % [str(k_first), str(k_second), str(k_run.get("current_step_id", "?"))])

	# ── L：其他 actor 的完成通知不推进自己的计划 ──
	var l_tracker := PlanExecutionTracker.new()
	l_tracker.prepare_decision("u", [_fish_plan(1)], _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 1)
	_decide(l_tracker, "u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		{"step_id": "ACQUIRE:item:wood", "selected": true, "candidate_key": "gather_wood@4,4", "blocker_reason": ""}, 1)
	var l_before: String = JSON.stringify(l_tracker.runs.get("u", {}))
	var l_r: Dictionary = l_tracker.on_action_complete("other", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(3, "gathered_wood", "other")], {"wood": 5}, 2)
	_check("l_other_actor_isolated", l_r.is_empty() and JSON.stringify(l_tracker.runs.get("u", {})) == l_before, "")

	# ── M：旧 run_id 的完成通知不影响新计划 ──
	var m_tracker := PlanExecutionTracker.new()
	m_tracker.no_progress_timeout = 2
	m_tracker.prepare_decision("u", [_fish_plan(1)], _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 1)
	var m_run1: Dictionary = m_tracker.runs["u"]
	var m_old_run_id := str(m_run1.get("run_id", ""))
	m_tracker.prepare_decision("u", [_fish_plan(1), _berry_plan()], _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 5)
	var m_run2: Dictionary = m_tracker.runs["u"]
	var m_stale: Dictionary = m_tracker.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(4, "gathered_wood", "u")], {"wood": 1}, 5)
	_check("m_stale_run_no_effect", str(m_run1.get("state", "")) == "CANCELLED"
		and str(m_run2.get("run_id", "")) != m_old_run_id
		and m_stale.is_empty() and str(m_run2.get("current_step_id", "")) == "MAIN:rule:berry_patch_food",
		"run1=%s(%s) run2=%s stale=%s" % [m_old_run_id, str(m_run1.get("state", "?")), str(m_run2.get("run_id", "?")), str(m_stale)])

	# ── N：材料中途被消耗 → 决策前重查，不得沿用旧 READY ──
	var n_tracker := PlanExecutionTracker.new()
	var n_plan := _fish_plan(1)
	n_tracker.prepare_decision("u", [n_plan], _ctx({"wood": 0, "shells": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 1)
	# 材料到位 → 自动推进到 CRAFT 步
	n_tracker.prepare_decision("u", [n_plan], _ctx({"wood": 1, "shells": 1}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 2)
	var n_run: Dictionary = n_tracker.runs["u"]
	# 材料被别的行动烧掉（make_fire）——决策时 CRAFT 前提失效
	_decide(n_tracker, "u", {"action": "make_fire", "target": Vector2i(3, 3)},
		{"step_id": "CRAFT:recipe:recipe_fish_spear", "selected": false, "candidate_key": "", "blocker_reason": "MATERIALS_MISSING"}, 3)
	_check("n_consumed_materials_recheck", str(n_run.get("current_step_id", "")) == "CRAFT:recipe:recipe_fish_spear"
		and str(n_run.get("state", "")) == "BLOCKED" and str(n_run.get("reason_code", "")) == "MATERIALS_MISSING",
		"state=%s reason=%s" % [str(n_run.get("state", "?")), str(n_run.get("reason_code", "?"))])

	# ── O（R1 §六.1）：真实 prepare→决策链恢复——被其他行动打断→再次考虑→恢复→实际完成 ──
	# 高饥饿+带 1 存粮：t1 eat_food（效用 1.17）压过 gather_shells → run 创建即 SUSPENDED；
	# 吃完后 eat 候选消失、意图自然过期（gap>0.35 不再 reinforce）→ gather_shells 重新
	# 进入考虑集（SUSPENDED 也提供步骤）→ 选中 → 同一 run 恢复并完成采集。
	if mq != null:
		var o_sim := _chain_sim(mq, true, "LIVE_BRIDGE", 30061, {"wood": 1, "food": 1})
		o_sim.actors["npc_chain"]["needs"]["hunger"] = 850
		var o_run_id := ""
		var o_suspended_at := -1
		var o_resumed_at := -1
		var o_acquire_done_at := -1
		var o_restarts_during_pause := 0
		for i in 60:
			o_sim.step()
			for tr in o_sim.agency_execution_trace():
				var td: Dictionary = tr
				if o_run_id == "" and str(td.get("event", "")) == "RUN_STARTED":
					o_run_id = str(td.get("run_id", ""))
				if str(td.get("run_id", "")) == o_run_id:
					if str(td.get("event", "")) == "RUN_SUSPENDED" and o_suspended_at < 0:
						o_suspended_at = int(td.get("tick", -1))
					if str(td.get("event", "")) == "RUN_RESUMED" and o_resumed_at < 0:
						o_resumed_at = int(td.get("tick", -1))
					if str(td.get("event", "")) == "STEP_COMPLETED" and str(td.get("step_id", "")) == "ACQUIRE:item:shells":
						o_acquire_done_at = int(td.get("tick", -1))
				# 暂停窗口内不得重启（同一 run 应被恢复而非替换）
				if o_suspended_at > 0 and o_acquire_done_at < 0 and str(td.get("event", "")) == "RUN_STARTED" \
						and str(td.get("run_id", "")) != o_run_id:
					o_restarts_during_pause += 1
		var o_final: Dictionary = o_sim.agency_plan_run("npc_chain")
		_check("o_suspend_resume_real_chain", o_suspended_at > 0
			and o_resumed_at > o_suspended_at and o_acquire_done_at > o_resumed_at
			and o_restarts_during_pause == 0
			and str(o_final.get("root_goal", "")) == "HUNGER",
			"susp@%d resumed@%d acquired@%d restarts=%d final_goal=%s" % [o_suspended_at,
				o_resumed_at, o_acquire_done_at, o_restarts_during_pause, str(o_final.get("root_goal", "?"))])
	else:
		_check("o_suspend_resume_real_chain", false, "no map")

	# ── SR2（R1 §六.2）：同一 proposal 持续存在——超时→冷却中不启动→到期新建 run ──
	var sr2 := PlanExecutionTracker.new()
	sr2.no_progress_timeout = 4
	var sr2_ctx := _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"])
	sr2.prepare_decision("u", [_fish_plan(1)], sr2_ctx, 1)
	var sr2_run1_id := str(sr2.runs["u"].get("run_id", ""))
	var sr2_run_at := {}
	for tk in range(2, 12):
		sr2.prepare_decision("u", [_fish_plan(1)], sr2_ctx, tk)
		var pr2: Dictionary = sr2.runs.get("u", {})
		if not pr2.is_empty():
			sr2_run_at[tk] = str(pr2.get("run_id", ""))
	# 取消在 t6（6-1=5>4），冷却到 t10；t7-9 不得有新 run（仍是已取消的 run1），t10 新建 run2
	var sr2_ok := true
	for tk in range(7, 10):
		if str(sr2_run_at.get(tk, "")) != sr2_run1_id:
			sr2_ok = false
	var sr2_new_id := str(sr2_run_at.get(10, ""))
	_check("sr2_cooldown_then_restart", sr2_ok and sr2_new_id != "" and sr2_new_id != sr2_run1_id
		and str(sr2.runs["u"].get("state", "")) == "ACTIVE",
		"run1=%s t7-9=%s t10=%s state=%s" % [sr2_run1_id, str(sr2_run_at.get(7, "?")), sr2_new_id, str(sr2.runs["u"].get("state", "?"))])

	# ── SR3（R1 §六.3）：材料失效 BLOCKED→冷却→材料恢复（真实 planner 重排）→重建继续 ──
	var sr3 := PlanExecutionTracker.new()
	sr3.no_progress_timeout = 4
	var sr3_store := KnowledgePack.load_island_pack()
	var sr3_ctx1 := _ctx({"wood": 1, "shells": 1}, [], ["WOOD", "SHELL", "FISH"],
		[{"tag": "SHELL", "source_id": "shell|2,2", "belief_ref": "k2", "last_seen_tick": 1, "confidence": 1.0},
			{"tag": "FISH", "source_id": "fish|3,3", "belief_ref": "k3", "last_seen_tick": 1, "confidence": 1.0}], ["recipe_fish_spear"])
	var sr3_p1: Array = MeansEndsPlanner.propose_plans("HUNGER", sr3_store, sr3_ctx1, recipes, items)
	sr3.prepare_decision("u", sr3_p1, sr3_ctx1, 1)
	var sr3_run1_id := str(sr3.runs["u"].get("run_id", ""))
	# 材料被烧掉：决策时 CRAFT 前提失效 → BLOCKED + 冷却
	_decide(sr3, "u", {"action": "make_fire", "target": Vector2i(3, 3)},
		{"step_id": "CRAFT:recipe:recipe_fish_spear", "selected": false, "candidate_key": "", "blocker_reason": "MATERIALS_MISSING"}, 2)
	var sr3_blocked_at_t2 := str(sr3.runs["u"].get("state", "")) == "BLOCKED"
	# 冷却期内（t3-5）材料已恢复也不重启同计划
	for tk in range(3, 6):
		sr3.prepare_decision("u", MeansEndsPlanner.propose_plans("HUNGER", sr3_store, sr3_ctx1, recipes, items), sr3_ctx1, tk)
	var sr3_still_blocked := str(sr3.runs["u"].get("run_id", "")) == sr3_run1_id and str(sr3.runs["u"].get("state", "")) == "BLOCKED"
	# 冷却到期（t6）+ 材料有效 + 计划 READY → 重建 run2，CRAFT 步 ACTIVE
	sr3.prepare_decision("u", MeansEndsPlanner.propose_plans("HUNGER", sr3_store, sr3_ctx1, recipes, items), sr3_ctx1, 6)
	var sr3_run2: Dictionary = sr3.runs["u"]
	_check("sr3_blocked_then_rebuild", sr3_blocked_at_t2 and sr3_still_blocked
		and str(sr3_run2.get("run_id", "")) != sr3_run1_id and str(sr3_run2.get("state", "")) == "ACTIVE"
		and str(sr3_run2.get("current_step_id", "")) == "CRAFT:recipe:recipe_fish_spear",
		"blocked=%s still=%s run2=%s step=%s" % [str(sr3_blocked_at_t2), str(sr3_still_blocked),
			str(sr3_run2.get("run_id", "?")), str(sr3_run2.get("current_step_id", "?"))])

	# ── SR4（R1 §六.4）：新旧 run 同 actor/action/target/step——旧完成不推进，新完成才推进，重复无效 ──
	var sr4 := PlanExecutionTracker.new()
	sr4.no_progress_timeout = 2
	var sr4_ctx := _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"])
	sr4.prepare_decision("u", [_fish_plan(1)], sr4_ctx, 1)
	var sr4_ident1: Dictionary = _decide(sr4, "u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		{"step_id": "ACQUIRE:item:wood", "selected": true, "candidate_key": "gather_wood@4,4", "blocker_reason": ""}, 1)
	# t5 超时取消（5-1=4>2），冷却到 t7；t8 重启同一计划 → run2 选同一候选
	sr4.prepare_decision("u", [_fish_plan(1)], sr4_ctx, 5)
	sr4.prepare_decision("u", [_fish_plan(1)], sr4_ctx, 8)
	var sr4_run2: Dictionary = sr4.runs["u"]
	var sr4_ident2: Dictionary = _decide(sr4, "u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		{"step_id": "ACQUIRE:item:wood", "selected": true, "candidate_key": "gather_wood@4,4", "blocker_reason": ""}, 8)
	var sr4_old: Dictionary = sr4.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(4, "gathered_wood", "u")], {"wood": 1}, 8, sr4_ident1)
	var sr4_step_after_old := str(sr4_run2.get("current_step_id", ""))
	var sr4_new: Dictionary = sr4.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(5, "gathered_wood", "u")], {"wood": 1}, 9, sr4_ident2)
	var sr4_dup: Dictionary = sr4.on_action_complete("u", {"action": "gather_wood", "target": Vector2i(4, 4)},
		[_ev(6, "gathered_wood", "u")], {"wood": 1}, 9, sr4_ident2)
	_check("sr4_attempt_identity_collision", sr4_old.is_empty() and sr4_step_after_old == "ACQUIRE:item:wood"
		and bool(sr4_new.get("advanced", false)) and sr4_dup.is_empty()
		and str(sr4_ident1.get("run_id", "")) != str(sr4_ident2.get("run_id", "")),
		"old=%s after_old=%s new=%s dup=%s" % [str(sr4_old), sr4_step_after_old, str(sr4_new), str(sr4_dup)])

	# ── SR5（R1 §六.5）：意图坚持早退的陈旧 trace——不得错误重挂 pending/串 run ──
	if mq != null:
		var sr5_sim := _chain_sim(mq, true, "LIVE_BRIDGE", 30071, {"wood": 1})
		sr5_sim.step()  # t1：run 创建，gather_shells 选中（身份已挂）
		var sr5_a: Dictionary = sr5_sim.actors["npc_chain"]
		var sr5_run: Dictionary = sr5_sim.agency_plan_run("npc_chain")
		var sr5_pending_before: Dictionary = (sr5_run.get("pending", {}) as Dictionary).duplicate(true)
		var sr5_inflight_before: Dictionary = (sr5_a.get("_plan_exec_inflight", {}) as Dictionary).duplicate(true)
		var sr5_ok_pre := not sr5_pending_before.is_empty() and not sr5_inflight_before.is_empty()
		# 模拟意图坚持早退：trace 是旧决策的（决策引擎未写新 trace，decision_tick 陈旧）
		sr5_a["last_decision_trace"]["agency_execution"]["decision_tick"] = 0
		sr5_sim._plan_execution_on_decision("npc_chain", sr5_a, {"action": "rest", "target": null})
		var sr5_unchanged := JSON.stringify(sr5_sim.agency_plan_run("npc_chain").get("pending", {})) == JSON.stringify(sr5_pending_before) \
			and JSON.stringify(sr5_a.get("_plan_exec_inflight", {})) == JSON.stringify(sr5_inflight_before)
		# 修复不应阻塞正常完成：继续跑，采集在同一 run 内完成
		var sr5_acquired := false
		for i in 30:
			sr5_sim.step()
			for tr5 in sr5_sim.agency_execution_trace():
				if str((tr5 as Dictionary).get("event", "")) == "STEP_COMPLETED" \
						and str((tr5 as Dictionary).get("step_id", "")) == "ACQUIRE:item:shells" \
						and str((tr5 as Dictionary).get("run_id", "")) == str(sr5_run.get("run_id", "")):
					sr5_acquired = true
		_check("sr5_stale_trace_no_rehook", sr5_ok_pre and sr5_unchanged and sr5_acquired,
			"pre=%s unchanged=%s acquired=%s" % [str(sr5_ok_pre), str(sr5_unchanged), str(sr5_acquired)])
	else:
		_check("sr5_stale_trace_no_rehook", false, "no map")

	# ── P：无进展超时——不因重规划续期 ──
	var p_tracker := PlanExecutionTracker.new()
	p_tracker.no_progress_timeout = 4
	var p_plan := _fish_plan(1)
	p_tracker.prepare_decision("u", [p_plan], _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), 1)
	var p_last_progress := -1
	var p_cancel_tick := -1
	for tk in range(2, 9):
		p_tracker.prepare_decision("u", [_fish_plan(1)], _ctx({"wood": 0}, [], ["WOOD", "SHELL", "FISH"], [], ["recipe_fish_spear"]), tk)
		var pr: Dictionary = p_tracker.runs.get("u", {})
		if p_last_progress < 0 and not pr.is_empty():
			p_last_progress = int(pr.get("last_progress_tick", -1))
		if p_cancel_tick < 0 and str(pr.get("reason_code", "")) == "NO_PROGRESS_TIMEOUT":
			p_cancel_tick = tk
	_check("p_no_progress_timeout", p_last_progress == 1 and p_cancel_tick == 6,
		"last_progress=%d cancel_at=%d（重规划每 tick 新实例——未续期）" % [p_last_progress, p_cancel_tick])

	# ── Q：同 seed 同输入双跑——执行 trace 与结果一致 ──
	if mq != null:
		var q1 := _chain_sim(mq, true, "LIVE_BRIDGE", 30041, {"wood": 1})
		var q2 := _chain_sim(mq, true, "LIVE_BRIDGE", 30041, {"wood": 1})
		for i in 60:
			q1.step(); q2.step()
		var q_ok := JSON.stringify(q1.agency_execution_trace()) == JSON.stringify(q2.agency_execution_trace()) \
			and JSON.stringify(q1.events) == JSON.stringify(q2.events) \
			and InventoryOps.canonical_hash(q1.actors["npc_chain"]["inventory"]) == InventoryOps.canonical_hash(q2.actors["npc_chain"]["inventory"])
		_check("q_deterministic_double_run", q_ok, "")
	else:
		_check("q_deterministic_double_run", false, "no map")

	# ── R：完整真实链——采集→crafted→fish，同一 run_id 贯穿 ──
	# 初始 wood×1（配方材料齐一半）+ 主观已知贝壳滩/鱼点：链 = ACQUIRE shells → CRAFT → MAIN fish。
	# 不注入树（wood 不再增长 → build_shelter/make_fire 无候选，排除效用黑洞——见报告 §fixture）。
	if mq != null:
		var r_sim := _chain_sim(mq, true, "LIVE_BRIDGE", 30051, {"wood": 1})
		for i in 100:
			r_sim.step()
		var r_run: Dictionary = r_sim.agency_plan_run("npc_chain")
		var r_trace: Array = r_sim.agency_execution_trace()
		# 事件时序
		var r_gather_wood_tick := -1
		var r_gather_shell_tick := -1
		var r_craft_tick := -1
		var r_fish_tick := -1
		for e in r_sim.events:
			match str(e.get("type", "")):
				"gathered_wood":
					if r_gather_wood_tick < 0: r_gather_wood_tick = int(e.get("tick", -1))
				"gathered_shells":
					if r_gather_shell_tick < 0: r_gather_shell_tick = int(e.get("tick", -1))
				"crafted":
					if r_craft_tick < 0 and str(e.get("recipe_id", "")) == "recipe_fish_spear": r_craft_tick = int(e.get("tick", -1))
				"fished":
					if r_fish_tick < 0: r_fish_tick = int(e.get("tick", -1))
		# 按 run 分组：COMPLETED 后重启是新需求周期的合法行为——链的证明是
		# 存在一个 run 完成 shells+CRAFT+MAIN 三步且带 RUN_COMPLETED 转移
		var r_steps_by_run := {}
		var r_completed_runs := {}
		for tr in r_trace:
			var td: Dictionary = tr
			var rid0 := str(td.get("run_id", ""))
			if str(td.get("event", "")) == "STEP_COMPLETED":
				if not r_steps_by_run.has(rid0):
					r_steps_by_run[rid0] = {}
				(r_steps_by_run[rid0] as Dictionary)[str(td.get("step_id", ""))] = true
			if str(td.get("event", "")) == "RUN_COMPLETED":
				r_completed_runs[rid0] = true
		var r_chain_run := ""
		for rid1 in r_steps_by_run:
			var sd: Dictionary = r_steps_by_run[rid1]
			if sd.has("ACQUIRE:item:shells") and sd.has("CRAFT:recipe:recipe_fish_spear") \
					and sd.has("MAIN:rule:fish_food"):
				r_chain_run = str(rid1)
		var r_chain_completed := r_chain_run != "" and r_completed_runs.has(r_chain_run)
		var r_order := r_gather_shell_tick > 0 \
			and r_craft_tick > r_gather_shell_tick and r_fish_tick > r_craft_tick
		var r_state := str(r_run.get("state", ""))
		print("R_CHAIN chain_run=%s final_state=%s gather_wood@%d shells@%d crafted@%d fished@%d runs=%d" % [
			r_chain_run, r_state, r_gather_wood_tick, r_gather_shell_tick, r_craft_tick, r_fish_tick, r_steps_by_run.size()])
		if not (r_order and r_chain_completed):
			_report_blockage(r_sim)
		_check("r_full_real_chain", r_order and r_chain_completed
			and int(r_sim.actors["npc_chain"]["inventory"].get("fish_spear", 0)) >= 1,
			"wood@%d shell@%d craft@%d fish@%d chain=%s completed=%s" % [r_gather_wood_tick, r_gather_shell_tick,
				r_craft_tick, r_fish_tick, r_chain_run, str(r_chain_completed)])
	else:
		_check("r_full_real_chain", false, "no map")

	_test_attempt_contract(mq)
	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(1 if _fail > 0 else 0)

## R2: every rejected identity is tested on a fresh live pending attempt.
func _test_attempt_contract(mq) -> void:
	var action := {"action": "gather_wood", "target": Vector2i(4, 4)}
	var ctx := _ctx({"wood": 0}, [], [], [], [])
	var malformed_ok := true
	for field in ["actor_id", "run_id", "step_id", "candidate_key", "attempt_id"]:
		for remove in [false, true]:
			var tracker := PlanExecutionTracker.new()
			var prep := tracker.prepare_decision("u", [_fish_plan(1)], ctx, 1)
			var info := {"run_id": prep["run_id"], "step_id": "ACQUIRE:item:wood",
				"selected": true, "candidate_key": "gather_wood@4,4"}
			var identity := tracker.on_decision("u", action, info, 1)
			var bad := identity.duplicate(true)
			if remove:
				bad.erase(field)
			else:
				bad[field] = float(identity[field]) if field == "attempt_id" else "wrong"
			var before := JSON.stringify(tracker.runs)
			var trace_before := JSON.stringify(tracker.traces)
			var rejected := tracker.on_action_complete("u", action, [_ev(2, "gathered_wood", "u")], {"wood": 1}, 2, bad)
			malformed_ok = malformed_ok and rejected.is_empty() and JSON.stringify(tracker.runs) == before \
				and JSON.stringify(tracker.traces) == trace_before
	_check("r2_identity_all_fields_fail_closed", malformed_ok)

	var stale := PlanExecutionTracker.new()
	stale.prepare_decision("u", [_fish_plan(1)], ctx, 1)
	var stale_before := JSON.stringify(stale.runs)
	var stale_trace := JSON.stringify(stale.traces)
	var wrong := stale.on_decision("u", action, {"run_id": "u#old", "step_id": "ACQUIRE:item:wood",
		"selected": true, "candidate_key": "gather_wood@4,4"}, 2)
	_check("r2_stale_selection_run_rejected", wrong.is_empty() and JSON.stringify(stale.runs) == stale_before
		and JSON.stringify(stale.traces) == stale_trace)

	var once := PlanExecutionTracker.new()
	var once_prep := once.prepare_decision("u", [_fish_plan(2)], ctx, 1)
	var once_info := {"run_id": once_prep["run_id"], "step_id": "ACQUIRE:item:wood",
		"selected": true, "candidate_key": "gather_wood@4,4"}
	var id1 := once.on_decision("u", action, once_info, 1)
	var incomplete := once.on_action_complete("u", action, [_ev(2, "gathered_wood", "u")], {"wood": 1}, 2, id1)
	var after_failure := JSON.stringify(once.runs)
	var duplicate := once.on_action_complete("u", action, [_ev(3, "gathered_wood", "u")], {"wood": 2}, 3, id1)
	var duplicate_unchanged := JSON.stringify(once.runs) == after_failure
	var id2 := once.on_decision("u", action, once_info, 4)
	var completed := once.on_action_complete("u", action, [_ev(5, "gathered_wood", "u")], {"wood": 2}, 5, id2)
	_check("r2_attempt_consumed_even_when_incomplete", not incomplete.get("advanced", true)
		and duplicate.is_empty() and duplicate_unchanged and completed.get("advanced", false)
		and id2.get("attempt_id", 0) > id1.get("attempt_id", 0))

	if mq == null:
		_check("r2_observer_snapshot_isolation", false, "no map")
		_check("r2_world_completion_consumes_identity", false, "no map")
		return
	var sim := _chain_sim(mq, true, "LIVE_BRIDGE", 30071, {"wood": 1})
	sim.step()
	var trace_before := JSON.stringify(sim.agency_execution_trace())
	var run_before := JSON.stringify(sim.agency_plan_run("npc_chain"))
	var run_view := sim.agency_plan_run("npc_chain")
	var traces_view := sim.agency_execution_trace()
	run_view["pending"]["candidate_key"] = "observer-write"
	traces_view[0]["event"] = "observer-write"
	_check("r2_observer_snapshot_isolation", JSON.stringify(sim.agency_execution_trace()) == trace_before
		and JSON.stringify(sim.agency_plan_run("npc_chain")) == run_before)
	# Use a separate real simulation: the observer mutation above must not taint this gate.
	var real := _chain_sim(mq, true, "LIVE_BRIDGE", 30071, {"wood": 1})
	real.step()
	var actor: Dictionary = real.actors["npc_chain"]
	var started := not (actor.get("_plan_exec_inflight", {}) as Dictionary).is_empty()
	var finished := false
	for i in 10:
		real.step()
		if actor.get("current_action", null) == null:
			finished = true
			break
	_check("r2_world_completion_consumes_identity", started and finished
		and (actor.get("_plan_exec_inflight", {}) as Dictionary).is_empty()
		and (real.agency_plan_run("npc_chain").get("pending", {}) as Dictionary).is_empty())

## Component fixture supplies the same run identity as the production prepare/trace path.
func _decide(tracker: PlanExecutionTracker, actor_id: String, action: Dictionary,
		info: Dictionary, tick: int) -> Dictionary:
	var current := info.duplicate(true)
	current["run_id"] = tracker.runs[actor_id]["run_id"]
	return tracker.on_decision(actor_id, action, current, tick)

## 手造鱼链计划（ACQUIRE wood×gap → ACQUIRE shells×gap → CRAFT → MAIN）
func _fish_plan(wood_gap: int) -> Dictionary:
	return {"plan_id": "PLAN_HUNGER_fish_food", "root_goal": "HUNGER", "via_rule": "fish_food",
		"status": "READY", "missing_requirements": [], "blockers": [],
		"knowledge_refs": ["kf_animal_meat"], "belief_refs": [],
		"steps": [
			PlanStepSpec.make("ACQUIRE", "ACQUIRE:item:wood", "PENDING", "", "wood", wood_gap, "", "", ["wood"], [], [], [], "取得木头"),
			PlanStepSpec.make("ACQUIRE", "ACQUIRE:item:shells", "PENDING", "", "shells", 1, "", "", ["shells"], [], [], [], "取得贝壳"),
			PlanStepSpec.make("CRAFT", "CRAFT:recipe:recipe_fish_spear", "PENDING", "", "fish_spear", 1, "recipe_fish_spear", "FISH", [], ["FISH"], ["recipe_fish_spear"], [], "制作鱼叉"),
			PlanStepSpec.make("MAIN", "MAIN:rule:fish_food", "PENDING", "fish", "", 0, "", "", [], [], [], [], "捕鱼"),
		]}

func _berry_plan() -> Dictionary:
	return {"plan_id": "PLAN_HUNGER_berry_patch_food", "root_goal": "HUNGER", "via_rule": "berry_patch_food",
		"status": "READY", "missing_requirements": [], "blockers": [],
		"knowledge_refs": ["kf_plant_food"], "belief_refs": [],
		"steps": [
			PlanStepSpec.make("MAIN", "MAIN:rule:berry_patch_food", "PENDING", "forage_berries", "", 0, "", "", [], [], [], [], "采浆果"),
		]}

func _ctx(possessed: Dictionary, caps: Array, source_tags: Array, sources: Array, recipe_refs: Array) -> Dictionary:
	return {
		"actor_id": "u",
		"possessed_tags": [], "possessed_capabilities": caps,
		"possessed_items": possessed,
		"known_sources": sources, "known_source_tags": source_tags,
		"expertise_tags": [], "known_recipe_refs": recipe_refs,
		"known_peers": [], "activated_problems": ["HUNGER"],
		"context_refs": [], "flags": [],
	}

func _ev(seq: int, type: String, actor: String) -> Dictionary:
	return {"seq": seq, "tick": seq, "type": type, "actor_id": actor, "text": ""}

## 单 actor 链 fixture：集群资源 + 主观信念注入 + 高饥饿（真实 DecisionEngine/世界执行）
## 无树注入：初始 wood 已给——链只走 ACQUIRE shells → CRAFT → MAIN；
## wood 始终 ≤1 → build_shelter(≥2)/make_fire(≥1 耗材) 无候选，排除效用黑洞。
## 超时取 40（fixture 显式配置：softmax 择步有正常的踌躇期；默认仍 16）。
func _chain_sim(mq, enabled: bool, mode: String, seed: int, start_inv: Dictionary) -> IslandSimulation:
	var spot: Vector2i = mq.get_poi_tile("post_house")
	var cfg := {"id": "npc_chain", "name": "链者", "spawn": spot,
		"traits": {"pragmatism": 0.9, "curiosity": 0.12, "caution": 0.3, "action_bias": 0.85,
			"sociability": 0.1, "expressiveness": 0.3, "conflict_avoidance": 0.5,
			"altruism": 0.3, "empathy": 0.3},
		"inventory": start_inv, "life_history": []}
	var sim := IslandSimulation.new(mq, seed, [cfg])
	sim.agency_mode = mode
	sim.agency_plan_execution_enabled = enabled
	sim.agency_no_progress_timeout = 40
	var a: Dictionary = sim.actors["npc_chain"]
	# 清初始感知信念——fixture 完全控制主观已知资源位置
	(a["spatial"] as SpatialBeliefMap).known_resources = {}
	var t: Vector2i = a["tile"]
	var shell := _walkable_near(mq, t, [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1), Vector2i(3, 0)])
	var fish := _walkable_near(mq, t, [Vector2i(0, 3), Vector2i(3, 1), Vector2i(1, 3), Vector2i(-3, 0), Vector2i(0, -3)])
	sim.world["trees"] = []
	sim.world["berry_bushes"] = []
	sim.world["water_springs"] = []
	sim.world["ruins"] = []
	sim.world["shell_beaches"] = [shell]
	sim.world["fish_spots"] = [fish]
	sim._flatten_resources()
	# fixture 护栏：现居地已有庇护所——排除 build_shelter 干扰链路（wood≥2 时的效用黑洞）
	sim.world["shelters"][str(t)] = true
	(a["spatial"] as SpatialBeliefMap).observe_resource("shell", shell, true, false, 1)
	(a["spatial"] as SpatialBeliefMap).observe_resource("fish", fish, true, false, 1)
	a["needs"]["hunger"] = 700
	a["needs"]["energy"] = 1000
	a["needs"]["thirst"] = 0
	a["needs"]["social"] = 0
	return sim

func _walkable_near(mq, base: Vector2i, offsets: Array) -> Vector2i:
	for o in offsets:
		var c: Vector2i = base + o
		if mq.is_walkable_tile(Vector3i(c.x, 0, c.y)):
			return c
	return base

## 完整链未达成时：输出实际竞争行动与阻断点（诚实报告，不换 seed）
func _report_blockage(sim: IslandSimulation) -> void:
	var counts := {}
	var last30: Array = []
	for e in sim.events:
		var ty := str(e.get("type", ""))
		counts[ty] = int(counts.get(ty, 0)) + 1
	for i in range(maxi(0, sim.events.size() - 30), sim.events.size()):
		var e: Dictionary = sim.events[i]
		last30.append("t%d:%s(%s)" % [int(e.get("tick", 0)), str(e.get("type", "")), str(e.get("actor_id", ""))])
	print("R_BLOCKAGE events_summary=" + str(counts))
	print("R_BLOCKAGE last_events=" + ", ".join(last30))
	var run: Dictionary = sim.agency_plan_run("npc_chain")
	print("R_BLOCKAGE run=" + JSON.stringify({"run_id": run.get("run_id", ""), "state": run.get("state", ""),
		"step": run.get("current_step_id", ""), "reason": run.get("reason_code", "")}))
	var inv: Dictionary = sim.actors["npc_chain"]["inventory"]
	print("R_BLOCKAGE inventory=" + str(inv))
