extends "res://test/p6_3b_causal_value_pilot.gd"
## Fixed paired experiment: both arms use causal step value; only plan adoption differs.

func _run() -> void:
	_out = "res://docs/validation/data/p6_4_adoption_pilot.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="): _seeds = arg.trim_prefix("--seeds=").to_int()
		elif arg.begins_with("--ticks="): _ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
	if _seeds < 1 or _seeds > 30 or _ticks < 1 or _ticks > 3000 or FileAccess.file_exists(_out):
		print("PILOT_FAIL invalid bounds or existing output")
		quit(1)
		return
	var rows: Array = []
	var violations: Array = []
	print("ADOPTION_PILOT_CONFIG seeds=%d..%d ticks=%d causal=true adoption=off_vs_on" % [FIRST_SEED, FIRST_SEED + _seeds - 1, _ticks])
	for offset in _seeds:
		var seed_value := FIRST_SEED + offset
		var a := SimulationBootstrap.create(seed_value, "causal")
		var b := SimulationBootstrap.create(seed_value, "framework")
		if not a.get("ok", false) or not b.get("ok", false):
			print("PILOT_FAIL bootstrap")
			quit(1)
			return
		var base: IslandSimulation = a["sim"]
		var treatment: IslandSimulation = b["sim"]
		var initial_equal := AgencyMeasure.canon(base.world) == AgencyMeasure.canon(treatment.world) \
			and AgencyMeasure.canonical_behavior_digest(base) == AgencyMeasure.canonical_behavior_digest(treatment)
		var first_diff := -1
		var hunger := {"baseline": 0, "treatment": 0}
		for i in _ticks:
			base.step()
			treatment.step()
			if first_diff < 0 and AgencyMeasure.canonical_behavior_digest(base) != AgencyMeasure.canonical_behavior_digest(treatment):
				first_diff = treatment.tick
			for id in treatment.actors:
				if int(base.actors[id]["needs"]["hunger"]) >= 950: hunger["baseline"] += 1
				if int(treatment.actors[id]["needs"]["hunger"]) >= 950: hunger["treatment"] += 1
		var baseline_summary := _summarize(base.agency_execution_trace(), base.events)
		var treatment_summary := _summarize(treatment.agency_execution_trace(), treatment.events)
		baseline_summary["multi_stage_completed"] = _multi_stage_completed(base.agency_execution_trace())
		treatment_summary["multi_stage_completed"] = _multi_stage_completed(treatment.agency_execution_trace())
		if not initial_equal: violations.append("initial state mismatch: %d" % seed_value)
		for v in baseline_summary["violations"]: violations.append("baseline %d: %s" % [seed_value, str(v)])
		for v in treatment_summary["violations"]: violations.append("treatment %d: %s" % [seed_value, str(v)])
		var row := {"seed": seed_value, "initial_equal": initial_equal, "first_behavior_difference_tick": first_diff,
			"baseline_runs": baseline_summary, "treatment_runs": treatment_summary,
			"baseline_summary": SimulationAudit.summary(base), "treatment_summary": SimulationAudit.summary(treatment),
			"high_hunger_actor_ticks": hunger, "treatment_fingerprint": SimulationAudit.fingerprint(treatment)}
		if offset == 0:
			var replay_created := SimulationBootstrap.create(seed_value, "framework")
			var replay: IslandSimulation = replay_created["sim"]
			for i in _ticks: replay.step()
			row["treatment_replay_equal"] = AgencyMeasure.canon(row["treatment_fingerprint"]) == AgencyMeasure.canon(SimulationAudit.fingerprint(replay))
			if not row["treatment_replay_equal"]: violations.append("treatment replay mismatch")
		rows.append(row)
		print("ADOPTION_PILOT_SEED seed=%d baseline_completed=%d treatment_completed=%d baseline_multi=%d treatment_multi=%d first_diff=%d" % [
			seed_value, baseline_summary["completed"], treatment_summary["completed"],
			baseline_summary["multi_stage_completed"], treatment_summary["multi_stage_completed"], first_diff])
		await process_frame
	var payload := {"meta": {"first_seed": FIRST_SEED, "seeds": _seeds, "ticks": _ticks,
		"engine": Engine.get_version_info()["string"], "comparison": "causal ON, adoption OFF vs ON",
		"same_terrain": true, "economy_overrides": {},
		"source_fingerprints": {"policy": FileAccess.get_sha256("res://src/simulation/knowledge/plan_adoption_policy.gd"),
			"tracker": FileAccess.get_sha256("res://src/simulation/knowledge/plan_execution_tracker.gd"),
			"core": FileAccess.get_sha256("res://src/simulation/core/island_simulation.gd")},
		"notes": ["Natural frequency is observational, not a success quota.",
			"Retained commitments use remaining effort and hysteresis; they grant no action execution rights."]},
		"rows": rows, "violations": violations}
	var saved := _write_result(payload)
	print("ADOPTION_PILOT_RESULT seeds=%d violations=%d saved=%s" % [rows.size(), violations.size(), str(saved)])
	quit(0 if saved and violations.is_empty() else 1)
