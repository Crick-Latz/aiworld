class_name CommitmentContract
extends RefCounted
## P7.2：条件承诺合约常量与构造/校验。权威台账是 IslandSimulation.obligations
## （单台账铁律）；本文件只定义记录形状，不持有状态。

const STATUS_PENDING_ACTIVATION := "PENDING_ACTIVATION"
const STATUS_ACTIVE := "ACTIVE"
const STATUS_FULFILLED := "FULFILLED"
const STATUS_VIOLATED := "VIOLATED"
const STATUS_CANCELLED := "CANCELLED"

const TERMINAL_STATUSES := [STATUS_FULFILLED, STATUS_VIOLATED, STATUS_CANCELLED]

const SOURCE_MATERIAL_REQUEST := "MATERIAL_REQUEST_COUNTER"

const CANCEL_SOURCE_TRANSFER_FAILED := "SOURCE_TRANSFER_FAILED"
const CANCEL_SOURCE_REQUEST_FAILED := "SOURCE_REQUEST_FAILED"
const CANCEL_CREDITOR_GONE := "CREDITOR_GONE"

const EVENT_COMMITMENT_CREATED := "COMMITMENT_CREATED"
const EVENT_COMMITMENT_ACTIVATED := "COMMITMENT_ACTIVATED"
const EVENT_COMMITMENT_FULFILLED := "COMMITMENT_FULFILLED"
const EVENT_COMMITMENT_VIOLATED := "COMMITMENT_VIOLATED"
const EVENT_COMMITMENT_CANCELLED := "COMMITMENT_CANCELLED"
const EVENT_COMMITMENT_TERMS_MISMATCH := "COMMITMENT_TERMS_MISMATCH"
const EVENT_COMMITMENT_TRANSFER_COMPLETED := "COMMITMENT_TRANSFER_COMPLETED"

## 承诺默认期限（tick）。来自协商条款时可覆盖。
const DEFAULT_DUE_TICKS := 240

static func is_terminal(status: String) -> bool:
	return TERMINAL_STATUSES.has(status)

static func is_active_debt(record: Dictionary) -> bool:
	## 新承诺：ACTIVE 才是真实债务；PENDING 无对价不成债。
	return str(record.get("status", "")) == STATUS_ACTIVE

## 旧 obligations 记录（无 status 字段）按未偿债务计；新承诺按 authoritative status。
static func counts_toward_load(record: Dictionary) -> bool:
	if record.has("status"):
		return is_active_debt(record)
	return not bool(record.get("repaid", false))

static func make(
	commitment_id: String,
	debtor_id: String,
	creditor_id: String,
	object_id: String,
	quantity: int,
	created_tick: int,
	due_tick: int,
	source_kind: String,
	source_request_id: String,
	terms: Dictionary
) -> Dictionary:
	return {
		"commitment_id": commitment_id,
		"debtor_id": debtor_id,
		"creditor_id": creditor_id,
		"object_id": object_id,
		"quantity": maxi(0, quantity),
		"status": STATUS_PENDING_ACTIVATION,
		"created_tick": created_tick,
		"activated_tick": -1,
		"due_tick": due_tick,
		"terminal_tick": -1,
		"source_kind": source_kind,
		"source_request_id": source_request_id,
		"source_transfer_event_id": "",
		"parent_plan_id": "",
		"parent_run_id": "",
		"blocker_step_id": "",
		"terms": terms.duplicate(true),
		"terminal_reason": "",
		"history": [],
		# 旧认知/视图兼容字段：由 authoritative status 派生，绝不独立维护。
		"debtor": debtor_id,
		"creditor": creditor_id,
		"object": object_id,
		"made_tick": created_tick,
		"repaid": false,
		"promise_event_seq": -1,
	}

## 合约校验：ID 唯一由 tracker 保证；此处校验记录自身完整性。
static func validate(record: Dictionary) -> Array:
	var errors: Array = []
	if str(record.get("commitment_id", "")) == "":
		errors.append("MISSING_COMMITMENT_ID")
	if str(record.get("debtor_id", "")) == "" or str(record.get("creditor_id", "")) == "":
		errors.append("MISSING_PARTY")
	if str(record.get("debtor_id", "")) == str(record.get("creditor_id", "")):
		errors.append("SELF_COMMITMENT")
	if str(record.get("object_id", "")) == "":
		errors.append("MISSING_OBJECT")
	if int(record.get("quantity", 0)) <= 0:
		errors.append("NON_POSITIVE_QUANTITY")
	if int(record.get("due_tick", -1)) < int(record.get("created_tick", 0)):
		errors.append("DUE_BEFORE_CREATED")
	if typeof(record.get("terms", null)) != TYPE_DICTIONARY:
		errors.append("MISSING_TERMS")
	if not [STATUS_PENDING_ACTIVATION, STATUS_ACTIVE, STATUS_FULFILLED, STATUS_VIOLATED, STATUS_CANCELLED].has(str(record.get("status", ""))):
		errors.append("INVALID_STATUS")
	return errors

## 双方确认的条款一致性：object / quantity / due 不超过对方要求。
static func terms_match(demanded: Dictionary, offered: Dictionary) -> bool:
	if str(offered.get("object", "")) != str(demanded.get("object", "")):
		return false
	if int(offered.get("quantity", -1)) != int(demanded.get("quantity", -1)):
		return false
	if int(offered.get("due_tick", -1)) > int(demanded.get("due_tick", -1)):
		return false
	return true

static func append_history(record: Dictionary, entry_kind: String, now_tick: int, detail: Dictionary = {}) -> void:
	var history: Array = record.get("history", [])
	history.append({
		"kind": entry_kind,
		"tick": now_tick,
		"status": str(record.get("status", "")),
		"detail": detail.duplicate(true),
	})
	record["history"] = history
