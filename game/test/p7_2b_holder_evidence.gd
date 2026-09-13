extends SceneTree
## P7.2B 单元测试：FIND_HOLDER 目标生命周期（并发纪律/多轮/完成与取消）、
## ToM 报告证据（observed/received 双时间、防重复放大）、应答策略类别、可信度单调性。

const TrackerClass = preload("res://src/simulation/knowledge/information_subgoal_tracker.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_tom_reported_evidence()
	_test_subjects_with_evidence()
	_test_exchange_policy_categories()
	_test_holder_goal_concurrency()
	_test_holder_goal_lifecycle()
	_test_report_weight_monotonicity()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])

func _request(request_id: String, item_id: String = "shells") -> Dictionary:
	return {"request_id": request_id, "requester_id": "a", "target_id": "",
		"item_id": item_id, "requested_quantity": 2, "root_goal": "HUNGER",
		"parent_plan_id": "PLAN_HUNGER_fish_food", "parent_run_id": "a#1",
		"blocker_step_id": "CRAFT:s", "urgency": 0.8}

func _test_tom_reported_evidence() -> void:
	var tom := TheoryOfMind.new()
	var first := tom.add_reported_evidence("b", "has_item:shells", 1.0, 0.5, 10, 5, 100, "c")
	_check("reported_evidence_accepted", first)
	_check("last_evidence_tick_returns_observed",
		tom.last_evidence_tick("b", "has_item:shells") == 5,
		str(tom.last_evidence_tick("b", "has_item:shells")))
	var belief_after_first := tom.confidence_of("b", "has_item:shells")
	var dup := tom.add_reported_evidence("b", "has_item:shells", 1.0, 0.5, 10, 5, 101, "c")
	_check("duplicate_report_rejected", not dup)
	_check("duplicate_does_not_inflate_confidence",
		tom.confidence_of("b", "has_item:shells") == belief_after_first)
	var neg := tom.add_reported_evidence("b", "has_item:shells", -1.0, 0.4, 11, 110, 110, "d")
	_check("negative_claim_recorded", neg
		and tom.belief_about("b", "has_item:shells") < tom.raw_belief("b", "has_item:shells"))
	_check("possession_predicate_unified",
		TheoryOfMind.possession_predicate("wood") == "has_item:wood"
		and TheoryOfMind.possession_predicate("wood")
			== MaterialRequestRuntimeBridge.holder_predicate("wood"))

func _test_subjects_with_evidence() -> void:
	var tom := TheoryOfMind.new()
	tom.add_evidence("b", "has_item:shells", 1.0, 0.5, 1, 10)
	tom.add_evidence("c", "has_item:shells", 1.0, 0.9, 2, 20)
	tom.add_evidence("d", "reliable", 1.0, 0.5, 3, 30)  # 无关键
	var rows := tom.subjects_with_evidence("has_item:shells")
	_check("subjects_only_with_predicate", rows.size() == 2)
	if rows.size() == 2:
		_check("subjects_ranked_by_strength", str(rows[0]["actor_id"]) == "c",
			str(rows[0]["actor_id"]))
		_check("subjects_carries_evidence_tick", int(rows[1]["last_evidence_tick"]) == 10)

func _test_exchange_policy_categories() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var generous: Dictionary = {"id": "b", "inventory": {"shells": 2},
		"personality": PersonalityProfile.new(
			{"altruism": 1.0, "empathy": 1.0, "sociability": 1.0, "conflict_avoidance": 0.0}, {}),
		"needs": {}}
	var share := InformationExchangePolicy.evaluate_holder_query(generous, "a", "shells", 800, 50, rng)
	_check("self_holder_shares", str(share.get("response", "")) == InformationExchangePolicy.HOLDER_SHARE
		and str(share.get("reported_holder_id", "")) == "b"
		and str(share.get("evidence_kind", "")) == "SELF_REPORT"
		and int(share.get("observed_tick", -1)) == 50, str(share.get("response", "")))
	var empty: Dictionary = {"id": "b", "inventory": {}, "personality": generous["personality"], "needs": {}}
	var absent := InformationExchangePolicy.evaluate_holder_query(empty, "a", "shells", 800, 50, rng)
	_check("self_absent_reported", str(absent.get("response", "")) == InformationExchangePolicy.HOLDER_SELF_ABSENT)
	# 第三方：B 无自持，但 B 的 ToM 有 C 的新鲜持有证据。
	var tom := TheoryOfMind.new()
	tom.add_evidence("c", "has_item:shells", 1.0, 0.8, 3, 40)
	var informant: Dictionary = {"id": "b", "inventory": {}, "tom": tom,
		"personality": generous["personality"], "needs": {}}
	var third := InformationExchangePolicy.evaluate_holder_query(informant, "a", "shells", 800, 60, rng)
	_check("third_party_reported", str(third.get("response", "")) == InformationExchangePolicy.HOLDER_SHARE
		and str(third.get("reported_holder_id", "")) == "c"
		and str(third.get("evidence_kind", "")) == "TOM_REPORT"
		and int(third.get("observed_tick", -1)) == 40, str(third))
	# 陈旧：证据 tick 太旧 → STALE。
	var old_tom := TheoryOfMind.new()
	old_tom.add_evidence("c", "has_item:shells", 1.0, 0.8, 3, 1)
	var stale_informant: Dictionary = {"id": "b", "inventory": {}, "tom": old_tom,
		"personality": generous["personality"], "needs": {}}
	var stale := InformationExchangePolicy.evaluate_holder_query(stale_informant, "a", "shells", 800, 200, rng)
	_check("stale_third_party_reported", str(stale.get("response", "")) == InformationExchangePolicy.HOLDER_STALE,
		str(stale.get("response", "")))
	# 拒绝：有货但人格吝啬 + roll 高。
	var stingy_rng := RandomNumberGenerator.new()
	stingy_rng.seed = 3
	var stingy: Dictionary = {"id": "b", "inventory": {"shells": 2},
		"personality": PersonalityProfile.new(
			{"altruism": 0.0, "empathy": 0.0, "sociability": 0.0, "conflict_avoidance": 1.0}, {}),
		"needs": {}}
	var refused_any := false
	for i in 8:
		var refused := InformationExchangePolicy.evaluate_holder_query(stingy, "a", "shells", -1000, 50, stingy_rng)
		if str(refused.get("response", "")) == InformationExchangePolicy.HOLDER_REFUSE:
			refused_any = true
			break
	_check("holder_refuse_reachable", refused_any, "never refused in 8 rolls")

func _test_holder_goal_concurrency() -> void:
	var tracker := TrackerClass.new()
	# A：同 request 复用。
	var g1 := tracker.prepare_holder("a", _request("m1"), 10)
	var g2 := tracker.prepare_holder("a", _request("m1"), 20)
	_check("same_request_reuses_goal", str(g1.get("goal_id", "")) == str(g2.get("goal_id", "")))
	# B：同 plan+item 的 SOURCE goal 让位。
	var st := TrackerClass.new()
	var source_goal := {
		"goal_id": "INFO:a:1:p:shells", "query_kind": "SOURCE", "state": "ACTIVE",
		"actor_id": "a", "parent_plan_id": "PLAN_HUNGER_fish_food", "item_id": "shells",
	}
	st.goals["a"] = source_goal
	var switched := st.prepare_holder("a", _request("m2"), 10)
	_check("source_goal_superseded_by_holder",
		str(switched.get("query_kind", "")) == "HOLDER"
		and str(source_goal.get("state", "")) == "CANCELLED"
		and str(source_goal.get("last_result", "")) == "MATERIAL_REQUEST_NEEDS_HOLDER",
		str(source_goal.get("state", "")))
	# C：无关 ACTIVE 目标不被覆盖。
	var other := TrackerClass.new()
	other.goals["a"] = {"goal_id": "INFO:a:9:other:wood", "query_kind": "SOURCE", "state": "ACTIVE",
		"actor_id": "a", "parent_plan_id": "PLAN_OTHER", "item_id": "wood"}
	var blocked := other.prepare_holder("a", _request("m3"), 10)
	_check("unrelated_goal_not_overridden", blocked.is_empty())
	# 多轮：resolve 后同 request 新建必须用新 goal_id。
	var rounds := TrackerClass.new()
	var r1 := rounds.prepare_holder("a", _request("m4"), 10)
	rounds.resolve_holder_goal("a", "m4", 20)
	var r2 := rounds.prepare_holder("a", _request("m4"), 30)
	_check("second_round_new_goal_id",
		str(r1.get("goal_id", "")) != str(r2.get("goal_id", "")))
	_check("one_active_goal_at_a_time",
		str(rounds.current_goal("a").get("state", "")) == "ACTIVE")

func _test_holder_goal_lifecycle() -> void:
	var tracker := TrackerClass.new()
	tracker.prepare_holder("a", _request("m5"), 10)
	# 唯一完成条件：同 request 的 OFFERED。
	var wrong := tracker.resolve_holder_goal("a", "mX", 20)
	_check("resolution_requires_same_request", wrong.is_empty())
	var right := tracker.resolve_holder_goal("a", "m5", 21)
	_check("resolution_on_matching_request",
		str(right.get("state", "")) == "RESOLVED"
		and str(right.get("last_result", "")) == "ACTIONABLE_HOLDER_ACQUIRED")
	# 取消语义。
	var tracker2 := TrackerClass.new()
	tracker2.prepare_holder("a", _request("m6"), 10)
	var cancelled := tracker2.cancel_holder_goal("a", "SOURCE_REQUEST_TERMINAL", 30)
	_check("cancellation_follows_request_terminal",
		str(cancelled.get("state", "")) == "CANCELLED"
		and str(cancelled.get("last_result", "")) == "SOURCE_REQUEST_TERMINAL")
	# 有效性判定：mismatch / gap。
	var tracker3 := TrackerClass.new()
	tracker3.prepare_holder("a", _request("m7"), 10)
	_check("still_valid_when_healthy",
		tracker3.holder_goal_still_valid("a", "", 2) == "")
	_check("invalid_on_run_mismatch",
		tracker3.holder_goal_still_valid("a", "PARENT_RUN_CHANGED", 2) == "PARENT_RUN_CHANGED")
	_check("invalid_on_gap_closed",
		tracker3.holder_goal_still_valid("a", "", 0) == "GAP_CLOSED")

func _test_report_weight_monotonicity() -> void:
	# 权重公式 = report_confidence × (trust_prob*0.5 + reliable_norm*0.5)，
	# 由 sim._holder_report_weight 实现——此处用两个 sim 对照（关系高 vs 低）。
	var base := SimulationBootstrap.create(76001, "holder_evidence")
	var sim: IslandSimulation = base["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var a_id := str(ids[0])
	var b_id := str(ids[1])
	sim.relationships.adjust(a_id, b_id, "benevolence", -800)
	sim.relationships.adjust(a_id, b_id, "reliability", -800)
	var low := sim._holder_report_weight(a_id, b_id, 0.8)
	var base2 := SimulationBootstrap.create(76002, "holder_evidence")
	var sim2: IslandSimulation = base2["sim"]
	var ids2: Array = sim2.actors.keys()
	ids2.sort()
	var a2 := str(ids2[0])
	var b2 := str(ids2[1])
	sim2.relationships.adjust(a2, b2, "benevolence", 900)
	sim2.relationships.adjust(a2, b2, "reliability", 900)
	var high := sim2._holder_report_weight(a2, b2, 0.8)
	_check("report_weight_monotone_in_credibility", high > low,
		"low=%.3f high=%.3f" % [low, high])
	_check("report_weight_bounded", low >= 0.0 and high <= 1.0)
