extends SceneTree
var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool) -> void:
	if ok:
		passed += 1
		print("PASS " + label)
	else:
		failed += 1
		print("FAIL " + label)

func _run() -> void:
	var created := SimulationBootstrap.create(61009, "framework")
	_check("headless_bootstrap_builds_without_scene", created.get("ok", false))
	if not created.get("ok", false):
		print("SUMMARY pass=%d fail=%d" % [passed, failed])
		quit(1)
		return
	var sim: IslandSimulation = created["sim"]
	_check("framework_profile_enables_all_plan_layers", sim.agency_mode == "LIVE_BRIDGE" and sim.agency_plan_execution_enabled and sim.agency_causal_step_value_enabled and sim.agency_plan_adoption_enabled)
	_check("map_query_is_render_independent", sim.map_query is HeadlessMapQuery)
	_check("map_query_exposes_walkable_spawn", sim.map_query.is_walkable_tile(sim.map_query.get_spawn_tile()))
	var initial_world := AgencyMeasure.canon(sim.world)
	var second := SimulationBootstrap.create(61009, "framework")
	var replay: IslandSimulation = second["sim"]
	_check("headless_bootstrap_deterministic", created["map_hash"] == second["map_hash"] and initial_world == AgencyMeasure.canon(replay.world))
	for i in 200:
		sim.step()
		replay.step()
	_check("headless_loop_advances_world", sim.tick == 200 and not sim.events.is_empty())
	_check("full_diagnostic_state_replay_matches", AgencyMeasure.canon(SimulationAudit.fingerprint(sim)) == AgencyMeasure.canon(SimulationAudit.fingerprint(replay)))
	_check("plan_adoption_trace_is_live", not sim.agency_adoption_trace().is_empty())
	_check("actor_plan_rngs_are_separate", sim.agency_adoption_rng_states().size() == sim.actors.size())
	var summaries := SimulationAudit.summary(sim)
	_check("summary_exposes_plan_choices", not summaries["adoption_counts"].is_empty())
	var snapshot := SimulationAudit.fingerprint(sim)
	var event_count := sim.events.size()
	SimulationAudit.summary(sim)
	SimulationAudit.fingerprint(sim)
	_check("diagnostics_do_not_change_simulation", AgencyMeasure.canon(snapshot) == AgencyMeasure.canon(SimulationAudit.fingerprint(sim)) and event_count == sim.events.size())
	var invalid := SimulationBootstrap.configure(sim, "not_a_profile")
	_check("unknown_profile_fails_closed", not invalid["ok"] and sim.agency_plan_adoption_enabled)
	_check("negative_seed_rejected", not SimulationBootstrap.create(-1)["ok"])
	var legacy_created := SimulationBootstrap.create(61009, "legacy")
	var legacy: IslandSimulation = legacy_created["sim"]
	_check("legacy_profile_keeps_new_layers_off", legacy.agency_mode == "OFF" and not legacy.agency_plan_adoption_enabled)
	for i in 20: legacy.step()
	_check("legacy_has_no_adoption_rng_or_trace", legacy.agency_adoption_rng_states().is_empty() and legacy.agency_adoption_trace().is_empty())
	var different := SimulationBootstrap.create(61008, "framework")
	_check("seed_changes_resources_with_fixed_terrain", different["map_hash"] == created["map_hash"] and initial_world != AgencyMeasure.canon(different["sim"].world))
	# A mutation in a cognitive object must be visible in the audit, not hidden as obj(RefCounted).
	var before: String = SimulationAudit.fingerprint(sim)["state_sha256"]
	sim.actors[sim.actors.keys()[0]]["personality"].adjust_emotion("anger", 0.2)
	_check("audit_hash_covers_cognitive_object_state", SimulationAudit.fingerprint(sim)["state_sha256"] != before)
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
