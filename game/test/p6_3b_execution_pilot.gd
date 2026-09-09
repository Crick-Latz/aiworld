extends SceneTree
## Read-only paired experiment. No resource, inventory, belief or utility overrides.
## Same fixed terrain; seeds vary resource placement and simulation RNG, not terrain.
const BASE_COMMIT := "a0a9cdd0458a8148e73d3c1b27f151bcd329d046"
const FIRST_SEED := 61000
var _started := false
var _seeds := 10
var _ticks := 1000
var _out := "res://docs/validation/data/p6_3b_1_natural_pilot.json"

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false

func _run() -> void:
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
	print("PILOT_CONFIG seeds=%d..%d ticks=%d same_terrain=true execution_timeout=16" % [FIRST_SEED, FIRST_SEED + _seeds - 1, _ticks])
	for offset in _seeds:
		var seed := FIRST_SEED + offset
		var baseline := _sim(mq, seed, configs, false)
		var execution := _sim(mq, seed, configs, true)
		var initial_equal := AgencyMeasure.canon(baseline.world) == AgencyMeasure.canon(execution.world) \
			and AgencyMeasure.canonical_behavior_digest(baseline) == AgencyMeasure.canonical_behavior_digest(execution)
		var first_diff := {}
		var sampled := {"fresh_execution_decisions": 0, "with_candidates": 0, "selected": 0,
			"blockers": {}, "high_hunger_actor_ticks_baseline": 0, "high_hunger_actor_ticks_execution": 0}
		var baseline_ms := 0
		var execution_ms := 0
		for i in _ticks:
			var start := Time.get_ticks_msec()
			baseline.step()
			baseline_ms += Time.get_ticks_msec() - start
			start = Time.get_ticks_msec()
			execution.step()
			execution_ms += Time.get_ticks_msec() - start
			if first_diff.is_empty() and AgencyMeasure.canonical_behavior_digest(baseline) != AgencyMeasure.canonical_behavior_digest(execution):
				first_diff = {"tick": execution.tick, "components": AgencyMeasure.diff_components(baseline, execution),
					"baseline_actions": _actions(baseline), "execution_actions": _actions(execution), "cause": "NOT_ATTRIBUTED"}
			for id in execution.actors:
				var ex: Dictionary = execution.actors[id].get("last_decision_trace", {}).get("agency_execution", {})
				if int(ex.get("decision_tick", -1)) == execution.tick:
					sampled["fresh_execution_decisions"] += 1
					if not ex.get("candidate_keys", []).is_empty(): sampled["with_candidates"] += 1
					if ex.get("selected", false): sampled["selected"] += 1
					if ex.get("blocker_reason", "") != "": _inc(sampled["blockers"], str(ex["blocker_reason"]))
				if int(baseline.actors[id]["needs"]["hunger"]) >= 950: sampled["high_hunger_actor_ticks_baseline"] += 1
				if int(execution.actors[id]["needs"]["hunger"]) >= 950: sampled["high_hunger_actor_ticks_execution"] += 1
		var summary := _summarize(execution.agency_execution_trace(), execution.events)
		if not initial_equal: violations.append("seed %d initial state mismatch" % seed)
		for v in summary["violations"]: violations.append("seed %d: %s" % [seed, str(v)])
		var row := {"seed": seed, "initial_equal": initial_equal, "ticks": _ticks,
			"first_scoped_difference": first_diff, "sampled": sampled, "runs": summary,
			"baseline": _outcome(baseline), "execution": _outcome(execution),
			"baseline_step_ms": baseline_ms, "execution_step_ms": execution_ms}
		# One predeclared replay checks ALL events and execution traces, plus scoped end state.
		if offset == 0:
			var replay := _sim(mq, seed, configs, true)
			for i in _ticks: replay.step()
			row["replay_equal"] = _fingerprint(replay) == _fingerprint(execution)
			if not row["replay_equal"]: violations.append("seed %d replay mismatch" % seed)
		rows.append(row)
		print("PILOT_SEED seed=%d started=%d completed=%d cancelled=%d blocked=%d pending=%d diff_tick=%d" % [
			seed, summary["started"], summary["completed"], summary["cancelled"], summary["blocked"],
			summary["active_or_suspended_at_end"], first_diff.get("tick", -1)])
		# Yield between seeds; observer scene stays disabled, simulation is explicit only.
		await process_frame
	var payload := {"meta": {"base_commit": BASE_COMMIT, "engine": Engine.get_version_info()["string"],
		"first_seed": FIRST_SEED, "seeds": _seeds, "ticks": _ticks, "actors": configs.size(),
		"comparison": "LIVE_BRIDGE execution=false vs true", "timeout": 16, "same_terrain": true,
		"spawn_policy": "three distinct existing POIs", "economy_overrides": {},
		"fingerprints": _source_fingerprints(), "metric_notes": [
			"run counts are episodes, not unique NPCs or success probabilities",
			"no completion by observation end is censored, not necessarily a failure",
			"hunger >=950 is an actor-tick count, not deaths",
			"first difference uses AgencyMeasure scoped digest, not all-state identity",
			"replay covers only first seed; timing excludes observation overhead"]},
		"rows": rows, "violations": violations}
	var saved := _write_result(payload)
	print("PILOT_RESULT seeds=%d violations=%d saved=%s path=%s" % [rows.size(), violations.size(), str(saved), _out])
	quit(0 if saved and violations.is_empty() else 1)

func _write_result(payload: Dictionary) -> bool:
	var path := ProjectSettings.globalize_path(_out)
	var temporary := path + ".tmp"
	if FileAccess.file_exists(path) or FileAccess.file_exists(temporary): return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return false
	var serialized := JSON.stringify(payload)
	file.store_string(serialized)
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK: return false
	if DirAccess.rename_absolute(temporary, path) != OK: return false
	return FileAccess.get_file_as_string(path) == serialized

func _sim(mq, seed: int, configs: Array, enabled: bool) -> IslandSimulation:
	var sim := IslandSimulation.new(mq, seed, configs.duplicate(true))
	sim.agency_mode = "LIVE_BRIDGE"
	sim.agency_plan_execution_enabled = enabled
	return sim

func _inc(d: Dictionary, key: String) -> void:
	d[key] = int(d.get(key, 0)) + 1

func _actions(sim: IslandSimulation) -> Dictionary:
	var out := {}
	for id in sim.actors:
		var action = sim.actors[id].get("current_action")
		out[id] = action.duplicate(true) if typeof(action) == TYPE_DICTIONARY else null
	return out

func _outcome(sim: IslandSimulation) -> Dictionary:
	var counts := {}
	for e in sim.events: _inc(counts, str(e["type"]))
	var actors := {}
	for id in sim.actors:
		actors[id] = {"inventory": sim.actors[id]["inventory"].duplicate(true), "needs": sim.actors[id]["needs"].duplicate(true)}
	return {"event_counts": counts, "actors": actors, "fingerprint": _fingerprint(sim),
		"planner_calls": sim.agency_planner_calls, "cache_hits": sim.agency_cache_hits}

func _fingerprint(sim: IslandSimulation) -> Dictionary:
	return {"events_sha256": AgencyMeasure.canon(sim.events).sha256_text(),
		"execution_trace_sha256": AgencyMeasure.canon(sim.agency_execution_trace()).sha256_text(),
		"scoped_behavior_digest": AgencyMeasure.canonical_behavior_digest(sim)}

func _source_fingerprints() -> Dictionary:
	var out := {}
	for path in ["res://test/p6_3b_execution_pilot.gd", "res://data/scenarios/deserted_island_v2.json",
		"res://data/demo_world/world_spec.json", "res://src/simulation/knowledge/plan_execution_tracker.gd",
		"res://src/simulation/core/island_simulation.gd", "res://src/simulation/decision/decision_engine.gd"]:
		out[path] = FileAccess.get_sha256(path)
	return out

func _summarize(traces: Array, events: Array) -> Dictionary:
	var runs := {}
	var by_event := {}
	for e in events: by_event[int(e["seq"])] = e
	var errors: Array = []
	var reasons := {}
	var completed_steps := {}
	var examples: Array = []
	for tr in traces:
		var rid := str(tr["run_id"])
		var ev := str(tr["event"])
		if ev == "RUN_STARTED":
			if runs.has(rid): errors.append("duplicate RUN_STARTED " + rid)
			runs[rid] = {"state": "ACTIVE", "actor_id": tr["actor_id"], "step_ids": [], "proofs": [], "started_tick": tr["tick"]}
		if not runs.has(rid):
			errors.append("trace without run " + rid)
			continue
		var run: Dictionary = runs[rid]
		if ev.begins_with("RUN_"):
			run["state"] = tr["state_after"]
			if tr.get("reason_code", "") != "": _inc(reasons, str(tr["reason_code"]))
		if ev == "STEP_COMPLETED":
			var sid := str(tr["step_id"])
			if run["step_ids"].has(sid): errors.append("duplicate step completion " + rid + "/" + sid)
			run["step_ids"].append(sid)
			_inc(completed_steps, sid)
			for ref in tr.get("source_event_refs", []):
				if not by_event.has(int(ref)):
					errors.append("unknown source event " + str(ref))
				else:
					var source: Dictionary = by_event[int(ref)]
					if source.get("actor_id", "") != tr["actor_id"] or int(source["tick"]) > int(tr["tick"]):
						errors.append("foreign/future source event " + str(ref))
					run["proofs"].append({"seq": ref, "type": source["type"], "tick": source["tick"], "step_id": sid})
		if ev == "RUN_COMPLETED" and examples.size() < 6:
			examples.append({"run_id": rid, "actor_id": run["actor_id"], "start": run["started_tick"],
				"end": tr["tick"], "steps": run["step_ids"].duplicate(), "proofs": run["proofs"].duplicate(true)})
	var result := {"started": runs.size(), "completed": 0, "cancelled": 0, "blocked": 0,
		"active_or_suspended_at_end": 0, "transition_reasons": reasons,
		"completed_steps": completed_steps, "completion_examples": examples, "violations": errors}
	for run in runs.values():
		match str(run["state"]):
			"COMPLETED": result["completed"] += 1
			"CANCELLED": result["cancelled"] += 1
			"BLOCKED": result["blocked"] += 1
			"ACTIVE", "SUSPENDED": result["active_or_suspended_at_end"] += 1
			_: errors.append("unknown final run state")
	if result["started"] != result["completed"] + result["cancelled"] + result["blocked"] + result["active_or_suspended_at_end"]:
		errors.append("run count conservation failed")
	return result

func _self_test() -> bool:
	var start := {"run_id": "a#1", "actor_id": "a", "event": "RUN_STARTED", "tick": 1, "state_after": "ACTIVE"}
	var step := {"run_id": "a#1", "actor_id": "a", "event": "STEP_COMPLETED", "tick": 2,
		"step_id": "MAIN:test", "source_event_refs": [7]}
	var done := {"run_id": "a#1", "actor_id": "a", "event": "RUN_COMPLETED", "tick": 2, "state_after": "COMPLETED"}
	var event := {"seq": 7, "actor_id": "a", "type": "fished", "tick": 2}
	var good := _summarize([start, step, done], [event])
	var checks := [good["violations"].is_empty() and good["started"] == 1 and good["completed"] == 1,
		not _summarize([start, step, done], [])["violations"].is_empty(),
		not _summarize([start, step, step, done], [event])["violations"].is_empty(),
		not _summarize([step], [event])["violations"].is_empty(),
		_summarize([start], [])["active_or_suspended_at_end"] == 1]
	var foreign := event.duplicate(); foreign["actor_id"] = "other"
	checks.append(not _summarize([start, step, done], [foreign])["violations"].is_empty())
	var ok := true
	for check in checks: ok = ok and check
	print("PILOT_MEASUREMENT_TEST checks=%d passed=%s" % [checks.size(), str(ok)])
	return ok
