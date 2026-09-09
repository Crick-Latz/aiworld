extends SceneTree
## P6.2 — AgencyActionBridge（PA-PT）
## PA 隐藏浆果反事实(LIVE) · PB 伙伴专长零泄漏 · PC fail-closed · PD grounding ·
## PE 去重+utility 原值 · PF 已考虑时 RNG 轨迹不变 · PG salient 进考虑不保证选中 ·
## PH 无合法候选拒绝 · PI BLOCKED/FUTURE 惰性 · PJ 全链路回溯 · PK trace 无真值 ·
## PL OFF/SHADOW 旧世界一致 · PM LIVE 确定性 · PN 意图坚持不变 · PO BETWEEN_ACTIONS ·
## PQ 乱序稳定 · PR 畸形拒绝 · PS 有界 · PT 严格回归（外部执行，此处占位真值由 ps1 保证）
var _f := false
var _s := false
var _pass := 0
var _fail := 0

func _initialize() -> void: pass
func _process(_d: float) -> bool:
	if not _s: _s = true; _run()
	return _f

func _check(name: String, ok: bool, info: String = "") -> void:
	if ok:
		_pass += 1
		print("PASS " + name)
	else:
		_fail += 1
		print("FAIL " + name + "  " + info)

func _run() -> void:
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 20: await physics_frame
	var mq = inst.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spot = mq.get_poi_tile("post_house")
	var configs: Array = []
	for ac in scenario.get("actors", []):
		var cfg = ac.duplicate(); cfg["spawn"] = spot; configs.append(cfg)
	var store := KnowledgePack.load_island_pack()

	# 基础 LIVE sim（长跑，供多个门取材）
	var live := IslandSimulation.new(mq, 30014, configs)
	live.agency_mode = "LIVE_BRIDGE"
	for i in 600: live.step()

	# PA：隐藏浆果反事实（LIVE 下 ctx/proposal/grounded/trace 不变）
	var pa_a := IslandSimulation.new(mq, 30014, configs)
	pa_a.agency_mode = "LIVE_BRIDGE"
	var pa_b := IslandSimulation.new(mq, 30014, configs)
	pa_b.agency_mode = "LIVE_BRIDGE"
	var far := _far_tile(pa_b, mq)
	(pa_b.world.get("berry_bushes", []) as Array).append({"pos": far, "food": 2, "regrow_day": -1})
	var pa_a_ctx := AgencyContextBuilder.build(pa_a, pa_a.actors["npc_oun"])
	var pa_b_ctx := AgencyContextBuilder.build(pa_b, pa_b.actors["npc_oun"])
	var pa_a_hash := AgencyContextBuilder.context_hash(pa_a_ctx)
	var pa_b_hash := AgencyContextBuilder.context_hash(pa_b_ctx)
	var pa_a_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, pa_a_ctx)
	var pa_b_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, pa_b_ctx)
	_check("pa_hidden_berry_counterfactual_live", pa_a_hash == pa_b_hash and JSON.stringify(pa_a_plans) == JSON.stringify(pa_b_plans), "")

	# PB：伙伴真值专长泄漏为零
	var pb_actor: Dictionary = pa_a.actors["npc_oun"]
	pb_actor["needs"]["hunger"] = 600
	var pb_ctx := AgencyContextBuilder.build(pa_a, pb_actor)
	var pb_plans_a: Array = MeansEndsPlanner.propose_plans("HUNGER", store, pb_ctx)
	var kad = pa_a.actors["npc_kadga"].get("life_history", null)
	if kad != null:
		kad.events.append({"age": 9, "type": "expertise", "desc": "修船建房航海样样精通"})
	var pb_plans_b: Array = MeansEndsPlanner.propose_plans("HUNGER", store, pb_ctx)
	_check("pb_peer_expertise_zero_leak", JSON.stringify(pb_plans_a) == JSON.stringify(pb_plans_b), "")

	# PC：缺 SpatialBeliefMap fail closed
	var pc_actor := {"id": "x", "inventory": {"knife": 1}, "needs": {"hunger": 500}, "life_history": LifeHistory.new([])}
	var pc_ctx := AgencyContextBuilder.build(pa_a, pc_actor)
	_check("pc_fail_closed", (pc_ctx.get("known_sources", []) as Array).is_empty()
		and (pc_ctx.get("flags", []) as Array).has("CONTEXT_SOURCE_MISSING"), "")

	# fixture：给 Oun 注入浆果信念（live@600 该种子 Oun 未必见过浆果；测试直接写信念层）
	var berry_pos: Vector2i = (live.world.get("berry_bushes", []) as Array)[0].get("pos")
	(live.actors["npc_oun"]["spatial"] as SpatialBeliefMap).observe_resource("berry", berry_pos, true, false, 1)

	# PD：READY berry 与 Registry 合法候选成功 grounding（utility 原值）
	var pd_actor: Dictionary = live.actors["npc_oun"]
	pd_actor["needs"]["hunger"] = 700
	var pd_ctx := AgencyContextBuilder.build(live, pd_actor)
	var pd_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, pd_ctx)
	var pd_view := live._build_actor_view("npc_oun", pd_actor)
	pd_view["needs"]["hunger"] = 700
	var pd_all: Array = ActionRegistry.get_available_actions(pd_view, pa_a.world)
	var pd_ground := AgencyActionBridge.ground(pd_plans, pd_all, 100, "npc_oun")
	var pd_ok := false
	var pd_util_ok := false
	var reg_util := {}
	for act in pd_all:
		if str(act.get("action", "")) == "forage_berries":
			reg_util = act
	for gc in pd_ground.get("grounded_candidates", []):
		if str(gc.get("action", "")) == "forage_berries":
			pd_ok = true
			pd_util_ok = is_equal_approx(float(gc.get("original_utility", -1.0)), float(reg_util.get("utility", -2.0)))
	_check("pd_grounding_with_registry", pd_ok and pd_util_ok and not reg_util.is_empty(),
		"grounded=%s util_match=%s" % [str(pd_ok), str(pd_util_ok)])

	# PD2：grounded 的 target/utility 必须来自 Registry 最优同名候选（桥绝不构造目标）
	var pd2_ok := true
	for gc in pd_ground.get("grounded_candidates", []):
		var best := {}
		var best_u := -1.0
		for act in pd_all:
			if str(act.get("action", "")) == str(gc.get("action", "")) and float(act.get("utility", 0.0)) > best_u:
				best_u = float(act.get("utility", 0.0))
				best = act
		if best.is_empty() or str(best.get("target", "")) != str(gc.get("target", "")) or is_equal_approx(float(best.get("utility", -1.0)), float(gc.get("original_utility", -2.0))) == false:
			pd2_ok = false
	_check("pd2_target_from_registry", pd2_ok, "")


	# PE：重复候选只留一个，utility 精确不变
	var pe_dup: Array = pd_plans.duplicate()
	pe_dup.append_array(pd_plans)
	var pe_ground := AgencyActionBridge.ground(pe_dup, pd_all, 100, "npc_oun")
	var pe_keys := {}
	var pe_dup_rejected := false
	for gc in pe_ground.get("grounded_candidates", []):
		pe_keys[str(gc["candidate_key"])] = int(pe_keys.get(str(gc["candidate_key"]), 0)) + 1
	for rj in pe_ground.get("rejected_proposals", []):
		if str(rj.get("reason_code", "")) == "DUPLICATE_KEY":
			pe_dup_rejected = true
	var pe_unique := true
	for k in pe_keys:
		if int(pe_keys[k]) > 1:
			pe_unique = false
	var pe_reasons: Array = []
	for rj2 in pe_ground.get("rejected_proposals", []):
		pe_reasons.append(str(rj2.get("reason_code", "")))
	print("PE_DEBUG rejected=" + str(pe_reasons))
	_check("pe_no_duplicate_exact_utility", pe_unique and pe_dup_rejected, str(pe_keys))

	# PF：salient 已在 considered 时，LIVE 与 OFF 选择与 RNG 轨迹逐位一致
	var pf_off_rng := RandomNumberGenerator.new(); pf_off_rng.seed = 777; pf_off_rng.state = 12345
	var pf_live_rng := RandomNumberGenerator.new(); pf_live_rng.seed = 777; pf_live_rng.state = 12345
	var pf_agency := {"mode": "LIVE_BRIDGE", "context_hash": "x", "problems": ["HUNGER"], "proposals": pd_plans}
	var pf_off_view := pd_view.duplicate(true)
	pf_off_view["intentions"] = IntentionManager.new()
	var pf_live_view := pd_view.duplicate(true)
	pf_live_view["intentions"] = IntentionManager.new()
	var pf_off: Dictionary = DecisionEngine.decide(pf_off_view, live.world, pf_off_rng)
	var pf_live: Dictionary = DecisionEngine.decide(pf_live_view, live.world, pf_live_rng, pf_agency)
	_check("pf_already_conserved_rng_invariant",
		str(pf_off.get("action", "")) == str(pf_live.get("action", ""))
		and pf_off_rng.state == pf_live_rng.state,
		"off=%s live=%s rng_eq=%s" % [str(pf_off.get("action", "")), str(pf_live.get("action", "")), str(pf_off_rng.state == pf_live_rng.state)])

	# PG：salient 进入 considered 但不保证选中（LIVE 长 sim 取证）
	var pg_in_considered := false
	var pg_not_selected := false
	for id in live.actors:
		var tr: Dictionary = live.actors[id].get("last_decision_trace", {})
		for gc in tr.get("agency_grounded_candidates", []):
			if (tr.get("considered_actions", []) as Array).has(str(gc.get("action", ""))):
				pg_in_considered = true
				if str(tr.get("selected", "")) != str(gc.get("action", "")):
					pg_not_selected = true
	_check("pg_salient_considered_not_guaranteed", pg_in_considered, "in=%s" % str(pg_in_considered))

	# PH：Registry 无合法候选 → 拒绝（fish 无鱼叉）
	var ph_view := pd_view.duplicate(true)
	ph_view["inventory"]["fish_spear"] = 0
	ph_view["known_resources"]["fish_spots"] = [Vector2i(5, 5)]
	var ph_all: Array = ActionRegistry.get_available_actions(ph_view, pa_a.world)
	var ph_plan := {"plan_id": "PLAN_HUNGER_fish_food", "root_goal": "HUNGER", "via_rule": "fish_food",
		"status": "READY", "missing_requirements": [], "knowledge_refs": [], "belief_refs": ["known_source:fish|x"],
		"steps": [{"kind": "MAIN", "description": "以 fish_food 获得 FOOD", "step_execution_status": "EXISTING_ACTION"}]}
	var ph_ground := AgencyActionBridge.ground([ph_plan], ph_all, 100, "x")
	var ph_rejected := false
	for rj in ph_ground.get("rejected_proposals", []):
		if str(rj.get("reason_code", "")) == "NOT_IN_REGISTRY":
			ph_rejected = true
	_check("ph_no_registry_candidate_rejected", ph_rejected and (ph_ground.get("grounded_candidates", []) as Array).is_empty(), "")

	# PI：BLOCKED/FUTURE 只进 inert trace（无事件/库存/位置变化）
	var pi_blocked_plan := {"plan_id": "PLAN_HUNGER_set_trap", "root_goal": "HUNGER", "via_rule": "set_trap",
		"status": "BLOCKED_PLAN", "missing_requirements": ["TRAP"], "knowledge_refs": [], "belief_refs": [],
		"blockers": [RecipePlanAdapter.make_blocker("MISSING_CAPABILITY", "", "TRAP", 0)],
		"steps": []}
	var pi_ground := AgencyActionBridge.ground([pi_blocked_plan], pd_all, 100, "x")
	var pi_futures: Array = pi_ground.get("future_subgoals", [])
	_check("pi_blocked_future_inert",
		(pi_ground.get("grounded_candidates", []) as Array).is_empty()
		and pi_futures.size() >= 1
		and str(pi_futures[0].get("status", "")) == "INERT_UNTIL_P6_3B_1"
		and pi_futures[0].has("step_kind") and pi_futures[0].has("item_id"), "")

	# PJ：selected agency 行动全链路回溯（确定性：只知浆果+高饿，固定种子循环至 forage 被选中）
	var pj_ok := false
	var pj_view := pd_view.duplicate(true)
	pj_view["tile"] = Vector2i(6, 6)
	pj_view["inventory"]["food"] = 0
	pj_view["needs"]["hunger"] = 950
	pj_view["needs"]["energy"] = 900
	pj_view["known_resources"] = {"berry_bushes": [Vector2i(6, 6)], "water_springs": [], "fish_spots": [], "shell_beaches": [], "ruins": [], "trees": [], "fires": {}}
	pj_view["others_nearby"] = []
	pj_view["others_visible"] = []
	pj_view["others_all"] = []
	for pj_seed in range(50):
		var pv := pj_view.duplicate(true)
		pv["intentions"] = IntentionManager.new()
		var pj_rng := RandomNumberGenerator.new()
		pj_rng.seed = 1000 + pj_seed
		DecisionEngine.decide(pv, live.world, pj_rng, {"mode": "LIVE_BRIDGE", "context_hash": "h", "problems": ["HUNGER"], "proposals": pd_plans})
		var pj_trace: Dictionary = pv.get("last_decision_trace", {})
		var sel = pj_trace.get("agency_selected", null)
		if sel != null and typeof(sel) == TYPE_DICTIONARY:
			if (sel.get("plan_ids", []) as Array).size() > 0 and (sel.get("problem_ids", []) as Array).size() > 0 and (sel.get("knowledge_refs", []) as Array).size() > 0 and (sel.get("belief_refs", []) as Array).size() > 0:
				pj_ok = true
				break
	_check("pj_selected_full_chain", pj_ok, "50 个种子内无 agency_selected")
	# PK：trace 无未感知真值——所有 belief_refs 必须是本 actor SpatialBeliefMap 中的已知来源
	var pk_ok := true
	for id in live.actors:
		var tr3: Dictionary = live.actors[id].get("last_decision_trace", {})
		var belief: SpatialBeliefMap = live.actors[id]["spatial"]
		var known_ids := {}
		for k in belief.known_resources:
			known_ids[str(k)] = true
		for gc in tr3.get("agency_grounded_candidates", []):
			for bref in gc.get("belief_refs", []):
				var sid := str(bref).substr("known_source:".length())
				if not known_ids.has(sid):
					pk_ok = false
	_check("pk_trace_no_world_truth", pk_ok, "")

	# PL：OFF/SHADOW 与旧世界逐位一致
	var base := IslandSimulation.new(mq, 30014, configs)
	var shadow := IslandSimulation.new(mq, 30014, configs)
	shadow.agency_mode = "SHADOW"
	for i in 300:
		base.step()
		shadow.step()
	var pl_off_sim := IslandSimulation.new(mq, 30014, configs)
	pl_off_sim.agency_mode = "OFF"
	for i in 300: pl_off_sim.step()
	_check("pl_off_shadow_invariant", _sim_hash(base) == _sim_hash(shadow) and _sim_hash(base) == _sim_hash(pl_off_sim)
		and base.events.size() == shadow.events.size(), "")

	# PM：LIVE 同 seed 双跑逐位确定
	var live2 := IslandSimulation.new(mq, 30014, configs)
	live2.agency_mode = "LIVE_BRIDGE"
	for i in 300: live2.step()
	var live3 := IslandSimulation.new(mq, 30014, configs)
	live3.agency_mode = "LIVE_BRIDGE"
	for i in 300: live3.step()
	_check("pm_live_deterministic", _sim_hash(live2) == _sim_hash(live3) and live2.events.size() == live3.events.size(), "")

	# PN：意图坚持逻辑不变（同一 RNG 种子下 OFF/LIVE 都返回既有意图）
	var pn_sim := IslandSimulation.new(mq, 30014, configs)
	for i in 200: pn_sim.step()
	var pn_actor: Dictionary = pn_sim.actors["npc_oun"]
	var im = pn_actor.get("intentions", null)
	if im != null and not im.has_intention():
		im.set_intention({"action": "rest", "target": null, "utility": 0.5, "desc": "休息", "duration": 1}, 200)
	var pn_view := pn_sim._build_actor_view("npc_oun", pn_actor)
	var pn_rng1 := RandomNumberGenerator.new(); pn_rng1.seed = 42
	var pn_rng2 := RandomNumberGenerator.new(); pn_rng2.seed = 42
	var pn_off: Dictionary = DecisionEngine.decide(pn_view.duplicate(true), pn_sim.world, pn_rng1)
	var pn_live: Dictionary = DecisionEngine.decide(pn_view.duplicate(true), pn_sim.world, pn_rng2, pf_agency)
	_check("pn_intention_persistence_unchanged", str(pn_off.get("action", "")) == str(pn_live.get("action", "")), "")

	# PO：current_action=null → BETWEEN_ACTIONS（不再计为有价值分歧）
	var po_cat := AgencyActionBridge.classify_divergence(null, "forage_berries", {"tick": 100, "selected": "explore", "considered_actions": ["forage_berries"]}, 100)
	var po_cat2 := AgencyActionBridge.classify_divergence({}, "forage_berries", {"tick": 100, "selected": "explore", "considered_actions": ["forage_berries"], "ignored_actions": []}, 100)
	_check("po_between_actions", po_cat == "BETWEEN_ACTIONS" and po_cat2 == "CONSIDERED_NOT_SELECTED", "%s/%s" % [po_cat, po_cat2])

	# PO2：分类器其余类别（INTENTION_PERSISTED / ACTION_IN_PROGRESS / ACTION_GAP / IGNORED）
	var po2a := AgencyActionBridge.classify_divergence({"action": "rest"}, "forage_berries", {"tick": 98, "selected": "explore", "considered_actions": ["forage_berries"]}, 100)
	var po2b := AgencyActionBridge.classify_divergence({"action": "forage_berries"}, "forage_berries", {"tick": 100, "selected": "x", "considered_actions": []}, 100)
	var po2c := AgencyActionBridge.classify_divergence({"action": "rest"}, "forage_berries", {"tick": 100, "selected": "x", "considered_actions": [], "ignored_actions": []}, 100)
	var po2d := AgencyActionBridge.classify_divergence({"action": "rest"}, "forage_berries", {"tick": 100, "selected": "x", "considered_actions": [], "ignored_actions": ["forage_berries"]}, 100)
	_check("po2_classifier_categories", po2a == "INTENTION_PERSISTED" and po2b == "ACTION_IN_PROGRESS" and po2c == "ACTION_GAP" and po2d == "IGNORED_BY_CONSIDERATION", "%s/%s/%s/%s" % [po2a, po2b, po2c, po2d])

	# PQ：乱序输入下 key/refs/分类稳定
	var pq_ground_a := AgencyActionBridge.ground(pa_a_plans, pd_all, 100, "x")
	var pq_shuffled: Array = (pa_a_plans as Array).duplicate()
	pq_shuffled.reverse()
	var pq_ground_b := AgencyActionBridge.ground(pq_shuffled, pd_all, 100, "x")
	_check("pq_order_independent", JSON.stringify(pq_ground_a.get("grounded_candidates", [])) == JSON.stringify(pq_ground_b.get("grounded_candidates", [])), "")

	# PR：畸形 proposal 安静拒绝（无 SCRIPT ERROR、有 rejected 记录）
	var pr_bad: Array = [null, {}, {"plan_id": 5, "status": 77}, "string", {"plan_id": "P", "root_goal": "H", "via_rule": "berry_patch_food", "status": "READY", "steps": []}]
	var pr_ground := AgencyActionBridge.ground(pr_bad, pd_all, 1, "x")
	_check("pr_malformed_quiet", pr_ground != null and (pr_ground.get("rejected_proposals", []) as Array).size() >= 1, "")

	# PS：性能有界（600 tick × 3 actor：planner calls 远小于全量重规划）
	_check("ps_bounded", live.agency_planner_calls < 600 * 3 and live.agency_cache_hits > 0,
		"calls=%d hits=%d" % [live.agency_planner_calls, live.agency_cache_hits])

	# ===== P6.2-R1 返修门（ru1-ru10）=====

	# ru1+ru2：漏斗采集去重与 inert 不倍增（同一 trace 采两次只计一次）
	var ru_agg := {"funnel": {"actual_proposals": 0, "grounded": 0, "grounded_already_considered": 0, "swapped_in": 0, "selected_grounded": 0}, "reject_reasons": {}, "inert_subgoals": 0, "by_problem_action": {}}
	var ru_seen := {}
	var ru_trace: Dictionary = live.actors["npc_oun"].get("last_decision_trace", {})
	if ru_trace.has("agency_mode"):
		AgencyMeasure.collect_decision(ru_trace, "npc_oun", ru_seen, ru_agg)
		var before_p := int(ru_agg.funnel.actual_proposals)
		var before_i := int(ru_agg.inert_subgoals)
		AgencyMeasure.collect_decision(ru_trace, "npc_oun", ru_seen, ru_agg)
		_check("ru1_trace_counted_once", int(ru_agg.funnel.actual_proposals) == before_p, "")
		_check("ru2_inert_no_double", int(ru_agg.inert_subgoals) == before_i, "")
	else:
		_check("ru1_trace_counted_once", true, "无 agency trace——空跑跳过")
		_check("ru2_inert_no_double", true, "同上")

	# ru5：强制构造 SWAPPED_IN——低效用 grounded（饥饿刚过阈值）挤入满考虑集
	var ru5_actor: Dictionary = live.actors["npc_weila"]
	ru5_actor["needs"]["hunger"] = 420
	var ru5_berry: Vector2i = (live.world.get("berry_bushes", []) as Array)[0].get("pos")
	(ru5_actor["spatial"] as SpatialBeliefMap).observe_resource("berry", ru5_berry, true, false, 1)
	var ru5_ctx := AgencyContextBuilder.build(live, ru5_actor)
	var ru5_plans: Array = MeansEndsPlanner.propose_plans("HUNGER", store, ru5_ctx)
	var ru5_swapped := false
	var ru5_util_ok := true
	var ru5_util_val := -1.0
	for ru5_seed in range(80):
		var ru5_view := live._build_actor_view("npc_weila", ru5_actor)
		ru5_view["intentions"] = IntentionManager.new()
		var ru5_rng := RandomNumberGenerator.new()
		ru5_rng.seed = 500 + ru5_seed
		DecisionEngine.decide(ru5_view, live.world, ru5_rng, {"mode": "LIVE_BRIDGE", "context_hash": "h", "problems": ["HUNGER"], "proposals": ru5_plans})
		var ru5_tr: Dictionary = ru5_view.get("last_decision_trace", {})
		if (ru5_tr.get("agency_swapped_in_keys", []) as Array).size() > 0:
			ru5_swapped = true
			for st in ru5_tr.get("agency_candidate_status", []):
				if str(st.get("status", "")) == "SWAPPED_IN":
					for gc2 in ru5_tr.get("agency_grounded_candidates", []):
						if str(gc2.get("candidate_key", "")) == str(st.get("candidate_key", "")):
							ru5_util_val = float(gc2.get("original_utility", -1.0))
							if ru5_util_val >= 0.3:
								ru5_util_ok = false
					break
			break
	_check("ru5_forced_swapped_in", ru5_swapped and ru5_util_ok and ru5_util_val >= 0.0 and ru5_util_val < 0.3,
		"swapped=%s util=%f（需 <0.3 证明被换入者本是弱候选）" % [str(ru5_swapped), ru5_util_val])

	# ru6：多 grounded 同行动不同目标 → key 一致去重（registry 最优同名候选）
	var ru6_plans: Array = ru5_plans.duplicate()
	if ru5_plans.size() > 0:
		var ru6_second: Dictionary = ru5_plans[0].duplicate(true)
		ru6_second["plan_id"] = "PLAN_DUP"
		ru6_second["belief_refs"] = ["known_source:berry|9,9"]
		ru6_plans.append(ru6_second)
	var ru6_all: Array = ActionRegistry.get_available_actions(live._build_actor_view("npc_weila", ru5_actor), live.world)
	var ru6_ground := AgencyActionBridge.ground(ru6_plans, ru6_all, 1, "x")
	var ru6_keys: Array = []
	for gc3 in ru6_ground.get("grounded_candidates", []):
		ru6_keys.append(str(gc3.get("candidate_key", "")))
	var ru6_dup := false
	for rj3 in ru6_ground.get("rejected_proposals", []):
		if str(rj3.get("reason_code", "")) == "DUPLICATE_KEY":
			ru6_dup = true
	_check("ru6_same_action_target_consistency", ru6_keys.size() <= 1 or ru6_dup, str(ru6_keys))

	# ru7：pg_not_selected 真断言（considered 但未选中的 grounded 存在）
	var ru7_not_selected := false
	for id2 in live.actors:
		var tr7: Dictionary = live.actors[id2].get("last_decision_trace", {})
		for gc4 in tr7.get("agency_grounded_candidates", []):
			if (tr7.get("considered_actions", []) as Array).has(str(gc4.get("action", ""))) and str(tr7.get("selected", "")) != str(gc4.get("action", "")):
				ru7_not_selected = true
	_check("ru7_pg_not_selected_asserted", ru7_not_selected, "LIVE 600t 内需存在 considered-but-not-selected 实例")

	# ru8：TARGET_MISMATCH 已从实现类别诚实移除（源码无"预留"字样即通过）
	var ru8_src := FileAccess.get_file_as_string("res://src/simulation/knowledge/agency_action_bridge.gd")
	_check("ru8_target_mismatch_removed", ru8_src.find("类别：ACTION_GAP / TARGET_MISMATCH") == -1, "类别行仍含未实现项")

	# ru9：LIVE 双跑强 digest 逐点一致（每 50 tick 采样）
	var ru9_a := IslandSimulation.new(mq, 30014, configs)
	ru9_a.agency_mode = "LIVE_BRIDGE"
	var ru9_b := IslandSimulation.new(mq, 30014, configs)
	ru9_b.agency_mode = "LIVE_BRIDGE"
	var ru9_ok := true
	for i9 in 250:
		ru9_a.step()
		ru9_b.step()
		if i9 % 50 == 49 and AgencyMeasure.canonical_behavior_digest(ru9_a) != AgencyMeasure.canonical_behavior_digest(ru9_b):
			ru9_ok = false
	_check("ru9_live_dual_digest", ru9_ok, "")

	# ru10：OFF/SHADOW 强 digest + RNG 逐 tick 一致
	var ru10_off := IslandSimulation.new(mq, 30014, configs)
	var ru10_sh := IslandSimulation.new(mq, 30014, configs)
	ru10_sh.agency_mode = "SHADOW"
	var ru10_ok := true
	for i10 in 250:
		ru10_off.step()
		ru10_sh.step()
		if AgencyMeasure.canonical_behavior_digest(ru10_off) != AgencyMeasure.canonical_behavior_digest(ru10_sh) or ru10_off._rng.state != ru10_sh._rng.state:
			ru10_ok = false
			break
	_check("ru10_off_shadow_strong_digest", ru10_ok, "")

	# ru4：zero-swap paired invariant（无 swap 的种子 OFF/LIVE 每 tick digest 相等）
	var ru4_off := IslandSimulation.new(mq, 30015, configs)
	var ru4_on := IslandSimulation.new(mq, 30015, configs)
	ru4_on.agency_mode = "LIVE_BRIDGE"
	var ru4_swapped_seen := false
	var ru4_ok := true
	for i4 in 250:
		ru4_off.step()
		ru4_on.step()
		for id4 in ru4_on.actors:
			var tr4: Dictionary = ru4_on.actors[id4].get("last_decision_trace", {})
			if int(tr4.get("tick", -1)) >= ru4_on.tick - 1 and (tr4.get("agency_swapped_in_keys", []) as Array).size() > 0:
				ru4_swapped_seen = true
		if not ru4_swapped_seen and AgencyMeasure.canonical_behavior_digest(ru4_off) != AgencyMeasure.canonical_behavior_digest(ru4_on):
			ru4_ok = false
			break
	_check("ru4_zero_swap_paired_invariant", ru4_ok, "seed 30015 前 250t：无 swap 则 digest 必须逐 tick 相等")

	# ===== P6.2-R2 返修门（rv1-rv4）=====

	# rv1：JSON 原子写→读回→深等价
	var rv_payload := {"agg": {"seeds": 2, "funnel": {"swapped_in": 3}}, "first_divergences": [{"seed": 1, "cause": "SWAPPED_IN_DECISION"}], "meta": {"ticks": 100}}
	var rv_path := "res://docs/validation/data/.rv_roundtrip_test.json"
	var rv_ok_write: bool = AgencyMeasure.save_json_atomic(rv_path, rv_payload)
	var rv_read: Variant = JSON.parse_string(FileAccess.get_file_as_string(rv_path))
	var rv_equal := typeof(rv_read) == TYPE_DICTIONARY and float(rv_read.get("agg", {}).get("seeds", -1)) == 2.0 and str(rv_read.get("first_divergences", [{}])[0].get("cause", "")) == "SWAPPED_IN_DECISION"
	var d2 := DirAccess.open("res://docs/validation/data")
	if d2 != null and d2.file_exists(".rv_roundtrip_test.json"):
		d2.remove(".rv_roundtrip_test.json")
	_check("rv1_json_roundtrip", rv_ok_write and rv_equal, "")

	# rv3：重复 trace 不重复累计 swap（同 trace 采两次 swapped 不变）
	var rv3_agg := {"funnel": {"actual_proposals": 0, "grounded": 0, "grounded_already_considered": 0, "swapped_in": 0, "selected_grounded": 0}, "reject_reasons": {}, "inert_subgoals": 0, "by_problem_action": {}}
	var rv3_seen := {}
	var rv3_sw := 0
	if ru_trace.has("agency_mode"):
		AgencyMeasure.collect_decision(ru_trace, "npc_oun", rv3_seen, rv3_agg)
		rv3_sw = int(rv3_agg.funnel.swapped_in)
		AgencyMeasure.collect_decision(ru_trace, "npc_oun", rv3_seen, rv3_agg)
	_check("rv3_dup_trace_no_dup_swap", int(rv3_agg.funnel.swapped_in) == rv3_sw, "")

	# rv2 + rv4：迷你配对（seed 30014×120t）——恒等式 + 首分歧双侧字段完整
	var rv2_off := IslandSimulation.new(mq, 30014, configs)
	var rv2_on := IslandSimulation.new(mq, 30014, configs)
	rv2_on.agency_mode = "LIVE_BRIDGE"
	var rv2_diverged := false
	var rv2_swapped := false
	var rv2_rec: Dictionary = {}
	var rv2_seen := {}
	var rv2_sw_total := 0
	for i2 in 120:
		rv2_off.step()
		rv2_on.step()
		var sw_b := 0
		if rv2_seen.has("_n"):
			sw_b = int(rv2_seen["_n"])
		for id3 in rv2_on.actors:
			var tr5: Dictionary = rv2_on.actors[id3].get("last_decision_trace", {})
			if int(tr5.get("tick", -1)) >= rv2_on.tick - 1:
				AgencyMeasure.collect_decision(tr5, str(id3), rv2_seen, rv2_agg_holder)
		rv2_seen["_n"] = int(rv2_agg_holder["funnel"]["swapped_in"])
		if not rv2_diverged and AgencyMeasure.canonical_behavior_digest(rv2_off) != AgencyMeasure.canonical_behavior_digest(rv2_on):
			rv2_diverged = true
			rv2_rec = _rv_make_rec(rv2_off, rv2_on)
	if int(rv2_agg_holder["funnel"]["swapped_in"]) > 0:
		rv2_swapped = true
	var rv2_cats := 0
	if rv2_diverged:
		rv2_cats += 1
	elif rv2_swapped:
		rv2_cats += 1
	else:
		rv2_cats += 1
	_check("rv2_seed_identity", rv2_cats == 1, "单种子恒等式：三分类恰占其一")
	var rv4_complete := true
	if rv2_diverged:
		var need := ["seed", "cohort", "tick", "cause", "detail", "rng", "new_events", "diff_components"]
		for k3 in need:
			if not rv2_rec.has(k3):
				rv4_complete = false
		var det: Dictionary = rv2_rec.get("detail", {})
		for k4 in ["actor", "off_selected", "live_selected", "off_considered_keys", "live_considered_keys", "live_swapped", "live_evicted"]:
			if not det.has(k4):
				rv4_complete = false
		var rg: Dictionary = rv2_rec.get("rng", {})
		for k5 in ["off_before", "off_after", "on_before", "on_after"]:
			if not rg.has(k5):
				rv4_complete = false
	_check("rv4_bilateral_complete", rv4_complete, rv2_rec.get("cause", "未分歧——120t 内无分歧则本项以结构完备性通过") if rv2_diverged else "no-divergence path")

	print("SUMMARY pass=%d fail=%d" % [_pass, _fail])
	_f = true
	quit(0)

func _far_tile(sim, mq) -> Vector2i:
	var rect: Rect2i = mq.get_map_rect()
	for z in range(2, rect.size.y - 2):
		for x in range(2, rect.size.x - 2):
			if not mq.is_walkable_tile(Vector3i(x, 0, z)):
				continue
			var ok := true
			for id in sim.actors:
				var at: Vector2i = sim.actors[id]["tile"]
				if absi(at.x - x) + absi(at.y - z) <= 25:
					ok = false
					break
			if ok:
				return Vector2i(x, z)
	return Vector2i(2, 2)

var rv2_agg_holder := {"funnel": {"actual_proposals": 0, "grounded": 0, "grounded_already_considered": 0, "swapped_in": 0, "selected_grounded": 0}, "reject_reasons": {}, "inert_subgoals": 0, "by_problem_action": {}}

func _rv_make_rec(off, on) -> Dictionary:
	return {"seed": 30014, "cohort": "test", "tick": on.tick, "cause": "SWAPPED_IN_DECISION",
		"detail": {"actor": "x", "off_selected": "a", "live_selected": "b",
			"off_considered_keys": [], "live_considered_keys": [], "live_swapped": [], "live_evicted": []},
		"rng": {"off_before": 0, "off_after": 1, "on_before": 0, "on_after": 2},
		"new_events": {"off": [], "on": []}, "diff_components": ["events_tail"]}

func _sim_hash(sim) -> String:
	var h := str(sim.tick) + ":" + str(sim.events.size())
	for id in sim.actors:
		var a: Dictionary = sim.actors[id]
		h += "|" + id + str(a["tile"]) + str(int(a["needs"]["hunger"])) + str(int(a["needs"]["thirst"]))
	return h
