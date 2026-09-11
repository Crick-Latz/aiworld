extends SceneTree

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")
const Tracker = preload("res://src/simulation/material_request/material_request_tracker.gd")
const RequestPolicy = preload("res://src/simulation/material_request/material_request_policy.gd")
const ResponsePolicy = preload("res://src/simulation/material_request/material_request_response_policy.gd")
const TransferService = preload("res://src/simulation/material_request/material_transfer_service.gd")
const Coordinator = preload("res://src/simulation/material_request/material_request_coordinator.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_contract_and_lifecycle()
	_test_subjective_target_selection()
	_test_recipient_response_policy()
	_test_transfer_evidence_boundary()
	_test_counter_and_parent_revalidation()
	_test_end_to_end_coordinator()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _request(request_id: String = "req-1", quantity: int = 2) -> Dictionary:
	return Contract.make_request(
		request_id,
		"actor-requester",
		"wood",
		quantity,
		"HUNGER",
		"plan-fish",
		10,
		100,
		0.8
	)

func _test_contract_and_lifecycle() -> void:
	var request := _request()
	_assert_eq(Contract.validate(request).size(), 0, "valid request has no contract errors")
	var invalid := _request("", 0)
	_assert_true(Contract.validate(invalid).has("REQUEST_ID_REQUIRED"), "contract requires request id")
	_assert_true(Contract.validate(invalid).has("QUANTITY_MUST_BE_POSITIVE"), "contract requires positive quantity")

	var tracker = Tracker.new()
	var started := tracker.start_request(request)
	_assert_true(bool(started.get("ok", false)), "tracker starts a valid request")
	_assert_eq(String(tracker.get_request("req-1").get("status", "")), Contract.STATUS_ACTIVE, "new request is active")
	_assert_eq(tracker.active_requests_for("actor-requester").size(), 1, "active request is indexed by requester")
	_assert_false(bool(tracker.start_request(request).get("ok", true)), "duplicate request id is rejected")
	_assert_true(tracker.record_offer("req-1", "actor-holder", 12, {"kind": "REQUEST_ITEM"}), "offer is recorded")
	_assert_eq(String(tracker.get_request("req-1").get("status", "")), Contract.STATUS_WAITING_RESPONSE, "offer waits for response")
	_assert_eq(int(tracker.get_request("req-1").get("attempt_count", 0)), 1, "offer increments attempts")
	_assert_false(tracker.record_response("req-1", "wrong-actor", Contract.OUTCOME_ACCEPT, 13, 2), "wrong responder cannot answer")
	_assert_true(tracker.record_response("req-1", "actor-holder", Contract.OUTCOME_REFUSE, 13, 0, "KEEP_RESERVE"), "refusal is recorded")
	_assert_eq(String(tracker.get_request("req-1").get("status", "")), Contract.STATUS_ACTIVE, "refusal returns request to active search")
	_assert_true(tracker.cancel("req-1", 14, "REQUESTER_CHANGED_PLAN"), "active request can be cancelled")
	_assert_eq(String(tracker.get_request("req-1").get("status", "")), Contract.STATUS_CANCELLED, "cancelled request is terminal")
	_assert_false(tracker.cancel("req-1", 15, "SECOND_CANCEL"), "terminal request cannot be cancelled twice")

	var expiring := _request("req-expire", 1)
	expiring["expires_tick"] = 11
	_assert_true(bool(tracker.start_request(expiring).get("ok", false)), "expiring request starts")
	_assert_eq(tracker.expire_due(11).size(), 0, "request remains valid at expiry tick")
	_assert_eq(tracker.expire_due(12).size(), 1, "request expires after expiry tick")
	_assert_eq(String(tracker.get_request("req-expire").get("status", "")), Contract.STATUS_EXPIRED, "expired request records terminal status")

func _test_subjective_target_selection() -> void:
	var policy = RequestPolicy.new()
	var request := _request("req-target", 2)
	var beliefs: Array = [
		{
			"actor_id": "actor-visible-low",
			"visible": true,
			"believed_quantity": 2,
			"confidence": 0.8,
			"relationship": 0.4,
			"expected_cooperation": 0.7,
			"distance": 3.0,
			"last_observed_tick": 90,
		},
		{
			"actor_id": "actor-invisible-rich",
			"visible": false,
			"believed_quantity": 50,
			"confidence": 1.0,
			"relationship": 1.0,
			"expected_cooperation": 1.0,
			"distance": 1.0,
			"last_observed_tick": 100,
		},
		{
			"actor_id": "actor-visible-best",
			"visible": true,
			"believed_quantity": 5,
			"confidence": 0.95,
			"relationship": 0.8,
			"expected_cooperation": 0.9,
			"distance": 2.0,
			"last_observed_tick": 99,
		},
	]
	var decision := policy.choose_target(request, beliefs, 100, 61000)
	_assert_true(bool(decision.get("ok", false)), "subjective policy finds a target")
	_assert_eq(String(decision.get("target_id", "")), "actor-visible-best", "policy chooses strongest visible subjective holder")
	_assert_true(bool(decision.get("subjective_only", false)), "decision records subjective-only boundary")
	_assert_eq(Array(decision.get("ranked_candidates", [])).size(), 2, "invisible world holder is excluded")

	var reversed := beliefs.duplicate(true)
	reversed.reverse()
	var repeated := policy.choose_target(request, reversed, 100, 61000)
	_assert_eq(String(repeated.get("target_id", "")), String(decision.get("target_id", "")), "selection is independent of candidate input order")
	_assert_approx(float(repeated.get("score", 0.0)), float(decision.get("score", 0.0)), 0.000001, "selection score is deterministic")

	var stale_beliefs: Array = [
		{
			"actor_id": "actor-stale",
			"visible": true,
			"believed_quantity": 10,
			"confidence": 1.0,
			"relationship": 0.2,
			"expected_cooperation": 0.5,
			"distance": 1.0,
			"last_observed_tick": 0,
		},
		{
			"actor_id": "actor-fresh",
			"visible": true,
			"believed_quantity": 2,
			"confidence": 0.9,
			"relationship": 0.2,
			"expected_cooperation": 0.5,
			"distance": 1.0,
			"last_observed_tick": 295,
		},
	]
	var freshness_decision := policy.choose_target(request, stale_beliefs, 300, 61001)
	_assert_eq(String(freshness_decision.get("target_id", "")), "actor-fresh", "fresh subjective evidence can beat stale abundance")

	var no_target := policy.choose_target(request, [{"actor_id": "hidden", "visible": false, "believed_quantity": 9}], 10, 1)
	_assert_false(bool(no_target.get("ok", true)), "policy declines when subjective candidates are absent")
	_assert_eq(String(no_target.get("reason", "")), "NO_SUBJECTIVE_TARGET", "no-target reason is explicit")

	var offer := policy.build_offer(request, decision, {"item_id": "shell", "quantity": 1})
	_assert_eq(String(offer.get("target_id", "")), "actor-visible-best", "offer carries chosen target")
	_assert_eq(String(offer.get("item_id", "")), "wood", "offer carries requested item")
	_assert_true(bool(Dictionary(offer.get("belief_basis", {})).get("subjective_only", false)), "offer preserves belief provenance")

func _test_recipient_response_policy() -> void:
	var policy = ResponsePolicy.new()
	var request := _request("req-response", 2)
	var generous_context := {
		"inventory_quantity": 6,
		"reserve_quantity": 2,
		"relationship": 0.8,
		"trust": 0.9,
		"generosity": 0.9,
		"own_need_pressure": 0.1,
		"risk_aversion": 0.2,
		"commitment_load": 0.1,
		"exchange_offer_value": 0.0,
	}
	var accepted := policy.evaluate(request, generous_context, 0.05)
	_assert_eq(String(accepted.get("outcome", "")), Contract.OUTCOME_ACCEPT, "cooperative recipient accepts from surplus")
	_assert_eq(int(accepted.get("accepted_quantity", 0)), 2, "acceptance covers requested quantity")
	_assert_false(bool(accepted.get("mutated_inventory", true)), "response policy never mutates inventory")
	_assert_true(float(accepted.get("accept_probability", 0.0)) > 0.5, "cooperative context raises acceptance probability")

	var reserve_context := generous_context.duplicate(true)
	reserve_context["inventory_quantity"] = 2
	reserve_context["reserve_quantity"] = 2
	var refused_reserve := policy.evaluate(request, reserve_context, 0.0)
	_assert_eq(String(refused_reserve.get("outcome", "")), Contract.OUTCOME_REFUSE, "recipient refuses when all stock is reserved")
	_assert_eq(String(refused_reserve.get("reason", "")), "NO_TRANSFERABLE_SURPLUS", "reserve refusal has causal reason")

	var partial_context := generous_context.duplicate(true)
	partial_context["inventory_quantity"] = 3
	partial_context["reserve_quantity"] = 2
	var partial := policy.evaluate(request, partial_context, 0.0)
	_assert_eq(String(partial.get("outcome", "")), Contract.OUTCOME_COUNTER, "partial surplus produces counteroffer")
	_assert_eq(int(partial.get("accepted_quantity", 0)), 1, "counteroffer is bounded by real surplus")
	_assert_eq(int(Dictionary(partial.get("counter", {})).get("quantity", 0)), 1, "counter records offered quantity")

	var guarded_context := {
		"inventory_quantity": 6,
		"reserve_quantity": 1,
		"relationship": -0.8,
		"trust": 0.05,
		"generosity": 0.05,
		"own_need_pressure": 0.9,
		"risk_aversion": 0.9,
		"commitment_load": 0.9,
		"exchange_offer_value": 0.0,
	}
	var guarded := policy.evaluate(request, guarded_context, 0.95)
	_assert_eq(String(guarded.get("outcome", "")), Contract.OUTCOME_REFUSE, "recipient can refuse despite sufficient stock")
	_assert_eq(String(guarded.get("reason", "")), "COOPERATION_THRESHOLD_NOT_MET", "interest-based refusal is explained")

	var conditional_context := guarded_context.duplicate(true)
	conditional_context["relationship"] = 0.6
	conditional_context["exchange_offer_value"] = 0.6
	var conditional := policy.evaluate(request, conditional_context, 0.99)
	_assert_eq(String(conditional.get("outcome", "")), Contract.OUTCOME_COUNTER, "valuable exchange can produce a conditional counter")
	_assert_true(bool(Dictionary(conditional.get("counter", {})).get("requires_exchange", false)), "conditional counter records exchange requirement")

func _test_transfer_evidence_boundary() -> void:
	var tracker = Tracker.new()
	var request := _request("req-transfer", 2)
	_assert_true(bool(tracker.start_request(request).get("ok", false)), "transfer test request starts")
	_assert_true(tracker.record_offer("req-transfer", "actor-holder", 20), "transfer test offer recorded")
	_assert_true(tracker.record_response("req-transfer", "actor-holder", Contract.OUTCOME_ACCEPT, 21, 2), "transfer test acceptance recorded")

	var dialogue_event := {
		"event_id": "dialogue-1",
		"type": "REQUEST_ACCEPTED",
		"request_id": "req-transfer",
		"from_actor_id": "actor-holder",
		"to_actor_id": "actor-requester",
		"item_id": "wood",
		"quantity": 2,
		"evidence_kind": "DIALOGUE",
	}
	_assert_false(tracker.record_transfer_evidence("req-transfer", dialogue_event, 22), "dialogue acceptance cannot resolve material request")
	_assert_eq(String(tracker.get_request("req-transfer").get("status", "")), Contract.STATUS_WAITING_TRANSFER, "request remains blocked before world mutation")

	var service = TransferService.new()
	var giver := {"wood": 4}
	var receiver := {"wood": 0}
	var preview := service.preview(tracker.get_request("req-transfer"), giver)
	_assert_true(bool(preview.get("ok", false)), "valid transfer can be previewed")
	_assert_eq(int(giver.get("wood", 0)), 4, "preview leaves giver inventory unchanged")
	_assert_eq(int(receiver.get("wood", 0)), 0, "preview leaves receiver inventory unchanged")

	var result := service.execute(tracker.get_request("req-transfer"), giver, receiver, 23)
	_assert_true(bool(result.get("ok", false)), "authorized transfer executes")
	_assert_true(bool(result.get("mutated", false)), "transfer reports real mutation")
	_assert_eq(int(giver.get("wood", 0)), 2, "giver loses transferred quantity")
	_assert_eq(int(receiver.get("wood", 0)), 2, "receiver gains transferred quantity")
	var event: Dictionary = result.get("event", {})
	_assert_eq(String(event.get("type", "")), Contract.EVENT_ITEM_TRANSFER_COMPLETED, "transfer emits completion event")
	_assert_eq(String(event.get("evidence_kind", "")), "WORLD_MUTATION", "transfer event carries mutation evidence")
	_assert_true(tracker.record_transfer_evidence("req-transfer", event, 23), "matching mutation evidence resolves request")
	_assert_eq(String(tracker.get_request("req-transfer").get("status", "")), Contract.STATUS_RESOLVED, "request becomes resolved after transfer")

	var insufficient_request := _request("req-insufficient", 3)
	var insufficient_tracker = Tracker.new()
	_assert_true(bool(insufficient_tracker.start_request(insufficient_request).get("ok", false)), "insufficient request starts")
	_assert_true(insufficient_tracker.record_offer("req-insufficient", "actor-holder", 30), "insufficient offer recorded")
	_assert_true(insufficient_tracker.record_response("req-insufficient", "actor-holder", Contract.OUTCOME_ACCEPT, 31, 3), "insufficient acceptance recorded")
	var low_giver := {"wood": 2}
	var low_receiver := {"wood": 1}
	var failed_transfer := service.execute(insufficient_tracker.get_request("req-insufficient"), low_giver, low_receiver, 32)
	_assert_false(bool(failed_transfer.get("ok", true)), "transfer fails when inventory changed after promise")
	_assert_eq(String(failed_transfer.get("reason", "")), "GIVER_INVENTORY_CHANGED", "failed transfer reports causal inventory change")
	_assert_eq(int(low_giver.get("wood", 0)), 2, "failed transfer preserves giver inventory")
	_assert_eq(int(low_receiver.get("wood", 0)), 1, "failed transfer preserves receiver inventory")

func _test_counter_and_parent_revalidation() -> void:
	var tracker = Tracker.new()
	var request := _request("req-counter", 3)
	_assert_true(bool(tracker.start_request(request).get("ok", false)), "counter request starts")
	_assert_true(tracker.record_offer("req-counter", "actor-holder", 40), "counter request offer recorded")
	_assert_true(tracker.record_response("req-counter", "actor-holder", Contract.OUTCOME_COUNTER, 41, 1, "PARTIAL", {"quantity": 1}), "counter response recorded")
	_assert_eq(String(tracker.get_request("req-counter").get("status", "")), Contract.STATUS_WAITING_REQUESTER, "counter waits for requester choice")
	_assert_true(tracker.accept_counter("req-counter", 42), "requester can accept counter")
	_assert_eq(String(tracker.get_request("req-counter").get("response_outcome", "")), Contract.OUTCOME_COUNTER_ACCEPTED, "accepted counter authorizes transfer")

	var service = TransferService.new()
	var giver := {"wood": 1}
	var receiver := {}
	var transfer := service.execute(tracker.get_request("req-counter"), giver, receiver, 43)
	_assert_true(bool(transfer.get("ok", false)), "counter quantity transfers")
	_assert_true(tracker.record_transfer_evidence("req-counter", transfer.get("event", {}), 43), "counter transfer resolves request")
	var revalidation := tracker.consume_parent_revalidation("req-counter")
	_assert_eq(String(revalidation.get("parent_plan_id", "")), "plan-fish", "resolved request identifies parent plan")
	_assert_eq(String(revalidation.get("root_goal", "")), "HUNGER", "resolved request preserves root goal")
	_assert_eq(int(revalidation.get("quantity", 0)), 1, "revalidation carries transferred quantity")
	_assert_true(not String(revalidation.get("transfer_event_id", "")).is_empty(), "revalidation cites transfer event")
	_assert_true(tracker.consume_parent_revalidation("req-counter").is_empty(), "parent revalidation is consumable once")

func _test_end_to_end_coordinator() -> void:
	var coordinator = Coordinator.new()
	var request := _request("req-flow", 2)
	_assert_true(bool(coordinator.open_request(request).get("ok", false)), "coordinator opens request")
	var beliefs: Array = [{
		"actor_id": "actor-helper",
		"visible": true,
		"believed_quantity": 3,
		"confidence": 0.9,
		"relationship": 0.8,
		"expected_cooperation": 0.9,
		"distance": 1.0,
		"last_observed_tick": 49,
	}]
	var offered := coordinator.choose_and_offer("req-flow", beliefs, 50, 61002)
	_assert_true(bool(offered.get("ok", false)), "coordinator chooses subjective target and records offer")
	_assert_eq(String(Dictionary(offered.get("offer", {})).get("target_id", "")), "actor-helper", "coordinator offer targets believed holder")
	var response_context := {
		"inventory_quantity": 5,
		"reserve_quantity": 1,
		"relationship": 0.8,
		"trust": 0.9,
		"generosity": 0.9,
		"own_need_pressure": 0.1,
		"risk_aversion": 0.1,
		"commitment_load": 0.0,
	}
	var answered := coordinator.answer_request("req-flow", "actor-helper", response_context, 0.0, 51)
	_assert_true(bool(answered.get("ok", false)), "coordinator records autonomous recipient acceptance")
	_assert_eq(String(Dictionary(answered.get("response", {})).get("outcome", "")), Contract.OUTCOME_ACCEPT, "coordinator exposes recipient outcome")
	var giver := {"wood": 5}
	var receiver := {"wood": 0}
	var completed := coordinator.transfer_and_resolve("req-flow", giver, receiver, 52)
	_assert_true(bool(completed.get("ok", false)), "coordinator completes verified transfer")
	_assert_eq(int(giver.get("wood", 0)), 3, "end-to-end helper inventory changes")
	_assert_eq(int(receiver.get("wood", 0)), 2, "end-to-end requester receives material")
	_assert_eq(String(Dictionary(completed.get("revalidation", {})).get("parent_plan_id", "")), "plan-fish", "end-to-end flow requests parent plan revalidation")

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

func _assert_approx(actual: float, expected: float, epsilon: float, label: String) -> void:
	if absf(actual - expected) <= epsilon:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		push_error("FAIL: %s | expected=%f actual=%f" % [label, expected, actual])
