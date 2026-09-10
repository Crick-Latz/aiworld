extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("PASS " + label)
	else:
		failed += 1
		print("FAIL %s %s" % [label, detail])

func _self() -> Dictionary:
	return {"needs": {"hunger": 800, "thirst": 100, "social": 0, "energy": 800},
		"traits": {"caution": 0.5, "pragmatism": 0.5, "curiosity": 0.5}, "commitment_strength": 0.8}

func _plan(pid: String = "PLAN_HUNGER_a", root_goal: String = "HUNGER", cost: float = 1.0) -> Dictionary:
	return {"plan_id": pid, "root_goal": root_goal, "status": "READY", "expected_benefit": 1.0,
		"estimated_cost": cost, "estimated_risk": 0.1, "confidence": 0.7,
		"steps": [PlanStepSpec.make("MAIN", "MAIN:rule:berry_food", "PENDING", "forage_berries")]}

func _rng(seed_value: int = 917) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _run() -> void:
	var self_state := _self()
	var plan := _plan()
	var row := PlanAdoptionPolicy.assess(plan, self_state)
	_check("ready_plan_is_valued", row["eligible"] and float(row["value"]) > 0.0)
	_check("subjective_pressure_is_recorded", is_equal_approx(float(row["problem_pressure"]), 0.8))
	var hungrier := self_state.duplicate(true)
	hungrier["needs"]["hunger"] = 980
	_check("pressure_increases_plan_value", PlanAdoptionPolicy.assess(plan, hungrier)["value"] > row["value"])
	var expensive := plan.duplicate(true)
	expensive["estimated_cost"] = 10.0
	_check("effort_lowers_value", PlanAdoptionPolicy.assess(expensive, self_state)["value"] < row["value"])
	var risky := plan.duplicate(true)
	risky["estimated_risk"] = 2.0
	_check("risk_lowers_value", PlanAdoptionPolicy.assess(risky, self_state)["value"] < row["value"])
	var confident := plan.duplicate(true)
	confident["confidence"] = 0.95
	_check("confidence_increases_value", PlanAdoptionPolicy.assess(confident, self_state)["value"] > row["value"])
	var cautious := self_state.duplicate(true)
	cautious["traits"]["caution"] = 1.0
	var bold := self_state.duplicate(true)
	bold["traits"]["caution"] = 0.0
	_check("personality_changes_risk_valuation", PlanAdoptionPolicy.assess(risky, cautious)["value"] < PlanAdoptionPolicy.assess(risky, bold)["value"])
	var resolved := self_state.duplicate(true)
	resolved["needs"]["hunger"] = 50
	_check("resolved_problem_rejected", PlanAdoptionPolicy.assess(plan, resolved)["reason"] == "PROBLEM_RESOLVED")
	var unknown := _plan("unknown", "MAGIC")
	_check("unknown_problem_fails_closed", not PlanAdoptionPolicy.assess(unknown, self_state)["eligible"])
	var blocked := plan.duplicate(true)
	blocked["status"] = "BLOCKED_PLAN"
	_check("blocked_plan_rejected", not PlanAdoptionPolicy.assess(blocked, self_state)["eligible"])
	var malformed := plan.duplicate(true)
	malformed.erase("confidence")
	_check("missing_estimate_rejected", PlanAdoptionPolicy.assess(malformed, self_state)["reason"] == "INVALID_ESTIMATES")
	malformed["confidence"] = NAN
	_check("nan_estimate_rejected", not PlanAdoptionPolicy.assess(malformed, self_state)["eligible"])
	malformed["confidence"] = 0.0
	_check("zero_confidence_rejected", not PlanAdoptionPolicy.assess(malformed, self_state)["eligible"])
	malformed = plan.duplicate(true)
	malformed["steps"] = []
	_check("empty_plan_rejected", not PlanAdoptionPolicy.assess(malformed, self_state)["eligible"])
	malformed["steps"] = [{"kind": "MAIN"}]
	_check("malformed_steps_rejected", not PlanAdoptionPolicy.assess(malformed, self_state)["eligible"])
	var before := AgencyMeasure.canon([plan, self_state])
	PlanAdoptionPolicy.deliberate(self_state, [plan], {}, _rng())
	_check("deliberation_is_read_only", before == AgencyMeasure.canon([plan, self_state]))
	var second := _plan("PLAN_HUNGER_b")
	var forward := PlanAdoptionPolicy.deliberate(self_state, [plan, second], {}, _rng())
	var reverse := PlanAdoptionPolicy.deliberate(self_state, [second, plan], {}, _rng())
	_check("proposal_order_independent", AgencyMeasure.canon(forward) == AgencyMeasure.canon(reverse))
	_check("same_seed_replays_choice", AgencyMeasure.canon(forward) == AgencyMeasure.canon(PlanAdoptionPolicy.deliberate(self_state, [plan, second], {}, _rng())))
	var duplicate := PlanAdoptionPolicy.deliberate(self_state, [plan, plan], {}, _rng())
	_check("duplicate_identity_fails_closed", duplicate["selected_plan_id"] == "" and duplicate["candidates"][0]["reason"] == "DUPLICATE_PLAN_ID")
	var no_rng := _rng()
	var before_rng := no_rng.state
	var empty := PlanAdoptionPolicy.deliberate(self_state, [], {}, no_rng)
	_check("empty_candidates_defer_without_rng", empty["decision"] == "DEFER" and before_rng == no_rng.state)
	var run := {"state": "ACTIVE", "plan_id": plan["plan_id"], "steps": plan["steps"], "current_step_id": plan["steps"][0]["step_id"]}
	var kept := PlanAdoptionPolicy.deliberate(self_state, [plan, second], run, no_rng)
	_check("commitment_retained_under_tie", kept["decision"] == "RETAIN" and kept["selected_plan_id"] == plan["plan_id"])
	_check("retention_does_not_consume_rng", no_rng.state == before_rng)
	run["state"] = "SUSPENDED"
	_check("suspended_commitment_retained", PlanAdoptionPolicy.deliberate(self_state, [plan], run, _rng())["decision"] == "RETAIN")
	_check("resolved_goal_releases_commitment", PlanAdoptionPolicy.deliberate(resolved, [plan], run, _rng())["selected_plan_id"] == "")
	var long_plan := _plan("long", "HUNGER", 8.0)
	long_plan["steps"] = [PlanStepSpec.make("ACQUIRE", "ACQUIRE:item:wood", "PENDING", "", "wood", 1), plan["steps"][0]]
	var progressed := {"state": "ACTIVE", "plan_id": "long", "steps": long_plan["steps"], "current_step_id": plan["steps"][0]["step_id"]}
	_check("remaining_cost_tracks_progress", is_equal_approx(PlanAdoptionPolicy.assess(long_plan, self_state, progressed)["remaining_cost"], 4.0))
	var choices := {}
	for seed_value in 128:
		var choice := PlanAdoptionPolicy.deliberate(self_state, [plan, second], {}, _rng(seed_value))
		choices[choice["selected_plan_id"]] = true
	_check("bounded_randomness_keeps_both_plans_possible", choices.has(plan["plan_id"]) and choices.has(second["plan_id"]))
	var probability_sum: float = forward.get("defer_probability", 0.0)
	for candidate in forward["candidates"]:
		probability_sum += float(candidate["probability"])
	_check("choice_probabilities_normalized", is_equal_approx(probability_sum, 1.0))
	# Tracker accepts a selected ID, never falls back to lexicographic order.
	var tracker := PlanExecutionTracker.new()
	var admission := {"mode": "SUBJECTIVE", "decision": "ADOPT", "selected_plan_id": second["plan_id"]}
	var prep := tracker.prepare_decision("u", [plan, second], {}, 1, admission)
	_check("tracker_adopts_explicit_plan", prep.get("plan_id", "") == second["plan_id"])
	_check("adoption_alone_does_not_complete_step", tracker.traces.size() == 1 and tracker.traces[0]["event"] == "RUN_STARTED")
	var rid: String = prep["run_id"]
	prep = tracker.prepare_decision("u", [plan, second], {}, 2, admission)
	_check("retention_keeps_run_identity", prep["run_id"] == rid)
	var defer := {"mode": "SUBJECTIVE", "decision": "DEFER", "selected_plan_id": ""}
	prep = tracker.prepare_decision("u", [plan, second], {}, 3, defer)
	_check("defer_releases_run_without_fallback", prep.is_empty() and tracker.runs["u"]["state"] == "CANCELLED")
	_check("reconsidered_plan_obeys_cooldown", tracker.adoption_candidates("u", [plan, second], 4).size() == 1)
	var other_tracker := PlanExecutionTracker.new()
	_check("missing_adopted_id_fails_closed", other_tracker.prepare_decision("u", [plan], {}, 1,
		{"mode": "SUBJECTIVE", "selected_plan_id": "absent"}).is_empty())
	var legacy := PlanExecutionTracker.new()
	_check("legacy_default_path_retained", legacy.prepare_decision("u", [second, plan], {}, 1)["plan_id"] == plan["plan_id"])
	# Better alternatives open review; they still face stochastic admission.
	var thirst := _plan("PLAN_THIRST_water", "THIRST", 0.0)
	var urgent := _self()
	urgent["needs"]["thirst"] = 1000
	var expensive_run := {"state": "ACTIVE", "plan_id": expensive["plan_id"], "steps": expensive["steps"], "current_step_id": expensive["steps"][0]["step_id"]}
	var reconsidered := PlanAdoptionPolicy.deliberate(urgent, [expensive, thirst], expensive_run, _rng())
	_check("opportunity_cost_triggers_review", reconsidered["rng_consumed"])
	_check("review_keeps_auditable_candidate_values", reconsidered["candidates"].size() == 2 and reconsidered.has("switch_margin"))
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
