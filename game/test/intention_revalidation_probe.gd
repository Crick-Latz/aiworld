extends "res://test/p6_3b_execution_diagnosis.gd"
## Fixed-seed before/after capture. Never overwrite a previous evidence file.
func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty() or FileAccess.file_exists(output):
		print("PROBE_FAIL missing output or output exists")
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
	var equal := true
	for seed in [61000, 61009]:
		var observed := _make_observed(mq, seed, configs.duplicate(true))
		observed.agency_mode = "LIVE_BRIDGE"
		observed.agency_plan_execution_enabled = true
		var plain := _sim(mq, seed, configs, true)
		var ticks: Array = []
		for i in 1000:
			observed.step()
			plain.step()
			var digest := AgencyMeasure.canonical_behavior_digest(observed)
			equal = equal and digest == AgencyMeasure.canonical_behavior_digest(plain)
			ticks.append({"tick": observed.tick, "digest": digest, "actions": _actions(observed)})
		var row := {"seed": seed, "ticks": ticks, "summary": _diagnostic_summary(observed.boundaries, observed.timeout_cases),
			"runs": _summarize(observed.agency_execution_trace(), observed.events),
			"fingerprint": _fingerprint(observed), "plain_equal": _fingerprint(observed) == _fingerprint(plain)}
		equal = equal and row["plain_equal"]
		row["extra"] = _extra_summary(observed)
		rows.append(row)
		print("PROBE_SEED " + JSON.stringify({"seed": seed, "summary": row["summary"], "runs": row["runs"], "plain_equal": row["plain_equal"]}))
		await process_frame
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		print("PROBE_FAIL cannot write output")
		quit(1)
		return
	file.store_string(JSON.stringify({"equal": equal, "rows": rows}, "\t"))
	file.close()
	scene.queue_free()
	await process_frame
	print("PROBE_DONE equal=" + str(equal))
	quit(0 if equal else 1)

func _make_observed(mq, seed: int, configs: Array) -> ObservedSimulation:
	return ObservedSimulation.new(mq, seed, configs)

func _extra_summary(_observed) -> Dictionary:
	return {}
