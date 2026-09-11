extends RefCounted
class_name MaterialRequestTracker

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")

var _requests: Dictionary = {}

func start_request(request: Dictionary) -> Dictionary:
	var errors := Contract.validate(request)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var request_id := String(request.get("request_id", ""))
	if _requests.has(request_id):
		return {"ok": false, "errors": PackedStringArray(["REQUEST_ALREADY_EXISTS"])}
	var stored: Dictionary = request.duplicate(true)
	_append_history(stored, "REQUEST_CREATED", int(stored.get("created_tick", 0)), {})
	_requests[request_id] = stored
	return {"ok": true, "request": Contract.snapshot(stored)}

func has_request(request_id: String) -> bool:
	return _requests.has(request_id)

func get_request(request_id: String) -> Dictionary:
	if not _requests.has(request_id):
		return {}
	return Contract.snapshot(_requests[request_id])

func active_requests_for(requester_id: String) -> Array:
	var result: Array = []
	for request_id in _requests.keys():
		var request: Dictionary = _requests[request_id]
		if String(request.get("requester_id", "")) != requester_id:
			continue
		if Contract.is_terminal(String(request.get("status", ""))):
			continue
		result.append(Contract.snapshot(request))
	result.sort_custom(_sort_by_created_then_id)
	return result

func record_offer(request_id: String, target_id: String, tick: int, offer: Dictionary = {}) -> bool:
	if not _requests.has(request_id):
		return false
	var request: Dictionary = _requests[request_id]
	if Contract.is_terminal(String(request.get("status", ""))):
		return false
	if target_id.strip_edges().is_empty() or target_id == String(request.get("requester_id", "")):
		return false
	request["target_id"] = target_id
	request["status"] = Contract.STATUS_WAITING_RESPONSE
	request["updated_tick"] = tick
	request["attempt_count"] = int(request.get("attempt_count", 0)) + 1
	request["last_offer"] = offer.duplicate(true)
	_append_history(request, "OFFER_SENT", tick, {
		"target_id": target_id,
		"offer": offer.duplicate(true),
	})
	_requests[request_id] = request
	return true

func record_response(
	request_id: String,
	responder_id: String,
	outcome: String,
	tick: int,
	accepted_quantity: int = 0,
	reason: String = "",
	counter: Dictionary = {}
) -> bool:
	if not _requests.has(request_id):
		return false
	# Work on a deep copy so validation failures cannot leak partial response state
	# into the stored request through Dictionary reference semantics.
	var request: Dictionary = (_requests[request_id] as Dictionary).duplicate(true)
	if String(request.get("status", "")) != Contract.STATUS_WAITING_RESPONSE:
		return false
	if responder_id != String(request.get("target_id", "")):
		return false
	if outcome not in [Contract.OUTCOME_ACCEPT, Contract.OUTCOME_REFUSE, Contract.OUTCOME_COUNTER, Contract.OUTCOME_UNKNOWN]:
		return false

	request["response_outcome"] = outcome
	request["response_reason"] = reason
	request["updated_tick"] = tick
	request["last_counter"] = counter.duplicate(true)

	match outcome:
		Contract.OUTCOME_ACCEPT:
			var requested := int(request.get("requested_quantity", 0))
			var accepted := accepted_quantity if accepted_quantity > 0 else requested
			if accepted <= 0 or accepted > requested:
				return false
			request["accepted_quantity"] = accepted
			request["status"] = Contract.STATUS_WAITING_TRANSFER
		Contract.OUTCOME_COUNTER:
			var counter_quantity := int(counter.get("quantity", accepted_quantity))
			if counter_quantity <= 0 or counter_quantity > int(request.get("requested_quantity", 0)):
				return false
			request["accepted_quantity"] = counter_quantity
			request["status"] = Contract.STATUS_WAITING_REQUESTER
		Contract.OUTCOME_REFUSE, Contract.OUTCOME_UNKNOWN:
			request["accepted_quantity"] = 0
			request["status"] = Contract.STATUS_ACTIVE

	_append_history(request, "RESPONSE_RECORDED", tick, {
		"responder_id": responder_id,
		"outcome": outcome,
		"accepted_quantity": int(request.get("accepted_quantity", 0)),
		"reason": reason,
		"counter": counter.duplicate(true),
	})
	_requests[request_id] = request
	return true

func accept_counter(request_id: String, tick: int) -> bool:
	if not _requests.has(request_id):
		return false
	var request: Dictionary = _requests[request_id]
	if String(request.get("status", "")) != Contract.STATUS_WAITING_REQUESTER:
		return false
	if int(request.get("accepted_quantity", 0)) <= 0:
		return false
	request["response_outcome"] = Contract.OUTCOME_COUNTER_ACCEPTED
	request["status"] = Contract.STATUS_WAITING_TRANSFER
	request["updated_tick"] = tick
	_append_history(request, "COUNTER_ACCEPTED", tick, {
		"accepted_quantity": int(request.get("accepted_quantity", 0)),
	})
	_requests[request_id] = request
	return true

func record_transfer_evidence(request_id: String, event: Dictionary, tick: int) -> bool:
	if not _requests.has(request_id):
		return false
	var request: Dictionary = _requests[request_id]
	if String(request.get("status", "")) != Contract.STATUS_WAITING_TRANSFER:
		return false
	if not _matches_transfer_evidence(request, event):
		_append_history(request, "TRANSFER_EVIDENCE_REJECTED", tick, {
			"event_id": String(event.get("event_id", "")),
			"event_type": String(event.get("type", "")),
		})
		_requests[request_id] = request
		return false

	request["status"] = Contract.STATUS_RESOLVED
	request["updated_tick"] = tick
	request["transfer_event_id"] = String(event.get("event_id", ""))
	request["parent_revalidation_pending"] = true
	request["parent_revalidation_consumed"] = false
	_append_history(request, "TRANSFER_CONFIRMED", tick, {
		"event_id": String(event.get("event_id", "")),
		"quantity": int(event.get("quantity", 0)),
	})
	_requests[request_id] = request
	return true

func consume_parent_revalidation(request_id: String) -> Dictionary:
	if not _requests.has(request_id):
		return {}
	var request: Dictionary = _requests[request_id]
	if String(request.get("status", "")) != Contract.STATUS_RESOLVED:
		return {}
	if not bool(request.get("parent_revalidation_pending", false)):
		return {}
	if bool(request.get("parent_revalidation_consumed", false)):
		return {}
	request["parent_revalidation_pending"] = false
	request["parent_revalidation_consumed"] = true
	_requests[request_id] = request
	return {
		"request_id": request_id,
		"requester_id": String(request.get("requester_id", "")),
		"parent_plan_id": String(request.get("parent_plan_id", "")),
		"root_goal": String(request.get("root_goal", "")),
		"item_id": String(request.get("item_id", "")),
		"quantity": int(request.get("accepted_quantity", 0)),
		"transfer_event_id": String(request.get("transfer_event_id", "")),
	}

func cancel(request_id: String, tick: int, reason: String = "") -> bool:
	return _finish(request_id, Contract.STATUS_CANCELLED, tick, reason)

func fail(request_id: String, tick: int, reason: String = "") -> bool:
	return _finish(request_id, Contract.STATUS_FAILED, tick, reason)

func expire_due(now_tick: int) -> Array:
	var expired: Array = []
	for request_id in _requests.keys():
		var request: Dictionary = _requests[request_id]
		if Contract.is_terminal(String(request.get("status", ""))):
			continue
		if now_tick <= int(request.get("expires_tick", now_tick)):
			continue
		request["status"] = Contract.STATUS_EXPIRED
		request["updated_tick"] = now_tick
		request["response_reason"] = "REQUEST_EXPIRED"
		_append_history(request, "REQUEST_EXPIRED", now_tick, {})
		_requests[request_id] = request
		expired.append(Contract.snapshot(request))
	return expired

func snapshot() -> Dictionary:
	var result: Dictionary = {}
	for request_id in _requests.keys():
		result[request_id] = Contract.snapshot(_requests[request_id])
	return result

func _finish(request_id: String, status: String, tick: int, reason: String) -> bool:
	if not _requests.has(request_id):
		return false
	var request: Dictionary = _requests[request_id]
	if Contract.is_terminal(String(request.get("status", ""))):
		return false
	request["status"] = status
	request["updated_tick"] = tick
	request["response_reason"] = reason
	_append_history(request, status, tick, {"reason": reason})
	_requests[request_id] = request
	return true

func _matches_transfer_evidence(request: Dictionary, event: Dictionary) -> bool:
	if String(event.get("type", "")) != Contract.EVENT_ITEM_TRANSFER_COMPLETED:
		return false
	if String(event.get("request_id", "")) != String(request.get("request_id", "")):
		return false
	if String(event.get("from_actor_id", "")) != String(request.get("target_id", "")):
		return false
	if String(event.get("to_actor_id", "")) != String(request.get("requester_id", "")):
		return false
	if String(event.get("item_id", "")) != String(request.get("item_id", "")):
		return false
	if int(event.get("quantity", 0)) < int(request.get("accepted_quantity", 0)):
		return false
	if String(event.get("evidence_kind", "")) != "WORLD_MUTATION":
		return false
	return not String(event.get("event_id", "")).strip_edges().is_empty()

func _append_history(request: Dictionary, kind: String, tick: int, payload: Dictionary) -> void:
	var history: Array = request.get("history", [])
	history.append({
		"kind": kind,
		"tick": tick,
		"payload": payload.duplicate(true),
	})
	request["history"] = history

static func _sort_by_created_then_id(a: Dictionary, b: Dictionary) -> bool:
	var a_tick := int(a.get("created_tick", 0))
	var b_tick := int(b.get("created_tick", 0))
	if a_tick != b_tick:
		return a_tick < b_tick
	return String(a.get("request_id", "")) < String(b.get("request_id", ""))
