extends RefCounted
class_name MaterialRequestCoordinator

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")
const Tracker = preload("res://src/simulation/material_request/material_request_tracker.gd")
const RequestPolicy = preload("res://src/simulation/material_request/material_request_policy.gd")
const ResponsePolicy = preload("res://src/simulation/material_request/material_request_response_policy.gd")
const TransferService = preload("res://src/simulation/material_request/material_transfer_service.gd")

var tracker
var request_policy
var response_policy
var transfer_service

func _init() -> void:
	tracker = Tracker.new()
	request_policy = RequestPolicy.new()
	response_policy = ResponsePolicy.new()
	transfer_service = TransferService.new()

func open_request(request: Dictionary) -> Dictionary:
	return tracker.start_request(request)

func choose_and_offer(
	request_id: String,
	candidate_beliefs: Array,
	now_tick: int,
	seed: int,
	exchange_offer: Dictionary = {}
) -> Dictionary:
	var request: Dictionary = tracker.get_request(request_id)
	if request.is_empty():
		return {"ok": false, "reason": "REQUEST_NOT_FOUND"}
	if String(request.get("status", "")) != Contract.STATUS_ACTIVE:
		return {"ok": false, "reason": "REQUEST_NOT_READY_FOR_TARGET_SELECTION"}
	var decision := request_policy.choose_target(request, candidate_beliefs, now_tick, seed)
	if not bool(decision.get("ok", false)):
		return decision
	var offer := request_policy.build_offer(request, decision, exchange_offer)
	if not tracker.record_offer(request_id, String(decision.get("target_id", "")), now_tick, offer):
		return {"ok": false, "reason": "OFFER_COULD_NOT_BE_RECORDED"}
	return {
		"ok": true,
		"reason": "OFFER_RECORDED",
		"decision": decision.duplicate(true),
		"offer": offer.duplicate(true),
		"request": tracker.get_request(request_id),
	}

func answer_request(
	request_id: String,
	responder_id: String,
	recipient_context: Dictionary,
	roll: float,
	tick: int
) -> Dictionary:
	var request := tracker.get_request(request_id)
	if request.is_empty():
		return {"ok": false, "reason": "REQUEST_NOT_FOUND"}
	var response := response_policy.evaluate(request, recipient_context, roll)
	var recorded := tracker.record_response(
		request_id,
		responder_id,
		String(response.get("outcome", "")),
		tick,
		int(response.get("accepted_quantity", 0)),
		String(response.get("reason", "")),
		response.get("counter", {})
	)
	return {
		"ok": recorded,
		"reason": "RESPONSE_RECORDED" if recorded else "RESPONSE_REJECTED",
		"response": response.duplicate(true),
		"request": tracker.get_request(request_id),
	}

func accept_counter(request_id: String, tick: int) -> Dictionary:
	var accepted := tracker.accept_counter(request_id, tick)
	return {
		"ok": accepted,
		"reason": "COUNTER_ACCEPTED" if accepted else "COUNTER_REJECTED",
		"request": tracker.get_request(request_id),
	}

func transfer_and_resolve(
	request_id: String,
	giver_inventory: Dictionary,
	receiver_inventory: Dictionary,
	tick: int
) -> Dictionary:
	var request := tracker.get_request(request_id)
	if request.is_empty():
		return {"ok": false, "reason": "REQUEST_NOT_FOUND", "event": {}}
	var transfer := transfer_service.execute(request, giver_inventory, receiver_inventory, tick)
	if not bool(transfer.get("ok", false)):
		return transfer
	var event: Dictionary = transfer.get("event", {})
	var resolved := tracker.record_transfer_evidence(request_id, event, tick)
	return {
		"ok": resolved,
		"reason": "REQUEST_RESOLVED" if resolved else "TRANSFER_EVIDENCE_REJECTED",
		"event": event.duplicate(true),
		"request": tracker.get_request(request_id),
		"revalidation": tracker.consume_parent_revalidation(request_id) if resolved else {},
	}
