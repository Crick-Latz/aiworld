extends SceneTree
## Execution-boundary contracts; no resource tuning or historical seed replacement.
var passed := 0
var failed := 0
var started := false

func _process(_delta: float) -> bool:
	if not started:
		started = true
		_run()
	return false

func _check(label: String, condition: bool) -> void:
	if condition: passed += 1; print("PASS " + label)
	else: failed += 1; print("FAIL " + label)

func _run() -> void:
	var manager := IntentionManager.new()
	var payload := {"action": "craft_fish_spear", "target": Vector2i(2, 3), "recipe_id": "recipe_spear",
		"target_actor": "peer", "duration": 4, "utility": 0.7, "desc": "craft", "evidence": {"ids": ["a"]}}
	manager.set_intention(payload, 11)
	_check("payload_duration", manager.current_intention.get("duration", -1) == 4)
	_check("payload_recipe", manager.current_intention.get("recipe_id", "") == "recipe_spear")
	_check("payload_target_actor", manager.current_intention.get("target_actor", "") == "peer")
	payload["evidence"]["ids"].append("outside")
	_check("payload_deep_copy", manager.current_intention.get("evidence", {}).get("ids", []) == ["a"])
	_check("commitment_metadata", manager.current_intention.get("started_tick") == 11 and manager.current_intention.get("commitment") == 0.8)
	var packed: PackedScene = load("res://scenes/observer/observer_main.tscn")
	var scene := packed.instantiate()
	root.add_child(scene)
	for i in 20: await physics_frame
	var mq = scene.get_node("World/MapController")
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var scenario: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var configs: Array = scenario["actors"].duplicate(true)
	for cfg in configs: cfg["spawn"] = mq.get_poi_tile("post_house")
	var sim := IslandSimulation.new(mq, 61000, configs)
	var id: String = sim.actors.keys()[0]
	var actor: Dictionary = sim.actors[id]
	actor["inventory"]["food"] = 0
	actor["inventory"]["wood"] = 1
	actor["inventory"]["shells"] = 1
	var view: Dictionary = sim._build_actor_view(id, actor)
	var intent: IntentionManager = view["intentions"]
	var unavailable_eat := true
	var fresh_invalid := true
	var legal_continues := 0
	var duration_ok := true
	var isolated := true
	var recipe_ok := true
	var target_ok := true
	var receiver_ok := true
	var available := ActionRegistry.get_available_actions(view, sim.world)
	var craft := {}
	for c in available:
		if c.has("recipe_id"): craft = c.duplicate(true)
	_check("craft_fixture_nonempty", not craft.is_empty())
	for seed in range(32):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		intent.set_intention({"action": "eat_food", "target": null, "utility": 2.0, "duration": 1}, 0)
		view["last_decision_trace"] = {"tick": -1}
		var chosen := DecisionEngine.decide(view, sim.world, rng)
		unavailable_eat = unavailable_eat and chosen["action"] != "eat_food"
		fresh_invalid = fresh_invalid and view["last_decision_trace"].get("tick", -1) == sim.world.get("tick", 0)
		var previous_energy = view["needs"]["energy"]
		view["needs"]["energy"] = 100
		intent.set_intention(ActionRegistry._rest(view["personality"], view["needs"]), 0)
		view["last_decision_trace"] = {"tick": -1}
		chosen = DecisionEngine.decide(view, sim.world, rng)
		if view["last_decision_trace"].get("tick", -1) == -1:
			legal_continues += 1
			duration_ok = duration_ok and chosen.get("duration", -1) == 3
			chosen["duration"] = 999
			isolated = isolated and intent.current_intention.get("duration", -1) == 3
		view["needs"]["energy"] = previous_energy
		if not craft.is_empty():
			var stale: Dictionary = craft.duplicate(true)
			stale["recipe_id"] = "unknown_recipe"
			stale["utility"] = 2.0
			intent.set_intention(stale, 0)
			view["last_decision_trace"] = {"tick": -1}
			chosen = DecisionEngine.decide(view, sim.world, rng)
			recipe_ok = recipe_ok and chosen.get("recipe_id", "") != "unknown_recipe" and view["last_decision_trace"].get("tick", -1) != -1
		intent.set_intention({"action": "rest", "target": Vector2i(-999, -999), "utility": 2.0, "duration": 3}, 0)
		chosen = DecisionEngine.decide(view, sim.world, rng)
		target_ok = target_ok and chosen.get("target") != Vector2i(-999, -999)
		intent.set_intention({"action": "rest", "target": null, "target_actor": "missing_peer", "utility": 2.0, "duration": 3}, 0)
		view["last_decision_trace"] = {"tick": -1}
		chosen = DecisionEngine.decide(view, sim.world, rng)
		receiver_ok = receiver_ok and chosen.get("target_actor", "") != "missing_peer" and view["last_decision_trace"].get("tick", -1) != -1
	_check("no_food_no_repeated_eat", unavailable_eat)
	_check("invalid_intention_fresh_trace", fresh_invalid)
	_check("valid_intention_still_persists", legal_continues > 0)
	_check("continued_duration_preserved", legal_continues > 0 and duration_ok)
	_check("returned_action_not_internal_alias", legal_continues > 0 and isolated)
	_check("recipe_identity_revalidated", not craft.is_empty() and recipe_ok)
	_check("target_identity_revalidated", target_ok)
	_check("receiver_identity_revalidated", receiver_ok)
	scene.queue_free()
	await process_frame
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
