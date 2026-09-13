class_name CommitmentTracker
extends RefCounted
## P7.2：承诺生命周期状态机。直接操作 IslandSimulation.obligations 这一唯一
## authoritative 台账（数组按引用传入、原地变更）；本类不持有任何独立状态副本，
## 无缓存索引——每次按 commitment_id 扫描（台账规模为个位数）。
## 旧字段（debtor/creditor/object/made_tick/repaid）一律由 status 派生，绝不独立写。

const Contract = preload("res://src/simulation/commitment/commitment_contract.gd")

func get_commitment(obligations: Array, commitment_id: String) -> Dictionary:
	for record in obligations:
		if typeof(record) == TYPE_DICTIONARY and str(record.get("commitment_id", "")) == commitment_id:
			return record
	return {}

func find_by_request(obligations: Array, source_request_id: String, statuses: Array = []) -> Array:
	var out: Array = []
	for record in obligations:
		if typeof(record) != TYPE_DICTIONARY or not record.has("commitment_id"):
			continue
		if str(record.get("source_request_id", "")) != source_request_id:
			continue
		if not statuses.is_empty() and not statuses.has(str(record.get("status", ""))):
			continue
		out.append(record)
	return out

func commitment_ids(obligations: Array) -> Array:
	var out: Array = []
	for record in obligations:
		if typeof(record) == TYPE_DICTIONARY and record.has("commitment_id"):
			out.append(str(record["commitment_id"]))
	return out

## 创建 PENDING_ACTIVATION：接受交换条件但材料尚未交付——无对价不成债。
func create(obligations: Array, record: Dictionary) -> Dictionary:
	var errors: Array = Contract.validate(record)
	if not errors.is_empty():
		return {"ok": false, "reason": "INVALID_COMMITMENT", "errors": errors}
	if str(record.get("commitment_id", "")) != "" and not get_commitment(obligations, str(record["commitment_id"])).is_empty():
		return {"ok": false, "reason": "DUPLICATE_COMMITMENT_ID"}
	Contract.append_history(record, "CREATED", int(record.get("created_tick", 0)), {"terms": record.get("terms", {})})
	obligations.append(record)
	return {"ok": true, "commitment": record}

## 匹配的真实转移证据 → ACTIVE。身份不符/状态不符一律拒绝（fail closed）。
func activate(obligations: Array, commitment_id: String, transfer_event: Dictionary, now_tick: int,
		required_quantity: int = 0) -> Dictionary:
	var record := get_commitment(obligations, commitment_id)
	if record.is_empty():
		return {"ok": false, "reason": "COMMITMENT_NOT_FOUND"}
	if str(record.get("status", "")) != Contract.STATUS_PENDING_ACTIVATION:
		return {"ok": false, "reason": "NOT_PENDING_ACTIVATION", "commitment": record}
	# 转移证据必须指向同一请求且物品一致——无关转移不得激活承诺。
	if str(transfer_event.get("request_id", "")) != str(record.get("source_request_id", "")):
		return {"ok": false, "reason": "TRANSFER_REQUEST_MISMATCH", "commitment": record}
	# P7.2A：激活只认真实 P7.1 材料转移证据——类型/证据号/世界变更标记/方向/物品/数量
	# 全字段核验；任何伪造或缺项一律拒绝，状态保持 PENDING、零副作用。
	var evidence_errors := _source_transfer_evidence_errors(record, transfer_event, required_quantity)
	if not evidence_errors.is_empty():
		return {"ok": false, "reason": evidence_errors[0], "errors": evidence_errors, "commitment": record}
	record["status"] = Contract.STATUS_ACTIVE
	record["activated_tick"] = now_tick
	record["source_transfer_event_id"] = str(transfer_event.get("event_id", ""))
	Contract.append_history(record, "ACTIVATED", now_tick, {
		"transfer_event_id": str(transfer_event.get("event_id", "")),
		"quantity": int(transfer_event.get("quantity", 0)),
	})
	_sync_legacy(record)
	return {"ok": true, "commitment": record}

## 未激活承诺取消：交换已接受但来源转移最终失败——不得留下无对价债务。
func cancel(obligations: Array, commitment_id: String, reason: String, now_tick: int) -> Dictionary:
	var record := get_commitment(obligations, commitment_id)
	if record.is_empty():
		return {"ok": false, "reason": "COMMITMENT_NOT_FOUND"}
	var status := str(record.get("status", ""))
	if status != Contract.STATUS_PENDING_ACTIVATION and status != Contract.STATUS_ACTIVE:
		return {"ok": false, "reason": "ALREADY_TERMINAL", "commitment": record}
	record["status"] = Contract.STATUS_CANCELLED
	record["terminal_tick"] = now_tick
	record["terminal_reason"] = reason
	Contract.append_history(record, "CANCELLED", now_tick, {"reason": reason})
	_sync_legacy(record)
	return {"ok": true, "commitment": record}

## 履约结算成功后 → FULFILLED（一次性；重复/无关转移被拒）。
func fulfill(obligations: Array, commitment_id: String, transfer_event: Dictionary, now_tick: int) -> Dictionary:
	var record := get_commitment(obligations, commitment_id)
	if record.is_empty():
		return {"ok": false, "reason": "COMMITMENT_NOT_FOUND"}
	if str(record.get("status", "")) != Contract.STATUS_ACTIVE:
		return {"ok": false, "reason": "NOT_ACTIVE", "commitment": record}
	# P7.2A：履约结算证据全字段身份核验（type/事件号/世界变更/双方/物品/数量/承诺号）。
	var settle_errors := _settlement_evidence_errors(record, transfer_event)
	if not settle_errors.is_empty():
		return {"ok": false, "reason": settle_errors[0], "errors": settle_errors, "commitment": record}
	record["status"] = Contract.STATUS_FULFILLED
	record["terminal_tick"] = now_tick
	record["terminal_reason"] = "FULFILLED"
	Contract.append_history(record, "FULFILLED", now_tick, {
		"transfer_event_id": str(transfer_event.get("event_id", "")),
		"quantity": int(transfer_event.get("quantity", 0)),
	})
	_sync_legacy(record)
	return {"ok": true, "commitment": record}

## 到期仍 ACTIVE 且未履约 → VIOLATED（一次性，返回本次新违约记录）。
func violate_due(obligations: Array, now_tick: int) -> Array:
	var violated: Array = []
	for record in obligations:
		if typeof(record) != TYPE_DICTIONARY or not record.has("commitment_id"):
			continue
		if str(record.get("status", "")) != Contract.STATUS_ACTIVE:
			continue
		if now_tick <= int(record.get("due_tick", 0)):
			continue
		record["status"] = Contract.STATUS_VIOLATED
		record["terminal_tick"] = now_tick
		record["terminal_reason"] = "OVERDUE"
		Contract.append_history(record, "VIOLATED", now_tick, {"due_tick": int(record.get("due_tick", 0))})
		_sync_legacy(record)
		violated.append(record)
	return violated

func active_of(obligations: Array, debtor_id: String) -> Array:
	var out: Array = []
	for record in obligations:
		if typeof(record) != TYPE_DICTIONARY or not record.has("commitment_id"):
			continue
		if str(record.get("debtor_id", "")) != debtor_id:
			continue
		if Contract.is_active_debt(record):
			out.append(record)
	return out

func active_count_for_load(obligations: Array, debtor_id: String) -> int:
	## §十四：负担计入真实 ACTIVE 承诺 + 旧未偿 obligations（同一台账，同一口径）。
	var count := 0
	for record in obligations:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var debtor := str(record.get("debtor", record.get("debtor_id", "")))
		if debtor != debtor_id:
			continue
		if Contract.counts_toward_load(record):
			count += 1
	return count

func next_serial(obligations: Array, debtor_id: String) -> int:
	var max_serial := 0
	for record in obligations:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var debtor := str(record.get("debtor", record.get("debtor_id", "")))
		if debtor != debtor_id:
			continue
		max_serial = maxi(max_serial, int(record.get("serial", 0)))
	return max_serial + 1

## P7.2A：来源转移证据校验——PENDING -> ACTIVE 只认真实世界 mutation。
static func _source_transfer_evidence_errors(record: Dictionary, event: Dictionary,
		required_quantity: int) -> Array:
	var errors: Array = []
	if str(event.get("type", "")) != "ITEM_TRANSFER_COMPLETED":
		errors.append("EVIDENCE_WRONG_TYPE")
	if str(event.get("event_id", "")) == "":
		errors.append("EVIDENCE_MISSING_EVENT_ID")
	if str(event.get("evidence_kind", "")) != "WORLD_MUTATION":
		errors.append("EVIDENCE_NOT_WORLD_MUTATION")
	if str(event.get("from_actor_id", "")) != str(record.get("creditor_id", "")):
		errors.append("EVIDENCE_WRONG_GIVER")
	if str(event.get("to_actor_id", "")) != str(record.get("debtor_id", "")):
		errors.append("EVIDENCE_WRONG_RECEIVER")
	if str(event.get("item_id", "")) != str(record.get("object_id", "")):
		errors.append("TRANSFER_ITEM_MISMATCH")
	if required_quantity > 0 and int(event.get("quantity", 0)) < required_quantity:
		errors.append("EVIDENCE_QUANTITY_BELOW_ACCEPTED")
	return errors

## P7.2A：履约结算证据校验——错向/错物/错量/伪证据不得 FULFILLED。
static func _settlement_evidence_errors(record: Dictionary, event: Dictionary) -> Array:
	var errors: Array = []
	if str(event.get("type", "")) != "COMMITMENT_TRANSFER_COMPLETED":
		errors.append("EVIDENCE_WRONG_TYPE")
	if str(event.get("event_id", "")) == "":
		errors.append("EVIDENCE_MISSING_EVENT_ID")
	if str(event.get("evidence_kind", "")) != "WORLD_MUTATION":
		errors.append("EVIDENCE_NOT_WORLD_MUTATION")
	if str(event.get("commitment_id", "")) != str(record.get("commitment_id", "")):
		errors.append("EVIDENCE_WRONG_COMMITMENT")
	if str(event.get("from_actor_id", "")) != str(record.get("debtor_id", "")):
		errors.append("EVIDENCE_WRONG_GIVER")
	if str(event.get("to_actor_id", "")) != str(record.get("creditor_id", "")):
		errors.append("EVIDENCE_WRONG_RECEIVER")
	if str(event.get("item_id", "")) != str(record.get("object_id", "")):
		errors.append("EVIDENCE_WRONG_ITEM")
	if int(event.get("quantity", 0)) < int(record.get("quantity", 0)):
		errors.append("TRANSFER_QUANTITY_INSUFFICIENT")
	return errors

## 兼容字段派生：repaid 只反映 authoritative status。
func _sync_legacy(record: Dictionary) -> void:
	record["repaid"] = Contract.is_terminal(str(record.get("status", "")))
	record["debtor"] = str(record.get("debtor_id", record.get("debtor", "")))
	record["creditor"] = str(record.get("creditor_id", record.get("creditor", "")))
	record["object"] = str(record.get("object_id", record.get("object", "")))
