extends SceneTree
## P7.2 承诺生命周期单元测试：合约校验、单台账状态机、激活/取消/履约/违约
## 的身份与一次性语义、库存结算的唯一性、负担口径。

const Contract = preload("res://src/simulation/commitment/commitment_contract.gd")
const Bridge = preload("res://src/simulation/commitment/commitment_runtime_bridge.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_contract_validation()
	_test_tracker_lifecycle()
	_test_transfer_activation_identity()
	_test_settlement()
	_test_violation_and_load()
	_test_trace_and_rng()
	_test_evidence_hardening()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])

func _make_terms(object_id: String = "shells", quantity: int = 2, due_tick: int = 240) -> Dictionary:
	return {"object": object_id, "quantity": quantity, "due_tick": due_tick}

func _make_commitment(
	commitment_id: String = "commitment:a:1:shells",
	debtor_id: String = "a",
	creditor_id: String = "b",
	object_id: String = "shells",
	quantity: int = 2,
	created_tick: int = 10,
	due_tick: int = 250,
	source_request_id: String = "material:a:1:shells"
) -> Dictionary:
	return Contract.make(commitment_id, debtor_id, creditor_id, object_id, quantity,
		created_tick, due_tick, Contract.SOURCE_MATERIAL_REQUEST, source_request_id,
		_make_terms(object_id, quantity, due_tick))

func _transfer_event(request_id: String, item_id: String = "shells", quantity: int = 2,
		event_id: String = "transfer:t1", from_actor: String = "b", to_actor: String = "a") -> Dictionary:
	return {"event_id": event_id, "type": "ITEM_TRANSFER_COMPLETED", "request_id": request_id,
		"item_id": item_id, "quantity": quantity, "from_actor_id": from_actor, "to_actor_id": to_actor,
		"evidence_kind": "WORLD_MUTATION"}

func _test_contract_validation() -> void:
	var good := _make_commitment()
	_check("contract_valid_record_passes", Contract.validate(good).is_empty(), str(Contract.validate(good)))
	var no_party := _make_commitment()
	no_party["creditor_id"] = ""
	_check("contract_missing_party_rejected", not Contract.validate(no_party).is_empty())
	var self_debt := _make_commitment("commitment:a:1:x", "a", "a", "wood", 1, 10, 240)
	_check("contract_self_commitment_rejected", Contract.validate(self_debt).has("SELF_COMMITMENT"))
	var bad_quantity := _make_commitment()
	bad_quantity["quantity"] = 0
	_check("contract_non_positive_quantity_rejected", Contract.validate(bad_quantity).has("NON_POSITIVE_QUANTITY"))
	var bad_due := _make_commitment()
	bad_due["due_tick"] = 9
	_check("contract_due_before_created_rejected", Contract.validate(bad_due).has("DUE_BEFORE_CREATED"))
	_check("contract_terms_quantity_mismatch_detected",
		not Contract.terms_match(_make_terms("shells", 2, 240), _make_terms("shells", 1, 240)))
	_check("contract_terms_object_mismatch_detected",
		not Contract.terms_match(_make_terms("shells", 2, 240), _make_terms("wood", 2, 240)))
	_check("contract_terms_longer_due_rejected",
		not Contract.terms_match(_make_terms("shells", 2, 240), _make_terms("shells", 2, 300)))
	_check("contract_terms_shorter_due_accepted",
		Contract.terms_match(_make_terms("shells", 2, 240), _make_terms("shells", 2, 200)))

func _test_tracker_lifecycle() -> void:
	var bridge := Bridge.new()
	var ledger: Array = []
	var created: Dictionary = bridge.open_commitment_for_request(ledger, 
		{"request_id": "material:a:1:shells", "requester_id": "a", "target_id": "b",
			"item_id": "shells", "requested_quantity": 2, "root_goal": "HUNGER",
			"parent_plan_id": "P", "parent_run_id": "a#1", "blocker_step_id": "CRAFT:s"},
		_make_terms("shells", 2, 60), 10)
	_check("created_commitment_is_pending", bool(created.get("ok", false))
		and str((created["commitment"] as Dictionary).get("status", "")) == Contract.STATUS_PENDING_ACTIVATION,
		str(created))
	var cid := str((created["commitment"] as Dictionary).get("commitment_id", ""))
	_check("commitment_carries_parent_identity",
		str((created["commitment"] as Dictionary).get("parent_plan_id", "")) == "P"
		and str((created["commitment"] as Dictionary).get("parent_run_id", "")) == "a#1"
		and str((created["commitment"] as Dictionary).get("blocker_step_id", "")) == "CRAFT:s")
	_check("pending_commitment_is_not_debt",
		not Contract.counts_toward_load(ledger[0]))
	var duplicate := bridge.tracker.create(ledger, _make_commitment(cid))
	_check("duplicate_commitment_id_rejected", not bool(duplicate.get("ok", false)), str(duplicate))
	# PENDING 承诺可因来源请求终局取消——不得留下无对价债务。
	var cancelled: Array = bridge.cancel_for_request(ledger, "material:a:1:shells",
		Contract.CANCEL_SOURCE_REQUEST_FAILED, 30)
	_check("pending_cancelled_on_request_terminal", cancelled.size() == 1
		and str((cancelled[0] as Dictionary).get("status", "")) == Contract.STATUS_CANCELLED)
	_check("cancelled_commitment_not_in_load",
		not Contract.counts_toward_load(ledger[0]))

func _test_transfer_activation_identity() -> void:
	var bridge := Bridge.new()
	var ledger: Array = []
	var created: Dictionary = bridge.open_commitment_for_request(ledger, 
		{"request_id": "material:a:2:shells", "requester_id": "a", "target_id": "b", "item_id": "shells"},
		_make_terms("shells", 2, 60), 10)
	var cid := str((created["commitment"] as Dictionary).get("commitment_id", ""))
	var wrong_request := bridge.activate_from_transfer(ledger,
		{"request_id": "material:a:2:shells"}, _transfer_event("material:other:9:shells"), 20)
	_check("unrelated_transfer_cannot_activate", not bool(wrong_request.get("ok", false)),
		str(wrong_request))
	var wrong_item := bridge.activate_from_transfer(ledger,
		{"request_id": "material:a:2:shells"}, _transfer_event("material:a:2:shells", "wood"), 20)
	_check("wrong_item_transfer_cannot_activate", not bool(wrong_item.get("ok", false)))
	var activated: Dictionary = bridge.activate_from_transfer(ledger,
		{"request_id": "material:a:2:shells"}, _transfer_event("material:a:2:shells"), 21)
	_check("matching_transfer_activates", bool(activated.get("ok", false))
		and str((ledger[0] as Dictionary).get("status", "")) == Contract.STATUS_ACTIVE, str(activated))
	_check("activated_commitment_records_evidence",
		str((ledger[0] as Dictionary).get("source_transfer_event_id", "")) == "transfer:t1"
		and int((ledger[0] as Dictionary).get("activated_tick", -1)) == 21)
	_check("activated_commitment_is_real_debt", Contract.counts_toward_load(ledger[0]))
	# 激活之后，父计划/父请求的任何变化都不得抹掉债务（§五）。
	var late_cancel: Array = bridge.cancel_for_request(ledger, "material:a:2:shells",
		Contract.CANCEL_SOURCE_REQUEST_FAILED, 40)
	_check("parent_terminal_after_activation_keeps_debt", late_cancel.is_empty()
		and str((ledger[0] as Dictionary).get("status", "")) == Contract.STATUS_ACTIVE)
	var again := bridge.activate_from_transfer(ledger,
		{"request_id": "material:a:2:shells"}, _transfer_event("material:a:2:shells", "shells", 2, "t2"), 22)
	_check("activation_is_single_shot", not bool(again.get("ok", false)), str(again))

func _test_settlement() -> void:
	var bridge := Bridge.new()
	var ledger: Array = []
	var created: Dictionary = bridge.open_commitment_for_request(ledger, 
		{"request_id": "material:a:3:shells", "requester_id": "a", "target_id": "b", "item_id": "shells"},
		_make_terms("shells", 2, 60), 10)
	var cid := str((created["commitment"] as Dictionary).get("commitment_id", ""))
	bridge.activate_from_transfer(ledger, {"request_id": "material:a:3:shells"},
		_transfer_event("material:a:3:shells"), 12)
	var debtor_inv := {"shells": 1}
	var creditor_inv := {"shells": 0}
	var insufficient := bridge.settle(ledger, cid, debtor_inv, creditor_inv, 30)
	_check("insufficient_inventory_rejected_without_mutation",
		not bool(insufficient.get("ok", false))
		and int(debtor_inv["shells"]) == 1 and int(creditor_inv["shells"]) == 0, str(insufficient))
	debtor_inv["shells"] = 2
	var settled := bridge.settle(ledger, cid, debtor_inv, creditor_inv, 31)
	_check("settlement_mutates_exactly_once", bool(settled.get("ok", false))
		and int(debtor_inv["shells"]) == 0 and int(creditor_inv["shells"]) == 2, str(settled))
	_check("settlement_marks_fulfilled",
		str((ledger[0] as Dictionary).get("status", "")) == Contract.STATUS_FULFILLED)
	var repeat := bridge.settle(ledger, cid, debtor_inv, creditor_inv, 32)
	_check("duplicate_settlement_rejected", not bool(repeat.get("ok", false))
		and int(debtor_inv["shells"]) == 0 and int(creditor_inv["shells"]) == 2, str(repeat))
	_check("fulfilled_commitment_leaves_load", not Contract.counts_toward_load(ledger[0]))

func _test_violation_and_load() -> void:
	var bridge := Bridge.new()
	var ledger: Array = []
	bridge.open_commitment_for_request(ledger, 
		{"request_id": "material:a:4:shells", "requester_id": "a", "target_id": "b", "item_id": "shells"},
		_make_terms("shells", 2, 60), 10)
	bridge.activate_from_transfer(ledger, {"request_id": "material:a:4:shells"},
		_transfer_event("material:a:4:shells"), 12)
	var record: Dictionary = ledger[0]
	record["due_tick"] = 50
	var first := bridge.violate_due(ledger, 51)
	_check("overdue_active_commitment_violated", first.size() == 1
		and str((record).get("status", "")) == Contract.STATUS_VIOLATED)
	var second := bridge.violate_due(ledger, 52)
	_check("violation_is_single_shot", second.is_empty())
	_check("violated_commitment_leaves_load", not Contract.counts_toward_load(record))
	var legacy := {"debtor": "a", "creditor": "b", "object": "food", "made_tick": 1,
		"due_tick": 90, "repaid": false, "promise_event_seq": 3}
	ledger.append(legacy)
	_check("legacy_unrepaid_counts_toward_load", Contract.counts_toward_load(legacy))
	_check("load_counts_active_and_legacy",
		bridge.tracker.active_count_for_load(ledger, "a") == 1)
	var orphan_bridge := Bridge.new()
	var orphan_ledger: Array = []
	var oc: Dictionary = orphan_bridge.open_commitment_for_request(orphan_ledger, 
		{"request_id": "material:a:5:shells", "requester_id": "a", "target_id": "gone", "item_id": "shells"},
		_make_terms("shells", 1, 60), 10)
	orphan_bridge.activate_from_transfer(orphan_ledger, {"request_id": "material:a:5:shells"},
		_transfer_event("material:a:5:shells", "shells", 1, "t5", "gone"), 12)
	var cancelled := orphan_bridge.cancel_orphaned(orphan_ledger, ["a", "b"], 60)
	_check("creditor_gone_cancels_active",
		cancelled.size() == 1
		and str((oc["commitment"] as Dictionary).get("status", "")) == Contract.STATUS_CANCELLED
		and str((oc["commitment"] as Dictionary).get("terminal_reason", "")) == Contract.CANCEL_CREDITOR_GONE)

func _test_trace_and_rng() -> void:
	var bridge := Bridge.new()
	var ledger: Array = []
	bridge.open_commitment_for_request(ledger, 
		{"request_id": "material:a:6:shells", "requester_id": "a", "target_id": "b", "item_id": "shells"},
		_make_terms("shells", 1, 60), 10)
	var traces: Array = bridge.trace_snapshot()
	_check("trace_covers_creation_with_identity", traces.size() == 1
		and str((traces[0] as Dictionary).get("event", "")) == Contract.EVENT_COMMITMENT_CREATED
		and str((traces[0] as Dictionary).get("source_request_id", "")) == "material:a:6:shells")
	_check("commitment_layer_consumes_no_rng", bridge.rng_states().is_empty())

func _test_evidence_hardening() -> void:
	# P7.2A D：伪造/缺项来源转移证据不得激活——状态保持 PENDING、零副作用。
	var forgeries := {
		"wrong_type": _transfer_event("material:a:7:shells").duplicate(true),
	}
	forgeries["wrong_type"]["type"] = "promise_kept"
	forgeries["blank_event_id"] = _transfer_event("material:a:7:shells")
	forgeries["blank_event_id"]["event_id"] = ""
	forgeries["wrong_kind"] = _transfer_event("material:a:7:shells")
	forgeries["wrong_kind"]["evidence_kind"] = "HEARSAY"
	forgeries["wrong_giver"] = _transfer_event("material:a:7:shells", "shells", 2, "t7", "c")
	forgeries["wrong_receiver"] = _transfer_event("material:a:7:shells", "shells", 2, "t7", "b", "c")
	for label in forgeries:
		var bridge := Bridge.new()
		var ledger: Array = []
		bridge.open_commitment_for_request(ledger,
			{"request_id": "material:a:7:shells", "requester_id": "a", "target_id": "b", "item_id": "shells"},
			_make_terms("shells", 2, 60), 10)
		var rejected: Dictionary = bridge.activate_from_transfer(ledger,
			{"request_id": "material:a:7:shells", "accepted_quantity": 2}, forgeries[label], 20)
		_check("forged_activation_%s_rejected" % label,
			not bool(rejected.get("ok", false))
			and str((ledger[0] as Dictionary).get("status", "")) == Contract.STATUS_PENDING_ACTIVATION,
			str(rejected.get("reason", "")))
	var short_bridge := Bridge.new()
	var short_ledger: Array = []
	short_bridge.open_commitment_for_request(short_ledger,
		{"request_id": "material:a:8:shells", "requester_id": "a", "target_id": "b", "item_id": "shells"},
		_make_terms("shells", 2, 60), 10)
	var short_ev := _transfer_event("material:a:8:shells", "shells", 1)
	var short_rejected: Dictionary = short_bridge.activate_from_transfer(short_ledger,
		{"request_id": "material:a:8:shells", "accepted_quantity": 2}, short_ev, 20)
	_check("activation_requires_accepted_quantity",
		not bool(short_rejected.get("ok", false))
		and str((short_ledger[0] as Dictionary).get("status", "")) == Contract.STATUS_PENDING_ACTIVATION,
		str(short_rejected.get("reason", "")))
	# P7.2A E：错误对手方不得结算（欠 B 的债不能被指向 C 的行动了结）。
	var settle_bridge := Bridge.new()
	var settle_ledger: Array = []
	settle_bridge.open_commitment_for_request(settle_ledger,
		{"request_id": "material:a:9:shells", "requester_id": "a", "target_id": "b", "item_id": "shells"},
		_make_terms("shells", 2, 60), 10)
	settle_bridge.activate_from_transfer(settle_ledger,
		{"request_id": "material:a:9:shells", "accepted_quantity": 2},
		_transfer_event("material:a:9:shells", "shells", 2, "t9"), 12)
	var debtor_inv := {"shells": 2}
	var creditor_inv := {"shells": 0}
	var wrong_party := settle_bridge.settle(settle_ledger,
		str((settle_ledger[0] as Dictionary).get("commitment_id", "")),
		debtor_inv, creditor_inv, 30, "a", "c", "shells")
	_check("wrong_party_settlement_rejected",
		not bool(wrong_party.get("ok", false))
		and str((settle_ledger[0] as Dictionary).get("status", "")) == Contract.STATUS_ACTIVE
		and int(debtor_inv["shells"]) == 2 and int(creditor_inv["shells"]) == 0,
		str(wrong_party.get("reason", "")))
	# P7.2A E：伪造履约证据不得 FULFILLED。
	var forged_fulfill := {"type": "promise_kept", "event_id": "x", "commitment_id":
		str((settle_ledger[0] as Dictionary).get("commitment_id", "")), "quantity": 2,
		"evidence_kind": "WORLD_MUTATION"}
	var not_fulfilled: Dictionary = settle_bridge.tracker.fulfill(settle_ledger,
		str((settle_ledger[0] as Dictionary).get("commitment_id", "")), forged_fulfill, 31)
	_check("forged_fulfillment_evidence_rejected",
		not bool(not_fulfilled.get("ok", false))
		and str((settle_ledger[0] as Dictionary).get("status", "")) == Contract.STATUS_ACTIVE,
		str(not_fulfilled.get("reason", "")))
