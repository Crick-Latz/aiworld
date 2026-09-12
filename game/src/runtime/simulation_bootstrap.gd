class_name SimulationBootstrap
extends RefCounted
## Shared assembly for the observer and headless runs. Core defaults stay legacy.
const PROFILE_PATH := "res://config/simulation_profiles.json"
const WORLD_PATH := "res://data/demo_world/world_spec.json"
const SCENARIO_PATH := "res://data/scenarios/deserted_island_v2.json"

static func configure(sim: IslandSimulation, profile: String = "") -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("profiles")) != TYPE_DICTIONARY:
		return {"ok": false, "error": "INVALID_PROFILE_CONFIG"}
	if profile == "": profile = str(parsed.get("default_profile", ""))
	if not parsed["profiles"].has(profile):
		return {"ok": false, "error": "UNKNOWN_SIMULATION_PROFILE", "profile": profile}
	var config: Dictionary = parsed["profiles"][profile]
	if str(config.get("agency_mode", "")) not in ["OFF", "SHADOW", "LIVE_BRIDGE"]:
		return {"ok": false, "error": "INVALID_AGENCY_MODE"}
	if bool(config.get("plan_adoption", false)) and not bool(config.get("plan_execution", false)):
		return {"ok": false, "error": "ADOPTION_REQUIRES_EXECUTION"}
	if bool(config.get("information_subgoals", false)) and not bool(config.get("plan_execution", false)):
		return {"ok": false, "error": "INFORMATION_REQUIRES_EXECUTION"}
	if bool(config.get("material_requests", false)) and not bool(config.get("plan_execution", false)):
		return {"ok": false, "error": "MATERIAL_REQUESTS_REQUIRE_EXECUTION"}
	if (bool(config.get("plan_execution", false)) or bool(config.get("causal_step_value", false)) \
			or bool(config.get("information_subgoals", false)) or bool(config.get("material_requests", false))) \
			and str(config["agency_mode"]) != "LIVE_BRIDGE":
		return {"ok": false, "error": "EXECUTION_REQUIRES_LIVE_BRIDGE"}
	sim.agency_mode = str(config["agency_mode"])
	sim.agency_plan_execution_enabled = bool(config.get("plan_execution", false))
	sim.agency_causal_step_value_enabled = bool(config.get("causal_step_value", false))
	sim.agency_plan_adoption_enabled = bool(config.get("plan_adoption", false))
	sim.agency_information_subgoals_enabled = bool(config.get("information_subgoals", false))
	sim.agency_material_requests_enabled = bool(config.get("material_requests", false))
	return {"ok": true, "profile": profile, "config": config.duplicate(true)}

static func create(seed_value: int, profile: String = "") -> Dictionary:
	if seed_value < 0:
		return {"ok": false, "error": "INVALID_SEED"}
	var world_spec: Variant = JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	var defaults: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://config/runtime.defaults.json"))
	var scenario: Variant = JSON.parse_string(FileAccess.get_file_as_string(SCENARIO_PATH))
	if typeof(world_spec) != TYPE_DICTIONARY or typeof(defaults) != TYPE_DICTIONARY or typeof(scenario) != TYPE_DICTIONARY:
		return {"ok": false, "error": "INVALID_BOOTSTRAP_DATA"}
	var generated := MapGenerator.generate(world_spec, defaults.get("map", {}))
	if not generated.get("ok", false):
		return {"ok": false, "error": "MAP_GENERATION_FAILED", "detail": generated.get("message", "")}
	var map := HeadlessMapQuery.new(generated["data"])
	var actors: Array = []
	var spots := [map.get_poi_tile("post_house"), map.get_poi_tile("tide_market"), map.get_poi_tile("old_lighthouse")]
	for original in scenario.get("actors", []):
		var actor: Dictionary = original.duplicate(true)
		actor["spawn"] = spots[actors.size() % spots.size()]
		actors.append(actor)
	var sim := IslandSimulation.new(map, seed_value, actors)
	var configured := configure(sim, profile)
	if not configured["ok"]:
		return configured
	return {"ok": true, "sim": sim, "map_hash": (generated["data"] as GeneratedMap).map_hash,
		"profile": configured["profile"], "scenario_id": scenario.get("scenario_id", ""),
		"terrain_seed": world_spec.get("seed", -1), "simulation_seed": seed_value}
