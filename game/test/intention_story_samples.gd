extends "res://test/p1_5_cognition.gd"
## Descriptive product samples, NOT a substitute for existing acceptance gates.
## Predeclared adjacent seeds. No selection/retry based on the resulting story.
func _run() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty() or FileAccess.file_exists(output):
		print("SAMPLE_ERROR missing output or output exists")
		quit(1)
		return
	var mq = await _make_map()
	mq.get_parent().get_parent().process_mode = Node.PROCESS_MODE_DISABLED
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var rows: Array = []
	for sample_seed in [777, 778, 779]:
		var cfg := _make_configs(mq, scenario, false)
		var scarce := IslandSimulation.new(mq, sample_seed, cfg.duplicate(true))
		var rich := IslandSimulation.new(mq, sample_seed, cfg.duplicate(true), {"berry_count": 6, "berry_food": 3,
			"berry_regrow_days": 2, "fish_prob": 0.8, "fish_amount": 2, "explore_food_prob": 0.08})
		for i in 1200: scarce.step()
		for i in 1200: rich.step()
		var tvd := _activity_distance(scarce, rich, "npc_oun")
		var row := {"kind": "environment_pair", "seed": sample_seed, "ticks": 1200,
			"tvd": tvd, "historical_threshold": 0.15, "exceeds_threshold": tvd > 0.15}
		rows.append(row)
		print("STORY_SAMPLE " + JSON.stringify(row))
		await process_frame
	for sample_seed in [30014, 30015, 30016]:
		var sim := IslandSimulation.new(mq, sample_seed, _make_configs(mq, scenario, true))
		for i in 1500: sim.step()
		var counts := {}
		var social_events: Array = []
		for e in sim.events:
			var event_type := str(e["type"])
			counts[event_type] = int(counts.get(event_type, 0)) + 1
			if event_type.contains("request") or event_type in ["reason_asked", "reason_claimed", "reason_deflected", "asked_about", "observing_person", "promise_made", "promise_kept", "promise_broken"]:
				social_events.append(e.duplicate(true))
		var row := {"kind": "social_episode", "seed": sample_seed, "ticks": 1500,
			"event_counts": counts, "social_events": social_events}
		rows.append(row)
		print("STORY_SAMPLE " + JSON.stringify({"kind": row["kind"], "seed": sample_seed, "counts": counts}))
		await process_frame
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		print("SAMPLE_ERROR cannot open output")
		quit(1)
		return
	file.store_string(JSON.stringify({"purpose": "descriptive_only_not_acceptance", "rows": rows}, "\t"))
	file.close()
	print("SAMPLE_DONE " + output)
	quit(0)
