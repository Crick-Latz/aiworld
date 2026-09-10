extends SceneTree
## P6.3B-2: an observed-disconfirmed resource target must stop the current
## physical attempt without consulting world truth or affecting another actor.

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool, info := "") -> void:
	if ok:
		passed += 1
		print("PASS " + label)
	else:
		failed += 1
		print("FAIL " + label + "  " + str(info))

func _run() -> void:
	var scene = load("res://scenes/observer/observer_main.tscn").instantiate()
	root.add_child(scene)
	for i in 20:
		await physics_frame
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	var mq = scene.get_node("World/MapController")
	var scenario: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://data/scenarios/deserted_island_v2.json"))
	var configs: Array = scenario["actors"].duplicate(true)
	var start: Vector2i = mq.get_poi_tile("post_house")
	for cfg in configs:
		cfg["spawn"] = start
	var target := _walkable_other(mq, start, 2)
	var alternate := _walkable_other(mq, target, 3, [start, target])
	var sim := IslandSimulation.new(mq, 62001, configs)
	var id: String = sim.actors.keys()[0]
	var actor: Dictionary = sim.actors[id]
	var belief: SpatialBeliefMap = actor["spatial"]

	var stale_action := ActionTargetContract.with_source({
		"action": "forage_berries", "target": target, "utility": 1.0,
		"desc": "去采浆果", "duration": 1,
	}, "berry_bushes")
	_check("unknown_is_not_disconfirmed",
		not ActionTargetContract.is_disconfirmed(stale_action, {}))
	_check("present_target_remains_valid",
		not ActionTargetContract.is_disconfirmed(stale_action, {"berry_bushes": [target]}))
	_check("observed_absence_disconfirms_target",
		ActionTargetContract.is_disconfirmed(stale_action, {"berry_bushes": [alternate]}))
	_check("actor_beliefs_are_isolated",
		ActionTargetContract.is_disconfirmed(stale_action, {"berry_bushes": [alternate]})
		and not ActionTargetContract.is_disconfirmed(stale_action, {"berry_bushes": [target]}))

	# The stale source is explicitly observed empty; another known bush remains.
	sim.world["berry_bushes"] = [
		{"pos": target, "food": 0, "regrow_day": 9},
		{"pos": alternate, "food": 2, "regrow_day": -1},
	]
	sim._flatten_resources()
	belief.observe_resource("berry", target, false, false, sim.tick)
	belief.observe_resource("berry", alternate, true, false, sim.tick)
	actor["tile"] = start
	actor["needs"]["hunger"] = 900
	# Attach this physical attempt to a real tracker run. A failed target must
	# consume the attempt but leave the plan able to retry another known source.
	sim.agency_mode = "LIVE_BRIDGE"
	sim.agency_plan_execution_enabled = true
	var plan := {"plan_id": "PLAN_HUNGER_REVALIDATE", "root_goal": "HUNGER", "status": "READY", "steps": [{
		"step_id": "MAIN:rule:berry_patch_food", "kind": "MAIN", "status": "PENDING",
		"action_name": "forage_berries", "item_id": "", "quantity": 0,
		"recipe_id": "", "capability": "", "requires": [], "provides": [],
		"knowledge_refs": [], "belief_refs": [], "description": "采集食物",
	}]}
	var tracker := sim._execution_tracker()
	var execution: Dictionary = tracker.prepare_decision(id, [plan], {
		"possessed_items": actor["inventory"], "possessed_capabilities": [],
	}, sim.tick)
	var identity: Dictionary = tracker.on_decision(id, stale_action, {
		"run_id": execution.get("run_id", ""), "step_id": (execution.get("step", {}) as Dictionary).get("step_id", ""),
		"candidate_key": AgencyActionBridge.candidate_key(stale_action), "selected": true,
	}, sim.tick)
	actor["_plan_exec_inflight"] = identity
	var original_run_id := str(execution.get("run_id", ""))
	(actor["intentions"] as IntentionManager).set_intention(stale_action, sim.tick)
	actor["current_action"] = stale_action.duplicate(true)
	actor["action_ticks_left"] = 1
	actor["action_travel_stall_ticks"] = 0
	var before_tile: Vector2i = actor["tile"]
	var before_food := int(actor["inventory"].get("food", 0))
	var event_start := sim.events.size()
	sim._tick_actor(id, actor, [])
	var segment: Array = sim.events.slice(event_start)
	_check("invalidated_attempt_cancelled",
		actor.get("current_action") == null and int(actor["action_ticks_left"]) == 0)
	_check("invalidated_attempt_stops_before_moving", actor["tile"] == before_tile)
	_check("invalidated_attempt_has_no_reward",
		int(actor["inventory"].get("food", 0)) == before_food
		and not segment.any(func(e): return str(e.get("type", "")) == "foraged"))
	_check("invalidated_attempt_emits_event",
		segment.any(func(e): return str(e.get("type", "")) == "action_target_invalidated"))
	var invalidated_events: Array = segment.filter(
		func(e): return str(e.get("type", "")) == "action_target_invalidated")
	var invalidated: Dictionary = invalidated_events[0] if not invalidated_events.is_empty() else {}
	_check("invalidated_event_is_grounded",
		str(invalidated.get("action", "")) == "forage_berries"
		and str(invalidated.get("target_source_key", "")) == "berry_bushes"
		and str(invalidated.get("target", "")) == str(target))
	_check("invalidated_attempt_clears_intention",
		not (actor["intentions"] as IntentionManager).has_intention())
	var failed_run: Dictionary = sim.agency_plan_run(id)
	_check("invalidated_attempt_consumes_pending_without_advancing",
		(failed_run.get("pending", {}) as Dictionary).is_empty()
		and str(failed_run.get("current_step_id", "")) == "MAIN:rule:berry_patch_food")
	_check("failed_target_keeps_same_plan_run_recoverable",
		str(failed_run.get("run_id", "")) == original_run_id
		and str(failed_run.get("state", "")) == "ACTIVE")

	# Existing decision machinery now sees only the alternate subjective source.
	sim._update_nearby_info()
	var actor_view: Dictionary = sim._build_actor_view(id, actor)
	var forage: Array = ActionRegistry.get_available_actions(actor_view, sim.world).filter(
		func(c): return str(c.get("action", "")) == "forage_berries")
	_check("registry_resource_actions_carry_source_metadata",
		forage.size() == 1
		and str((forage[0] as Dictionary).get(ActionTargetContract.SOURCE_KEY_FIELD, "")) == "berry_bushes")
	_check("next_candidate_uses_alternate_known_source",
		forage.size() == 1 and (forage[0] as Dictionary).get("target") == alternate,
		"target=%s alternate=%s" % [(forage[0] as Dictionary).get("target", null) if not forage.is_empty() else null, alternate])
	var retry: Dictionary = tracker.prepare_decision(id, [plan], {
		"possessed_items": actor["inventory"], "possessed_capabilities": [],
	}, sim.tick + 1)
	var retry_match := PlanStepActionAdapter.match_candidates(
		retry.get("step", {}), forage, AgencyContextBuilder.build(sim, actor),
		sim._recipe_catalog_if_any(), sim._item_catalog_if_any())
	_check("same_run_can_retry_alternate_source",
		str(retry.get("run_id", "")) == original_run_id
		and (retry_match.get("candidates", []) as Array).size() == 1
		and ((retry_match.get("candidates", []) as Array)[0] as Dictionary).get("target") == alternate)

	scene.queue_free()
	await process_frame
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)

func _walkable_other(mq, origin: Vector2i, radius: int, excluded: Array = []) -> Vector2i:
	for r in range(1, radius + 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var candidate := origin + Vector2i(dx, dy)
				if candidate == origin or excluded.has(candidate):
					continue
				if mq.is_walkable_tile(Vector3i(candidate.x, 0, candidate.y)):
					return candidate
	return origin
