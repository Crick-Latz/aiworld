extends RefCounted
class_name MaterialRequestRuntimeAdapter

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")
const HolderBeliefs = preload("res://src/simulation/material_request/material_holder_belief_adapter.gd")
const REQUEST_TTL_TICKS := 24

static func prepare(actor_id: String, proposals: Array, actor: Dictionary,
		relationships: RelationshipStore, coordinator: MaterialRequestCoordinator,
		now_tick: int, seed: int) -> Dictionary:
	coordinator.tracker.expire_due(now_tick)
	var active: Array = coordinator.tracker.active_requests_for(actor_id)
	if not active.is_empty():
		return _runtime_state(active[0], actor, relationships, coordinator, now_tick, seed)

	var blocker := _select_material_blocker(proposals)
	if blocker.is_empty():
		return {}
	var item_id := String(blocker.get("item_id", ""))
	var quantity := maxi(1, int(blocker.get("quantity", 1)))
	var plan_id := String(blocker.get("plan_id", ""))
	var root_goal := String(blocker.get("root_goal", ""))
	var request_id := "MR:%s:%s:%s" % [actor_id, plan_id, item_id]
	if coordinator.tracker.has_request(request_id):
		var existing := coordinator.tracker.get_request(request_id)
		if not Contract.is_terminal(String(existing.get("status", ""))):
			return _runtime_state(existing, actor, relationships, coordinator, now_tick, seed)
		return {}

	var request := Contract.make_request(request_id, actor_id, item_id, quantity, root_goal,
		plan_id, now_tick, now_tick + REQUEST_TTL_TICKS, _urgency(actor, root_goal))
	request["knowledge_context"] = {"max_holder_belief_age_ticks": HolderBeliefs.DEFAULT_MAX_AGE_TICKS}
	var preview_state := _runtime_state(request, actor, relationships, coordinator, now_tick, seed)
	if (preview_state.get("candidate", {}) as Dictionary).is_empty():
		return {}
	var opened: Dictionary = coordinator.open_request(request)
	if not bool(opened.get("ok", false)):
		return {}
	return _runtime_state(coordinator.tracker.get_request(request_id), actor, relationships, coordinator, now_tick, seed)

static func recipient_context(sim: IslandSimulation, recipient_id: String,
		requester_id: String, item_id: String) -> Dictionary:
	if not sim.actors.has(recipient_id):
		return {}
	var recipient: Dictionary = sim.actors[recipient_id]
	var inv: Dictionary = recipient.get("inventory", {})
	var needs: Dictionary = recipient.get("needs", {})
	var personality: PersonalityProfile = recipient.get("personality", null)
	var raw_trust := sim.relationships.composite_trust(recipient_id, requester_id)
	var own_need := maxf(float(needs.get("hunger", 0)), float(needs.get("thirst", 0))) / 1000.0
	var generosity := 0.5
	var risk := 0.5
	if personality != null:
		generosity = personality.effective_trait("altruism", needs)
		risk = personality.effective_trait("caution", needs)
	var intentions: IntentionManager = recipient.get("intentions", null)
	return {
		"inventory_quantity": maxi(0, int(inv.get(item_id, 0))),
		"reserve_quantity": _reserve_quantity(sim, recipient_id, item_id),
		"relationship": clampf(float(raw_trust) / 1000.0, -1.0, 1.0),
		"trust": clampf((float(raw_trust) + 1000.0) / 2000.0, 0.0, 1.0),
		"generosity": clampf(generosity, 0.0, 1.0),
		"own_need_pressure": clampf(own_need, 0.0, 1.0),
		"risk_aversion": clampf(risk, 0.0, 1.0),
		"commitment_load": 1.0 if intentions != null and intentions.has_intention() else 0.0,
		"exchange_offer_value": 0.0,
	}

static func _runtime_state(request: Dictionary, actor: Dictionary,
		relationships: RelationshipStore, coordinator: MaterialRequestCoordinator,
		now_tick: int, seed: int) -> Dictionary:
	var status := String(request.get("status", ""))
	var result := {"request": request.duplicate(true), "candidate": {}, "target_decision": {}}
	var visible: Array = actor.get("others_visible", [])
	match status:
		Contract.STATUS_ACTIVE:
			var excluded := _answered_targets(request)
			var knowledge: Dictionary = request.get("knowledge_context", {})
			var beliefs := HolderBeliefs.candidates(actor, String(request.get("item_id", "")), visible,
				relationships, now_tick, excluded, int(knowledge.get("max_holder_belief_age_ticks", HolderBeliefs.DEFAULT_MAX_AGE_TICKS)))
			var decision: Dictionary = coordinator.request_policy.choose_target(request, beliefs, now_tick, seed)
			if bool(decision.get("ok", false)):
				result["target_decision"] = decision
				result["candidate"] = _request_candidate(request, decision)
		Contract.STATUS_WAITING_REQUESTER:
			if visible.has(String(request.get("target_id", ""))):
				result["candidate"] = _counter_candidate(request)
		Contract.STATUS_WAITING_TRANSFER:
			if visible.has(String(request.get("target_id", ""))):
				result["candidate"] = _transfer_candidate(request)
	return result

static func _select_material_blocker(proposals: Array) -> Dictionary:
	var rows: Array = []
	for raw_plan in proposals:
		if not raw_plan is Dictionary:
			continue
		var plan: Dictionary = raw_plan
		for raw_blocker in plan.get("blockers", []):
			if not raw_blocker is Dictionary:
				continue
			var blocker: Dictionary = raw_blocker
			if String(blocker.get("reason_code", "")) != "UNKNOWN_SOURCE":
				continue
			if String(blocker.get("item_id", "")).is_empty() or int(blocker.get("quantity", 0)) <= 0:
				continue
			var row := blocker.duplicate(true)
			row["plan_id"] = String(plan.get("plan_id", ""))
			row["root_goal"] = String(plan.get("root_goal", ""))
			rows.append(row)
	rows.sort_custom(func(a, b):
		var ak := "%s|%s" % [String(a.get("plan_id", "")), String(a.get("item_id", ""))]
		var bk := "%s|%s" % [String(b.get("plan_id", "")), String(b.get("item_id", ""))]
		return ak < bk)
	return {} if rows.is_empty() else (rows[0] as Dictionary).duplicate(true)

static func _answered_targets(request: Dictionary) -> Array:
	var out: Array = []
	for raw in request.get("history", []):
		if not raw is Dictionary or String(raw.get("kind", "")) != "RESPONSE_RECORDED":
			continue
		var payload: Dictionary = raw.get("payload", {})
		var outcome := String(payload.get("outcome", ""))
		if outcome not in [Contract.OUTCOME_REFUSE, Contract.OUTCOME_UNKNOWN]:
			continue
		var target := String(payload.get("responder_id", ""))
		if not target.is_empty() and not out.has(target):
			out.append(target)
	return out

static func _request_candidate(request: Dictionary, decision: Dictionary) -> Dictionary:
	var urgency := clampf(float(request.get("urgency", 0.5)), 0.0, 1.0)
	var score := clampf(float(decision.get("score", 0.0)), 0.0, 1.0)
	return {"action": "request_material", "target": null,
		"target_actor": String(decision.get("target_id", "")),
		"request_id": String(request.get("request_id", "")),
		"item_id": String(request.get("item_id", "")),
		"quantity": int(request.get("requested_quantity", 0)),
		"utility": clampf(urgency * 0.65 + score * 0.35, 0.0, 1.0),
		"desc": "请求所缺材料", "duration": 1, "material_request": true}

static func _counter_candidate(request: Dictionary) -> Dictionary:
	var requested := maxi(1, int(request.get("requested_quantity", 1)))
	var accepted := maxi(0, int(request.get("accepted_quantity", 0)))
	var fraction := clampf(float(accepted) / float(requested), 0.0, 1.0)
	return {"action": "accept_material_counter", "target": null,
		"target_actor": String(request.get("target_id", "")),
		"request_id": String(request.get("request_id", "")),
		"item_id": String(request.get("item_id", "")), "quantity": accepted,
		"utility": clampf(float(request.get("urgency", 0.5)) * 0.7 + fraction * 0.3, 0.0, 1.0),
		"desc": "接受材料还价", "duration": 1, "material_request": true}

static func _transfer_candidate(request: Dictionary) -> Dictionary:
	var urgency := clampf(float(request.get("urgency", 0.5)), 0.0, 1.0)
	return {"action": "receive_material", "target": null,
		"target_actor": String(request.get("target_id", "")),
		"request_id": String(request.get("request_id", "")),
		"item_id": String(request.get("item_id", "")),
		"quantity": int(request.get("accepted_quantity", 0)),
		"utility": urgency, "desc": "接收约定材料", "duration": 1, "material_request": true}

static func _urgency(actor: Dictionary, root_goal: String) -> float:
	var needs: Dictionary = actor.get("needs", {})
	match root_goal:
		"HUNGER": return clampf(float(needs.get("hunger", 0)) / 1000.0, 0.0, 1.0)
		"THIRST": return clampf(float(needs.get("thirst", 0)) / 1000.0, 0.0, 1.0)
	return clampf(maxf(float(needs.get("hunger", 0)), float(needs.get("thirst", 0))) / 1000.0, 0.0, 1.0)

static func _reserve_quantity(sim: IslandSimulation, actor_id: String, item_id: String) -> int:
	var actor: Dictionary = sim.actors.get(actor_id, {})
	var inv_quantity := maxi(0, int((actor.get("inventory", {}) as Dictionary).get(item_id, 0)))
	if inv_quantity <= 0:
		return 0
	if item_id == "food":
		return mini(inv_quantity, ceili(clampf(float((actor.get("needs", {}) as Dictionary).get("hunger", 0)) / 1000.0, 0.0, 1.0) * float(inv_quantity)))
	var run: Dictionary = sim.agency_plan_run(actor_id)
	if run.is_empty():
		return 0
	var step_id := String(run.get("current_step_id", ""))
	for raw_step in run.get("steps", []):
		if not raw_step is Dictionary:
			continue
		var step: Dictionary = raw_step
		if String(step.get("step_id", "")) == step_id and String(step.get("item_id", "")) == item_id:
			return mini(inv_quantity, maxi(0, int(step.get("quantity", 0))))
	return 0
