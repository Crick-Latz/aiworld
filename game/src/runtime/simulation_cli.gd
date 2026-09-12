extends SceneTree
## Example: godot --headless --path game --script res://src/runtime/simulation_cli.gd -- --ticks=1000 --seed=61000 --verify-replay --out=/absolute/run.json

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var ticks := 1000
	var seed_value := 61000
	var profile := "framework"
	var output := ""
	var verify := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ticks=") and arg.trim_prefix("--ticks=").is_valid_int(): ticks = arg.trim_prefix("--ticks=").to_int()
		elif arg.begins_with("--seed=") and arg.trim_prefix("--seed=").is_valid_int(): seed_value = arg.trim_prefix("--seed=").to_int()
		elif arg.begins_with("--profile="): profile = arg.trim_prefix("--profile=")
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=")
		elif arg == "--verify-replay": verify = true
		else:
			_fail("UNKNOWN_OR_INVALID_ARGUMENT: " + arg)
			return
	if ticks < 1 or ticks > 100000 or seed_value < 0 or output == "" or FileAccess.file_exists(output):
		_fail("INVALID_BOUNDS_OR_EXISTING_OUTPUT")
		return
	var created := SimulationBootstrap.create(seed_value, profile)
	if not created.get("ok", false):
		_fail(str(created))
		return
	var sim: IslandSimulation = created["sim"]
	print("SIM_START profile=%s seed=%d ticks=%d actors=%d headless=true" % [profile, seed_value, ticks, sim.actors.size()])
	for i in ticks: sim.step()
	var fingerprint := SimulationAudit.fingerprint(sim)
	var replay_equal: Variant = null
	if verify:
		var second := SimulationBootstrap.create(seed_value, profile)
		if not second.get("ok", false):
			_fail("REPLAY_BOOTSTRAP_FAILED")
			return
		var replay: IslandSimulation = second["sim"]
		for i in ticks: replay.step()
		replay_equal = AgencyMeasure.canon(fingerprint) == AgencyMeasure.canon(SimulationAudit.fingerprint(replay))
	var report := {"schema_version": 1, "engine": Engine.get_version_info()["string"],
		"profile": profile, "simulation_seed": seed_value, "terrain_seed": created["terrain_seed"],
		"map_hash": created["map_hash"], "scenario_id": created["scenario_id"],
		"ticks": ticks, "replay_verified": replay_equal, "summary": SimulationAudit.summary(sim),
		"fingerprint": fingerprint, "final_snapshot": sim.get_snapshot(),
		"events": sim.events, "plan_execution_trace": sim.agency_execution_trace(),
		"plan_adoption_trace": sim.agency_adoption_trace(),
		"information_subgoal_trace": sim.agency_information_trace(),
		"material_request_trace": sim.agency_material_request_trace(),
		"notes": ["Terrain remains the existing fixture; simulation seed controls resource placement and agent randomness.",
			"Replay is recomputation from initial inputs, not fast mid-run save/restore.",
			"No live LLM or graphical UI is required."]}
	var absolute := ProjectSettings.globalize_path(output)
	if DirAccess.make_dir_recursive_absolute(absolute.get_base_dir()) != OK:
		_fail("OUTPUT_DIRECTORY_FAILED")
		return
	var file := FileAccess.open(absolute + ".tmp", FileAccess.WRITE)
	if file == null:
		_fail("OUTPUT_OPEN_FAILED")
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(absolute + ".tmp", absolute) != OK:
		_fail("OUTPUT_WRITE_FAILED")
		return
	print("SIM_RESULT " + JSON.stringify({"ok": not verify or replay_equal == true,
		"summary": report["summary"], "replay_verified": replay_equal, "output": absolute}))
	quit(0 if not verify or replay_equal == true else 1)

func _fail(error: String) -> void:
	print("SIM_FAIL " + error)
	quit(1)
