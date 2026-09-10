extends "res://test/p6_3b_execution_pilot.gd"
## P6.3B-4 paired natural experiment.
## Both arms execute plans. The only treatment difference is causal step-value propagation.
const CAUSAL_BASE_COMMIT := "498f55a07fc693f39caced22dbe7196c7e64d3fa"

func _run() -> void:
	_out = "res://docs/validation/data/p6_3b_4_causal_value_pilot.json"
	for arg in OS.get_cmdline_user_args():
		if arg == "--self-test":
			quit(0 if _self_test() else 1)
			return
		if arg.begins_with("--seeds="): _seeds = arg.trim_prefix("--seeds=").to_int()
		elif arg.begins_with("--ticks="): _ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	if _seeds < 1 or _seeds > 30 or _ticks < 1 or _ticks > 3000 or FileAccess.file_exists(_out):
		print("PILOT_FAIL invalid bounds or output already exists: " + _out)
		quit(1)
		return
	var packed: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var scene := packed.instantiate()
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
	var rows: Array = []
	var violations: Array = []
	print("PILOT_CONFIG seeds=%d..%d ticks=%d execution=true causal=off_vs_on timeout=16" % [FIRST_SEED, FIRST_SEED + _seeds - 1, _ticks])
	for offset in _seeds:
		var seed := FIRST_SEED + offset
		var baseline := _sim(mq, seed, configs, false)
		var treatment := _sim(mq, seed, configs, true)
		var initial_equal := AgencyMeasure.canon(baseline.world) == AgencyMeasure.canon(treatment.world) \
			and AgencyMeasure.canonical_behavior_digest(baseline) == AgencyMeasure.canonical_behavior_digest(treatment)
		var first_diff := {}
		var sampled := {
			"treatment_value_decisions": 0, "treatment_value_candidates": 0,
			"treatment_positive_uplifts": 0, "treatment_utility_delta_sum": 0.0,
			"high_hunger_actor_ticks_baseline": 0, "high_hunger_actor_ticks_treatment": 0,
		}
		var baseline_ms := 0
		var treatment_ms := 0
		for i in _ticks:
			var start := Time.get_ticks_msec()
			baseline.step()
			baseline_ms += Time.get_ticks_msec() - start
			start = Time.get_ticks_msec()
			treatment.step()
			treatment_ms += Time.get_ticks_msec() - start
			if first_diff.is_empty() and AgencyMeasure.canonical_behavior_digest(baseline) != AgencyMeasure.canonical_behavior_digest(treatment):
				first_diff = {"tick": treatment.tick, "components": AgencyMeasure.diff_components(baseline, treatment),
					"baseline_actions": _actions(baseline), "treatment_actions": _actions(treatment),
					"cause": "CAUSAL_STEP_VALUE_TREATMENT"}
			for id in treatment.actors:
				var ex: Dictionary = treatment.actors[id].get("last_decision_trace", {}).get("agency_execution", {})
				if int(ex.get("decision_tick", -1)) == treatment.tick \
						and str(ex.get("utility_mode", "")) == "CAUSAL_STEP_VALUE":
					sampled["treatment_value_decisions"] += 1
					for row in ex.get("candidate_values", []):
						var rd: Dictionary = row
						sampled["treatment_value_candidates"] += 1
						var delta := float(rd.get("utility_delta", 0.0))
						if delta > 0.0: sampled["treatment_positive_uplifts"] += 1
						sampled["treatment_utility_delta_sum"] += delta
				if int(baseline.actors[id]["needs"]["hunger"]) >= 950: sampled["high_hunger_actor_ticks_baseline"] += 1
				if int(treatment.actors[id]["needs"]["hunger"]) >= 950: sampled["high_hunger_actor_ticks_treatment"] += 1
		var baseline_summary := _summarize(baseline.agency_execution_trace(), baseline.events)
		var treatment_summary := _summarize(treatment.agency_execution_trace(), treatment.events)
		baseline_summary["multi_stage_completed"] = _multi_stage_completed(baseline.agency_execution_trace())
		treatment_summary["multi_stage_completed"] = _multi_stage_completed(treatment.agency_execution_trace())
		if not initial_equal: violations.append("seed %d initial state mismatch" % seed)
		for v in baseline_summary["violations"]: violations.append("seed %d baseline: %s" % [seed, str(v)])
		for v in treatment_summary["violations"]: violations.append("seed %d treatment: %s" % [seed, str(v)])
		var row := {
			"seed": seed, "initial_equal": initial_equal, "ticks": _ticks,
			"first_scoped_difference": first_diff, "sampled": sampled,
			"baseline_runs": baseline_summary, "treatment_runs": treatment_summary,
			"baseline": _outcome(baseline), "treatment": _outcome(treatment),
			"baseline_step_ms": baseline_ms, "treatment_step_ms": treatment_ms,
		}
		if offset == 0:
			var replay := _sim(mq, seed, configs, true)
			for i in _ticks: replay.step()
			row["treatment_replay_equal"] = _fingerprint(replay) == _fingerprint(treatment)
			if not row["treatment_replay_equal"]: violations.append("seed %d treatment replay mismatch" % seed)
		rows.append(row)
		print("PILOT_SEED seed=%d base_complete=%d treat_complete=%d base_multi=%d treat_multi=%d diff_tick=%d uplift=%d" % [
			seed, baseline_summary["completed"], treatment_summary["completed"],
			baseline_summary["multi_stage_completed"], treatment_summary["multi_stage_completed"],
			first_diff.get("tick", -1), sampled["treatment_positive_uplifts"]])
		await process_frame
	var payload := {
		"meta": {
			"base_commit": CAUSAL_BASE_COMMIT, "engine": Engine.get_version_info()["string"],
			"first_seed": FIRST_SEED, "seeds": _seeds, "ticks": _ticks, "actors": configs.size(),
			"comparison": "LIVE_BRIDGE execution=true causal_step_value=false vs true",
			"timeout": 16, "same_terrain": true, "spawn_policy": "three distinct existing POIs",
			"economy_overrides": {}, "fingerprints": _source_fingerprints(),
			"metric_notes": [
				"the treatment changes decision utility only for active ACQUIRE/CRAFT plan-step candidates",
				"MAIN actions retain Registry utility to avoid double-counting their root need",
				"multi_stage_completed requires one completed run to contain ACQUIRE, CRAFT and MAIN step completions",
				"same seeds and resource generation are used in both arms; no seed selection or tuning",
			],
		},
		"rows": rows, "violations": violations,
	}
	var saved := _write_result(payload)
	print("PILOT_RESULT seeds=%d violations=%d saved=%s path=%s" % [rows.size(), violations.size(), str(saved), _out])
	quit(0 if saved and violations.is_empty() else 1)

func _sim(mq, seed: int, configs: Array, causal_value_enabled: bool) -> IslandSimulation:
	var sim := IslandSimulation.new(mq, seed, configs.duplicate(true))
	sim.agency_mode = "LIVE_BRIDGE"
	sim.agency_plan_execution_enabled = true
	sim.agency_causal_step_value_enabled = causal_value_enabled
	return sim

func _multi_stage_completed(traces: Array) -> int:
	var kinds_by_run := {}
	var completed_runs := {}
	for tr in traces:
		var td: Dictionary = tr
		var rid := str(td.get("run_id", ""))
		if rid == "": continue
		if str(td.get("event", "")) == "STEP_COMPLETED":
			var sid := str(td.get("step_id", ""))
			var kind := sid.get_slice(":", 0)
			if not kinds_by_run.has(rid): kinds_by_run[rid] = {}
			(kinds_by_run[rid] as Dictionary)[kind] = true
		elif str(td.get("event", "")) == "RUN_COMPLETED":
			completed_runs[rid] = true
	var count := 0
	for rid in completed_runs:
		var kinds: Dictionary = kinds_by_run.get(rid, {})
		if kinds.has("ACQUIRE") and kinds.has("CRAFT") and kinds.has("MAIN"):
			count += 1
	return count

func _source_fingerprints() -> Dictionary:
	var out := {}
	for path in [
		"res://test/p6_3b_causal_value_pilot.gd",
		"res://data/scenarios/deserted_island_v2.json",
		"res://data/demo_world/world_spec.json",
		"res://src/simulation/decision/plan_step_value_model.gd",
		"res://src/simulation/knowledge/plan_execution_tracker.gd",
		"res://src/simulation/core/island_simulation.gd",
		"res://src/simulation/decision/decision_engine.gd",
	]:
		out[path] = FileAccess.get_sha256(path)
	return out
