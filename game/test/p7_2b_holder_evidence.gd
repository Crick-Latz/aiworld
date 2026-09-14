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
	_test_holder_survives_ordinary_prepare()
	_test_ask_completion_bookkeeping()
	_test_new_round_resets_asked()
	_test_polarity_freshness()
	_test_holder_unknown_reserved()
	_test_holder_attempt_limit_semantics()
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

# ── P7.2B-R1 回归：生命周期存活 / 询问记账 / 新一轮重置 / 极性新鲜度 ──

func _test_holder_survives_ordinary_prepare() -> void:
	# A：普通 SOURCE prepare（含 blocker 已消失的提案集）不得取消 HOLDER goal。
	var tracker := TrackerClass.new()
	var goal := tracker.prepare_holder("a", _request("m10"), 10)
	var after := tracker.prepare("a", [], {}, {"needs": {"hunger": 800}}, 11, null)
	_check("holder_survives_ordinary_prepare",
		str(after.get("state", "")) == "ACTIVE"
		and str(after.get("goal_id", "")) == str(goal.get("goal_id", "")))
	_check("holder_source_request_unchanged",
		str(after.get("source_request_id", "")) == "m10")
	var again := tracker.prepare("a", [{"plan_id": "OTHER", "root_goal": "HUNGER",
		"blockers": [], "steps": [], "expected_benefit": 1.0, "estimated_cost": 1.0,
		"estimated_risk": 0.1, "confidence": 0.7}], {}, {"needs": {"hunger": 800}}, 12, null)
	_check("ordinary_prepare_not_cancel_condition",
		str(again.get("goal_id", "")) == str(goal.get("goal_id", ""))
		and str(again.get("state", "")) == "ACTIVE")

func _test_ask_completion_bookkeeping() -> void:
	# C：ask_item_holder 完成后 attempts/asks/asked_actor_ids/结果分类/evidence_refs 落账。
	var tracker := TrackerClass.new()
	var goal := tracker.prepare_holder("a", _request("m11"), 10)
	var action := {"action": "ask_item_holder", "target_actor": "b",
		"information_goal_id": goal.get("goal_id"), "item_id": "shells"}
	var segment := [{"type": "holder_information_requested", "seq": 40,
		"information_goal_id": goal.get("goal_id")},
		{"type": "holder_information_shared", "seq": 41,
		"information_goal_id": goal.get("goal_id"), "reported_holder_id": "b"}]
	var done: Dictionary = tracker.on_action_complete("a", action, segment, {}, 11)
	_check("ask_bookkeeping_counts",
		int(done.get("attempts", 0)) == 1 and int(done.get("asks", 0)) == 1
		and (done.get("asked_actor_ids", []) as Array).has("b"), str(done.get("asks", -1)))
	_check("ask_bookkeeping_result_shared",
		str(done.get("last_result", "")) == "HOLDER_REPORT_SHARED")
	_check("ask_bookkeeping_evidence_refs",
		(done.get("evidence_refs", []) as Array).has("event:41"))
	var refused_segment := [{"type": "holder_information_refused", "seq": 42,
		"information_goal_id": goal.get("goal_id")}]
	var done2: Dictionary = tracker.on_action_complete("a", action, refused_segment, {}, 12)
	_check("ask_bookkeeping_refusal_counted",
		int(done2.get("refusals", 0)) == 1
		and str(done2.get("last_result", "")) == "HOLDER_REPORT_REFUSED")
	var stale_segment := [{"type": "holder_information_stale", "seq": 43,
		"information_goal_id": goal.get("goal_id")}]
	var done3: Dictionary = tracker.on_action_complete("a", action, stale_segment, {}, 13)
	_check("ask_bookkeeping_stale_counted",
		int(done3.get("stale_reports", 0)) == 1
		and str(done3.get("last_result", "")) == "HOLDER_REPORT_STALE")

func _test_new_round_resets_asked() -> void:
	# E：终态后新一轮新 goal_id，asked_actor_ids 重新开始。
	var tracker := TrackerClass.new()
	var r1 := tracker.prepare_holder("a", _request("m12"), 10)
	var action := {"action": "ask_item_holder", "target_actor": "b",
		"information_goal_id": r1.get("goal_id"), "item_id": "shells"}
	tracker.on_action_complete("a", action, [{"type": "holder_information_shared",
		"seq": 50, "information_goal_id": r1.get("goal_id")}], {}, 11)
	tracker.resolve_holder_goal("a", "m12", 12)
	var r2 := tracker.prepare_holder("a", _request("m12"), 20)
	_check("new_round_new_goal_and_fresh_asked",
		str(r2.get("goal_id", "")) != str(r1.get("goal_id", ""))
		and (r2.get("asked_actor_ids", []) as Array).is_empty())

func _test_polarity_freshness() -> void:
	# F：旧正证(t5) + 新负证(t100)——正判断新鲜度必须读正证 tick。
	var tom := TheoryOfMind.new()
	tom.add_evidence("c", "has_item:shells", 1.0, 0.9, 1, 5)
	tom.add_evidence("c", "has_item:shells", -1.0, 0.2, 2, 100)
	_check("positive_freshness_reads_positive_tick",
		tom.latest_supporting_tick("c", "has_item:shells", 1.0) == 5)
	_check("negative_freshness_reads_negative_tick",
		tom.latest_supporting_tick("c", "has_item:shells", -1.0) == 100)
	_check("mixed_last_evidence_tick_semantics_unchanged",
		tom.last_evidence_tick("c", "has_item:shells") == 100)
	# 评估层：净 belief 仍为正（负证弱）→ 旧正证不可被洗白为新鲜。
	var responder: Dictionary = {"id": "b", "inventory": {}, "tom": tom,
		"personality": PersonalityProfile.new(
			{"altruism": 1.0, "empathy": 1.0, "sociability": 1.0, "conflict_avoidance": 0.0}, {}),
		"needs": {}}
	var answer := InformationExchangePolicy.evaluate_holder_query(responder, "a", "shells", 0, 110, null)
	_check("fresh_negative_cannot_launder_stale_positive",
		str(answer.get("response", "")) == InformationExchangePolicy.HOLDER_STALE
		and int(answer.get("observed_tick", -1)) == 5, str(answer.get("response", "")))
	# 对称：旧负证(t5) + 新正证(t100)、净 belief 为负 → 不进入正报路径（无 HOLDER_SHARE）。
	var tom2 := TheoryOfMind.new()
	tom2.add_evidence("c", "has_item:shells", -1.0, 0.9, 1, 5)
	tom2.add_evidence("c", "has_item:shells", 1.0, 0.2, 2, 100)
	_check("symmetric_negative_dominant_not_reported_positive",
		tom2.belief_about("c", "has_item:shells") <= 0.0)

func _test_holder_unknown_reserved() -> void:
	# 决策 A：完整库存自知模型下 UNKNOWN 不可达——无自持+无第三方 → SELF_ABSENT。
	var empty: Dictionary = {"id": "b", "inventory": {},
		"personality": PersonalityProfile.new(
			{"altruism": 1.0, "empathy": 1.0, "sociability": 1.0, "conflict_avoidance": 0.0}, {}),
		"needs": {}, "tom": TheoryOfMind.new()}
	var answer := InformationExchangePolicy.evaluate_holder_query(empty, "a", "shells", 0, 50, null)
	_check("unknown_reserved_unreachable_with_full_self_knowledge",
		str(answer.get("response", "")) == InformationExchangePolicy.HOLDER_SELF_ABSENT)

func _test_holder_attempt_limit_semantics() -> void:
	# P7.2B-R1.1 C：HOLDER 不因通用 MAX_ATTEMPTS 进 FAILED——终止权唯一归
	# request/run/step/gap contract；问尽后保持 ACTIVE。SOURCE 语义逐位不变。
	var tracker := TrackerClass.new()
	var goal := tracker.prepare_holder("a", _request("m30"), 10)
	var action := {"action": "ask_item_holder", "information_goal_id": goal.get("goal_id"),
		"item_id": "shells"}
	# 10 次完成（超过 MAX_ATTEMPTS=8），每次问不同的人。
	for i in 10:
		action["target_actor"] = "peer_%d" % i
		var seg := [{"type": "holder_information_self_absent", "seq": 100 + i,
			"information_goal_id": goal.get("goal_id")}]
		tracker.on_action_complete("a", action, seg, {}, 11 + i)
	var after := tracker.current_goal("a")
	_check("holder_beyond_max_attempts_stays_active",
		str(after.get("state", "")) == "ACTIVE"
		and str(after.get("goal_id", "")) == str(goal.get("goal_id", ""))
		and int(after.get("attempts", 0)) == 10, str(after.get("state", "")))
	_check("holder_asked_list_preserved_after_limit",
		(after.get("asked_actor_ids", []) as Array).size() == 10)
	var reused := tracker.prepare_holder("a", _request("m30"), 30)
	_check("prepare_holder_reuses_goal_beyond_limit",
		str(reused.get("goal_id", "")) == str(goal.get("goal_id", ""))
		and (reused.get("asked_actor_ids", []) as Array).size() == 10)
	# SOURCE：8 次 search 完成仍走旧 ATTEMPT_LIMIT + 冷却。
	var source_goal := {
		"goal_id": "INFO:a:99:p:shells", "query_kind": "SOURCE", "state": "ACTIVE",
		"actor_id": "a", "parent_plan_id": "PLAN_HUNGER_fish_food",
		"item_id": "shells", "source_kinds": ["shell"], "attempts": 0,
		"asks": 0, "refusals": 0, "stale_reports": 0, "unknown_responses": 0,
		"search_failures": 0, "tried_tiles": [], "asked_actor_ids": [],
		"evidence_refs": [], "last_result": "", "retry_after_tick": -1,
		"last_attempt_tick": -1, "created_tick": 1, "updated_tick": 1,
		"root_goal": "HUNGER", "score": 1.0, "quantity": 1,
	}
	tracker.goals["a"] = source_goal
	var search_action := {"action": "search_resource_source",
		"information_goal_id": source_goal["goal_id"], "target": Vector2i(3, 4)}
	for i in 8:
		var seg := [{"type": "source_search_failed", "seq": 200 + i,
			"information_goal_id": source_goal["goal_id"]}]
		tracker.on_action_complete("a", search_action, seg, {}, 40 + i)
	var source_after := tracker.current_goal("a")
	_check("source_attempt_limit_unchanged",
		str(source_after.get("state", "")) == "FAILED"
		and str(source_after.get("last_result", "")) == "ATTEMPT_LIMIT"
		and int(source_after.get("retry_after_tick", -1)) >= 47,
		str(source_after.get("state", "")) + "/" + str(source_after.get("last_result", "")))
