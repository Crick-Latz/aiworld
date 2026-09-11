extends SceneTree
## P7.0 strict gate: UNKNOWN_SOURCE becomes an executable, subjective information goal.
## Tests cover search, asking, reports, refusal/staleness, refutation and parent-plan revalidation.

var passed := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		passed += 1
		print("PASS " + label)
	else:
		failed += 1
		print("FAIL %s %s" % [label, detail])

func _plan(plan_id: String, item_id: String = "shells", quantity: int = 1,
		cost: float = 4.0, confidence: float = 0.7, root_goal: String = "HUNGER") -> Dictionary:
	return {
		"plan_id": plan_id,
		"root_goal": root_goal,
		"status": "BLOCKED_PLAN",
		"expected_benefit": 1.0,
		"estimated_cost": cost,
		"estimated_risk": 0.1,
		"confidence": confidence,
		"steps": [PlanStepSpec.make("SUBGOAL", "SUBGOAL:find:" + item_id,
			"INERT_UNTIL_P7", "", item_id, quantity)],
		"blockers": [RecipePlanAdapter.make_blocker("UNKNOWN_SOURCE", item_id, "", quantity)],
	}

func _self_state(hunger: int = 850) -> Dictionary:
	return {"needs": {"hunger": hunger, "thirst": 0, "social": 0, "energy": 800}}

func _empty_ctx() -> Dictionary:
	return {"known_sources": [], "known_source_tags": []}

func _source_ctx(tag: String, source_id: String = "shell|3,4", confidence: float = 0.8) -> Dictionary:
	return {
		"known_source_tags": [tag],
		"known_sources": [{
			"tag": tag,
			"source_id": source_id,
			"belief_ref": "known_source:" + source_id,
			"confidence": confidence,
		}],
	}

func _active_goal(goal_id: String = "INFO:u:1:PLAN_HUNGER_fish_food:shells") -> Dictionary:
	return {
		"goal_id": goal_id,
		"actor_id": "u",
		"state": InformationSubgoalTracker.STATE_ACTIVE,
		"parent_plan_id": "PLAN_HUNGER_fish_food",
		"root_goal": "HUNGER",
		"item_id": "shells",
		"quantity": 1,
		"source_kinds": ["shell"],
		"attempts": 0,
		"search_failures": 0,
		"asks": 0,
		"refusals": 0,
		"stale_reports": 0,
		"unknown_responses": 0,
		"tried_tiles": [],
		"asked_actor_ids": [],
		"evidence_refs": [],
	}

func _find_plan(plans: Array, plan_id: String) -> Dictionary:
	for plan in plans:
		if str(plan.get("plan_id", "")) == plan_id:
			return plan
	return {}

func _has_action(actions: Array, action_name: String) -> bool:
	for action in actions:
		if str(action.get("action", "")) == action_name:
			return true
	return false

func _action(actions: Array, action_name: String) -> Dictionary:
	for action in actions:
		if str(action.get("action", "")) == action_name:
			return action
	return {}

func _event_exists(events: Array, event_type: String) -> bool:
	for event in events:
		if str(event.get("type", "")) == event_type:
			return true
	return false

func _run() -> void:
	var items := ItemCatalog.load_default()
	_check("source_kind_shells_is_catalog_derived",
		InformationSubgoalTracker.source_kinds_for_item("shells", items) == ["shell"])
	_check("source_kind_wood_is_catalog_derived",
		InformationSubgoalTracker.source_kinds_for_item("wood", items) == ["tree"])
	_check("unknown_item_has_no_invented_source",
		InformationSubgoalTracker.source_kinds_for_item("missing", items).is_empty())

	var plans := [_plan("PLAN_HUNGER_fish_food")]
	var tracker := InformationSubgoalTracker.new()
	var goal := tracker.prepare("u", plans, _empty_ctx(), _self_state(), 10, items)
	_check("unknown_source_creates_information_goal", not goal.is_empty()
		and str(goal.get("state", "")) == InformationSubgoalTracker.STATE_ACTIVE, str(goal))
	_check("goal_keeps_parent_and_exact_gap", str(goal.get("parent_plan_id", "")) == "PLAN_HUNGER_fish_food"
		and str(goal.get("item_id", "")) == "shells" and int(goal.get("quantity", 0)) == 1, str(goal))
	_check("goal_id_is_deterministic_and_actor_scoped",
		str(goal.get("goal_id", "")) == "INFO:u:1:PLAN_HUNGER_fish_food:shells", str(goal))
	var same := tracker.prepare("u", plans, _empty_ctx(), _self_state(), 11, items)
	_check("active_goal_retains_identity", same.get("goal_id", "") == goal.get("goal_id", ""), str(same))

	var expensive := _plan("PLAN_HUNGER_expensive", "shells", 1, 8.0, 0.5)
	var cheap := _plan("PLAN_HUNGER_cheap", "shells", 1, 1.0, 0.9)
	var ranked_a := InformationSubgoalTracker.new().prepare("u", [expensive, cheap], _empty_ctx(), _self_state(), 1, items)
	var ranked_b := InformationSubgoalTracker.new().prepare("u", [cheap, expensive], _empty_ctx(), _self_state(), 1, items)
	_check("subjective_value_selects_stronger_blocker", ranked_a.get("parent_plan_id", "") == "PLAN_HUNGER_cheap", str(ranked_a))
	_check("proposal_order_does_not_change_goal", ranked_a.get("parent_plan_id", "") == ranked_b.get("parent_plan_id", ""),
		"a=%s b=%s" % [str(ranked_a), str(ranked_b)])
	_check("resolved_need_does_not_create_goal",
		InformationSubgoalTracker.new().prepare("u", plans, _empty_ctx(), _self_state(20), 1, items).is_empty())
	_check("known_source_blocks_stale_goal_creation",
		InformationSubgoalTracker.new().prepare("u", plans, _source_ctx("SHELL"), _self_state(), 1, items).is_empty())
	var malformed := _plan("PLAN_HUNGER_bad")
	malformed["blockers"] = [{"reason_code": "UNKNOWN_SOURCE", "item_id": "shells"}]
	_check("malformed_blocker_fails_closed",
		InformationSubgoalTracker.new().prepare("u", [malformed], _empty_ctx(), _self_state(), 1, items).is_empty())
	_check("unsupported_root_goal_fails_closed",
		InformationSubgoalTracker.new().prepare("u", [_plan("PLAN_MAGIC", "shells", 1, 1.0, 0.8, "MAGIC")],
			_empty_ctx(), _self_state(), 1, items).is_empty())

	tracker.prepare("u", plans, _source_ctx("SHELL"), _self_state(), 12, items)
	var resolved := tracker.current_goal("u")
	_check("new_subjective_source_resolves_goal", resolved.get("state", "") == InformationSubgoalTracker.STATE_RESOLVED,
		str(resolved))
	_check("resolution_keeps_belief_evidence_ref", (resolved.get("evidence_refs", []) as Array).has("known_source:shell|3,4"),
		str(resolved))

	var cancelled_tracker := InformationSubgoalTracker.new()
	cancelled_tracker.prepare("u", plans, _empty_ctx(), _self_state(), 1, items)
	cancelled_tracker.prepare("u", [], _empty_ctx(), _self_state(), 2, items)
	_check("removed_parent_blocker_cancels_goal",
		cancelled_tracker.current_goal("u").get("state", "") == InformationSubgoalTracker.STATE_CANCELLED,
		str(cancelled_tracker.current_goal("u")))

	var cooldown_tracker := InformationSubgoalTracker.new()
	cooldown_tracker.goals["u"] = {"state": InformationSubgoalTracker.STATE_FAILED, "retry_after_tick": 20}
	_check("failed_goal_respects_retry_cooldown",
		cooldown_tracker.prepare("u", plans, _empty_ctx(), _self_state(), 19, items).is_empty())
	_check("goal_can_retry_after_cooldown",
		not cooldown_tracker.prepare("u", plans, _empty_ctx(), _self_state(), 20, items).is_empty())

	var attempt_tracker := InformationSubgoalTracker.new()
	var attempt_goal := attempt_tracker.prepare("u", plans, _empty_ctx(), _self_state(), 1, items)
	var wrong_action := {"action": "search_resource_source", "information_goal_id": "other", "target": Vector2i(7, 8)}
	attempt_tracker.on_action_complete("u", wrong_action, [], _empty_ctx(), 2)
	_check("wrong_goal_identity_cannot_advance", int(attempt_tracker.current_goal("u").get("attempts", -1)) == 0)
	var search_action := {"action": "search_resource_source", "information_goal_id": attempt_goal["goal_id"],
		"target": Vector2i(7, 8)}
	attempt_tracker.on_action_complete("u", search_action, [{"type": "source_search_failed", "seq": 41,
		"information_goal_id": attempt_goal["goal_id"]}], _empty_ctx(), 3)
	var after_search := attempt_tracker.current_goal("u")
	_check("failed_search_records_attempt_and_tile", int(after_search.get("attempts", 0)) == 1
		and int(after_search.get("search_failures", 0)) == 1
		and (after_search.get("tried_tiles", []) as Array).has("7,8"), str(after_search))
	_check("failed_search_keeps_event_evidence", (after_search.get("evidence_refs", []) as Array).has("event:41"), str(after_search))
	var ask_action := {"action": "ask_resource_source", "information_goal_id": attempt_goal["goal_id"],
		"target_actor": "peer"}
	attempt_tracker.on_action_complete("u", ask_action, [{"type": "source_information_refused", "seq": 42,
		"information_goal_id": attempt_goal["goal_id"]}], _empty_ctx(), 4)
	var after_refusal := attempt_tracker.current_goal("u")
	_check("refusal_records_social_attempt", int(after_refusal.get("asks", 0)) == 1
		and int(after_refusal.get("refusals", 0)) == 1
		and (after_refusal.get("asked_actor_ids", []) as Array).has("peer"), str(after_refusal))
	attempt_tracker.on_action_complete("u", ask_action, [{"type": "source_information_shared", "seq": 43,
		"information_goal_id": attempt_goal["goal_id"]}], _empty_ctx(), 5)
	_check("message_event_without_belief_update_does_not_resolve",
		attempt_tracker.current_goal("u").get("state", "") == InformationSubgoalTracker.STATE_ACTIVE)
	attempt_tracker.on_action_complete("u", ask_action, [{"type": "source_information_shared", "seq": 44,
		"information_goal_id": attempt_goal["goal_id"]}], _source_ctx("SHELL", "shell|9,9", 0.5), 6)
	var resolved_after_report := attempt_tracker.current_goal("u")
	_check("report_plus_subjective_belief_resolves_goal",
		resolved_after_report.get("state", "") == InformationSubgoalTracker.STATE_RESOLVED, str(resolved_after_report))
	_check("report_resolution_is_auditable", (resolved_after_report.get("evidence_refs", []) as Array).has("event:44")
		and (resolved_after_report.get("evidence_refs", []) as Array).has("known_source:shell|9,9"), str(resolved_after_report))

	var limit_tracker := InformationSubgoalTracker.new()
	var limit_goal := _active_goal()
	limit_goal["attempts"] = InformationSubgoalTracker.MAX_ATTEMPTS - 1
	limit_tracker.goals["u"] = limit_goal
	limit_tracker.on_action_complete("u", {"action": "search_resource_source",
		"information_goal_id": limit_goal["goal_id"], "target": Vector2i(1, 1)},
		[{"type": "source_search_failed", "seq": 55, "information_goal_id": limit_goal["goal_id"]}],
		_empty_ctx(), 30)
	var limited := limit_tracker.current_goal("u")
	_check("attempt_limit_fails_goal", limited.get("state", "") == InformationSubgoalTracker.STATE_FAILED, str(limited))
	_check("failed_goal_gets_retry_tick", int(limited.get("retry_after_tick", -1)) == 30 + InformationSubgoalTracker.RETRY_COOLDOWN_TICKS,
		str(limited))
	var trace_copy := attempt_tracker.trace_snapshot()
	trace_copy[0]["event"] = "MUTATED"
	_check("trace_snapshot_is_read_only_copy", str(attempt_tracker.trace_snapshot()[0].get("event", "")) != "MUTATED")

	var belief := SpatialBeliefMap.new()
	belief.configure(Rect2i(0, 0, 20, 20))
	var report_ok := belief.learn_reported_resource("shell", Vector2i(4, 5), 10, 12, "peer", 0.6, 77)
	var report := belief.resource_belief("shell", Vector2i(4, 5))
	_check("reported_source_is_stored", report_ok and report.get("evidence_kind", "") == SpatialBeliefMap.EVIDENCE_REPORT,
		str(report))
	_check("report_keeps_source_time_and_confidence", int(report.get("last_seen_tick", -1)) == 10
		and int(report.get("received_tick", -1)) == 12 and report.get("source_actor_id", "") == "peer"
		and is_equal_approx(float(report.get("confidence", 0.0)), 0.6), str(report))
	_check("older_report_cannot_overwrite_newer_report",
		not belief.learn_reported_resource("shell", Vector2i(4, 5), 9, 13, "other", 0.9, 78))
	belief.observe_resource("shell", Vector2i(4, 5), false, false, 10)
	var direct := belief.resource_belief("shell", Vector2i(4, 5))
	_check("direct_perception_overrides_report", direct.get("evidence_kind", "") == SpatialBeliefMap.EVIDENCE_PERCEPT
		and not bool(direct.get("believed_present", true)), str(direct))
	_check("same_tick_report_cannot_overwrite_perception",
		not belief.learn_reported_resource("shell", Vector2i(4, 5), 10, 14, "peer", 0.9, 79))
	_check("out_of_bounds_report_is_rejected",
		not belief.learn_reported_resource("shell", Vector2i(25, 25), 10, 12, "peer", 0.8))
	_check("anonymous_report_is_rejected",
		not belief.learn_reported_resource("shell", Vector2i(3, 3), 10, 12, "", 0.8))
	belief.observe_resource("shell", Vector2i(8, 8), true, false, 5)
	belief.observe_resource("shell", Vector2i(2, 2), true, false, 15)
	var ordered_sources := belief.resource_beliefs("shell")
	_check("resource_beliefs_sort_newest_first", ordered_sources.size() == 2
		and ordered_sources[0].get("tile", Vector2i.ZERO) == Vector2i(2, 2), str(ordered_sources))
	belief.observe_resource("shell", Vector2i(8, 8), false, false, 16)
	_check("unavailable_source_is_excluded_by_default", belief.resource_beliefs("shell").size() == 1)
	_check("unavailable_source_remains_auditable", belief.resource_beliefs("shell", true).size() == 3)
	var belief_a := SpatialBeliefMap.new()
	var belief_b := SpatialBeliefMap.new()
	belief_a.configure(Rect2i(0, 0, 20, 20)); belief_b.configure(Rect2i(0, 0, 20, 20))
	belief_a.learn_reported_resource("shell", Vector2i(1, 1), 2, 3, "peer_a", 0.7)
	belief_b.learn_reported_resource("shell", Vector2i(1, 1), 2, 3, "peer_b", 0.7)
	_check("belief_hash_includes_report_provenance", belief_a.hash_state() != belief_b.hash_state())
	var time_a := SpatialBeliefMap.new(); var time_b := SpatialBeliefMap.new()
	time_a.configure(Rect2i(0, 0, 20, 20)); time_b.configure(Rect2i(0, 0, 20, 20))
	time_a.learn_reported_resource("shell", Vector2i(6, 6), 2, 5, "peer", 0.7)
	time_b.learn_reported_resource("shell", Vector2i(6, 6), 2, 9, "peer", 0.7)
	_check("actors_keep_distinct_information_arrival_times",
		int(time_a.resource_belief("shell", Vector2i(6, 6)).get("received_tick", -1)) !=
		int(time_b.resource_belief("shell", Vector2i(6, 6)).get("received_tick", -1)))

	var responder := {"personality": PersonalityProfile.new({}, {}), "needs": {}, "spatial": SpatialBeliefMap.new()}
	(responder["spatial"] as SpatialBeliefMap).configure(Rect2i(0, 0, 20, 20))
	var response_rng := RandomNumberGenerator.new(); response_rng.seed = 17
	_check("responder_without_source_says_unknown",
		InformationExchangePolicy.evaluate(responder, "asker", "shell", 0, 10, response_rng).get("response", "") ==
		InformationExchangePolicy.RESPONSE_UNKNOWN)
	(responder["spatial"] as SpatialBeliefMap).observe_resource("shell", Vector2i(3, 3), true, false, 1)
	_check("old_subjective_source_is_marked_stale",
		InformationExchangePolicy.evaluate(responder, "asker", "shell", 0, 100, response_rng).get("response", "") ==
		InformationExchangePolicy.RESPONSE_STALE)
	(responder["spatial"] as SpatialBeliefMap).observe_resource("shell", Vector2i(3, 3), true, false, 20)
	_check("missing_rng_fails_closed_as_refusal",
		InformationExchangePolicy.evaluate(responder, "asker", "shell", 0, 21, null).get("response", "") ==
		InformationExchangePolicy.RESPONSE_REFUSE)
	var generous := {"personality": PersonalityProfile.new({"altruism": 1.0, "empathy": 1.0,
		"sociability": 1.0, "conflict_avoidance": 1.0}, {}), "needs": {"hunger": 0, "energy": 1000}}
	var low_will := InformationExchangePolicy.assess_willingness(generous, "asker", -1000)
	var high_will := InformationExchangePolicy.assess_willingness(generous, "asker", 1000)
	_check("trust_changes_share_probability", float(high_will.get("share_probability", 0.0)) >
		float(low_will.get("share_probability", 0.0)), "low=%s high=%s" % [str(low_will), str(high_will)])
	_check("knowledge_predicate_is_schema_stable",
		InformationExchangePolicy.knowledge_predicate("shell") == "knows_source:shell")

	var action_belief := SpatialBeliefMap.new()
	action_belief.configure(Rect2i(0, 0, 20, 20))
	action_belief.observe_cell(5, 5, SpatialBeliefMap.CELL_FREE, "none", 1)
	var action_goal := _active_goal()
	var actor := {
		"id": "u", "tile": Vector2i(5, 5), "personality": PersonalityProfile.new({}, {}),
		"needs": {"hunger": 850, "energy": 800}, "spatial": action_belief,
		"others_visible": [], "trust_of": {}, "tom": TheoryOfMind.new(),
	}
	var base_actions := InformationActionPolicy.build(actor, action_goal, 1)
	_check("active_goal_produces_purposeful_search", _has_action(base_actions, "search_resource_source"), str(base_actions))
	_check("unseen_peers_are_not_asked", not _has_action(base_actions, "ask_resource_source"), str(base_actions))
	(actor["tom"] as TheoryOfMind).add_evidence("peer", "knows_source:shell", 1.0, 0.8, 1, 1)
	actor["others_visible"] = [{"id": "peer", "tile": Vector2i(17, 5)}]
	actor["trust_of"] = {"peer": 400}
	var ask_actions := InformationActionPolicy.build(actor, action_goal, 2)
	var ask_candidate := _action(ask_actions, "ask_resource_source")
	_check("visible_peer_with_evidence_can_be_asked", not ask_candidate.is_empty()
		and ask_candidate.get("target_actor", "") == "peer", str(ask_actions))
	_check("ask_duration_covers_conversation_approach", int(ask_candidate.get("duration", 0)) == 4, str(ask_candidate))
	var asked_goal := action_goal.duplicate(true); asked_goal["asked_actor_ids"] = ["peer"]
	_check("already_asked_peer_is_not_repeated", not _has_action(InformationActionPolicy.build(actor, asked_goal, 3),
		"ask_resource_source"))
	var first_target := InformationActionPolicy.choose_search_target(Vector2i(5, 5), action_belief, [], 0)
	var second_target := InformationActionPolicy.choose_search_target(Vector2i(5, 5), action_belief,
		[SpatialBeliefMap.key(first_target.x, first_target.y)], 0)
	_check("search_target_is_deterministic",
		first_target == InformationActionPolicy.choose_search_target(Vector2i(5, 5), action_belief, [], 0), str(first_target))
	_check("tried_search_tile_is_avoided", first_target != second_target, "first=%s second=%s" % [str(first_target), str(second_target)])
	var no_belief_actor := actor.duplicate(true); no_belief_actor.erase("spatial")
	_check("missing_subjective_map_yields_no_information_action",
		InformationActionPolicy.build(no_belief_actor, action_goal, 1).is_empty())

	var framework_created := SimulationBootstrap.create(61003, "framework")
	var information_created := SimulationBootstrap.create(61003, "information")
	_check("framework_profile_keeps_information_layer_off", framework_created.get("ok", false)
		and not (framework_created["sim"] as IslandSimulation).agency_information_subgoals_enabled)
	_check("information_profile_enables_complete_prerequisites", information_created.get("ok", false)
		and (information_created["sim"] as IslandSimulation).agency_plan_execution_enabled
		and (information_created["sim"] as IslandSimulation).agency_information_subgoals_enabled)
	var sim_a: IslandSimulation = information_created["sim"]
	var sim_b: IslandSimulation = SimulationBootstrap.create(61003, "information")["sim"]
	for i in 200:
		sim_a.step(); sim_b.step()
	_check("information_profile_is_deterministic",
		AgencyMeasure.canon(SimulationAudit.fingerprint(sim_a)) == AgencyMeasure.canon(SimulationAudit.fingerprint(sim_b)))
	_check("natural_fixed_seed_activates_information_goal", not sim_a.agency_information_trace().is_empty(),
		str(SimulationAudit.summary(sim_a)))
	_check("natural_fixed_seed_records_search_result", _event_exists(sim_a.events, "source_search_found")
		or _event_exists(sim_a.events, "source_search_failed"), str(SimulationAudit.summary(sim_a)))
	var audit_before := AgencyMeasure.canon(SimulationAudit.fingerprint(sim_a))
	SimulationAudit.summary(sim_a)
	sim_a.agency_information_trace()
	_check("information_diagnostics_do_not_mutate", audit_before == AgencyMeasure.canon(SimulationAudit.fingerprint(sim_a)))

	# Parent-plan revalidation: the only new input is a report in the actor's SpatialBeliefMap.
	var replan_created := SimulationBootstrap.create(61011, "information")
	var replan_sim: IslandSimulation = replan_created["sim"]
	var replan_actor: Dictionary = replan_sim.actors["npc_kadga"]
	replan_actor["needs"]["hunger"] = 900
	replan_actor["inventory"] = {"wood": 1}
	var replan_belief: SpatialBeliefMap = replan_actor["spatial"]
	replan_belief.known_resources.clear()
	var fish_tile: Vector2i = replan_sim.world["fish_spots"][0]
	replan_belief.observe_resource("fish", fish_tile, true, false, 1)
	var ctx_before := AgencyContextBuilder.build(replan_sim, replan_actor)
	var plans_before := MeansEndsPlanner.propose_plans("HUNGER", replan_sim.agency_knowledge_store(), ctx_before,
		replan_sim._recipe_catalog_if_any(), replan_sim._item_catalog_if_any())
	var fish_before := _find_plan(plans_before, "PLAN_HUNGER_fish_food")
	_check("fish_plan_is_blocked_by_unknown_shell_source", fish_before.get("status", "") == "BLOCKED_PLAN"
		and str((fish_before.get("blockers", []) as Array)[0].get("reason_code", "")) == "UNKNOWN_SOURCE", str(fish_before))
	var reported_tile: Vector2i = replan_sim.world["shell_beaches"][0]
	replan_belief.learn_reported_resource("shell", reported_tile, 2, 3, "npc_weila", 0.7, 99)
	var ctx_after := AgencyContextBuilder.build(replan_sim, replan_actor)
	var plans_after := MeansEndsPlanner.propose_plans("HUNGER", replan_sim.agency_knowledge_store(), ctx_after,
		replan_sim._recipe_catalog_if_any(), replan_sim._item_catalog_if_any())
	var fish_after := _find_plan(plans_after, "PLAN_HUNGER_fish_food")
	var kinds: Array = []
	for step in fish_after.get("steps", []): kinds.append(str(step.get("kind", "")))
	_check("reported_source_revalidates_parent_plan", fish_after.get("status", "") == "READY", str(fish_after))
	_check("revalidated_plan_contains_full_causal_chain", kinds.has("ACQUIRE") and kinds.has("CRAFT") and kinds.has("MAIN"), str(kinds))
	_check("context_hash_changes_when_information_arrives",
		AgencyContextBuilder.context_hash(ctx_before) != AgencyContextBuilder.context_hash(ctx_after))

	# A report can be wrong or obsolete. Physical perception at the claimed tile must refute it.
	var ids: Array = replan_sim.actors.keys(); ids.sort()
	var asker_id := str(ids[0]); var responder_id := str(ids[1])
	var asker: Dictionary = replan_sim.actors[asker_id]
	var answerer: Dictionary = replan_sim.actors[responder_id]
	var fake_tile: Vector2i = asker["tile"]
	if (replan_sim.world["shell_beaches"] as Array).has(fake_tile):
		fake_tile = replan_sim.map_query.get_spawn_tile()
	asker["tile"] = fake_tile; answerer["tile"] = fake_tile
	(asker["spatial"] as SpatialBeliefMap).known_resources.clear()
	(answerer["spatial"] as SpatialBeliefMap).known_resources.clear()
	(answerer["spatial"] as SpatialBeliefMap).observe_resource("shell", fake_tile, true, false, replan_sim.tick)
	answerer["personality"] = PersonalityProfile.new({"altruism": 1.0, "empathy": 1.0,
		"sociability": 1.0, "conflict_avoidance": 1.0}, {})
	replan_sim.relationships.adjust(responder_id, asker_id, "benevolence", 1000)
	replan_sim.relationships.adjust(responder_id, asker_id, "reliability", 1000)
	replan_sim.relationships.adjust(responder_id, asker_id, "obligation", 1000)
	var forced_information_rng := RandomNumberGenerator.new()
	forced_information_rng.seed = 1
	replan_sim._information_rngs[responder_id] = forced_information_rng
	var world_rng_before := str(replan_sim._rng.state)
	var information_rng_before := str(forced_information_rng.state)
	var fixture_goal := _active_goal("INFO:fixture")
	fixture_goal["actor_id"] = asker_id
	replan_sim._information_tracker_state = InformationSubgoalTracker.new()
	replan_sim._information_tracker_state.goals[asker_id] = fixture_goal
	var exchange_action := {
		"action": "ask_resource_source", "duration": 1,
		"information_goal_id": "INFO:fixture", "parent_plan_id": "PLAN_HUNGER_fish_food",
		"source_kind": "shell", "item_id": "shells", "target_actor": responder_id,
	}
	asker["current_action"] = exchange_action
	var event_start := replan_sim.events.size()
	replan_sim._complete_action(asker_id, asker, [])
	var exchange_events := replan_sim.events.slice(event_start)
	var information_states := replan_sim.agency_information_rng_states()
	_check("information_exchange_does_not_consume_world_rng", str(replan_sim._rng.state) == world_rng_before)
	_check("information_exchange_uses_responder_scoped_rng", information_states.has(responder_id)
		and str(information_states[responder_id]) != information_rng_before, str(information_states))
	information_states[responder_id] = "MUTATED"
	_check("information_rng_diagnostics_are_read_only",
		str(replan_sim.agency_information_rng_states().get(responder_id, "")) != "MUTATED")
	var learned := (asker["spatial"] as SpatialBeliefMap).resource_belief("shell", fake_tile)
	_check("shared_answer_creates_report_belief", _event_exists(exchange_events, "source_information_shared")
		and learned.get("evidence_kind", "") == SpatialBeliefMap.EVIDENCE_REPORT
		and learned.get("source_actor_id", "") == responder_id, "events=%s learned=%s" % [str(exchange_events), str(learned)])
	_check("controlled_ask_resolves_information_goal",
		replan_sim.agency_information_goal(asker_id).get("state", "") == InformationSubgoalTracker.STATE_RESOLVED,
		str(replan_sim.agency_information_goal(asker_id)))
	SpatialPerception.perceive(replan_sim, asker)
	var refuted := (asker["spatial"] as SpatialBeliefMap).resource_belief("shell", fake_tile)
	_check("physical_revisit_refutes_false_report", refuted.get("evidence_kind", "") == SpatialBeliefMap.EVIDENCE_PERCEPT
		and not bool(refuted.get("believed_present", true)), str(refuted))
	_check("refuted_source_disappears_from_planning_context",
		not (AgencyContextBuilder.build(replan_sim, asker).get("known_source_tags", []) as Array).has("SHELL"))

	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
