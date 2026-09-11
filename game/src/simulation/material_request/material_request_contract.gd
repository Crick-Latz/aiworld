extends RefCounted
class_name MaterialRequestContract

const STATUS_ACTIVE := "ACTIVE"
const STATUS_WAITING_RESPONSE := "WAITING_RESPONSE"
const STATUS_WAITING_REQUESTER := "WAITING_REQUESTER"
const STATUS_WAITING_TRANSFER := "WAITING_TRANSFER"
const STATUS_RESOLVED := "RESOLVED"
const STATUS_CANCELLED := "CANCELLED"
const STATUS_FAILED := "FAILED"
const STATUS_EXPIRED := "EXPIRED"

const OUTCOME_ACCEPT := "ACCEPT"
const OUTCOME_REFUSE := "REFUSE"
const OUTCOME_COUNTER := "COUNTER"
const OUTCOME_UNKNOWN := "UNKNOWN"
const OUTCOME_COUNTER_ACCEPTED := "COUNTER_ACCEPTED"

const EVENT_ITEM_TRANSFER_COMPLETED := "ITEM_TRANSFER_COMPLETED"

static func make_request(
	request_id: String,
	requester_id: String,
	item_id: String,
	quantity: int,
	root_goal: String,
	parent_plan_id: String,
	created_tick: int,
	expires_tick: int,
	urgency: float = 0.5
) -> Dictionary:
	return {
		"request_id": request_id,
		"requester_id": requester_id,
		"target_id": "",
		"item_id": item_id,
		"requested_quantity": quantity,
		"accepted_quantity": 0,
		"root_goal": root_goal,
		"parent_plan_id": parent_plan_id,
		"created_tick": created_tick,
		"updated_tick": created_tick,
		"expires_tick": expires_tick,
		"urgency": clampf(urgency, 0.0, 1.0),
		"status": STATUS_ACTIVE,
		"response_outcome": "",
		"response_reason": "",
		"attempt_count": 0,
		"transfer_event_id": "",
		"parent_revalidation_pending": false,
		"parent_revalidation_consumed": false,
		"history": [],
	}

static func validate(request: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if String(request.get("request_id", "")).strip_edges().is_empty():
		errors.append("REQUEST_ID_REQUIRED")
	if String(request.get("requester_id", "")).strip_edges().is_empty():
		errors.append("REQUESTER_ID_REQUIRED")
	if String(request.get("item_id", "")).strip_edges().is_empty():
		errors.append("ITEM_ID_REQUIRED")
	if int(request.get("requested_quantity", 0)) <= 0:
		errors.append("QUANTITY_MUST_BE_POSITIVE")
	if int(request.get("expires_tick", -1)) < int(request.get("created_tick", 0)):
		errors.append("EXPIRY_PRECEDES_CREATION")
	if not _valid_status(String(request.get("status", ""))):
		errors.append("INVALID_STATUS")
	return errors

static func is_terminal(status: String) -> bool:
	return status in [STATUS_RESOLVED, STATUS_CANCELLED, STATUS_FAILED, STATUS_EXPIRED]

static func snapshot(request: Dictionary) -> Dictionary:
	return request.duplicate(true)

static func _valid_status(status: String) -> bool:
	return status in [
		STATUS_ACTIVE,
		STATUS_WAITING_RESPONSE,
		STATUS_WAITING_REQUESTER,
		STATUS_WAITING_TRANSFER,
		STATUS_RESOLVED,
		STATUS_CANCELLED,
		STATUS_FAILED,
		STATUS_EXPIRED,
	]
