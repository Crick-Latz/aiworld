extends SceneTree

const Bridge = preload("res://src/simulation/material_request/material_request_runtime_bridge.gd")
const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_review_fixes()
	_test_lifecycle_recovery()
	_test_counter_rejection_continues_holder_search()
	_test_request_from_blocker_and_subjective_target()
	_test_accept_refuse_counter_and_transfer()
	_test_runtime_island_wiring()
	_test_profiles_and_determinism()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _test_review_fixes() -> void:
	_check("relationship_signal_preserves_sign",
		is_equal_approx(Bridge.relationship_signal(-1000), -1.0)
		and is_equal_approx(Bridge.relationship_signal(0), 0.0)
		and is_equal_approx(Bridge.relationship_signal(1000), 1.0))
	_check("trust_probability_uses_probability_scale",
		is_equal_approx(Bridge.trust_probability(-1000), 0.0)
		and is_equal_approx(Bridge.trust_probability(0), 0.5)
		and is_equal_approx(Bridge.trust_probability(1000), 1.0))

	var bridge := Bridge.new(72001)
	var step := _craft_step(3)
	var run := _run_fixture("requester", "PLAN_HUNGER_fish_food")
	var first_gap := bridge.material_gap(step, run, {"possessed_items": {"shells": 1}}, _recipes())
	_check("craft_quantity_scales_requirement_before_gap",
		str(first_gap.get("item_id", "")) == "shells" and int(first_gap.get("quantity", 0)) == 2,
		str(first_gap))
	var items := ItemCatalog.load_default()
	var synthetic_recipes := RecipeCatalog.new(items)
	synthetic_recipes.recipes["synthetic_multi"] = {
		"recipe_id": "synthetic_multi",
		"ingredients": {"shells": 2},
		"outputs": {"fish_spear": 1},
		"required_capabilities": [],
		"duration_ticks": 1,
		"compat_action": "craft_fish_spear",
		"knowledge_refs": [],
	}
	var synthetic_step := PlanStepSpec.make(
		"CRAFT", "CRAFT:synthetic", "PENDING", "craft_fish_spear", "fish_spear",
		3, "synthetic_multi", "FISH", [], [], [], [], "synthetic"
	)
	var second_gap := bridge.material_gap(synthetic_step, run, {"possessed_items": {"shells": 1}}, synthetic_recipes)
	_check("craft_gap_handles_ingredient_greater_than_one",
		int(second_gap.get("quantity", 0)) == 5, str(second_gap))

	var hostile_view := _actor_view("requester", Vector2i(10, 10), "holder", Vector2i(11, 10))
	hostile_view["trust_of"]["holder"] = -1000
	(hostile_view["tom"] as TheoryOfMind).add_evidence("holder", Bridge.holder_predicate("shells"), 1.0, 1.0, -1, 1)
	var hostile_candidate: Dictionary = bridge.build_holder_beliefs("requester", "shells", hostile_view, 1)[0]
	_check("hostile_candidate_relationship_is_not_double_normalized",
		is_equal_approx(float(hostile_candidate.get("relationship", 99.0)), -1.0), str(hostile_candidate))
	var hostile_response := MaterialRequestResponsePolicy.new().evaluate(
		Contract.make_request("hostile", "requester", "shells", 1, "HUNGER", "plan", 0, 10),
		{
			"inventory_quantity": 1, "reserve_quantity": 0,
			"relationship": -1.0, "trust": 0.0, "generosity": 0.0,
			"own_need_pressure": 1.0, "risk_aversion": 1.0,
			"commitment_load": 1.0, "exchange_offer_value": 0.0,
		},
		0.5
	)
	_check("hostile_relationship_stays_hostile",
		str(hostile_response.get("outcome", "")) == Contract.OUTCOME_REFUSE
		and float(hostile_response.get("accept_probability", 1.0)) < 0.1, str(hostile_response))

	var stale_pair := _runtime_pair(72002)
	var stale_sim: IslandSimulation = stale_pair["sim"]
	var stale_requester: Dictionary = stale_pair["requester"]
	var stale_giver: Dictionary = stale_pair["giver"]
	var stale_step := _craft_step()
	var stale_run := _run_fixture(str(stale_pair["requester_id"]), "PLAN_HUNGER_fish_food")
	stale_run["run_id"] = str(stale_pair["requester_id"]) + "#old"
	stale_run["current_step_id"] = str(stale_step.get("step_id", ""))
	stale_run["steps"] = [stale_step]
	stale_sim._execution_tracker().runs[str(stale_pair["requester_id"])] = stale_run
	var stale_opened := stale_sim._material_request_runtime_bridge().ensure_request_for_blocker(
		str(stale_pair["requester_id"]), stale_run, stale_step,
		AgencyContextBuilder.build(stale_sim, stale_requester), 1, _recipes(), 0.8)
	var stale_request_id := str(stale_opened.get("request", {}).get("request_id", ""))
	var stale_view := stale_sim._build_actor_view(str(stale_pair["requester_id"]), stale_requester)
	stale_sim._material_request_runtime_bridge().try_offer(stale_request_id,
		stale_sim._material_request_runtime_bridge().build_holder_beliefs(
			str(stale_pair["requester_id"]), "shells", stale_view, 2), 2)
	stale_sim._material_request_runtime_bridge().respond(
		stale_request_id, str(stale_pair["giver_id"]), _generous_context(2), 3)
	var run_b := stale_run.duplicate(true)
	run_b["run_id"] = str(stale_pair["requester_id"]) + "#new"
	stale_sim._execution_tracker().runs[str(stale_pair["requester_id"])] = run_b
	var stale_giver_before := int(stale_giver["inventory"].get("shells", 0))
	var stale_requester_before := int(stale_requester["inventory"].get("shells", 0))
	stale_sim._material_requests_process_actor(str(stale_pair["requester_id"]), stale_requester, [])
	_check("stale_parent_run_cannot_transfer",
		str(stale_sim.agency_material_request(stale_request_id).get("status", "")) == Contract.STATUS_FAILED
		and int(stale_giver["inventory"].get("shells", 0)) == stale_giver_before
		and int(stale_requester["inventory"].get("shells", 0)) == stale_requester_before
		and stale_sim._material_request_runtime_bridge().pending_requests_for(
			str(stale_pair["requester_id"])).is_empty(),
		str(stale_sim.agency_material_request(stale_request_id)))

	var fulfilled_pair := _runtime_pair(72003)
	var fulfilled_sim: IslandSimulation = fulfilled_pair["sim"]
	var fulfilled_requester: Dictionary = fulfilled_pair["requester"]
	var fulfilled_giver: Dictionary = fulfilled_pair["giver"]
	var fulfilled_run := _run_fixture(str(fulfilled_pair["requester_id"]), "PLAN_HUNGER_fish_food")
	fulfilled_run["run_id"] = str(fulfilled_pair["requester_id"]) + "#fulfilled"
	fulfilled_sim._execution_tracker().runs[str(fulfilled_pair["requester_id"])] = fulfilled_run
	var fulfilled_opened := fulfilled_sim._material_request_runtime_bridge().ensure_request_for_blocker(
		str(fulfilled_pair["requester_id"]), fulfilled_run, _craft_step(),
		AgencyContextBuilder.build(fulfilled_sim, fulfilled_requester), 1, _recipes(), 0.8)
	var fulfilled_id := str(fulfilled_opened.get("request", {}).get("request_id", ""))
	var fulfilled_beliefs := fulfilled_sim._material_request_runtime_bridge().build_holder_beliefs(
		str(fulfilled_pair["requester_id"]), "shells",
		fulfilled_sim._build_actor_view(str(fulfilled_pair["requester_id"]), fulfilled_requester), 2)
	fulfilled_sim._material_request_runtime_bridge().try_offer(fulfilled_id, fulfilled_beliefs, 2)
	fulfilled_sim._material_request_runtime_bridge().respond(
		fulfilled_id, str(fulfilled_pair["giver_id"]), _generous_context(2), 3)
	fulfilled_requester["inventory"]["shells"] = 1
	var fulfilled_giver_before := int(fulfilled_giver["inventory"].get("shells", 0))
	fulfilled_sim._material_requests_process_actor(str(fulfilled_pair["requester_id"]), fulfilled_requester, [])
	_check("transfer_cancels_when_material_no_longer_needed",
		str(fulfilled_sim.agency_material_request(fulfilled_id).get("status", "")) == Contract.STATUS_CANCELLED
		and int(fulfilled_giver["inventory"].get("shells", 0)) == fulfilled_giver_before,
		str(fulfilled_sim.agency_material_request(fulfilled_id)))

	var conditional_pair := _runtime_pair(72004)
	var conditional_sim: IslandSimulation = conditional_pair["sim"]
	var conditional_requester: Dictionary = conditional_pair["requester"]
	var conditional_run := _run_fixture(str(conditional_pair["requester_id"]), "PLAN_HUNGER_fish_food")
	conditional_run["run_id"] = str(conditional_pair["requester_id"]) + "#conditional"
	conditional_sim._execution_tracker().runs[str(conditional_pair["requester_id"])] = conditional_run
	var conditional_opened := conditional_sim._material_request_runtime_bridge().ensure_request_for_blocker(
		str(conditional_pair["requester_id"]), conditional_run, _craft_step(2),
		{"possessed_items": {}}, 1, _recipes(), 0.8)
	var conditional_id := str(conditional_opened.get("request", {}).get("request_id", ""))
	var conditional_request: Dictionary = conditional_sim._material_request_runtime_bridge().coordinator.tracker._requests[conditional_id]
	conditional_request["status"] = Contract.STATUS_WAITING_REQUESTER
	conditional_request["accepted_quantity"] = 1
	conditional_request["last_counter"] = {"quantity": 1, "requires_exchange": true}
	var conditional_before := int(conditional_requester["inventory"].get("shells", 0))
	conditional_sim._material_requests_process_actor(
		str(conditional_pair["requester_id"]), conditional_requester, [])
	_check("conditional_counter_rejection_keeps_request_active",
		str(conditional_sim.agency_material_request(conditional_id).get("status", "")) == Contract.STATUS_ACTIVE
		and int(conditional_requester["inventory"].get("shells", 0)) == conditional_before,
		str(conditional_sim.agency_material_request(conditional_id)))

	var active_pair := _runtime_pair(72005)
	var active_sim: IslandSimulation = active_pair["sim"]
	var active_requester: Dictionary = active_pair["requester"]
	active_pair["requester"]["inventory"] = {"wood": 0}
	active_pair["giver"]["inventory"] = {"wood": 2}
	var active_step := PlanStepSpec.make(
		"ACQUIRE", "ACQUIRE:wood", "PENDING", "", "wood", 2, "", "",
		[], [], [], [], "acquire wood"
	)
	var active_run := _run_fixture(str(active_pair["requester_id"]), "PLAN_HUNGER_wood")
	active_run["run_id"] = str(active_pair["requester_id"]) + "#active"
	active_run["current_step_id"] = str(active_step.get("step_id", ""))
	active_run["steps"] = [active_step]
	active_run["state"] = "ACTIVE"
	active_sim._execution_tracker().runs[str(active_pair["requester_id"])] = active_run
	var active_opened := active_sim._material_request_runtime_bridge().ensure_request_for_blocker(
		str(active_pair["requester_id"]), active_run, active_step,
		{"possessed_items": {}}, 1, _recipes(), 0.8)
	var active_id := str(active_opened.get("request", {}).get("request_id", ""))
	var active_request: Dictionary = active_sim._material_request_runtime_bridge().coordinator.tracker._requests[active_id]
	active_request["status"] = Contract.STATUS_WAITING_REQUESTER
	active_request["target_id"] = str(active_pair["giver_id"])
	active_request["accepted_quantity"] = 1
	active_request["last_counter"] = {"quantity": 1, "requires_exchange": false}
	active_sim._material_requests_process_actor(str(active_pair["requester_id"]), active_requester, [])
	_check("active_acquire_counter_can_transfer",
		int(active_requester["inventory"].get("wood", 0)) == 1
		and int(active_pair["giver"]["inventory"].get("wood", 0)) == 1,
		str(active_sim.agency_material_request(active_id)))

	var expiry_bridge := Bridge.new(72006)
	var expiry_id := _open_and_offer(expiry_bridge, "expiry", 1, "holder", 1)
	expiry_bridge.respond(expiry_id, "holder", _generous_context(1), 20)
	expiry_bridge.coordinator.tracker._requests[expiry_id]["expires_tick"] = 25
	var expiry_giver := {"shells": 1}
	var expiry_receiver := {"shells": 0}
	var at_expiry := expiry_bridge.transfer(expiry_id, expiry_giver, expiry_receiver, 25)
	_check("transfer_at_expiry_tick_still_valid",
		bool(at_expiry.get("ok", false)) and int(expiry_receiver.get("shells", 0)) == 1, str(at_expiry))
	var expired_id := _open_and_offer(expiry_bridge, "expired", 1, "holder", 1)
	expiry_bridge.respond(expired_id, "holder", _generous_context(1), 20)
	expiry_bridge.coordinator.tracker._requests[expired_id]["expires_tick"] = 25
	var expired_giver := {"shells": 1}
	var expired_receiver := {"shells": 0}
	var after_expiry := expiry_bridge.transfer(expired_id, expired_giver, expired_receiver, 26)
	_check("transfer_after_expiry_fails_without_mutation",
		not bool(after_expiry.get("ok", true))
		and str(after_expiry.get("reason", "")) == "REQUEST_EXPIRED"
		and int(expired_giver.get("shells", 0)) == 1
		and int(expired_receiver.get("shells", 0)) == 0, str(after_expiry))

	var event_pair := _runtime_pair(72007)
	var event_sim: IslandSimulation = event_pair["sim"]
	var event_requester_id := str(event_pair["requester_id"])
	var event_run := _run_fixture(event_requester_id, "PLAN_HUNGER_fish_food")
	event_run["run_id"] = event_requester_id + "#event"
	event_run["state"] = "ACTIVE"
	event_sim._execution_tracker().runs[event_requester_id] = event_run
	var event_request := {
		"request_id": "event-request", "requester_id": event_requester_id,
		"parent_plan_id": "PLAN_HUNGER_fish_food", "parent_run_id": event_run["run_id"],
		"blocker_step_id": event_run["current_step_id"], "item_id": "shells",
		"requested_quantity": 1, "accepted_quantity": 1, "target_id": str(event_pair["giver_id"]),
	}
	var event_before := _count_events(event_sim.events, "PARENT_PLAN_REVALIDATION_REQUESTED")
	event_sim._material_requests_handle_revalidation({
		"request": event_request,
		"revalidation": {"transfer_event_id": "transfer:event"},
	})
	_check("revalidation_event_not_emitted_without_token",
		_count_events(event_sim.events, "PARENT_PLAN_REVALIDATION_REQUESTED") == event_before)

func _test_lifecycle_recovery() -> void:
	var expiry := _open_runtime_request(72010, 3, "expiry")
	var expiry_sim: IslandSimulation = expiry["sim"]
	var expiry_bridge = expiry_sim._material_request_runtime_bridge()
	var expiry_old_id := str(expiry["request_id"])
	expiry_sim.tick = 50
	expiry_bridge.coordinator.tracker._requests[expiry_old_id]["expires_tick"] = 40
	expiry_sim._material_requests_expire_due()
	expiry_sim._material_requests_process_actor(
		str(expiry["requester_id"]), expiry["requester"], [])
	var expiry_pending: Array = expiry_bridge.pending_requests_for(str(expiry["requester_id"]))
	var expiry_new: Dictionary = expiry_pending[0] if expiry_pending.size() == 1 else {}
	_check("expired_craft_request_is_recreated",
		str(expiry_bridge.request(expiry_old_id).get("status", "")) == Contract.STATUS_EXPIRED
		and str(expiry_new.get("request_id", "")) != expiry_old_id
		and str(expiry_new.get("parent_run_id", "")) == str(expiry["run"].get("run_id", ""))
		and str(expiry_new.get("blocker_step_id", "")) == str(expiry["step"].get("step_id", ""))
		and int(expiry_new.get("requested_quantity", 0)) == 3
		and str(expiry_new.get("retry_of_request_id", "")) == expiry_old_id
		and str(expiry_new.get("retry_reason", "")) == "REQUEST_EXPIRED",
		"old=%s new=%s" % [str(expiry_bridge.request(expiry_old_id)), str(expiry_new)])
	_check("expired_request_world_event_keeps_execution_identity",
		_event_has_identity(expiry_sim.events, "MATERIAL_REQUEST_EXPIRED", expiry_old_id,
			str(expiry["run"].get("run_id", "")), str(expiry["step"].get("step_id", "")), "MATERIALS_MISSING"))
	_check("expired_request_trace_keeps_execution_identity",
		_traces_have_identity(expiry_bridge, expiry_old_id,
			["MATERIAL_REQUEST_CREATED", "MATERIAL_REQUEST_EXPIRED"],
			str(expiry["run"].get("run_id", "")), str(expiry["step"].get("step_id", "")), "MATERIALS_MISSING"))

	var missing := _open_runtime_request(72011, 2, "missing")
	var missing_sim: IslandSimulation = missing["sim"]
	var missing_bridge = missing_sim._material_request_runtime_bridge()
	var missing_old_id := str(missing["request_id"])
	var missing_giver: Dictionary = missing["giver"]
	_set_runtime_waiting_transfer(missing, 2)
	missing_sim.tick = 3
	missing_sim.actors.erase(str(missing["giver_id"]))
	missing_sim._material_requests_process_actor(
		str(missing["requester_id"]), missing["requester"], [])
	var missing_pending: Array = missing_bridge.pending_requests_for(str(missing["requester_id"]))
	var missing_new: Dictionary = missing_pending[0] if missing_pending.size() == 1 else {}
	_check("missing_target_recreates_request_without_inventory_mutation",
		str(missing_bridge.request(missing_old_id).get("status", "")) == Contract.STATUS_FAILED
		and str(missing_bridge.request(missing_old_id).get("response_reason", "")) == "TARGET_MISSING"
		and str(missing_new.get("request_id", "")) != missing_old_id
		and int(missing_new.get("requested_quantity", 0)) == 2
		and int(missing_giver["inventory"].get("shells", 0)) == 2
		and int(missing["requester"]["inventory"].get("shells", 0)) == 0,
		"old=%s new=%s" % [str(missing_bridge.request(missing_old_id)), str(missing_new)])
	_check("failed_request_trace_keeps_execution_identity",
		_traces_have_identity(missing_bridge, missing_old_id,
			["MATERIAL_REQUEST_CREATED", "MATERIAL_REQUEST_FAILED"],
			str(missing["run"].get("run_id", "")), str(missing["step"].get("step_id", "")), "MATERIALS_MISSING"))

	var inventory := _open_runtime_request(72012, 2, "inventory")
	var inventory_sim: IslandSimulation = inventory["sim"]
	var inventory_bridge = inventory_sim._material_request_runtime_bridge()
	var inventory_old_id := str(inventory["request_id"])
	_set_runtime_waiting_transfer(inventory, 2)
	inventory_sim.tick = 4
	inventory["giver"]["inventory"]["shells"] = 0
	inventory_sim._material_requests_process_actor(
		str(inventory["requester_id"]), inventory["requester"], [])
	var inventory_pending: Array = inventory_bridge.pending_requests_for(str(inventory["requester_id"]))
	var inventory_new: Dictionary = inventory_pending[0] if inventory_pending.size() == 1 else {}
	_check("inventory_changed_recreates_request_from_current_gap",
		str(inventory_bridge.request(inventory_old_id).get("status", "")) == Contract.STATUS_FAILED
		and str(inventory_bridge.request(inventory_old_id).get("response_reason", "")) == "GIVER_INVENTORY_CHANGED"
		and str(inventory_new.get("request_id", "")) != inventory_old_id
		and int(inventory_new.get("requested_quantity", 0)) == 2
		and int(inventory["giver"]["inventory"].get("shells", 0)) == 0
		and int(inventory["requester"]["inventory"].get("shells", 0)) == 0,
		"old=%s new=%s" % [str(inventory_bridge.request(inventory_old_id)), str(inventory_new)])
	_check("inventory_failure_trace_keeps_execution_identity",
		_traces_have_identity(inventory_bridge, inventory_old_id,
			["MATERIAL_REQUEST_CREATED", "MATERIAL_TRANSFER_FAILED"],
			str(inventory["run"].get("run_id", "")), str(inventory["step"].get("step_id", "")), "MATERIALS_MISSING"))

	var stale := _open_runtime_request(72013, 3, "stale")
	var stale_sim: IslandSimulation = stale["sim"]
	var stale_bridge = stale_sim._material_request_runtime_bridge()
	var stale_old_id := str(stale["request_id"])
	_set_runtime_waiting_counter(stale, 3)
	stale_sim.tick = 5
	stale["requester"]["inventory"]["shells"] = 2
	stale_sim._material_requests_process_actor(
		str(stale["requester_id"]), stale["requester"], [])
	var stale_pending: Array = stale_bridge.pending_requests_for(str(stale["requester_id"]))
	var stale_new: Dictionary = stale_pending[0] if stale_pending.size() == 1 else {}
	_check("stale_accepted_quantity_recreates_request_for_current_gap",
		str(stale_bridge.request(stale_old_id).get("status", "")) == Contract.STATUS_CANCELLED
		and str(stale_bridge.request(stale_old_id).get("response_reason", "")) == "REQUEST_QUANTITY_STALE"
		and str(stale_new.get("request_id", "")) != stale_old_id
		and int(stale_new.get("requested_quantity", 0)) == 1
		and int(stale["requester"]["inventory"].get("shells", 0)) == 2,
		"old=%s new=%s" % [str(stale_bridge.request(stale_old_id)), str(stale_new)])
	_check("stale_request_trace_keeps_execution_identity",
		_traces_have_identity(stale_bridge, stale_old_id,
			["MATERIAL_REQUEST_CREATED", "MATERIAL_REQUEST_CANCELLED"],
			str(stale["run"].get("run_id", "")), str(stale["step"].get("step_id", "")), "MATERIALS_MISSING"))

	var fulfilled := _open_runtime_request(72014, 2, "fulfilled")
	var fulfilled_sim: IslandSimulation = fulfilled["sim"]
	var fulfilled_bridge = fulfilled_sim._material_request_runtime_bridge()
	var fulfilled_old_id := str(fulfilled["request_id"])
	_set_runtime_waiting_transfer(fulfilled, 2)
	fulfilled["requester"]["inventory"]["wood"] = 2
	fulfilled["requester"]["inventory"]["shells"] = 2
	fulfilled_sim._material_requests_process_actor(
		str(fulfilled["requester_id"]), fulfilled["requester"], [])
	_check("no_longer_needed_does_not_recreate_request",
		str(fulfilled_bridge.request(fulfilled_old_id).get("status", "")) == Contract.STATUS_CANCELLED
		and str(fulfilled_bridge.request(fulfilled_old_id).get("response_reason", "")) == "NO_LONGER_NEEDED"
		and fulfilled_bridge.pending_requests_for(str(fulfilled["requester_id"])).is_empty(),
		str(fulfilled_bridge.pending_requests_for(str(fulfilled["requester_id"]))))

func _test_counter_rejection_continues_holder_search() -> void:
	var triple := _runtime_triple(72015)
	var sim: IslandSimulation = triple["sim"]
	var requester_id := str(triple["requester_id"])
	var first_holder := str(triple["giver_id"])
	var second_holder := str(triple["third_id"])
	var step := _craft_step()
	var run := _run_fixture(requester_id, "PLAN_HUNGER_fish_food")
	run["run_id"] = requester_id + "#counter-reject"
	run["current_step_id"] = str(step.get("step_id", ""))
	run["steps"] = [step]
	run["state"] = "BLOCKED"
	sim._execution_tracker().runs[requester_id] = run
	var opened := sim._material_request_runtime_bridge().ensure_request_for_blocker(
		requester_id, run, step, AgencyContextBuilder.build(sim, triple["requester"]),
		sim.tick, _recipes(), 0.8, "MATERIALS_MISSING")
	var request_id := str(opened.get("request", {}).get("request_id", ""))
	var request: Dictionary = sim._material_request_runtime_bridge().coordinator.tracker._requests[request_id]
	request["status"] = Contract.STATUS_WAITING_REQUESTER
	request["target_id"] = first_holder
	request["accepted_quantity"] = 1
	request["last_counter"] = {"quantity": 1, "requires_exchange": true}
	sim._material_requests_process_actor(requester_id, triple["requester"], [])
	var rejected: Dictionary = sim.agency_material_request(request_id)
	_check("counter_rejection_keeps_same_request_active",
		str(rejected.get("status", "")) == Contract.STATUS_ACTIVE
		and int(rejected.get("accepted_quantity", -1)) == 0
		and str(rejected.get("response_outcome", "")) == Contract.OUTCOME_COUNTER_REJECTED
		and _has_event(sim.events, "MATERIAL_COUNTER_REJECTED"), str(rejected))
	_check("counter_rejection_preserves_rejected_counter_history",
		_history_has_counter_rejection(rejected, first_holder), str(rejected.get("history", [])))
	sim._material_requests_process_actor(requester_id, triple["requester"], [])
	var next_offer: Dictionary = sim.agency_material_request(request_id)
	_check("rejected_counter_holder_is_excluded_from_next_offer",
		str(next_offer.get("status", "")) == Contract.STATUS_WAITING_RESPONSE
		and str(next_offer.get("target_id", "")) == second_holder
		and str(next_offer.get("target_id", "")) != first_holder, str(next_offer))

func _test_request_from_blocker_and_subjective_target() -> void:
	var bridge := Bridge.new(71001)
	var step := _craft_step()
	var run := _run_fixture("requester", "PLAN_HUNGER_fish_food")
	var ctx := {"possessed_items": {"wood": 1}}
	var first := bridge.ensure_request_for_blocker("requester", run, step, ctx, 10, _recipes(), 0.8)
	_check("runtime_blocker_creates_request", bool(first.get("created", false)), str(first))
	var request: Dictionary = first.get("request", {})
	_check("request_uses_real_material_gap", str(request.get("item_id", "")) == "shells"
		and int(request.get("requested_quantity", 0)) == 1, str(request))
	var request_id := str(request.get("request_id", ""))
	var repeated := bridge.ensure_request_for_blocker("requester", run, step, ctx, 11, _recipes(), 0.8)
	_check("active_blocker_does_not_duplicate_request", not bool(repeated.get("created", true))
		and str(repeated.get("request", {}).get("request_id", "")) == request_id, str(repeated))

	var view := _actor_view("requester", Vector2i(10, 10), "holder", Vector2i(11, 10))
	var unknown := bridge.build_holder_beliefs("requester", "shells", view, 12)
	_check("unknown_holder_is_not_selectable", unknown.is_empty(), str(unknown))
	(view["tom"] as TheoryOfMind).add_evidence("holder", Bridge.holder_predicate("shells"), 1.0, 1.0, -1, 12)
	var known := bridge.build_holder_beliefs("requester", "shells", view, 13)
	_check("visible_known_holder_is_selectable", known.size() == 1
		and str(known[0].get("actor_id", "")) == "holder", str(known))
	var hidden_view := _actor_view("requester", Vector2i(10, 10), "", Vector2i.ZERO)
	hidden_view["tom"] = view["tom"]
	_check("known_but_unseen_holder_is_not_selectable",
		bridge.build_holder_beliefs("requester", "shells", hidden_view, 13).is_empty())
	var offered := bridge.try_offer(request_id, known, 14)
	_check("subjective_holder_receives_offer", bool(offered.get("ok", false))
		and str(offered.get("request", {}).get("status", "")) == Contract.STATUS_WAITING_RESPONSE, str(offered))

func _test_accept_refuse_counter_and_transfer() -> void:
	var accept_bridge := Bridge.new(71002)
	var accept_id := _open_and_offer(accept_bridge, "req-accept", 2, "holder", 2)
	var giver := {"shells": 2}
	var receiver := {"shells": 0}
	var accepted := accept_bridge.respond(accept_id, "holder", _generous_context(2), 20)
	_check("accept_is_social_only", bool(accepted.get("ok", false))
		and str(accepted.get("request", {}).get("status", "")) == Contract.STATUS_WAITING_TRANSFER
		and int(giver.get("shells", 0)) == 2, str(accepted))
	var unrelated := {
		"event_id": "unrelated",
		"type": Contract.EVENT_ITEM_TRANSFER_COMPLETED,
		"request_id": "other",
		"from_actor_id": "holder",
		"to_actor_id": "requester",
		"item_id": "shells",
		"quantity": 2,
		"evidence_kind": "WORLD_MUTATION",
	}
	_check("unrelated_transfer_evidence_rejected",
		not accept_bridge.coordinator.tracker.record_transfer_evidence(accept_id, unrelated, 21))
	var completed := accept_bridge.transfer(accept_id, giver, receiver, 22)
	_check("matching_transfer_mutates_once", bool(completed.get("ok", false))
		and int(giver.get("shells", 0)) == 0 and int(receiver.get("shells", 0)) == 2, str(completed))
	_check("matching_transfer_grants_revalidation",
		not Dictionary(completed.get("revalidation", {})).is_empty(), str(completed))
	_check("duplicate_transfer_evidence_rejected",
		not accept_bridge.coordinator.tracker.record_transfer_evidence(
			accept_id, completed.get("event", {}), 23))

	var refuse_bridge := Bridge.new(71003)
	var refuse_id := _open_and_offer(refuse_bridge, "req-refuse", 1, "holder", 1)
	var refused := refuse_bridge.respond(refuse_id, "holder", {
		"inventory_quantity": 0, "reserve_quantity": 0,
		"relationship": 0.5, "trust": 0.5, "generosity": 0.5,
		"own_need_pressure": 0.5, "risk_aversion": 0.5, "commitment_load": 0.0,
	}, 20)
	_check("refusal_does_not_forge_completion", bool(refused.get("ok", false))
		and str(refused.get("request", {}).get("status", "")) == Contract.STATUS_ACTIVE
		and int(refused.get("request", {}).get("accepted_quantity", 0)) == 0, str(refused))

	var counter_bridge := Bridge.new(71004)
	var counter_id := _open_and_offer(counter_bridge, "req-counter", 3, "holder", 3)
	var counter := counter_bridge.respond(counter_id, "holder", _generous_context(1), 20)
	_check("partial_surplus_enters_counter", bool(counter.get("ok", false))
		and str(counter.get("response", {}).get("outcome", "")) == Contract.OUTCOME_COUNTER
		and str(counter.get("request", {}).get("status", "")) == Contract.STATUS_WAITING_REQUESTER, str(counter))
	var counter_accepted := counter_bridge.accept_counter(counter_id, 21)
	_check("requester_can_accept_counter", bool(counter_accepted.get("ok", false))
		and str(counter_accepted.get("request", {}).get("status", "")) == Contract.STATUS_WAITING_TRANSFER, str(counter_accepted))
	var counter_giver := {"shells": 1}
	var counter_receiver := {"shells": 0}
	var partial := counter_bridge.transfer(counter_id, counter_giver, counter_receiver, 22)
	_check("accepted_counter_transfers_real_quantity", bool(partial.get("ok", false))
		and int(counter_giver.get("shells", 0)) == 0 and int(counter_receiver.get("shells", 0)) == 1, str(partial))

	var changed_bridge := Bridge.new(71005)
	var changed_id := _open_and_offer(changed_bridge, "req-changed", 2, "holder", 2)
	changed_bridge.respond(changed_id, "holder", _generous_context(2), 20)
	var changed_giver := {"shells": 0}
	var changed_receiver := {"shells": 0}
	var changed := changed_bridge.transfer(changed_id, changed_giver, changed_receiver, 21)
	_check("inventory_revalidation_blocks_stale_promise", not bool(changed.get("ok", true))
		and int(changed_giver.get("shells", 0)) == 0 and int(changed_receiver.get("shells", 0)) == 0, str(changed))
	_check("failed_transfer_is_terminal", str(changed.get("request", {}).get("status", "")) == Contract.STATUS_FAILED, str(changed))

	var expire_bridge := Bridge.new(71006)
	var expire_id := _open_and_offer(expire_bridge, "req-expire", 1, "holder", 1)
	expire_bridge.coordinator.tracker._requests[expire_id]["expires_tick"] = 25
	_check("active_request_expires", expire_bridge.expire_due(25).is_empty()
		and expire_bridge.expire_due(26).size() == 1
		and str(expire_bridge.request(expire_id).get("status", "")) == Contract.STATUS_EXPIRED)
	var missing_bridge := Bridge.new(71007)
	var missing_id := _open_and_offer(missing_bridge, "req-missing", 1, "holder", 1)
	_check("missing_target_fails_safely",
		missing_bridge.fail_request(missing_id, 30, "TARGET_MISSING")
		and str(missing_bridge.request(missing_id).get("status", "")) == Contract.STATUS_FAILED)

func _test_runtime_island_wiring() -> void:
	var created := SimulationBootstrap.create(71010, "material_request")
	_check("material_profile_bootstraps", bool(created.get("ok", false)), str(created))
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var giver_id := str(ids[1])
	sim.actors.erase(str(ids[2]))
	var requester: Dictionary = sim.actors[requester_id]
	var giver: Dictionary = sim.actors[giver_id]
	requester["tile"] = Vector2i(10, 10)
	giver["tile"] = Vector2i(11, 10)
	requester["inventory"] = {"wood": 1}
	giver["inventory"] = {"shells": 2}
	giver["personality"] = PersonalityProfile.new({"altruism": 1.0, "empathy": 1.0, "caution": 0.0}, {})
	sim.relationships.adjust(giver_id, requester_id, "benevolence", 1000)
	sim.relationships.adjust(giver_id, requester_id, "reliability", 1000)
	sim.relationships.adjust(giver_id, requester_id, "obligation", 1000)
	(requester["tom"] as TheoryOfMind).add_evidence(
		giver_id, Bridge.holder_predicate("shells"), 1.0, 1.0, -1, sim.tick)

	var step := _craft_step()
	var run := _run_fixture(requester_id, "PLAN_HUNGER_fish_food")
	run["run_id"] = requester_id + "#1"
	run["current_step_id"] = str(step.get("step_id", ""))
	run["steps"] = [step]
	sim._execution_tracker().runs[requester_id] = run
	var execution_receipt := {
		"actor_id": requester_id,
		"decision_tick": sim.tick,
		"run_id": run["run_id"],
		"step_id": run["current_step_id"],
		"selected": false,
		"candidate_key": "",
		"chosen_key": AgencyActionBridge.candidate_key({"action": "do_nothing"}),
		"selection_mode": "SOFTMAX",
		"blocker_reason": "MATERIALS_MISSING",
	}
	requester["_execution_receipt"] = execution_receipt
	var ctx := AgencyContextBuilder.build(sim, requester)
	sim._plan_execution_on_decision(
		requester_id,
		requester,
		{"action": "do_nothing", "target": null},
		{"ctx": ctx, "catalog": sim._recipe_catalog_if_any()}
	)
	var pending := sim._material_request_runtime_bridge().pending_requests_for(requester_id)
	_check("runtime_decision_creates_one_material_request", pending.size() == 1
		and str(pending[0].get("item_id", "")) == "shells", str(pending))
	var before_id := str(pending[0].get("request_id", ""))
	_check("runtime_request_separates_blocker_reason_and_step_kind",
		str(pending[0].get("blocker_reason", "")) == "MATERIALS_MISSING"
		and str(pending[0].get("blocker_step_kind", "")) == "CRAFT", str(pending[0]))
	sim._material_requests_on_blocker(requester_id, requester, execution_receipt, {
		"ctx": ctx, "catalog": sim._recipe_catalog_if_any(),
	})
	_check("runtime_blocker_mapping_prevents_duplicate",
		sim._material_request_runtime_bridge().pending_requests_for(requester_id).size() == 1,
		str(sim._material_request_runtime_bridge().pending_requests_for(requester_id)))

	sim._material_requests_process_actor(requester_id, requester, [])
	_check("runtime_offer_targets_subjective_visible_holder",
		str(sim.agency_material_request(before_id).get("status", "")) == Contract.STATUS_WAITING_RESPONSE
		and str(sim.agency_material_request(before_id).get("target_id", "")) == giver_id,
		str(sim.agency_material_request(before_id)))
	var forced_rng := RandomNumberGenerator.new()
	forced_rng.seed = 1
	sim._material_request_runtime_bridge()._rngs[giver_id] = forced_rng
	sim._material_requests_process_actor(giver_id, giver, [])
	var resolved := sim.agency_material_request(before_id)
	_check("runtime_chain_transfers_real_inventory",
		str(resolved.get("status", "")) == Contract.STATUS_RESOLVED
		and int(requester["inventory"].get("shells", 0)) == 1
		and int(giver["inventory"].get("shells", 0)) == 1, str(resolved))
	_check("runtime_chain_emits_auditable_events",
		_has_event(sim.events, "MATERIAL_REQUEST_CREATED")
		and _has_event(sim.events, "MATERIAL_REQUEST_OFFERED")
		and _has_event(sim.events, "MATERIAL_REQUEST_ACCEPTED")
		and _has_event(sim.events, Contract.EVENT_ITEM_TRANSFER_COMPLETED)
		and _has_event(sim.events, "MATERIAL_REQUEST_RESOLVED")
		and _has_event(sim.events, "PARENT_PLAN_REVALIDATION_REQUESTED"))
	_check("runtime_chain_events_keep_execution_identity",
		_event_has_identity(sim.events, "MATERIAL_REQUEST_CREATED", before_id,
			str(run.get("run_id", "")), str(step.get("step_id", "")), "MATERIALS_MISSING")
		and _event_has_identity(sim.events, "MATERIAL_REQUEST_RESOLVED", before_id,
			str(run.get("run_id", "")), str(step.get("step_id", "")), "MATERIALS_MISSING")
		and _event_has_request_id(sim.events, Contract.EVENT_ITEM_TRANSFER_COMPLETED, before_id),
		str(sim.events))
	_check("runtime_chain_trace_keeps_execution_identity",
		_traces_have_identity(sim._material_request_runtime_bridge(), before_id,
			["MATERIAL_REQUEST_CREATED", "MATERIAL_REQUEST_RESOLVED"],
			str(run.get("run_id", "")), str(step.get("step_id", "")), "MATERIALS_MISSING"))
	var ready_plan := {"plan_id": "PLAN_HUNGER_fish_food", "root_goal": "HUNGER", "status": "READY"}
	var revalidated := sim._execution_tracker().consume_parent_revalidation(requester_id, [ready_plan], sim.tick)
	var revalidated_again := sim._execution_tracker().consume_parent_revalidation(requester_id, [ready_plan], sim.tick)
	_check("runtime_parent_revalidation_is_one_shot", bool(revalidated.get("ok", false))
		and revalidated_again.is_empty(), "first=%s second=%s" % [str(revalidated), str(revalidated_again)])
	var replaced_tracker := PlanExecutionTracker.new()
	var replaced_run := _run_fixture(requester_id, "PLAN_HUNGER_fish_food")
	replaced_run["state"] = "BLOCKED"
	replaced_tracker.runs[requester_id] = replaced_run
	_check("replaced_parent_plan_cannot_be_revived",
		replaced_tracker.request_parent_revalidation(requester_id, "PLAN_HUNGER_other", sim.tick,
			"transfer:replacement", "other-run", "other-step").is_empty())

func _test_profiles_and_determinism() -> void:
	var framework := SimulationBootstrap.create(71020, "framework")
	var information := SimulationBootstrap.create(71020, "information")
	var material := SimulationBootstrap.create(71020, "material_request")
	_check("framework_keeps_material_requests_off", bool(framework.get("ok", false))
		and not (framework["sim"] as IslandSimulation).agency_material_requests_enabled)
	_check("information_keeps_material_requests_off", bool(information.get("ok", false))
		and not (information["sim"] as IslandSimulation).agency_material_requests_enabled)
	_check("material_profile_enables_material_requests", bool(material.get("ok", false))
		and (material["sim"] as IslandSimulation).agency_material_requests_enabled
		and (material["sim"] as IslandSimulation).agency_information_subgoals_enabled)

	var bridge_a := Bridge.new(71021)
	var bridge_b := Bridge.new(71021)
	var request_a := _open_and_offer(bridge_a, "deterministic", 1, "holder", 1)
	var request_b := _open_and_offer(bridge_b, "deterministic", 1, "holder", 1)
	_check("same_seed_reproduces_request_decision",
		request_a == request_b
		and str(bridge_a.trace_snapshot()) == str(bridge_b.trace_snapshot()), "a=%s b=%s" % [request_a, request_b])
	var sim_a: IslandSimulation = SimulationBootstrap.create(71022, "material_request")["sim"]
	var sim_b: IslandSimulation = SimulationBootstrap.create(71022, "material_request")["sim"]
	for i in 40:
		sim_a.step()
		sim_b.step()
	_check("material_profile_replays_same_input",
		AgencyMeasure.canon(SimulationAudit.fingerprint(sim_a)) == AgencyMeasure.canon(SimulationAudit.fingerprint(sim_b)))

func _open_and_offer(bridge, request_id: String, quantity: int, target_id: String, target_quantity: int) -> String:
	var step := _craft_step(quantity)
	var run := _run_fixture("requester", "PLAN_HUNGER_fish_food")
	var ctx := {"possessed_items": {"wood": 1}}
	var opened: Dictionary = bridge.ensure_request_for_blocker("requester", run, step, ctx, 1, _recipes(), 0.8)
	var actual_id := str(opened.get("request", {}).get("request_id", request_id))
	var view := _actor_view("requester", Vector2i(10, 10), target_id, Vector2i(11, 10))
	(view["tom"] as TheoryOfMind).add_evidence(target_id, Bridge.holder_predicate("shells"), 1.0, 1.0, -1, 1)
	var beliefs: Array = bridge.build_holder_beliefs("requester", "shells", view, 1)
	if target_quantity != 2:
		beliefs[0]["believed_quantity"] = target_quantity
	var offered: Dictionary = bridge.try_offer(actual_id, beliefs, 2)
	_check("bridge_offer_created", bool(offered.get("ok", false)), str(offered))
	return actual_id

func _open_runtime_request(seed_value: int, quantity: int, suffix: String) -> Dictionary:
	var pair := _runtime_pair(seed_value)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var step := _craft_step(quantity)
	var run := _run_fixture(requester_id, "PLAN_HUNGER_fish_food")
	run["run_id"] = requester_id + "#" + suffix
	run["current_step_id"] = str(step.get("step_id", ""))
	run["steps"] = [step]
	run["state"] = "BLOCKED"
	sim._execution_tracker().runs[requester_id] = run
	var opened := sim._material_request_runtime_bridge().ensure_request_for_blocker(
		requester_id,
		run,
		step,
		AgencyContextBuilder.build(sim, pair["requester"]),
		sim.tick,
		_recipes(),
		0.8,
		"MATERIALS_MISSING"
	)
	pair["step"] = step
	pair["run"] = run
	pair["opened"] = opened
	pair["request_id"] = str(opened.get("request", {}).get("request_id", ""))
	return pair

func _runtime_triple(seed_value: int) -> Dictionary:
	var created := SimulationBootstrap.create(seed_value, "material_request")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var giver_id := str(ids[1])
	var third_id := str(ids[2])
	var requester: Dictionary = sim.actors[requester_id]
	var giver: Dictionary = sim.actors[giver_id]
	var third: Dictionary = sim.actors[third_id]
	requester["tile"] = Vector2i(10, 10)
	giver["tile"] = Vector2i(11, 10)
	third["tile"] = Vector2i(12, 10)
	requester["inventory"] = {"wood": 1}
	giver["inventory"] = {"shells": 2}
	third["inventory"] = {"shells": 2}
	for holder in [giver, third]:
		holder["personality"] = PersonalityProfile.new({"altruism": 1.0, "empathy": 1.0, "caution": 0.0}, {})
	for holder_id in [giver_id, third_id]:
		sim.relationships.adjust(holder_id, requester_id, "benevolence", 1000)
		sim.relationships.adjust(holder_id, requester_id, "reliability", 1000)
		sim.relationships.adjust(holder_id, requester_id, "obligation", 1000)
		(requester["tom"] as TheoryOfMind).add_evidence(
			holder_id, Bridge.holder_predicate("shells"), 1.0, 1.0, -1, sim.tick)
	return {
		"sim": sim,
		"requester_id": requester_id,
		"giver_id": giver_id,
		"third_id": third_id,
		"requester": requester,
		"giver": giver,
		"third": third,
	}

func _set_runtime_waiting_transfer(runtime: Dictionary, accepted_quantity: int) -> void:
	var bridge = (runtime["sim"] as IslandSimulation)._material_request_runtime_bridge()
	var request: Dictionary = bridge.coordinator.tracker._requests[str(runtime["request_id"])]
	request["status"] = Contract.STATUS_WAITING_TRANSFER
	request["target_id"] = str(runtime["giver_id"])
	request["accepted_quantity"] = accepted_quantity
	request["response_outcome"] = Contract.OUTCOME_ACCEPT
	request["last_counter"] = {}

func _set_runtime_waiting_counter(runtime: Dictionary, accepted_quantity: int) -> void:
	var bridge = (runtime["sim"] as IslandSimulation)._material_request_runtime_bridge()
	var request: Dictionary = bridge.coordinator.tracker._requests[str(runtime["request_id"])]
	request["status"] = Contract.STATUS_WAITING_REQUESTER
	request["target_id"] = str(runtime["giver_id"])
	request["accepted_quantity"] = accepted_quantity
	request["last_counter"] = {"quantity": accepted_quantity, "requires_exchange": false}

func _runtime_pair(seed_value: int) -> Dictionary:
	var created := SimulationBootstrap.create(seed_value, "material_request")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var giver_id := str(ids[1])
	sim.actors.erase(str(ids[2]))
	var requester: Dictionary = sim.actors[requester_id]
	var giver: Dictionary = sim.actors[giver_id]
	requester["tile"] = Vector2i(10, 10)
	giver["tile"] = Vector2i(11, 10)
	requester["inventory"] = {"wood": 1}
	giver["inventory"] = {"shells": 2}
	giver["personality"] = PersonalityProfile.new({"altruism": 1.0, "empathy": 1.0, "caution": 0.0}, {})
	sim.relationships.adjust(giver_id, requester_id, "benevolence", 1000)
	sim.relationships.adjust(giver_id, requester_id, "reliability", 1000)
	sim.relationships.adjust(giver_id, requester_id, "obligation", 1000)
	(requester["tom"] as TheoryOfMind).add_evidence(
		giver_id, Bridge.holder_predicate("shells"), 1.0, 1.0, -1, sim.tick)
	return {
		"sim": sim,
		"requester_id": requester_id,
		"giver_id": giver_id,
		"requester": requester,
		"giver": giver,
	}

func _run_fixture(requester_id: String, plan_id: String) -> Dictionary:
	var step := _craft_step()
	return {
		"run_id": requester_id + "#0",
		"actor_id": requester_id,
		"plan_id": plan_id,
		"root_goal": "HUNGER",
		"current_step_id": str(step.get("step_id", "")),
		"steps": [step],
		"state": "ACTIVE",
		"baseline_items": {"wood": 1},
		"pending": {},
		"attempt_seq": 0,
		"missed_opportunities": 0,
	}

func _craft_step(step_quantity: int = 1) -> Dictionary:
	return PlanStepSpec.make(
		"CRAFT",
		"CRAFT:fish_spear",
		"PENDING",
		"craft_fish_spear",
		"fish_spear",
		step_quantity,
		"recipe_fish_spear",
		"FISH",
		[], [], ["kf_spear_recipe"], [],
		"制作鱼叉"
	)

func _recipes() -> RecipeCatalog:
	return RecipeCatalog.load_default(ItemCatalog.load_default())

func _actor_view(requester_id: String, origin: Vector2i, target_id: String, target_tile: Vector2i) -> Dictionary:
	var visible: Array = []
	var trust: Dictionary = {}
	if target_id != "":
		visible.append({"id": target_id, "tile": target_tile})
		trust[target_id] = 800
	return {
		"id": requester_id,
		"tile": origin,
		"tom": TheoryOfMind.new(),
		"trust_of": trust,
		"others_visible": visible,
	}

func _generous_context(inventory_quantity: int) -> Dictionary:
	return {
		"inventory_quantity": inventory_quantity,
		"reserve_quantity": 0,
		"relationship": 1.0,
		"trust": 1.0,
		"generosity": 1.0,
		"own_need_pressure": 0.0,
		"risk_aversion": 0.0,
		"commitment_load": 0.0,
		"exchange_offer_value": 0.0,
	}

func _has_event(events: Array, event_type: String) -> bool:
	for event in events:
		if typeof(event) == TYPE_DICTIONARY and str(event.get("type", "")) == event_type:
			return true
	return false

func _count_events(events: Array, event_type: String) -> int:
	var count := 0
	for event in events:
		if typeof(event) == TYPE_DICTIONARY and str(event.get("type", "")) == event_type:
			count += 1
	return count

func _event_has_request_id(events: Array, event_type: String, request_id: String) -> bool:
	for event in events:
		if typeof(event) != TYPE_DICTIONARY or str(event.get("type", "")) != event_type:
			continue
		if str(event.get("request_id", "")) == request_id:
			return true
	return false

func _event_has_identity(
	events: Array,
	event_type: String,
	request_id: String,
	parent_run_id: String,
	blocker_step_id: String,
	blocker_reason: String
) -> bool:
	for event in events:
		if typeof(event) != TYPE_DICTIONARY or str(event.get("type", "")) != event_type:
			continue
		if str(event.get("request_id", "")) != request_id:
			continue
		if str(event.get("parent_run_id", "")) == parent_run_id \
				and str(event.get("blocker_step_id", "")) == blocker_step_id \
				and str(event.get("blocker_reason", "")) == blocker_reason:
			return true
	return false

func _traces_have_identity(
	bridge,
	request_id: String,
	event_names: Array,
	parent_run_id: String,
	blocker_step_id: String,
	blocker_reason: String
) -> bool:
	var found := {}
	for trace in bridge.trace_snapshot():
		if str(trace.get("request_id", "")) != request_id:
			continue
		var event_name := str(trace.get("event", ""))
		if event_name not in event_names:
			continue
		if str(trace.get("parent_run_id", "")) == parent_run_id \
				and str(trace.get("blocker_step_id", "")) == blocker_step_id \
				and str(trace.get("blocker_reason", "")) == blocker_reason:
			found[event_name] = true
	return found.size() == event_names.size()

func _history_has_counter_rejection(request: Dictionary, target_id: String) -> bool:
	for entry in request.get("history", []):
		if typeof(entry) != TYPE_DICTIONARY or str(entry.get("kind", "")) != "COUNTER_REJECTED":
			continue
		var payload: Dictionary = entry.get("payload", {})
		var counter: Dictionary = payload.get("counter", {})
		if bool(counter.get("requires_exchange", false)):
			return true
	return false

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS " + label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])
