class_name MaterialRequestRuntimeBridge
extends RefCounted

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")
const Coordinator = preload("res://src/simulation/material_request/material_request_coordinator.gd")

const REQUEST_TTL_TICKS := 48
const MAX_HOLDER_BELIEF_AGE_TICKS := 240
const INTERACTION_RANGE := 8
const MIN_HOLDER_BELIEF := 0.08
const MIN_RESPONSE_PRESSURE := 0.05

var coordinator
var traces: Array = []

var _request_by_blocker: Dictionary = {}
var _meta: Dictionary = {}
var _refused_targets: Dictionary = {}
var _rngs: Dictionary = {}
var _serials: Dictionary = {}
var _world_seed := 0

func _init(seed_value: int = 0) -> void:
	coordinator = Coordinator.new()
	_world_seed = seed_value

func ensure_request_for_blocker(
	requester_id: String,
	run: Dictionary,
	step: Dictionary,
	ctx: Dictionary,
	now_tick: int,
	recipes: RecipeCatalog,
	urgency: float = 0.5
) -> Dictionary:
	var gap := material_gap(step, run, ctx, recipes)
	var item_id := str(gap.get("item_id", ""))
	var quantity := int(gap.get("quantity", 0))
	if item_id == "" or quantity <= 0:
		return {"ok": false, "created": false, "reason": "NO_MATERIAL_GAP"}

	var parent_plan_id := str(run.get("plan_id", ""))
	var root_goal := str(run.get("root_goal", ""))
	var blocker_key := "%s|%s|%s" % [requester_id, parent_plan_id, item_id]
	if _request_by_blocker.has(blocker_key):
		var existing_id := str(_request_by_blocker[blocker_key])
		var existing: Dictionary = coordinator.tracker.get_request(existing_id)
		if not existing.is_empty() and not Contract.is_terminal(str(existing.get("status", ""))):
			return {"ok": true, "created": false, "reason": "REQUEST_ALREADY_ACTIVE", "request": existing}

	var serial := int(_serials.get(requester_id, 0)) + 1
	_serials[requester_id] = serial
	var request_id := "material:%s:%d:%s" % [requester_id, serial, item_id]
	var request := Contract.make_request(
		request_id,
		requester_id,
		item_id,
		quantity,
		root_goal,
		parent_plan_id,
		now_tick,
		now_tick + REQUEST_TTL_TICKS,
		urgency
	)
	request["knowledge_context"] = {
		"max_holder_belief_age_ticks": MAX_HOLDER_BELIEF_AGE_TICKS,
	}
	request["blocker_step_id"] = str(step.get("step_id", ""))
	request["blocker_reason"] = str(step.get("step_kind", step.get("kind", "")))
	var opened: Dictionary = coordinator.open_request(request)
	if not bool(opened.get("ok", false)):
		return {"ok": false, "created": false, "reason": "REQUEST_OPEN_FAILED", "errors": opened.get("errors", [])}
	_request_by_blocker[blocker_key] = request_id
	_meta[request_id] = {
		"blocker_key": blocker_key,
		"step_id": str(step.get("step_id", "")),
		"step_kind": str(step.get("kind", "")),
		"blocker_quantity": quantity,
	}
	_trace("MATERIAL_REQUEST_CREATED", opened.get("request", request), now_tick, "CREATED")
	return {
		"ok": true,
		"created": true,
		"reason": "CREATED",
		"request": coordinator.tracker.get_request(request_id),
	}

func build_holder_beliefs(
	requester_id: String,
	item_id: String,
	actor_view: Dictionary,
	now_tick: int
) -> Array:
	var out: Array = []
	var tom: TheoryOfMind = actor_view.get("tom", null)
	if tom == null or item_id == "":
		return out
	var origin: Vector2i = actor_view.get("tile", Vector2i.ZERO)
	var trust_of: Dictionary = actor_view.get("trust_of", {})
	var visible: Array = actor_view.get("others_visible", [])
	var predicate := holder_predicate(item_id)
	for peer in visible:
		if typeof(peer) != TYPE_DICTIONARY:
			continue
		var peer_id := str(peer.get("id", ""))
		if peer_id == "" or peer_id == requester_id:
			continue
		var peer_tile: Vector2i = peer.get("tile", origin)
		var distance := absi(origin.x - peer_tile.x) + absi(origin.y - peer_tile.y)
		if distance > INTERACTION_RANGE:
			continue
		var belief := tom.belief_about(peer_id, predicate)
		var confidence := tom.confidence_of(peer_id, predicate)
		if belief < MIN_HOLDER_BELIEF or confidence <= 0.0:
			continue
		var evidence_tick := tom.last_evidence_tick(peer_id, predicate)
		if evidence_tick < 0:
			evidence_tick = now_tick
		var trust_norm := normalize_relationship(int(trust_of.get(peer_id, 0)))
		out.append({
			"actor_id": peer_id,
			"item_id": item_id,
			"visible": true,
			"believed_quantity": 1,
			"confidence": confidence,
			"relationship": trust_norm,
			"expected_cooperation": tom.response_belief(peer_id, "shares_with_me"),
			"distance": distance,
			"evidence_tick": evidence_tick,
			"source": "TOM_POSSESSION_EVIDENCE",
		})
	out.sort_custom(func(a, b): return str(a.get("actor_id", "")) < str(b.get("actor_id", "")))
	return out

func try_offer(request_id: String, candidate_beliefs: Array, now_tick: int) -> Dictionary:
	var request: Dictionary = coordinator.tracker.get_request(request_id)
	if request.is_empty() or str(request.get("status", "")) != Contract.STATUS_ACTIVE:
		return {"ok": false, "reason": "REQUEST_NOT_ACTIVE", "request": request}
	var refused: Dictionary = _refused_targets.get(request_id, {})
	var eligible: Array = []
	for candidate in candidate_beliefs:
		if typeof(candidate) != TYPE_DICTIONARY:
			continue
		var target_id := str(candidate.get("actor_id", ""))
		if target_id == "" or refused.has(target_id):
			continue
		eligible.append((candidate as Dictionary).duplicate(true))
	var offered: Dictionary = coordinator.choose_and_offer(
		request_id,
		eligible,
		now_tick,
		_target_seed(request_id),
		{}
	)
	if bool(offered.get("ok", false)):
		var current: Dictionary = coordinator.tracker.get_request(request_id)
		_trace("MATERIAL_REQUEST_OFFERED", current, now_tick, "OFFERED")
		return offered
	if str(offered.get("reason", "")) == "NO_SUBJECTIVE_TARGET" and not bool(_meta.get(request_id, {}).get("no_target_traced", false)):
		var meta: Dictionary = _meta.get(request_id, {})
		meta["no_target_traced"] = true
		_meta[request_id] = meta
		_trace("MATERIAL_REQUEST_NO_SUBJECTIVE_TARGET", request, now_tick, "NO_SUBJECTIVE_TARGET")
	return offered

func respond(request_id: String, responder_id: String, recipient_context: Dictionary, now_tick: int) -> Dictionary:
	var request: Dictionary = coordinator.tracker.get_request(request_id)
	if request.is_empty() or str(request.get("status", "")) != Contract.STATUS_WAITING_RESPONSE:
		return {"ok": false, "reason": "REQUEST_NOT_WAITING_RESPONSE", "request": request}
	var rng := _response_rng(responder_id)
	var result: Dictionary = coordinator.answer_request(
		request_id,
		responder_id,
		recipient_context,
		rng.randf(),
		now_tick
	)
	if bool(result.get("ok", false)):
		var response: Dictionary = result.get("response", {})
		var outcome := str(response.get("outcome", ""))
		if outcome == Contract.OUTCOME_REFUSE:
			_remember_refusal(request_id, responder_id)
		_trace("MATERIAL_REQUEST_" + outcome, result.get("request", {}), now_tick, outcome)
	return result

func accept_counter(request_id: String, now_tick: int) -> Dictionary:
	var request: Dictionary = coordinator.tracker.get_request(request_id)
	if request.is_empty() or str(request.get("status", "")) != Contract.STATUS_WAITING_REQUESTER:
		return {"ok": false, "reason": "REQUEST_NOT_WAITING_REQUESTER", "request": request}
	if int(request.get("accepted_quantity", 0)) <= 0:
		return {"ok": false, "reason": "COUNTER_QUANTITY_INVALID", "request": request}
	var accepted: Dictionary = coordinator.accept_counter(request_id, now_tick)
	if bool(accepted.get("ok", false)):
		_trace("MATERIAL_COUNTER_ACCEPTED", accepted.get("request", {}), now_tick, "COUNTER_ACCEPTED")
	return accepted

func decline_counter(request_id: String, now_tick: int, reason: String = "REQUESTER_DECLINED") -> Dictionary:
	var request: Dictionary = coordinator.tracker.get_request(request_id)
	if request.is_empty() or str(request.get("status", "")) != Contract.STATUS_WAITING_REQUESTER:
		return {"ok": false, "reason": "REQUEST_NOT_WAITING_REQUESTER", "request": request}
	var cancelled: bool = coordinator.tracker.cancel(request_id, now_tick, reason)
	if cancelled:
		_trace("MATERIAL_COUNTER_DECLINED", coordinator.tracker.get_request(request_id), now_tick, reason)
	return {"ok": cancelled, "reason": reason, "request": coordinator.tracker.get_request(request_id)}

func transfer(request_id: String, giver_inventory: Dictionary, receiver_inventory: Dictionary, now_tick: int) -> Dictionary:
	var request: Dictionary = coordinator.tracker.get_request(request_id)
	if request.is_empty() or str(request.get("status", "")) != Contract.STATUS_WAITING_TRANSFER:
		return {"ok": false, "reason": "REQUEST_NOT_WAITING_TRANSFER", "request": request, "event": {}}
	var result: Dictionary = coordinator.transfer_and_resolve(
		request_id,
		giver_inventory,
		receiver_inventory,
		now_tick
	)
	if bool(result.get("ok", false)):
		_trace("MATERIAL_TRANSFER_COMPLETED", result.get("request", {}), now_tick, "TRANSFER_COMPLETED", str(result.get("event", {}).get("event_id", "")))
		_trace("MATERIAL_REQUEST_RESOLVED", result.get("request", {}), now_tick, "RESOLVED", str(result.get("event", {}).get("event_id", "")))
	else:
		coordinator.tracker.fail(request_id, now_tick, str(result.get("reason", "TRANSFER_FAILED")))
		_trace("MATERIAL_TRANSFER_FAILED", coordinator.tracker.get_request(request_id), now_tick, str(result.get("reason", "TRANSFER_FAILED")))
		result["request"] = coordinator.tracker.get_request(request_id)
	return result

func fail_request(request_id: String, now_tick: int, reason: String) -> bool:
	var failed: bool = coordinator.tracker.fail(request_id, now_tick, reason)
	if failed:
		_trace("MATERIAL_REQUEST_FAILED", coordinator.tracker.get_request(request_id), now_tick, reason)
	return failed

func expire_due(now_tick: int) -> Array:
	var expired: Array = coordinator.tracker.expire_due(now_tick)
	for request in expired:
		_trace("MATERIAL_REQUEST_EXPIRED", request, now_tick, "EXPIRED")
	return expired

func pending_requests_for(actor_id: String) -> Array:
	var out: Array = []
	for request_id in coordinator.tracker.snapshot():
		var request: Dictionary = coordinator.tracker.get_request(str(request_id))
		if request.is_empty() or Contract.is_terminal(str(request.get("status", ""))):
			continue
		if str(request.get("requester_id", "")) == actor_id or str(request.get("target_id", "")) == actor_id:
			out.append(request)
	out.sort_custom(func(a, b):
		var at := int(a.get("created_tick", 0))
		var bt := int(b.get("created_tick", 0))
		if at != bt:
			return at < bt
		return str(a.get("request_id", "")) < str(b.get("request_id", "")))
	return out

func request(request_id: String) -> Dictionary:
	return coordinator.tracker.get_request(request_id)

func trace_snapshot() -> Array:
	return traces.duplicate(true)

func rng_states() -> Dictionary:
	var states := {}
	var ids: Array = _rngs.keys()
	ids.sort()
	for id in ids:
		states[id] = str((_rngs[id] as RandomNumberGenerator).state)
	return states

func material_gap(step: Dictionary, run: Dictionary, ctx: Dictionary, recipes: RecipeCatalog) -> Dictionary:
	if typeof(step) != TYPE_DICTIONARY or recipes == null:
		return {}
	var possessed: Dictionary = ctx.get("possessed_items", {})
	var kind := str(step.get("kind", ""))
	if kind == "ACQUIRE":
		var item_id := str(step.get("item_id", ""))
		var baseline := int((run.get("baseline_items", {}) as Dictionary).get(item_id, 0))
		var required := baseline + int(step.get("quantity", 0))
		var gap := required - int(possessed.get(item_id, 0))
		if item_id != "" and gap > 0:
			return {"item_id": item_id, "quantity": gap}
		return {}
	if kind == "CRAFT":
		var recipe_id := str(step.get("recipe_id", ""))
		var recipe: Dictionary = recipes.spec(recipe_id)
		if recipe.is_empty():
			return {}
		var missing: Dictionary = RecipePlanAdapter.missing_ingredients(
			recipe.get("ingredients", {}),
			possessed
		)
		var keys: Array = missing.keys()
		keys.sort()
		if keys.is_empty():
			return {}
		var item_id := str(keys[0])
		var quantity := int(missing[item_id]) * maxi(1, int(step.get("quantity", 1)))
		return {"item_id": item_id, "quantity": quantity}
	return {}

static func holder_predicate(item_id: String) -> String:
	return "has_item:" + item_id

static func normalize_relationship(raw_trust: int) -> float:
	return clampf((float(raw_trust) + 1000.0) / 2000.0, 0.0, 1.0)

static func possession_observations(event: Dictionary) -> Array:
	var out: Array = []
	var event_type := str(event.get("type", ""))
	var actor_id := str(event.get("actor_id", ""))
	match event_type:
		"gathered_wood":
			out.append({"actor_id": actor_id, "item_id": "wood"})
		"gathered_shells":
			out.append({"actor_id": actor_id, "item_id": "shells"})
		"crafted":
			var produced: Dictionary = event.get("produced_items", {})
			var produced_keys: Array = produced.keys()
			produced_keys.sort()
			for item_id in produced_keys:
				if int(produced[item_id]) > 0:
					out.append({"actor_id": actor_id, "item_id": str(item_id)})
		Contract.EVENT_ITEM_TRANSFER_COMPLETED:
			var to_id := str(event.get("to_actor_id", ""))
			var item_id := str(event.get("item_id", ""))
			if to_id != "" and item_id != "":
				out.append({"actor_id": to_id, "item_id": item_id})
		"shared_food":
			var to_id := str(event.get("to_id", ""))
			if to_id != "":
				out.append({"actor_id": to_id, "item_id": "food"})
	return out

func _response_rng(responder_id: String) -> RandomNumberGenerator:
	if not _rngs.has(responder_id):
		var rng := RandomNumberGenerator.new()
		rng.seed = SeedDeriver.derive(_world_seed, "material_request_response:" + responder_id)
		_rngs[responder_id] = rng
	return _rngs[responder_id]

func _target_seed(request_id: String) -> int:
	return SeedDeriver.derive(_world_seed, "material_request_target:" + request_id)

func _remember_refusal(request_id: String, target_id: String) -> void:
	var refused: Dictionary = _refused_targets.get(request_id, {})
	refused[target_id] = true
	_refused_targets[request_id] = refused

func _trace(
	event_name: String,
	request: Dictionary,
	now_tick: int,
	reason: String = "",
	evidence_event_id: String = ""
) -> void:
	traces.append({
		"event": event_name,
		"tick": now_tick,
		"request_id": str(request.get("request_id", "")),
		"requester_id": str(request.get("requester_id", "")),
		"target_id": str(request.get("target_id", "")),
		"parent_plan_id": str(request.get("parent_plan_id", "")),
		"item_id": str(request.get("item_id", "")),
		"quantity": int(request.get("requested_quantity", 0)),
		"accepted_quantity": int(request.get("accepted_quantity", 0)),
		"status": str(request.get("status", "")),
		"reason": reason,
		"evidence_event_id": evidence_event_id,
	})
