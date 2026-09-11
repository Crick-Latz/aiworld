extends "res://test/p6_3b_causal_value_pilot.gd"
## P7.0 paired natural experiment.
## Both arms use the validated P6.4 framework; only information_subgoals differs.

func _run() -> void:
	_out = "res://docs/validation/data/p7_0_information_pilot.json"
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
	print("INFORMATION_PILOT_CONFIG seeds=%d..%d ticks=%d framework_vs_information" % [
		FIRST_SEED, FIRST_SEED + _seeds - 1, _ticks])
	for offset in _seeds:
		var seed_value := FIRST_SEED + offset
		var base_created := SimulationBootstrap.create(seed_value, "framework")
		var treatment_created := SimulationBootstrap.create(seed_value, "information")
		if not base_created.get("ok", false) or not treatment_created.get("ok", false):
			print("PILOT_FAIL bootstrap seed=" + str(seed_value))
			quit(1)
			return
		var baseline: IslandSimulation = base_created["sim"]
		var treatment: IslandSimulation = treatment_created["sim"]
		var initial_equal := AgencyMeasure.canon(baseline.world) == AgencyMeasure.canon(treatment.world) \
			and AgencyMeasure.canonical_behavior_digest(baseline) == AgencyMeasure.canonical_behavior_digest(treatment)
		var first_diff := -1
		var high_hunger := {"baseline": 0, "treatment": 0}
		for i in _ticks:
			baseline.step()
			treatment.step()
			if first_diff < 0 and AgencyMeasure.canonical_behavior_digest(baseline) != \
					AgencyMeasure.canonical_behavior_digest(treatment):
				first_diff = treatment.tick
			for id in treatment.actors:
				if int(baseline.actors[id]["needs"]["hunger"]) >= 950: high_hunger["baseline"] += 1
				if int(treatment.actors[id]["needs"]["hunger"]) >= 950: high_hunger["treatment"] += 1
		var base_runs := _summarize(baseline.agency_execution_trace(), baseline.events)
		var treatment_runs := _summarize(treatment.agency_execution_trace(), treatment.events)
		base_runs["multi_stage_completed"] = _multi_stage_completed(baseline.agency_execution_trace())
		treatment_runs["multi_stage_completed"] = _multi_stage_completed(treatment.agency_execution_trace())
		var info_summary := _information_summary(treatment)
		if not initial_equal: violations.append("seed %d initial state mismatch" % seed_value)
		if not baseline.agency_information_trace().is_empty():
			violations.append("seed %d framework baseline emitted information trace" % seed_value)
		for v in base_runs["violations"]: violations.append("baseline %d: %s" % [seed_value, str(v)])
		for v in treatment_runs["violations"]: violations.append("treatment %d: %s" % [seed_value, str(v)])
		var row := {
			"seed": seed_value,
			"initial_equal": initial_equal,
			"first_behavior_difference_tick": first_diff,
			"baseline_runs": base_runs,
			"treatment_runs": treatment_runs,
			"information": info_summary,
			"baseline_summary": SimulationAudit.summary(baseline),
			"treatment_summary": SimulationAudit.summary(treatment),
			"high_hunger_actor_ticks": high_hunger,
			"treatment_fingerprint": SimulationAudit.fingerprint(treatment),
		}
		if offset == 0:
			var replay_created := SimulationBootstrap.create(seed_value, "information")
			var replay: IslandSimulation = replay_created["sim"]
			for i in _ticks: replay.step()
			row["treatment_replay_equal"] = AgencyMeasure.canon(row["treatment_fingerprint"]) == \
				AgencyMeasure.canon(SimulationAudit.fingerprint(replay))
			if not row["treatment_replay_equal"]: violations.append("treatment replay mismatch")
		rows.append(row)
		print("INFORMATION_PILOT_SEED seed=%d goals=%d resolved=%d searches=%d asks=%d shared=%d full_chain=%d first_diff=%d" % [
			seed_value, info_summary["goals_created"], info_summary["goals_resolved"],
			info_summary["search_attempts"], info_summary["ask_attempts"], info_summary["reports_shared"],
			treatment_runs["multi_stage_completed"], first_diff])
		await process_frame
	var payload := {
		"meta": {
			"base_commit": "dff3b5de1483f9b863dc698c7ab48d2488740923",
			"engine": Engine.get_version_info()["string"],
			"first_seed": FIRST_SEED,
			"seeds": _seeds,
			"ticks": _ticks,
			"comparison": "P6.4 framework information_subgoals=false vs true",
			"same_terrain": true,
			"economy_overrides": {},
			"source_fingerprints": {
				"tracker": FileAccess.get_sha256("res://src/simulation/knowledge/information_subgoal_tracker.gd"),
				"action_policy": FileAccess.get_sha256("res://src/simulation/knowledge/information_action_policy.gd"),
				"exchange_policy": FileAccess.get_sha256("res://src/simulation/knowledge/information_exchange_policy.gd"),
				"spatial_belief": FileAccess.get_sha256("res://src/simulation/spatial/spatial_belief_map.gd"),
				"core": FileAccess.get_sha256("res://src/simulation/core/island_simulation.gd"),
			},
			"notes": [
				"Natural frequency is observational and is not a pass quota.",
				"Information goals arise only from structured UNKNOWN_SOURCE blockers.",
				"Search uses subjective map frontiers; reports come from the responder's own spatial belief.",
				"A resolved information goal does not itself transfer items or complete the parent plan.",
			],
		},
		"rows": rows,
		"totals": _totals(rows),
		"violations": violations,
	}
	var saved := _write_result(payload)
	print("INFORMATION_PILOT_RESULT seeds=%d violations=%d saved=%s" % [rows.size(), violations.size(), str(saved)])
	quit(0 if saved and violations.is_empty() else 1)

func _information_summary(sim: IslandSimulation) -> Dictionary:
	var out := {
		"goals_created": 0,
		"goals_resolved": 0,
		"goals_failed": 0,
		"goals_cancelled": 0,
		"attempts_completed": 0,
		"search_attempts": 0,
		"search_found": 0,
		"search_failed": 0,
		"ask_attempts": 0,
		"reports_shared": 0,
		"reports_refused": 0,
		"reports_stale": 0,
		"reports_unknown": 0,
		"reports_missed": 0,
		"parent_runs_started_after_resolution": 0,
	}
	var resolved: Array = []
	for row in sim.agency_information_trace():
		match str(row.get("event", "")):
			"GOAL_CREATED": out["goals_created"] += 1
			"GOAL_RESOLVED":
				out["goals_resolved"] += 1
				resolved.append(row)
			"GOAL_FAILED": out["goals_failed"] += 1
			"GOAL_CANCELLED": out["goals_cancelled"] += 1
			"ATTEMPT_COMPLETED": out["attempts_completed"] += 1
	for event in sim.events:
		match str(event.get("type", "")):
			"source_search_found": out["search_found"] += 1; out["search_attempts"] += 1
			"source_search_failed": out["search_failed"] += 1; out["search_attempts"] += 1
			"source_information_requested": out["ask_attempts"] += 1
			"source_information_shared": out["reports_shared"] += 1
			"source_information_refused": out["reports_refused"] += 1
			"source_information_stale": out["reports_stale"] += 1
			"source_information_unknown": out["reports_unknown"] += 1
			"source_information_missed": out["reports_missed"] += 1
	for info in resolved:
		for execution in sim.agency_execution_trace():
			if str(execution.get("event", "")) == "RUN_STARTED" \
					and str(execution.get("actor_id", "")) == str(info.get("actor_id", "")) \
					and str(execution.get("plan_id", "")) == str(info.get("parent_plan_id", "")) \
					and int(execution.get("tick", -1)) >= int(info.get("tick", 0)):
				out["parent_runs_started_after_resolution"] += 1
				break
	return out

func _totals(rows: Array) -> Dictionary:
	var totals := {}
	for row in rows:
		for key in row.get("information", {}):
			totals[key] = int(totals.get(key, 0)) + int(row["information"][key])
		totals["baseline_completed"] = int(totals.get("baseline_completed", 0)) + int(row["baseline_runs"].get("completed", 0))
		totals["treatment_completed"] = int(totals.get("treatment_completed", 0)) + int(row["treatment_runs"].get("completed", 0))
		totals["baseline_multi_stage_completed"] = int(totals.get("baseline_multi_stage_completed", 0)) + int(row["baseline_runs"].get("multi_stage_completed", 0))
		totals["treatment_multi_stage_completed"] = int(totals.get("treatment_multi_stage_completed", 0)) + int(row["treatment_runs"].get("multi_stage_completed", 0))
	return totals
