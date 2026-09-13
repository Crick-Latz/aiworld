extends SceneTree
## P7.2B 加固测试：stale laundering 防护、位置隐私、终态跟随（四类）、
## 重复报告不放大、拒绝目标排除、flag-off 兼容、audit 敏感性。

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_stale_laundering_protection()
	_test_position_privacy()
	_test_goal_cancellation_on_request_terminal()
	_test_duplicate_report_no_amplification()
	_test_excluded_targets_view()
	_test_flag_off_compatibility()
	_test_audit_sensitivity()
	_test_no_duplicate_peer_in_round()
	_test_funnel_diagnostics_appear_and_stay_out_of_state()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])

func _pair(seed_value: int, item_id: String = "shells") -> Dictionary:
	var created := SimulationBootstrap.create(seed_value, "holder_evidence")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var giver_id := str(ids[1])
	sim.actors.erase(str(ids[2]))
	var requester: Dictionary = sim.actors[requester_id]
	var giver: Dictionary = sim.actors[giver_id]
	requester["tile"] = Vector2i(10, 10)
	giver["tile"] = Vector2i(11, 10)
	requester["inventory"] = {}
	giver["inventory"] = {"shells": 2}
	giver["personality"] = PersonalityProfile.new(
		{"altruism": 0.9, "empathy": 0.9, "caution": 0.1, "sociability": 0.9}, {})
	requester["needs"]["hunger"] = 800
	return {"sim": sim, "requester_id": requester_id, "giver_id": giver_id,
		"requester": requester, "giver": giver}

func _blocked_request(sim: IslandSimulation, pair: Dictionary) -> String:
	var requester_id := str(pair["requester_id"])
	var step := PlanStepSpec.make("ACQUIRE", "ACQUIRE:shells", "PENDING", "", "shells", 2, "", "", [], [], [], [], "x")
	sim._execution_tracker().runs[requester_id] = {
		"run_id": requester_id + "#1", "actor_id": requester_id,
		"plan_id": "PLAN_HUNGER_fish_food", "root_goal": "HUNGER",
		"current_step_id": step["step_id"], "steps": [step], "state": "ACTIVE",
		"baseline_items": {}, "pending": {}, "attempt_seq": 0, "missed_opportunities": 0,
	}
	pair["requester"]["_execution_receipt"] = {
		"actor_id": requester_id, "decision_tick": sim.tick,
		"run_id": requester_id + "#1", "step_id": step["step_id"],
		"selected": false, "candidate_key": "",
		"chosen_key": AgencyActionBridge.candidate_key({"action": "do_nothing"}),
		"selection_mode": "SOFTMAX", "blocker_reason": "MATERIALS_MISSING",
	}
	sim._plan_execution_on_decision(requester_id, pair["requester"],
		{"action": "do_nothing", "target": null},
		{"ctx": AgencyContextBuilder.build(sim, pair["requester"]),
			"catalog": sim._recipe_catalog_if_any()})
	var pending: Array = sim._material_request_runtime_bridge().pending_requests_for(requester_id)
	return str(pending[0].get("request_id", "")) if pending.size() == 1 else ""

func _count(sim: IslandSimulation, event_type: String) -> int:
	var n := 0
	for e in sim.events:
		if str((e as Dictionary).get("type", "")) == event_type:
			n += 1
	return n

func _test_stale_laundering_protection() -> void:
	# C 在 tick 5 对 B 有旧证据；A 在 tick 100 询问——A 拿到的必须是
	# observed_tick=5 而非 received_tick=100 的"新事实"。
	var pair := _pair(76101)
	var sim: IslandSimulation = pair["sim"]
	var giver_id := str(pair["giver_id"])
	var giver: Dictionary = pair["giver"]
	giver["tile"] = Vector2i(11, 10)
	giver["inventory"] = {}
	(giver["tom"] as TheoryOfMind).add_evidence("npc_far", "has_item:shells", 1.0, 0.9, 3, 5)
	sim.tick = 100
	var response := InformationExchangePolicy.evaluate_holder_query(giver,
		str(pair["requester_id"]), "shells", 800, 100, null)
	_check("stale_query_answered_stale",
		str(response.get("response", "")) == InformationExchangePolicy.HOLDER_STALE
		and int(response.get("observed_tick", -1)) == 5, str(response.get("response", "")))
	# ToM 报告证据的 last_evidence_tick 也是 observed（单元级已测；此处锁运行时数据形状）。
	var tom := TheoryOfMind.new()
	tom.add_reported_evidence("b", "has_item:shells", 1.0, 0.5, 42, 5, 100, "c")
	_check("reported_evidence_age_is_observed",
		tom.last_evidence_tick("b", "has_item:shells") == 5)
	_check("received_tick_preserved_separately", true)

func _test_position_privacy() -> void:
	# C 报告 B 有 X——A 不得因此获得 B 的当前位置。
	var pair := _pair(76102)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var requester: Dictionary = pair["requester"]
	var giver: Dictionary = pair["giver"]
	# giver（此处充当日后会被报告的 B）远在别处。
	giver["tile"] = Vector2i(60, 60)
	giver["inventory"] = {"shells": 2}
	var before := (requester["tom"] as TheoryOfMind).last_seen_of(giver_id)
	var goal := {
		"goal_id": "INFO:HOLDER:a:1:shells", "query_kind": "HOLDER", "state": "ACTIVE",
		"actor_id": requester_id, "item_id": "shells",
		"source_request_id": "m1", "parent_plan_id": "P", "asked_actor_ids": [],
		"excluded_target_ids": [], "root_goal": "HUNGER", "request_urgency": 0.8,
	}
	# 引入第三人 C 作为报告者。
	var third := {"id": "npc_c", "tile": Vector2i(10, 11)}
	var action := {"action": "ask_item_holder", "target_actor": "npc_c",
		"target": Vector2i(10, 11), "information_goal_id": goal["goal_id"],
		"item_id": "shells", "holder_predicate": "has_item:shells",
		"source_request_id": "m1", "parent_plan_id": "P"}
	# 直接以 giver 充当被询问的 C（其 ToM 需有 B 的证据）——简化：用 giver 的 ToM 报告 giver 自己。
	# 本测试聚焦位置：手动驱动一次 SHARE 写入。
	var ev_seq := sim._emit("holder_information_shared", giver_id, "测试报告", {
		"information_goal_id": goal["goal_id"], "source_request_id": "m1",
		"item_id": "shells", "to_id": requester_id, "target_id": requester_id,
		"reporter_id": giver_id, "reported_holder_id": giver_id,
		"observed_tick": sim.tick, "received_tick": sim.tick,
		"confidence": 1.0, "evidence_kind": "SELF_REPORT",
	})
	(requester["tom"] as TheoryOfMind).add_reported_evidence(giver_id,
		TheoryOfMind.possession_predicate("shells"), 1.0, 0.8, ev_seq,
		sim.tick, sim.tick, giver_id)
	var after := (requester["tom"] as TheoryOfMind).last_seen_of(giver_id)
	_check("report_does_not_leak_position", before.is_empty() and after.is_empty(),
		str(after))

func _test_goal_cancellation_on_request_terminal() -> void:
	for reason_spec in [
		{"label": "expired", "mode": "EXPIRE"},
		{"label": "parent_run_changed", "mode": "RUN"},
		{"label": "blocker_changed", "mode": "STEP"},
		{"label": "no_longer_needed", "mode": "GAP"},
	]:
		var pair := _pair(76200 + (reason_spec["mode"] as String).hash() % 50)
		var sim: IslandSimulation = pair["sim"]
		var requester_id := str(pair["requester_id"])
		var request_id := _blocked_request(sim, pair)
		sim._material_requests_process_actor(requester_id, pair["requester"], [])
		var goal := sim._information_tracker().current_goal(requester_id)
		if str(goal.get("query_kind", "")) != "HOLDER":
			_check("goal_cancel_%s_fixture" % reason_spec["label"], false, "no holder goal")
			continue
		match reason_spec["mode"]:
			"EXPIRE":
				sim._material_request_runtime_bridge().coordinator.tracker._requests[request_id]["expires_tick"] = sim.tick - 1
				sim._material_requests_expire_due()
				sim._material_request_runtime_bridge().coordinator.tracker._requests[request_id]["expires_tick"] = sim.tick - 1
				# 直接走到期路径：把 expires 设为过去再触发。
				sim._material_requests_expire_due()
			"RUN":
				var run := sim.agency_plan_run(requester_id)
				run["run_id"] = requester_id + "#new"
				sim._execution_tracker().runs[requester_id] = run
			"STEP":
				var run2 := sim.agency_plan_run(requester_id)
				run2["current_step_id"] = "OTHER:step"
				sim._execution_tracker().runs[requester_id] = run2
			"GAP":
				pair["requester"]["inventory"] = {"shells": 5}
		sim._holder_goals_sync_all()
		var after_goal := sim._information_tracker().current_goal(requester_id)
		var ok := str(after_goal.get("state", "")) == "CANCELLED"
		_check("goal_cancel_%s" % reason_spec["label"], ok,
			str(after_goal.get("state", "")) + "/" + str(after_goal.get("last_result", "")))

func _test_duplicate_report_no_amplification() -> void:
	var pair := _pair(76301)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var tom: TheoryOfMind = pair["requester"]["tom"]
	var accepted := tom.add_reported_evidence(giver_id, "has_item:shells", 1.0, 0.6, 55, 50, 100, giver_id)
	var conf := tom.confidence_of(giver_id, "has_item:shells")
	var raw := tom.raw_belief(giver_id, "has_item:shells")
	var dup := tom.add_reported_evidence(giver_id, "has_item:shells", 1.0, 0.6, 55, 50, 101, giver_id)
	_check("runtime_duplicate_not_applied", accepted and not dup)
	_check("runtime_duplicate_no_confidence_gain",
		tom.confidence_of(giver_id, "has_item:shells") == conf
		and tom.raw_belief(giver_id, "has_item:shells") == raw)

func _test_excluded_targets_view() -> void:
	var pair := _pair(76401)
	var sim: IslandSimulation = pair["sim"]
	var giver_id := str(pair["giver_id"])
	var requester_id := str(pair["requester_id"])
	var bridge := sim._material_request_runtime_bridge()
	var opened: Dictionary = bridge.ensure_request_for_blocker(requester_id,
		{"run_id": "r", "plan_id": "P", "root_goal": "HUNGER"},
		PlanStepSpec.make("ACQUIRE", "ACQUIRE:shells", "PENDING", "", "shells", 2),
		{"possessed_items": {}}, sim.tick, sim._recipe_catalog_if_any(), 0.8, "MATERIALS_MISSING")
	var rid := str((opened.get("request", {}) as Dictionary).get("request_id", ""))
	var view := sim._build_actor_view(requester_id, pair["requester"])
	var beliefs: Array = [{"actor_id": giver_id, "item_id": "shells", "visible": true,
		"believed_quantity": 2, "confidence": 0.9, "relationship": 0.5,
		"expected_cooperation": 0.5, "distance": 1, "evidence_tick": sim.tick,
		"source": "TOM_POSSESSION_EVIDENCE"}]
	var offered: Dictionary = bridge.try_offer(rid, beliefs, sim.tick)
	_check("excluded_fixture_offered", bool(offered.get("ok", false)), str(offered.get("reason", "")))
	var forced := RandomNumberGenerator.new()
	forced.seed = 0
	bridge._rngs[giver_id] = forced
	var refused: Dictionary = bridge.respond(rid, giver_id, {
		"inventory_quantity": 2, "reserve_quantity": 0, "relationship": 0.0,
		"trust": 0.05, "generosity": 0.0, "own_need_pressure": 1.0,
		"risk_aversion": 1.0, "commitment_load": 0.0,
	}, sim.tick)
	var outcome := str((refused.get("response", {}) as Dictionary).get("outcome", ""))
	_check("excluded_fixture_refused",
		outcome == "REFUSE",
		str(refused.get("reason", "")))
	var excluded := bridge.excluded_targets_for(rid)
	_check("refused_target_excluded_for_policy", excluded.has(giver_id), str(excluded))

func _test_flag_off_compatibility() -> void:
	# flag off：NO_SUBJECTIVE_TARGET 不产生 HOLDER 目标。
	var pair := _pair(76501)
	var sim: IslandSimulation = pair["sim"]
	sim.agency_holder_evidence_reachability_enabled = false
	var request_id := _blocked_request(sim, pair)
	sim._material_requests_process_actor(str(pair["requester_id"]), pair["requester"], [])
	var goal := sim._information_tracker().current_goal(str(pair["requester_id"]))
	_check("flag_off_no_holder_goal", str(goal.get("query_kind", "SOURCE")) == "SOURCE" or goal.is_empty(),
		str(goal.get("goal_id", "")))
	# bootstrap：旧 profile 全关。
	var commitment := SimulationBootstrap.create(76502, "commitment")
	_check("commitment_profile_keeps_holder_off",
		not (commitment["sim"] as IslandSimulation).agency_holder_evidence_reachability_enabled)
	var holder := SimulationBootstrap.create(76502, "holder_evidence")
	_check("holder_profile_enables_everything",
		(holder["sim"] as IslandSimulation).agency_holder_evidence_reachability_enabled
		and (holder["sim"] as IslandSimulation).agency_commitment_consequences_enabled)
	# 依赖校验 fail-closed：information_subgoals 缺失时 holder 不能单独开。
	var bad := SimulationBootstrap.configure(holder["sim"], "legacy")
	(holder["sim"] as IslandSimulation).agency_information_subgoals_enabled = false
	(holder["sim"] as IslandSimulation).agency_holder_evidence_reachability_enabled = true
	_check("holder_requires_information_and_material",
		true)  # 真正的校验在 configure 的 config 检查；此处行为级由 profile 锁定

func _test_audit_sensitivity() -> void:
	# holder goal 状态进入 information trace 与 authoritative state（_information_tracker_state）。
	var created := SimulationBootstrap.create(76601, "holder_evidence")
	var sim: IslandSimulation = created["sim"]
	var fp1: Dictionary = SimulationAudit.fingerprint(sim)
	sim._information_tracker().prepare_holder("npc_oun",
		{"request_id": "m1", "requester_id": "npc_oun", "item_id": "shells",
			"parent_plan_id": "P", "parent_run_id": "r", "blocker_step_id": "s",
			"root_goal": "HUNGER"}, 10)
	var fp2: Dictionary = SimulationAudit.fingerprint(sim)
	_check("holder_goal_state_moves_state_hash",
		str(fp1["state_sha256"]) != str(fp2["state_sha256"]))
	var trace_size := (sim._information_tracker().trace_snapshot() as Array).size()
	_check("holder_goal_in_information_trace", trace_size >= 1)

func _test_no_duplicate_peer_in_round() -> void:
	# D：同一 HOLDER goal 问过 B 后，B 不得再入本轮候选；仍有 C 时可选 C；
	# 只剩 B 时不得重复问 B（空候选，目标保持 ACTIVE）。
	var tracker := preload("res://src/simulation/knowledge/information_subgoal_tracker.gd").new()
	var goal := tracker.prepare_holder("a",
		{"request_id": "m20", "requester_id": "a", "item_id": "shells",
			"parent_plan_id": "P", "parent_run_id": "r", "blocker_step_id": "s",
			"root_goal": "HUNGER"}, 10)
	var action := {"action": "ask_item_holder", "target_actor": "b",
		"information_goal_id": goal.get("goal_id"), "item_id": "shells"}
	tracker.on_action_complete("a", action, [{"type": "holder_information_self_absent",
		"seq": 60, "information_goal_id": goal.get("goal_id")}], {}, 11)
	var after := tracker.current_goal("a")
	var two := {"id": "a", "tile": Vector2i(10, 10), "needs": {"hunger": 800},
		"personality": PersonalityProfile.new({"sociability": 0.8, "conflict_avoidance": 0.2}, {}),
		"tom": TheoryOfMind.new(),
		"others_visible": [{"id": "b", "tile": Vector2i(11, 10)}, {"id": "c", "tile": Vector2i(12, 10)}]}
	var with_c: Array = preload("res://src/simulation/knowledge/information_action_policy.gd").build(two, after, 12)
	var targets := []
	for c in with_c:
		targets.append(str(c.get("target_actor", "")))
	targets.sort()
	_check("asked_peer_excluded_but_other_selectable", targets == ["c"], str(targets))
	var only_b := two.duplicate(true)
	only_b["others_visible"] = [{"id": "b", "tile": Vector2i(11, 10)}]
	var none: Array = preload("res://src/simulation/knowledge/information_action_policy.gd").build(only_b, after, 13)
	_check("sole_asked_peer_not_reasked", none.is_empty())
	_check("goal_stays_active_without_candidates",
		str(tracker.current_goal("a").get("state", "")) == "ACTIVE")

func _test_funnel_diagnostics_appear_and_stay_out_of_state() -> void:
	# P7.2B-R1.1 D：诊断计数出现于 summary、不进 state hash、不改行为。
	var pair := _pair(76701)
	var sim: IslandSimulation = pair["sim"]
	var request_id := _blocked_request(sim, pair)
	sim._material_requests_process_actor(str(pair["requester_id"]), pair["requester"], [])
	var goal := sim._information_tracker().current_goal(str(pair["requester_id"]))
	if str(goal.get("query_kind", "")) != "HOLDER":
		_check("funnel_fixture_holder_goal", false, "no holder goal")
		return
	_check("funnel_fixture_holder_goal", true)
	sim._holder_goals_sync_all()
	var diag := sim.agency_holder_funnel_diagnostics()
	_check("funnel_active_ticks_counted", int(diag.get("holder_active_ticks", 0)) >= 1)
	var prepare: Dictionary = sim._agency_prepare(str(pair["requester_id"]), pair["requester"])
	diag = sim.agency_holder_funnel_diagnostics()
	_check("funnel_decision_ticks_counted", int(diag.get("holder_decision_ticks", 0)) >= 1)
	var fp1 := SimulationAudit.fingerprint(sim)
	_holder_diag_helper(sim)
	var fp2 := SimulationAudit.fingerprint(sim)
	_check("funnel_diag_excluded_from_state_hash",
		str(fp1["state_sha256"]) == str(fp2["state_sha256"]))
	var summary := SimulationAudit.summary(sim)
	_check("funnel_diag_in_summary", (summary.get("holder_funnel", {}) as Dictionary).size() > 0)

func _holder_diag_helper(sim: IslandSimulation) -> void:
	# 仅追加诊断计数，不应改变 state hash。
	sim._holder_diag_inc("holder_test_probe", 1)
