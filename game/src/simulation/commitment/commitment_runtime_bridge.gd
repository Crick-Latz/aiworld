class_name CommitmentRuntimeBridge
extends RefCounted
## P7.2：承诺运行时编排——协商接线、激活/取消钩子、到期检查、履约结算、
## 追加式 trace。权威状态在 IslandSimulation.obligations（由 tracker 原地操作）；
## 本类只编排与记录，不复制状态。所有策略判断是确定性纯函数（无 RNG 消耗，
## 自然可错性来自角色主观输入）。

const Contract = preload("res://src/simulation/commitment/commitment_contract.gd")
const Policy = preload("res://src/simulation/commitment/commitment_offer_policy.gd")

var tracker: CommitmentTracker
var traces: Array = []

func _init() -> void:
	tracker = CommitmentTracker.new()

# ── 协商：请求者侧 ──

## A 收到 requires_exchange counter：独立决定是否以未来回报承诺换取材料。
## 返回 {accept, offered_terms, demanded_terms, reason}。
func requester_exchange_decision(
	request: Dictionary,
	counter: Dictionary,
	requester_context: Dictionary,
	now_tick: int
) -> Dictionary:
	var item_id := str(request.get("item_id", ""))
	var terms: Dictionary = counter.get("terms", {})
	var promise_quantity := maxi(1, int(terms.get("promise_quantity",
		counter.get("quantity", int(request.get("requested_quantity", 1))))))
	var evaluation: Dictionary = Policy.evaluate_requester_acceptance(requester_context)
	var demanded_due := now_tick + int(terms.get("due_ticks", Contract.DEFAULT_DUE_TICKS))
	var demanded := {
		"object": item_id,
		"quantity": promise_quantity,
		"due_tick": demanded_due,
	}
	# 条款分歧只发生在"A 愿意成交、但自己的期限估计确实超出对方要求"时——
	# 如实报出更长条款；不愿成交走 EXCHANGE_DECLINED，不冒充误解。
	var offered_due := demanded_due
	var terms_match := true
	if bool(evaluation.get("accept", false)):
		var estimate_due := now_tick + int(evaluation.get("offered_due_ticks", Contract.DEFAULT_DUE_TICKS))
		if estimate_due > demanded_due:
			offered_due = estimate_due
			terms_match = false
	var offered := {
		"object": item_id,
		"quantity": promise_quantity,
		"due_tick": mini(offered_due, demanded_due),
	}
	return {
		"accept": bool(evaluation.get("accept", false)) and terms_match,
		"reason": evaluation.get("reason", ""),
		"willingness": float(evaluation.get("willingness", 0.0)),
		"demanded_terms": demanded,
		"offered_terms": offered,
		"terms_match": terms_match,
	}

## A 接受 → 创建 PENDING_ACTIVATION 承诺（尚未成债）。
func open_commitment_for_request(
	obligations: Array,
	request: Dictionary,
	offered_terms: Dictionary,
	now_tick: int
) -> Dictionary:
	var debtor_id := str(request.get("requester_id", ""))
	var creditor_id := str(request.get("target_id", ""))
	var serial := tracker.next_serial(obligations, debtor_id)
	var commitment_id := "commitment:%s:%d:%s" % [debtor_id, serial, str(offered_terms.get("object", ""))]
	var record := Contract.make(
		commitment_id,
		debtor_id,
		creditor_id,
		str(offered_terms.get("object", "")),
		maxi(1, int(offered_terms.get("quantity", 1))),
		now_tick,
		int(offered_terms.get("due_tick", now_tick + Contract.DEFAULT_DUE_TICKS)),
		Contract.SOURCE_MATERIAL_REQUEST,
		str(request.get("request_id", "")),
		offered_terms
	)
	record["serial"] = serial
	record["parent_plan_id"] = str(request.get("parent_plan_id", ""))
	record["parent_run_id"] = str(request.get("parent_run_id", ""))
	record["blocker_step_id"] = str(request.get("blocker_step_id", ""))
	var created: Dictionary = tracker.create(obligations, record)
	if bool(created.get("ok", false)):
		_trace(Contract.EVENT_COMMITMENT_CREATED, created["commitment"], now_tick, "CREATED")
	return created

# ── 协商：授予方侧 ──

## B 验证 A 的承诺条款是否满足自己的条件（counter 接受前的最后一道门）。
func creditor_validate_offer(demanded_terms: Dictionary, offered_terms: Dictionary,
		creditor_context: Dictionary) -> Dictionary:
	if not Contract.terms_match(demanded_terms, offered_terms):
		return {
			"decision": "TERMS_MISMATCH",
			"reason": "COMMITMENT_TERMS_MISMATCH",
			"evaluation": {},
		}
	var evaluation: Dictionary = Policy.evaluate_commitment_offer(demanded_terms, offered_terms, creditor_context)
	if bool(evaluation.get("accepted", false)):
		return {"decision": "ACCEPT", "reason": evaluation.get("reason", ""), "evaluation": evaluation}
	return {"decision": "REJECT", "reason": evaluation.get("reason", ""), "evaluation": evaluation}

# ── 激活 / 取消钩子 ──

## 匹配的真实材料转移 → 承诺 ACTIVE。无关转移、状态不符一律拒绝。
func activate_from_transfer(obligations: Array, request: Dictionary, transfer_event: Dictionary,
		now_tick: int) -> Dictionary:
	var pending: Array = tracker.find_by_request(obligations, str(request.get("request_id", "")),
		[Contract.STATUS_PENDING_ACTIVATION])
	if pending.is_empty():
		return {"ok": false, "reason": "NO_PENDING_COMMITMENT"}
	var result: Dictionary = tracker.activate(obligations, str(pending[0].get("commitment_id", "")),
		transfer_event, now_tick)
	if bool(result.get("ok", false)):
		_trace(Contract.EVENT_COMMITMENT_ACTIVATED, result["commitment"], now_tick, "ACTIVATED",
			str(transfer_event.get("event_id", "")))
	return result

## 来源请求终态（转移失败/取消）→ 未激活承诺取消，不产生债务。
func cancel_for_request(obligations: Array, source_request_id: String, reason: String,
		now_tick: int) -> Array:
	var cancelled: Array = []
	for record in tracker.find_by_request(obligations, source_request_id,
			[Contract.STATUS_PENDING_ACTIVATION]):
		var result: Dictionary = tracker.cancel(obligations, str(record.get("commitment_id", "")),
			reason, now_tick)
		if bool(result.get("ok", false)):
			_trace(Contract.EVENT_COMMITMENT_CANCELLED, result["commitment"], now_tick, reason)
			cancelled.append(result["commitment"])
	return cancelled

## ACTIVE 承诺的债权人已不存在：义务无从履行 → 取消（不是违约）。
func cancel_orphaned(obligations: Array, existing_actor_ids: Array, now_tick: int) -> Array:
	var cancelled: Array = []
	for record in obligations:
		if typeof(record) != TYPE_DICTIONARY or not record.has("commitment_id"):
			continue
		if not Contract.is_active_debt(record):
			continue
		if existing_actor_ids.has(str(record.get("creditor_id", ""))):
			continue
		var result: Dictionary = tracker.cancel(obligations, str(record.get("commitment_id", "")),
			Contract.CANCEL_CREDITOR_GONE, now_tick)
		if bool(result.get("ok", false)):
			_trace(Contract.EVENT_COMMITMENT_CANCELLED, result["commitment"], now_tick,
				Contract.CANCEL_CREDITOR_GONE)
			cancelled.append(result["commitment"])
	return cancelled

## 到期违约检查：返回本次新违约记录（一次性）。
func violate_due(obligations: Array, now_tick: int) -> Array:
	var violated: Array = tracker.violate_due(obligations, now_tick)
	for record in violated:
		_trace(Contract.EVENT_COMMITMENT_VIOLATED, record, now_tick, "OVERDUE")
	return violated

# ── 履约结算 ──

## 真实履约：身份/数量/库存核验 → 唯一一次库存转移 → 证据 → FULFILLED。
## 重复执行、无关调用、库存不足一律拒绝且不改动库存。
func settle(obligations: Array, commitment_id: String, debtor_inventory: Dictionary,
		creditor_inventory: Dictionary, now_tick: int) -> Dictionary:
	var record := tracker.get_commitment(obligations, commitment_id)
	if record.is_empty():
		return {"ok": false, "reason": "COMMITMENT_NOT_FOUND", "mutated": false}
	if str(record.get("status", "")) != Contract.STATUS_ACTIVE:
		return {"ok": false, "reason": "NOT_ACTIVE", "mutated": false, "commitment": record}
	var quantity := int(record.get("quantity", 0))
	var object_id := str(record.get("object_id", ""))
	if int(debtor_inventory.get(object_id, 0)) < quantity:
		return {"ok": false, "reason": "INSUFFICIENT_QUANTITY", "mutated": false, "commitment": record}
	debtor_inventory[object_id] = int(debtor_inventory.get(object_id, 0)) - quantity
	creditor_inventory[object_id] = int(creditor_inventory.get(object_id, 0)) + quantity
	var evidence := {
		"event_id": "commitment-transfer:%s:%d" % [commitment_id, now_tick],
		"type": Contract.EVENT_COMMITMENT_TRANSFER_COMPLETED,
		"commitment_id": commitment_id,
		"request_id": "",
		"from_actor_id": str(record.get("debtor_id", "")),
		"to_actor_id": str(record.get("creditor_id", "")),
		"item_id": object_id,
		"quantity": quantity,
		"tick": now_tick,
		"evidence_kind": "WORLD_MUTATION",
	}
	_trace(Contract.EVENT_COMMITMENT_TRANSFER_COMPLETED, record, now_tick, "TRANSFER_COMPLETED", str(evidence["event_id"]))
	var fulfilled: Dictionary = tracker.fulfill(obligations, commitment_id, evidence, now_tick)
	if not bool(fulfilled.get("ok", false)):
		# 结算写账失败属不变式破坏：回滚转移并如实报告。
		debtor_inventory[object_id] = int(debtor_inventory.get(object_id, 0)) + quantity
		creditor_inventory[object_id] = int(creditor_inventory.get(object_id, 0)) - quantity
		return {"ok": false, "reason": str(fulfilled.get("reason", "FULFILL_FAILED")), "mutated": false,
			"commitment": fulfilled.get("commitment", record)}
	_trace(Contract.EVENT_COMMITMENT_FULFILLED, fulfilled["commitment"], now_tick, "FULFILLED",
		str(evidence["event_id"]))
	return {"ok": true, "mutated": true, "event": evidence, "commitment": fulfilled["commitment"]}

# ── 诊断输出 ──

func commitment(obligations: Array, commitment_id: String) -> Dictionary:
	return tracker.get_commitment(obligations, commitment_id)

func trace_snapshot() -> Array:
	return traces.duplicate(true)

func rng_states() -> Dictionary:
	## 承诺层决策为确定性纯函数——不消耗随机流（空状态即诊断证据）。
	return {}

func _trace(event_name: String, record: Dictionary, now_tick: int, reason: String,
		evidence_event_id: String = "") -> void:
	traces.append({
		"event": event_name,
		"tick": now_tick,
		"commitment_id": str(record.get("commitment_id", "")),
		"debtor_id": str(record.get("debtor_id", "")),
		"creditor_id": str(record.get("creditor_id", "")),
		"object_id": str(record.get("object_id", "")),
		"quantity": int(record.get("quantity", 0)),
		"status": str(record.get("status", "")),
		"reason": reason,
		"source_request_id": str(record.get("source_request_id", "")),
		"source_transfer_event_id": str(record.get("source_transfer_event_id", "")),
		"parent_plan_id": str(record.get("parent_plan_id", "")),
		"parent_run_id": str(record.get("parent_run_id", "")),
		"evidence_event_id": evidence_event_id,
	})
