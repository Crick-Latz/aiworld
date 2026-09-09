extends "res://test/p6_3b_execution_pilot.gd"
## Fixed post-hoc diagnosis of seeds 61000/61009, NOT a population success estimate.
## Instrumentation lives only in this test subclass; production simulation is untouched.

class ObservedSimulation extends IslandSimulation:
	var boundaries: Array = []
	var timeout_cases: Array = []
	var crafts: Array = []
	var _prepared := {}

	static func phase_for(trace_tick: int, world_tick: int, had_intent: bool,
			prior_key: String, chosen_key: String) -> String:
		if trace_tick == world_tick: return "SOFTMAX"
		if had_intent and prior_key == chosen_key: return "INTENTION_CONTINUE"
		return "UNCLASSIFIED"

	func _agency_prepare(id: String, a: Dictionary) -> Dictionary:
		var before := agency_plan_run(id)
		var cursor := agency_execution_trace().size()
		var result := super._agency_prepare(id, a)
		for tr in agency_execution_trace().slice(cursor):
			if tr.get("event", "") == "RUN_CANCELLED" and tr.get("reason_code", "") == "NO_PROGRESS_TIMEOUT":
				var recent: Array = []
				var counts := {"fresh": 0, "continued": 0, "selected": 0}
				for rec in boundaries:
					if rec.get("run_id", "") != tr["run_id"]: continue
					if rec["phase"] == "SOFTMAX": counts["fresh"] += 1
					if rec["phase"] == "INTENTION_CONTINUE": counts["continued"] += 1
					if rec.get("fresh_step_selected", false): counts["selected"] += 1
					recent.append(rec)
				timeout_cases.append({"transition": tr, "run_before": _run_view(before),
					"boundary_counts": counts, "recent_boundaries": recent.slice(maxi(0, recent.size() - 4))})
		var prep: Dictionary = result.get("execution_step", {})
		var intent: IntentionManager = a.get("intentions")
		var prior := intent.current_intention.duplicate(true) if intent != null and intent.has_intention() else {}
		# Re-read only the same actor-facing inputs used by Registry; no injected knowledge.
		# Side-effect checks compare this subclass against plain IslandSimulation below.
		var available := ActionRegistry.get_available_actions(_build_actor_view(id, a), world)
		available.append(DecisionEngine._do_nothing())
		var matching := {}
		if not prep.is_empty():
			matching = PlanStepActionAdapter.match_candidates(prep["step"], available, result["ctx"], result["catalog"], result["items"])
		var candidates: Array = []
		for c in matching.get("candidates", []):
			candidates.append({"key": AgencyActionBridge.candidate_key(c), "utility": c["utility"], "action": c["action"]})
		_prepared[id] = {"tick": tick, "actor_id": id, "had_intent": not prior.is_empty(),
			"prior_key": AgencyActionBridge.candidate_key(prior) if not prior.is_empty() else "",
			"prior_intention": prior, "step_offered": not prep.is_empty(),
			"inventory_before": a["inventory"].duplicate(true), "needs_before": a["needs"].duplicate(true),
			"run_id": prep.get("run_id", ""), "step": prep.get("step", {}).duplicate(true),
			"step_candidates": candidates, "match_blocker": matching.get("blocker_reason", ""),
			"available_action_names": available.map(func(c): return str(c["action"])),
			"available_keys": available.map(func(c): return AgencyActionBridge.candidate_key(c))}
		return result

	func _plan_execution_on_decision(id: String, a: Dictionary, decision: Dictionary) -> void:
		var rec: Dictionary = _prepared[id]
		var tr: Dictionary = a.get("last_decision_trace", {})
		var chosen_key := AgencyActionBridge.candidate_key(decision)
		rec["phase"] = phase_for(int(tr.get("tick", -1)), int(world.get("tick", 0)), rec["had_intent"], rec["prior_key"], chosen_key)
		rec["chosen"] = decision.duplicate(true)
		rec["chosen_key"] = chosen_key
		rec["chosen_currently_available"] = rec["available_keys"].has(chosen_key)
		rec["chosen_action_name_available"] = rec["available_action_names"].has(str(decision["action"]))
		rec["fresh_step_selected"] = false
		var ex: Dictionary = tr.get("agency_execution", {})
		if rec["phase"] == "SOFTMAX":
			rec["trace_tick"] = tr.get("tick", -1)
			rec["considered_keys"] = tr.get("considered_keys", []).duplicate()
			rec["swapped_keys"] = tr.get("agency_swapped_in_keys", []).duplicate()
			rec["candidate_status"] = tr.get("agency_candidate_status", []).duplicate(true)
			if int(ex.get("decision_tick", -1)) == tick:
				rec["fresh_step_selected"] = bool(ex.get("selected", false))
		# No stale trace is counted as a fresh decision or as a new selection.
		super._plan_execution_on_decision(id, a, decision)
		rec["inflight_after"] = (a.get("_plan_exec_inflight", {}) as Dictionary).duplicate(true)
		boundaries.append(rec)

	func _plan_execution_on_complete(id: String, a: Dictionary, action: Dictionary, segment: Array) -> void:
		var before := agency_plan_run(id)
		var identity: Dictionary = (a.get("_plan_exec_inflight", {}) as Dictionary).duplicate(true)
		super._plan_execution_on_complete(id, a, action, segment)
		for e in segment:
			if e.get("type", "") != "crafted": continue
			var recent: Array = []
			for rec in boundaries:
				if rec["actor_id"] == id: recent.append(rec)
			crafts.append({"event": e.duplicate(true), "actual_action": action.duplicate(true),
				"identity": identity, "run_before": _run_view(before), "run_after": _run_view(agency_plan_run(id)),
				"recent_boundaries_context_only": recent.slice(maxi(0, recent.size() - 4))})

	func _run_view(run: Dictionary) -> Dictionary:
		var out := {}
		for key in ["run_id", "plan_id", "root_goal", "state", "current_step_id", "started_tick", "last_progress_tick", "reason_code", "pending"]:
			out[key] = run.get(key)
		return out.duplicate(true)

func _run() -> void:
	if OS.get_cmdline_user_args().has("--self-test"):
		var ok := _diagnostic_self_test()
		quit(0 if ok else 1)
		return
	_out = "res://docs/validation/data/p6_3b_1_execution_diagnosis.json"
	if FileAccess.file_exists(_out):
		print("DIAG_FAIL output already exists")
		quit(1)
		return
	var ps: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var scene := ps.instantiate()
	root.add_child(scene)
	for i in 20: await physics_frame
	var mq = scene.get_node("World/MapController")
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var spots := [mq.get_poi_tile("post_house"), mq.get_poi_tile("tide_market"), mq.get_poi_tile("old_lighthouse")]
	var configs: Array = []
	for original in scenario["actors"]:
		var cfg: Dictionary = original.duplicate(true)
		cfg["spawn"] = spots[configs.size() % spots.size()]
		configs.append(cfg)
	var prior: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/validation/data/p6_3b_1_natural_pilot.json"))
	var rows: Array = []
	var errors: Array = []
	for seed in [61000, 61009]:
		var normal := _sim(mq, seed, configs, true)
		var observed := ObservedSimulation.new(mq, seed, configs.duplicate(true))
		observed.agency_mode = "LIVE_BRIDGE"
		observed.agency_plan_execution_enabled = true
		var first_instrumentation_diff := -1
		for i in 1000:
			normal.step()
			observed.step()
			if first_instrumentation_diff < 0 and AgencyMeasure.canonical_behavior_digest(normal) != AgencyMeasure.canonical_behavior_digest(observed):
				first_instrumentation_diff = observed.tick
		var final_equal := _fingerprint(normal) == _fingerprint(observed)
		var historical_equal := false
		for row in prior["rows"]:
			if int(row["seed"]) == seed: historical_equal = row["execution"]["fingerprint"] == _fingerprint(observed)
		if first_instrumentation_diff >= 0 or not final_equal or not historical_equal: errors.append("instrumentation/replay mismatch " + str(seed))
		var summary := _diagnostic_summary(observed.boundaries, observed.timeout_cases)
		if summary["unclassified"] > 0: errors.append("unclassified decision " + str(seed))
		var examples: Array = []
		for rec in observed.boundaries:
			if rec["step_offered"] and examples.size() < 6: examples.append(rec)
		rows.append({"seed": seed, "summary": summary, "first_instrumentation_difference": first_instrumentation_diff,
			"final_event_trace_scoped_equal": final_equal, "matches_previous_pilot": historical_equal,
			"timeout_examples": observed.timeout_cases.slice(0, 5), "decision_examples": examples,
			"craft_cases": observed.crafts, "fingerprint": _fingerprint(observed)})
		print("DIAG_SEED " + JSON.stringify({"seed": seed, "summary": summary, "equal": final_equal, "historical_equal": historical_equal}))
		await process_frame
	var fingerprints := _source_fingerprints()
	for path in ["res://test/p6_3b_execution_diagnosis.gd", "res://src/simulation/decision/action_registry.gd"]:
		fingerprints[path] = FileAccess.get_sha256(path)
	var saved := _write_result({"meta": {"base_commit": "acf05e503260dd1ede5a69a201e7e9964fedc3c7",
		"seeds": [61000, 61009], "ticks": 1000, "post_hoc_diagnostic_sample": true, "fingerprints": fingerprints,
		"notes": ["no production code changes", "utility values are raw Registry/actual decision values, not hindsight scores",
			"recent craft boundaries are context only; exact action callback and identity provide attribution",
			"extra Registry reads validated against plain simulation; no RNG or world writes in observer"]}, "rows": rows, "errors": errors})
	print("DIAG_RESULT saved=%s errors=%s" % [str(saved), str(errors)])
	quit(0 if saved and errors.is_empty() else 1)

func _diagnostic_summary(records: Array, timeouts: Array) -> Dictionary:
	var out := {"all_boundaries": records.size(), "fresh_softmax": 0, "intention_continue": 0, "unclassified": 0,
		"offered": 0, "offered_fresh": 0, "offered_continued": 0, "fresh_step_selected": 0,
		"fresh_step_with_swap": 0, "fresh_step_all_present_without_swap": 0,
		"continued_action_unavailable": 0, "continued_action_unavailable_by_name": {},
		"continued_action_type_unavailable": 0, "continued_action_type_unavailable_by_name": {},
		"lost_to": {}, "losing_step_best_utility_sum": 0.0, "winning_utility_sum": 0.0, "utility_pairs": 0,
		"continued_step_match_without_identity": 0, "timeouts": timeouts.size(), "timeouts_no_fresh": 0,
		"timeouts_never_selected": 0}
	for rec in records:
		var fresh: bool = rec["phase"] == "SOFTMAX"
		if fresh: out["fresh_softmax"] += 1
		elif rec["phase"] == "INTENTION_CONTINUE": out["intention_continue"] += 1
		else: out["unclassified"] += 1
		if rec["phase"] == "INTENTION_CONTINUE" and not rec["chosen_currently_available"]:
			out["continued_action_unavailable"] += 1
			_inc(out["continued_action_unavailable_by_name"], str(rec["chosen"]["action"]))
		if rec["phase"] == "INTENTION_CONTINUE" and not rec.get("chosen_action_name_available", true):
			out["continued_action_type_unavailable"] += 1
			_inc(out["continued_action_type_unavailable_by_name"], str(rec["chosen"]["action"]))
		if not rec["step_offered"]: continue
		out["offered"] += 1
		if not fresh:
			out["offered_continued"] += 1
			for c in rec["step_candidates"]:
				if c["key"] == rec["chosen_key"] and rec["inflight_after"].is_empty(): out["continued_step_match_without_identity"] += 1
			continue
		out["offered_fresh"] += 1
		if rec["fresh_step_selected"]: out["fresh_step_selected"] += 1
		var swapped := false
		var all_present: bool = not rec["step_candidates"].is_empty()
		var best := -INF
		for c in rec["step_candidates"]:
			swapped = swapped or rec["swapped_keys"].has(c["key"])
			all_present = all_present and rec["considered_keys"].has(c["key"])
			best = maxf(best, float(c["utility"]))
		if swapped: out["fresh_step_with_swap"] += 1
		elif all_present: out["fresh_step_all_present_without_swap"] += 1
		if not rec["fresh_step_selected"]:
			_inc(out["lost_to"], str(rec["chosen"]["action"]))
			if is_finite(best):
				out["losing_step_best_utility_sum"] += best
				out["winning_utility_sum"] += float(rec["chosen"].get("utility", 0.0))
				out["utility_pairs"] += 1
	for timeout in timeouts:
		if timeout["boundary_counts"]["fresh"] == 0: out["timeouts_no_fresh"] += 1
		if timeout["boundary_counts"]["selected"] == 0: out["timeouts_never_selected"] += 1
	return out

func _diagnostic_self_test() -> bool:
	var checks := [ObservedSimulation.phase_for(4, 4, true, "a", "b") == "SOFTMAX",
		ObservedSimulation.phase_for(3, 4, true, "a", "a") == "INTENTION_CONTINUE",
		ObservedSimulation.phase_for(3, 4, false, "a", "a") == "UNCLASSIFIED",
		ObservedSimulation.phase_for(3, 4, true, "a", "b") == "UNCLASSIFIED"]
	var rec := {"phase": "SOFTMAX", "chosen_currently_available": true, "step_offered": true,
		"fresh_step_selected": false, "step_candidates": [{"key": "fish@1,1", "utility": 0.2}],
		"swapped_keys": [], "considered_keys": ["fish@1,1"], "chosen": {"action": "rest", "utility": 0.8}}
	var summary := _diagnostic_summary([rec], [{"boundary_counts": {"fresh": 0, "selected": 0}}])
	checks.append(summary["fresh_step_all_present_without_swap"] == 1 and summary["fresh_step_selected"] == 0 and summary["lost_to"]["rest"] == 1)
	checks.append(summary["timeouts_no_fresh"] == 1 and summary["timeouts_never_selected"] == 1)
	var ok := true
	for check in checks: ok = ok and check
	print("DIAG_SELF_TEST checks=%d passed=%s" % [checks.size(), str(ok)])
	return ok
