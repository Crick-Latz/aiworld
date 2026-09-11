extends SceneTree

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")
const Tracker = preload("res://src/simulation/material_request/material_request_tracker.gd")
const RequestPolicy = preload("res://src/simulation/material_request/material_request_policy.gd")
const ResponsePolicy = preload("res://src/simulation/material_request/material_request_response_policy.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_invalid_response_is_atomic()
	_test_target_filters_item_and_staleness()
	_test_partial_surplus_remains_recipient_choice()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _request(request_id: String, quantity: int) -> Dictionary:
	return Contract.make_request(
		request_id,
		"requester",
		"wood",
		quantity,
		"HUNGER",
		"plan-fish",
		10,
		100,
		0.8
	)

func _test_invalid_response_is_atomic() -> void:
	var tracker = Tracker.new()
	_assert_true(bool(tracker.start_request(_request("atomic", 2)).get("ok", false)), "atomic request starts")
	_assert_true(tracker.record_offer("atomic", "holder", 11), "atomic request is offered")
	_assert_false(tracker.record_response("atomic", "holder", Contract.OUTCOME_ACCEPT, 12, 3), "oversized acceptance is rejected")
	var snapshot := tracker.get_request("atomic")
	_assert_eq(String(snapshot.get("status", "")), Contract.STATUS_WAITING_RESPONSE, "invalid response preserves status")
	_assert_eq(String(snapshot.get("response_outcome", "")), "", "invalid response preserves outcome")
	_assert_eq(int(snapshot.get("accepted_quantity", 0)), 0, "invalid response preserves quantity")
	_assert_eq(Array(snapshot.get("history", [])).size(), 2, "invalid response adds no history entry")

func _test_target_filters_item_and_staleness() -> void:
	var policy = RequestPolicy.new()
	var request := _request("filters", 2)
	var candidates: Array = [
		{
			"actor_id": "wrong-item",
			"visible": true,
			"item_id": "shell",
			"believed_quantity": 99,
			"confidence": 1.0,
			"relationship": 1.0,
			"expected_cooperation": 1.0,
			"distance": 1.0,
			"last_observed_tick": 100,
		},
		{
			"actor_id": "stale-holder",
			"visible": true,
			"item_id": "wood",
			"stale": true,
			"believed_quantity": 99,
			"confidence": 1.0,
			"relationship": 1.0,
			"expected_cooperation": 1.0,
			"distance": 1.0,
			"last_observed_tick": 100,
		},
		{
			"actor_id": "valid-holder",
			"visible": true,
			"item_id": "wood",
			"believed_quantity": 2,
			"confidence": 0.8,
			"relationship": 0.2,
			"expected_cooperation": 0.5,
			"distance": 3.0,
			"last_observed_tick": 95,
		},
	]
	var decision := policy.choose_target(request, candidates, 100, 61003)
	_assert_true(bool(decision.get("ok", false)), "filtered target decision succeeds")
	_assert_eq(String(decision.get("target_id", "")), "valid-holder", "only matching fresh holder is selectable")
	_assert_eq(Array(decision.get("ranked_candidates", [])).size(), 1, "wrong-item and stale beliefs are excluded")

func _test_partial_surplus_remains_recipient_choice() -> void:
	var policy = ResponsePolicy.new()
	var context := {
		"inventory_quantity": 2,
		"reserve_quantity": 1,
		"relationship": -0.8,
		"trust": 0.05,
		"generosity": 0.05,
		"own_need_pressure": 0.9,
		"risk_aversion": 0.9,
		"commitment_load": 0.9,
		"exchange_offer_value": 0.0,
	}
	var result := policy.evaluate(_request("partial", 2), context, 0.99)
	_assert_eq(String(result.get("outcome", "")), Contract.OUTCOME_REFUSE, "recipient may withhold partial surplus")
	_assert_eq(String(result.get("reason", "")), "PARTIAL_SURPLUS_WITHHELD", "partial refusal records causal reason")
	_assert_eq(int(result.get("accepted_quantity", -1)), 0, "partial refusal authorizes no transfer")
	_assert_false(bool(result.get("mutated_inventory", true)), "partial decision does not mutate inventory")

func _assert_true(value: bool, label: String) -> void:
	if value:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		push_error("FAIL: %s" % label)

func _assert_false(value: bool, label: String) -> void:
	_assert_true(not value, label)

func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		push_error("FAIL: %s | expected=%s actual=%s" % [label, str(expected), str(actual)])
