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

func _info(root_goal: String = "HUNGER", cost: float = 4.0, risk: float = 0.0,
		confidence: float = 0.7, benefit: float = 1.0) -> Dictionary:
	return {
		"run_id": "u#1", "plan_id": "PLAN_HUNGER_fish_food", "root_goal": root_goal,
		"step": {"step_id": "ACQUIRE:item:wood", "kind": "ACQUIRE", "item_id": "wood"},
		"valuation_context": {
			"expected_benefit": benefit, "estimated_cost": cost, "estimated_risk": risk,
			"confidence": confidence, "step_index": 0, "step_count": 4,
		},
	}

func _assess(hunger: float, info: Dictionary = {}) -> Dictionary:
	var exec := info if not info.is_empty() else _info()
	return PlanStepValueModel.assess(
		{"needs": {"hunger": hunger, "thirst": 0, "social": 0}}, exec,
		{"action": "gather_wood", "target": Vector2i(2, 2), "utility": 0.2})

func _run() -> void:
	var base := _assess(800.0)
	_check("pressure_reads_subjective_need", is_equal_approx(float(base["problem_pressure"]), 0.8), str(base))
	_check("causal_value_positive_for_live_problem", float(base["causal_value"]) > 0.0, str(base))
	_check("effective_utility_only_supplements", float(base["effective_utility"]) > float(base["original_utility"]), str(base))
	_check("bounded_when_registry_bounded", float(base["effective_utility"]) <= 1.0, str(base))

	var low_pressure := _assess(450.0)
	_check("higher_problem_pressure_means_higher_value", float(base["causal_value"]) > float(low_pressure["causal_value"]),
		"high=%s low=%s" % [str(base), str(low_pressure)])

	var low_conf := _assess(800.0, _info("HUNGER", 4.0, 0.0, 0.3))
	_check("confidence_modulates_value", float(base["causal_value"]) > float(low_conf["causal_value"]),
		"base=%s low_conf=%s" % [str(base), str(low_conf)])

	var high_cost := _assess(800.0, _info("HUNGER", 12.0, 0.0, 0.7))
	_check("cost_modulates_value", float(base["causal_value"]) > float(high_cost["causal_value"]),
		"base=%s high_cost=%s" % [str(base), str(high_cost)])

	var risky := _assess(800.0, _info("HUNGER", 4.0, 0.8, 0.7))
	_check("risk_modulates_value", float(base["causal_value"]) > float(risky["causal_value"]),
		"base=%s risky=%s" % [str(base), str(risky)])

	var unknown := _assess(800.0, _info("ESCAPE_DESIRE", 4.0, 0.0, 0.7))
	_check("unsupported_problem_fails_closed", is_zero_approx(float(unknown["causal_value"]))
		and is_equal_approx(float(unknown["effective_utility"]), float(unknown["original_utility"])), str(unknown))

	var missing_meta := PlanStepValueModel.assess(
		{"needs": {"hunger": 900}}, {"root_goal": "HUNGER"},
		{"action": "gather_wood", "utility": 0.35})
	_check("missing_plan_estimates_fail_closed", is_zero_approx(float(missing_meta["causal_value"]))
		and is_equal_approx(float(missing_meta["effective_utility"]), 0.35), str(missing_meta))

	var over_one := PlanStepValueModel.assess(
		{"needs": {"hunger": 900}}, _info(), {"action": "x", "utility": 1.2})
	_check("registry_over_one_preserved", is_equal_approx(float(over_one["effective_utility"]), 1.2), str(over_one))
	var veto := PlanStepValueModel.assess(
		{"needs": {"hunger": 900}}, _info(), {"action": "x", "utility": -0.2})
	_check("negative_registry_veto_preserved", is_equal_approx(float(veto["effective_utility"]), -0.2), str(veto))
	_check("assessment_deterministic", JSON.stringify(base) == JSON.stringify(_assess(800.0)))

	# MAIN 是根问题的直接动作，原 Registry 已按 hunger/thirst 等计分，因此不二次传播。
	var main_info := _info()
	main_info["step"] = {"step_id": "MAIN:rule:fish_food", "kind": "MAIN", "action_name": "fish"}
	var main_value := PlanStepValueModel.assess(
		{"needs": {"hunger": 900}}, main_info, {"action": "fish", "utility": 0.72})
	_check("main_action_not_double_counted", is_zero_approx(float(main_value["causal_value"]))
		and is_equal_approx(float(main_value["effective_utility"]), 0.72), str(main_value))

	# DecisionEngine integration：真实 ACQUIRE wood 候选在开关 ON 时获得可审计的 effective utility；
	# OFF 时 trace 明确回到 REGISTRY_ONLY，且不产生 valuation 行。
	var p := PersonalityProfile.new({}, {})
	var actor := {
		"id": "u", "personality": p, "tile": Vector2i(3, 3),
		"needs": {"energy": 800, "hunger": 800, "thirst": 0, "social": 0},
		"physical": {}, "inventory": {},
		"known_resources": {"trees": [Vector2i(3, 3)]},
	}
	var exec := _info("HUNGER", 4.0, 0.0, 0.7)
	var ctx := {
		"possessed_items": {}, "possessed_capabilities": [], "known_source_tags": ["WOOD"],
		"known_sources": [{"tag": "WOOD", "source_id": "tree|3,3", "belief_ref": "k_tree"}],
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 91041
	DecisionEngine.decide(actor, {"tick": 12}, rng, {
		"mode": "LIVE_BRIDGE", "decision_tick": 12, "ctx": ctx, "proposals": [],
		"execution_step": exec, "causal_step_value_enabled": true,
		"items": ItemCatalog.load_default(),
	})
	var on_trace: Dictionary = actor.get("last_decision_trace", {}).get("agency_execution", {})
	var rows: Array = on_trace.get("candidate_values", [])
	_check("decision_trace_marks_causal_mode", str(on_trace.get("utility_mode", "")) == "CAUSAL_STEP_VALUE", str(on_trace))
	_check("decision_trace_explains_uplift", rows.size() == 1
		and float((rows[0] as Dictionary).get("effective_utility", 0.0)) > float((rows[0] as Dictionary).get("original_utility", 0.0)), str(rows))

	var actor_off := actor.duplicate(true)
	actor_off.erase("last_decision_trace")
	rng.seed = 91041
	DecisionEngine.decide(actor_off, {"tick": 12}, rng, {
		"mode": "LIVE_BRIDGE", "decision_tick": 12, "ctx": ctx, "proposals": [],
		"execution_step": exec, "causal_step_value_enabled": false,
		"items": ItemCatalog.load_default(),
	})
	var off_trace: Dictionary = actor_off.get("last_decision_trace", {}).get("agency_execution", {})
	_check("off_path_marks_registry_only", str(off_trace.get("utility_mode", "")) == "REGISTRY_ONLY", str(off_trace))
	_check("off_path_has_no_valuation_rows", (off_trace.get("candidate_values", []) as Array).is_empty(), str(off_trace))

	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
