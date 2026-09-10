extends "res://test/p1_5_cognition.gd"
## Diagnostic ONLY: replay legacy payload behavior in a test-local subclass.
## No production flag, no retuned seeds, and no replacement of regression gates.
class ProbeIntent extends IntentionManager:
	var legacy_payload := false
	func set_intention(action: Dictionary, at_tick: int) -> void:
		if not legacy_payload:
			super.set_intention(action, at_tick)
			return
		current_intention = {"action": str(action.get("action", "wait")), "desc": str(action.get("desc", "")),
			"target": action.get("target", null), "commitment": 0.8, "started_tick": at_tick,
			"utility": float(action.get("utility", 0.0))}
	func matching_candidate(_candidates: Array) -> Dictionary:
		return current_intention
	func continue_action(candidate: Dictionary) -> Dictionary:
		if not legacy_payload: return super.continue_action(candidate)
		reinforce()
		return current_intention

func _run() -> void:
	var mq = await _make_map()
	mq.get_parent().get_parent().process_mode = Node.PROCESS_MODE_DISABLED
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	for mode in ["legacy", "payload_only", "fixed"]:
		var cfg := _make_configs(mq, scenario, false)
		var scarce := IslandSimulation.new(mq, 777, cfg.duplicate(true))
		var rich := IslandSimulation.new(mq, 777, cfg.duplicate(true), {"berry_count": 6, "berry_food": 3,
			"berry_regrow_days": 2, "fish_prob": 0.8, "fish_amount": 2, "explore_food_prob": 0.08})
		var social := IslandSimulation.new(mq, 30014, _make_configs(mq, scenario, true))
		for sim in [scarce, rich, social]:
			if mode != "fixed":
				for id in sim.actors:
					var im := ProbeIntent.new()
					im.legacy_payload = mode == "legacy"
					sim.actors[id]["intentions"] = im
		for i in 1200: scarce.step()
		for i in 1200: rich.step()
		for i in 1500: social.step()
		var counts := {}
		for e in social.events:
			var event_type := str(e["type"])
			counts[event_type] = int(counts.get(event_type, 0)) + 1
		print("REGRESSION_PROBE " + JSON.stringify({"mode": mode, "tvd_seed777": _activity_distance(scarce, rich, "npc_oun"), "social_seed30014": counts}))
		await process_frame
	quit(0)
