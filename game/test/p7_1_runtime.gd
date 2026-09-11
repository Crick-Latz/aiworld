extends SceneTree

var passed := 0
var failed := 0

func _initialize() -> void:
	_run()

func _check(name: String, condition: bool, detail: String = "") -> void:
	if condition:
		passed += 1
		print("PASS %s" % name)
	else:
		failed += 1
		print("FAIL %s %s" % [name, detail])

func _run() -> void:
	var material_boot: Dictionary = SimulationBootstrap.create(61201, "material")
	_check("material_profile_boots", bool(material_boot.get("ok", false)), str(material_boot))
	var material_sim: IslandSimulation = material_boot.get("sim", null)
	_check("material_profile_enables_requests", material_sim != null and material_sim.agency_material_requests_enabled)
	_check("material_profile_keeps_information", material_sim != null and material_sim.agency_information_subgoals_enabled)
	_check("material_profile_live_bridge", material_sim != null and material_sim.agency_mode == "LIVE_BRIDGE")

	var framework_boot: Dictionary = SimulationBootstrap.create(61201, "framework")
	_check("framework_profile_boots", bool(framework_boot.get("ok", false)), str(framework_boot))
	var framework_sim: IslandSimulation = framework_boot.get("sim", null)
	_check("framework_profile_material_off", framework_sim != null and not framework_sim.agency_material_requests_enabled)
	_check("material_tracker_initially_empty", material_sim != null and material_sim.agency_material_request_snapshot().is_empty())
	_check("material_rng_initially_empty", material_sim != null and material_sim.agency_material_request_rng_states().is_empty())

	var actor := {
		"id": "actor_a",
		"others_visible": ["actor_b"],
		"needs": {"hunger": 800.0, "thirst": 200.0},
		"material_holder_beliefs": {},
	}
	var relationships := RelationshipStore.new()
	MaterialHolderBeliefAdapter.observe_event(actor, {
		"type": "gathered_wood", "actor_id": "actor_b", "wood": 2, "seq": 7,
	}, 5)
	var beliefs: Dictionary = MaterialHolderBeliefAdapter.snapshot(actor)
	_check("witness_creates_holder_belief", beliefs.has("actor_b|wood"), str(beliefs))
	_check("witness_belief_tracks_quantity", int((beliefs.get("actor_b|wood", {}) as Dictionary).get("believed_quantity", 0)) == 2)

	var hidden: Array = MaterialHolderBeliefAdapter.candidates(actor, "wood", [], relationships, 6)
	_check("hidden_holder_not_selectable", hidden.is_empty(), str(hidden))
	var visible: Array = MaterialHolderBeliefAdapter.candidates(actor, "wood", ["actor_b"], relationships, 6)
	_check("visible_subjective_holder_selectable", visible.size() == 1 and String((visible[0] as Dictionary).get("actor_id", "")) == "actor_b", str(visible))
	var wrong_item: Array = MaterialHolderBeliefAdapter.candidates(actor, "shells", ["actor_b"], relationships, 6)
	_check("item_mismatch_not_selectable", wrong_item.is_empty(), str(wrong_item))

	MaterialHolderBeliefAdapter.mark_refuted(actor, "actor_b", "wood", 7)
	var refuted: Array = MaterialHolderBeliefAdapter.candidates(actor, "wood", ["actor_b"], relationships, 8)
	_check("refuted_holder_not_selectable", refuted.is_empty(), str(refuted))
	MaterialHolderBeliefAdapter.observe_event(actor, {
		"type": "ITEM_TRANSFER_COMPLETED", "from_actor_id": "actor_b", "to_actor_id": "actor_c",
		"item_id": "wood", "giver_after": 4, "receiver_after": 1, "seq": 8,
	}, 9)
	beliefs = MaterialHolderBeliefAdapter.snapshot(actor)
	var refreshed: Dictionary = beliefs.get("actor_b|wood", {})
	_check("transfer_refreshes_holder_belief", not bool(refreshed.get("stale", true)), str(refreshed))
	_check("transfer_records_exact_visible_quantity", int(refreshed.get("believed_quantity", -1)) == 4, str(refreshed))

	var proposals := [{
		"plan_id": "plan-a",
		"root_goal": "HUNGER",
		"blockers": [{"reason_code": "UNKNOWN_SOURCE", "item_id": "wood", "quantity": 2}],
	}]
	var coordinator := MaterialRequestCoordinator.new()
	var state_10: Dictionary = MaterialRequestRuntimeAdapter.prepare(
		"actor_a", proposals, actor, relationships, coordinator, 10, 901)
	var candidate_10: Dictionary = state_10.get("candidate", {})
	var request_10: Dictionary = state_10.get("request", {})
	var request_id_10 := String(request_10.get("request_id", ""))
	_check("blocker_opens_runtime_request", not request_10.is_empty(), str(state_10))
	_check("runtime_candidate_is_request_material", String(candidate_10.get("action", "")) == "request_material", str(candidate_10))
	_check("runtime_candidate_uses_subjective_target", String(candidate_10.get("target_actor", "")) == "actor_b", str(candidate_10))
	_check("runtime_request_is_tracked", coordinator.tracker.active_requests_for("actor_a").size() == 1)
	_check("runtime_request_identity_has_epoch", request_id_10.ends_with(":10"), request_id_10)

	var state_11: Dictionary = MaterialRequestRuntimeAdapter.prepare(
		"actor_a", proposals, actor, relationships, coordinator, 11, 901)
	_check("active_request_reused_without_duplicate", String((state_11.get("request", {}) as Dictionary).get("request_id", "")) == request_id_10)
	_check("active_request_count_stays_one", coordinator.tracker.active_requests_for("actor_a").size() == 1)

	var state_35: Dictionary = MaterialRequestRuntimeAdapter.prepare(
		"actor_a", proposals, actor, relationships, coordinator, 35, 901)
	_check("expired_request_suppresses_immediate_retry", state_35.is_empty(), str(state_35))
	_check("expiry_sets_retry_cooldown", int(actor.get("material_request_cooldown_until", 0)) >= 41, str(actor.get("material_request_cooldown_until", 0)))
	_check("expired_request_is_terminal", String(coordinator.tracker.get_request(request_id_10).get("status", "")) == MaterialRequestContract.STATUS_EXPIRED)
	var state_40: Dictionary = MaterialRequestRuntimeAdapter.prepare(
		"actor_a", proposals, actor, relationships, coordinator, 40, 901)
	_check("cooldown_blocks_retry", state_40.is_empty(), str(state_40))
	var state_42: Dictionary = MaterialRequestRuntimeAdapter.prepare(
		"actor_a", proposals, actor, relationships, coordinator, 42, 901)
	var request_id_42 := String((state_42.get("request", {}) as Dictionary).get("request_id", ""))
	_check("retry_reopens_after_cooldown", not request_id_42.is_empty(), str(state_42))
	_check("retry_gets_new_identity", request_id_42 != request_id_10 and request_id_42.ends_with(":42"), request_id_42)

	var tick_before := material_sim.tick if material_sim != null else -1
	if material_sim != null:
		for i in 5:
			material_sim.step()
	_check("material_profile_steps_cleanly", material_sim != null and material_sim.tick == tick_before + 5,
		"before=%d after=%d" % [tick_before, material_sim.tick if material_sim != null else -1])

	print("SUMMARY: passed=%d failed=%d" % [passed, failed])
	quit(0 if failed == 0 else 1)
