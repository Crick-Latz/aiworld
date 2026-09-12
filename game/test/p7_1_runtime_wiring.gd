extends SceneTree

const Bridge = preload("res://src/simulation/material_request/material_request_runtime_bridge.gd")
const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_request_from_blocker_and_subjective_target()
	_test_accept_refuse_counter_and_transfer()
	_test_runtime_island_wiring()
	_test_profiles_and_determinism()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

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
			"transfer:replacement").is_empty())

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

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS " + label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])
