extends RefCounted
class_name MaterialTransferService

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")

func execute(
	request: Dictionary,
	giver_inventory: Dictionary,
	receiver_inventory: Dictionary,
	tick: int
) -> Dictionary:
	var validation := _validate_execution(request, giver_inventory)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"reason": String(validation.get("reason", "INVALID_TRANSFER")),
			"event": {},
			"mutated": false,
		}

	var item_id := String(request.get("item_id", ""))
	var quantity := int(request.get("accepted_quantity", 0))
	var giver_before := int(giver_inventory.get(item_id, 0))
	var receiver_before := int(receiver_inventory.get(item_id, 0))

	giver_inventory[item_id] = giver_before - quantity
	receiver_inventory[item_id] = receiver_before + quantity

	var event := {
		"event_id": "transfer:%s:%d" % [String(request.get("request_id", "")), tick],
		"type": Contract.EVENT_ITEM_TRANSFER_COMPLETED,
		"request_id": String(request.get("request_id", "")),
		"from_actor_id": String(request.get("target_id", "")),
		"to_actor_id": String(request.get("requester_id", "")),
		"item_id": item_id,
		"quantity": quantity,
		"tick": tick,
		"evidence_kind": "WORLD_MUTATION",
		"giver_before": giver_before,
		"giver_after": int(giver_inventory.get(item_id, 0)),
		"receiver_before": receiver_before,
		"receiver_after": int(receiver_inventory.get(item_id, 0)),
	}
	return {
		"ok": true,
		"reason": "TRANSFER_COMPLETED",
		"event": event,
		"mutated": true,
	}

func preview(request: Dictionary, giver_inventory: Dictionary) -> Dictionary:
	var validation := _validate_execution(request, giver_inventory)
	return {
		"ok": bool(validation.get("ok", false)),
		"reason": String(validation.get("reason", "")),
		"item_id": String(request.get("item_id", "")),
		"quantity": int(request.get("accepted_quantity", 0)),
		"available": int(giver_inventory.get(String(request.get("item_id", "")), 0)),
		"mutated": false,
	}

func _validate_execution(request: Dictionary, giver_inventory: Dictionary) -> Dictionary:
	if String(request.get("status", "")) != Contract.STATUS_WAITING_TRANSFER:
		return {"ok": false, "reason": "REQUEST_NOT_WAITING_FOR_TRANSFER"}
	var outcome := String(request.get("response_outcome", ""))
	if outcome not in [Contract.OUTCOME_ACCEPT, Contract.OUTCOME_COUNTER_ACCEPTED]:
		return {"ok": false, "reason": "TRANSFER_NOT_AUTHORIZED"}
	var item_id := String(request.get("item_id", ""))
	if item_id.strip_edges().is_empty():
		return {"ok": false, "reason": "ITEM_ID_REQUIRED"}
	var quantity := int(request.get("accepted_quantity", 0))
	if quantity <= 0:
		return {"ok": false, "reason": "TRANSFER_QUANTITY_INVALID"}
	if int(giver_inventory.get(item_id, 0)) < quantity:
		return {"ok": false, "reason": "GIVER_INVENTORY_CHANGED"}
	if String(request.get("target_id", "")).strip_edges().is_empty():
		return {"ok": false, "reason": "GIVER_REQUIRED"}
	if String(request.get("requester_id", "")).strip_edges().is_empty():
		return {"ok": false, "reason": "RECEIVER_REQUIRED"}
	return {"ok": true, "reason": "TRANSFER_VALID"}
