extends SceneTree
## P7.2 加固测试：估值单调性（§七）、请求者独立决策（§八）、条款语义、
## 应答策略条款兼容（旧上下文输出不变）、负担口径。

const Policy = preload("res://src/simulation/commitment/commitment_offer_policy.gd")
const Contract = preload("res://src/simulation/commitment/commitment_contract.gd")
const ResponsePolicy = preload("res://src/simulation/material_request/material_request_response_policy.gd")
const MRContract = preload("res://src/simulation/material_request/material_request_contract.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_offer_value_monotonicity()
	_test_offer_validation()
	_test_requester_decision()
	_test_due_estimate_and_mismatch()
	_test_load_and_terms()
	_test_response_policy_terms_compat()
	_test_truthful_mismatch_payload()
	_test_audit_hash_sensitivity()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])

func _creditor_context(reliability: float, relationship: float = 0.0,
		load: float = 0.0, reciprocity: float = 0.5) -> Dictionary:
	return {"debtor_reliability_belief": reliability, "relationship": relationship,
		"own_reciprocity_norm": reciprocity, "debtor_visible_commitment_load": load}

func _test_offer_value_monotonicity() -> void:
	var low := Policy.estimate_promise_value(_creditor_context(0.2))
	var mid := Policy.estimate_promise_value(_creditor_context(0.6))
	var high := Policy.estimate_promise_value(_creditor_context(0.95))
	_check("promise_value_monotone_in_reliability", low <= mid and mid <= high,
		"%.4f %.4f %.4f" % [low, mid, high])
	var distrust := Policy.estimate_promise_value(_creditor_context(0.02))
	_check("deep_distrust_lowers_promise_value", distrust < low, "%.4f" % distrust)
	var loaded := Policy.estimate_promise_value(_creditor_context(0.6, 0.0, 0.9))
	_check("commitment_burden_lowers_promise_value", loaded < mid, "%.4f" % loaded)
	var full := Policy.evaluate_commitment_offer(
		{"object": "shells", "quantity": 2, "due_tick": 300},
		{"object": "shells", "quantity": 2, "due_tick": 300},
		_creditor_context(0.8))
	var partial := Policy.evaluate_commitment_offer(
		{"object": "shells", "quantity": 2, "due_tick": 300},
		{"object": "shells", "quantity": 1, "due_tick": 300},
		_creditor_context(0.8))
	_check("higher_coverage_not_lower_value",
		float(partial["offer_value"]) <= float(full["offer_value"]),
		"%.4f vs %.4f" % [float(partial["offer_value"]), float(full["offer_value"])])

func _test_offer_validation() -> void:
	var context := _creditor_context(0.8, 0.8)
	context["minimum_offer_value"] = 0.5
	var good := Policy.evaluate_commitment_offer(
		{"object": "shells", "quantity": 2, "due_tick": 300},
		{"object": "shells", "quantity": 2, "due_tick": 280},
		context)
	_check("credible_offer_meets_minimum", bool(good["accepted"]), str(good))
	var weak_context := _creditor_context(0.05, -1.0)
	weak_context["minimum_offer_value"] = 0.5
	var weak := Policy.evaluate_commitment_offer(
		{"object": "shells", "quantity": 2, "due_tick": 300},
		{"object": "shells", "quantity": 2, "due_tick": 300},
		weak_context)
	_check("distrusted_offer_below_minimum", not bool(weak["accepted"]), str(weak))
	# 相同条款下，履约历史（可靠性信念）提升估值——后续合作变化的纯函数基础。
	var reliable_value := float(good["offer_value"])
	var neutral := Policy.evaluate_commitment_offer(
		{"object": "shells", "quantity": 2, "due_tick": 300},
		{"object": "shells", "quantity": 2, "due_tick": 280},
		_creditor_context(0.5, 0.8))
	_check("reliability_history_raises_offer_value",
		reliable_value > float(neutral["offer_value"]),
		"%.4f vs %.4f" % [reliable_value, float(neutral["offer_value"])])

func _test_requester_decision() -> void:
	var eager := Policy.evaluate_requester_acceptance({
		"need_urgency": 0.9, "own_reciprocity_norm": 0.8, "trust_in_creditor": 0.8,
		"relationship": 0.8, "subjective_reobtainability": 0.8,
		"active_commitment_load": 0.0, "promised_quantity_ratio": 0.3,
	})
	_check("eager_requester_accepts", bool(eager["accept"]), str(eager))
	var overloaded := Policy.evaluate_requester_acceptance({
		"need_urgency": 0.5, "own_reciprocity_norm": 0.8, "trust_in_creditor": 0.8,
		"relationship": 0.8, "subjective_reobtainability": 0.4,
		"active_commitment_load": 1.0, "promised_quantity_ratio": 0.3,
	})
	_check("overloaded_requester_declines", not bool(overloaded["accept"]), str(overloaded))
	var clueless := Policy.evaluate_requester_acceptance({
		"need_urgency": 0.9, "own_reciprocity_norm": 0.8, "trust_in_creditor": 0.8,
		"relationship": 0.8, "subjective_reobtainability": 0.1,
		"active_commitment_load": 0.0, "promised_quantity_ratio": 0.3,
	})
	_check("clueless_requester_less_willing",
		float(clueless["willingness"]) < float(eager["willingness"]),
		"%.4f vs %.4f" % [float(clueless["willingness"]), float(eager["willingness"])])
	var apathetic := Policy.evaluate_requester_acceptance({
		"need_urgency": 0.1, "own_reciprocity_norm": 0.2, "trust_in_creditor": 0.2,
		"relationship": 0.0, "subjective_reobtainability": 0.2,
		"active_commitment_load": 0.0, "promised_quantity_ratio": 1.0,
	})
	_check("apathetic_requester_declines", not bool(apathetic["accept"]), str(apathetic))

func _test_due_estimate_and_mismatch() -> void:
	var knows := Policy.evaluate_requester_acceptance({
		"need_urgency": 0.9, "subjective_reobtainability": 0.8, "own_reciprocity_norm": 0.8,
	})
	var clueless := Policy.evaluate_requester_acceptance({
		"need_urgency": 0.9, "subjective_reobtainability": 0.2, "own_reciprocity_norm": 0.8,
	})
	_check("due_estimate_longer_when_clueless",
		int(clueless["offered_due_ticks"]) > int(knows["offered_due_ticks"]),
		"%d vs %d" % [int(clueless["offered_due_ticks"]), int(knows["offered_due_ticks"])])
	_check("knowing_requester_fits_default_window",
		int(knows["offered_due_ticks"]) <= Contract.DEFAULT_DUE_TICKS,
		str(int(knows["offered_due_ticks"])))

func _test_load_and_terms() -> void:
	_check("load_scales_with_active_commitments",
		Policy.commitment_load(0) == 0.0 and Policy.commitment_load(1) > 0.0
		and Policy.commitment_load(3) >= 1.0)
	var matched := Contract.terms_match(
		{"object": "shells", "quantity": 2, "due_tick": 250},
		{"object": "shells", "quantity": 2, "due_tick": 240})
	var late := Contract.terms_match(
		{"object": "shells", "quantity": 2, "due_tick": 250},
		{"object": "shells", "quantity": 2, "due_tick": 310})
	_check("terms_match_accepts_faster_rejects_later", matched and not late)

func _test_response_policy_terms_compat() -> void:
	var policy := ResponsePolicy.new()
	var request := MRContract.make_request("material:a:1:shells", "a", "shells", 3, "HUNGER", "P", 0, 100, 0.8)
	# 旧上下文（无 exchange_terms_enabled）：partial counter 不带条款。
	var legacy_context := {
		"inventory_quantity": 2, "reserve_quantity": 0, "relationship": 0.0,
		"trust": 0.3, "generosity": 0.3, "own_need_pressure": 0.8,
		"risk_aversion": 0.5, "commitment_load": 0.0, "exchange_offer_value": 0.0,
	}
	var legacy := policy.evaluate(request, legacy_context, 0.1)
	var legacy_counter: Dictionary = legacy.get("counter", {})
	_check("legacy_context_counter_has_no_terms",
		str(legacy.get("outcome", "")) == MRContract.OUTCOME_COUNTER
		and bool(legacy_counter.get("requires_exchange", false))
		and not legacy_counter.has("terms"), str(legacy))
	# 新上下文（exchange_terms_enabled）：同型 counter 附带条款。
	var p72_context := legacy_context.duplicate(true)
	p72_context["exchange_terms_enabled"] = true
	p72_context["exchange_due_ticks"] = 240
	var modern := policy.evaluate(request, p72_context, 0.1)
	var modern_counter: Dictionary = modern.get("counter", {})
	var terms: Dictionary = modern_counter.get("terms", {})
	_check("enabled_context_counter_carries_terms",
		str(modern.get("outcome", "")) == MRContract.OUTCOME_COUNTER
		and str(terms.get("promise_object", "")) == "shells"
		and int(terms.get("promise_quantity", 0)) == 2, str(modern))
	_check("legacy_decision_shape_unchanged_by_flag",
		str(legacy.get("reason", "")) == str(modern.get("reason", ""))
		and is_equal_approx(float(legacy.get("accept_probability", -1.0)),
			float(modern.get("accept_probability", -2.0))))

func _test_truthful_mismatch_payload() -> void:
	# P7.2A F：报价条款=A 的真实期限估计（可长于对方要求）；单一真源 Contract.terms_match。
	var Bridge = preload("res://src/simulation/commitment/commitment_runtime_bridge.gd")
	var bridge = Bridge.new()
	var request := {"request_id": "m", "requester_id": "a", "item_id": "shells", "requested_quantity": 2}
	var counter := {"quantity": 2, "requires_exchange": true,
		"terms": {"promise_object": "wood", "promise_quantity": 2, "due_ticks": 240}}
	var decision: Dictionary = bridge.requester_exchange_decision(request, counter, {
		"need_urgency": 0.9, "own_reciprocity_norm": 0.8, "trust_in_creditor": 0.8,
		"relationship": 0.8, "subjective_reobtainability": 0.2,
		"active_commitment_load": 0.0, "promised_quantity_ratio": 0.3,
	}, 0)
	var demanded: Dictionary = decision.get("demanded_terms", {})
	var offered: Dictionary = decision.get("offered_terms", {})
	_check("mismatch_payload_reports_true_estimate",
		int(offered.get("due_tick", 0)) > int(demanded.get("due_tick", 0))
		and not bool(decision.get("terms_match", true)),
		str(decision))
	_check("mismatch_terms_match_uses_contract_truth",
		not Contract.terms_match(demanded, offered)
		and not bool(decision.get("accept", true)))
	_check("promise_object_takes_protocol_priority",
		str(demanded.get("object", "")) == "wood" and str(offered.get("object", "")) == "wood",
		str(demanded))
	var fitting: Dictionary = bridge.requester_exchange_decision(request, counter, {
		"need_urgency": 0.9, "own_reciprocity_norm": 0.8, "trust_in_creditor": 0.8,
		"relationship": 0.8, "subjective_reobtainability": 0.8,
		"active_commitment_load": 0.0, "promised_quantity_ratio": 0.3,
	}, 0)
	_check("fitting_estimate_accepts_with_truthful_terms",
		bool(fitting.get("accept", false))
		and int((fitting.get("offered_terms", {}) as Dictionary).get("due_tick", 0))
			<= int((fitting.get("demanded_terms", {}) as Dictionary).get("due_tick", 0)),
		str(fitting))

func _test_audit_hash_sensitivity() -> void:
	# P7.2A H：authoritative obligations 变化必须反映进 state_sha256；
	# 仅追加诊断 trace 必须反映进 commitment_sha256（且不动 state）。
	var created := SimulationBootstrap.create(74001, "commitment")
	var sim: IslandSimulation = created["sim"]
	var fp1: Dictionary = SimulationAudit.fingerprint(sim)
	sim.obligations.append(CommitmentContract.make("commitment:x:1:shells", "npc_oun",
		"npc_weila", "shells", 1, 0, 500, "MATERIAL_REQUEST_COUNTER", "m",
		{"object": "shells", "quantity": 1, "due_tick": 500}))
	var fp2: Dictionary = SimulationAudit.fingerprint(sim)
	_check("authoritative_ledger_change_moves_state_hash",
		str(fp1["state_sha256"]) != str(fp2["state_sha256"]))
	var traces: Array = sim._commitment_runtime_bridge().traces
	traces.append({"event": "COMMITMENT_CREATED", "tick": 0, "commitment_id": "c"})
	var fp3: Dictionary = SimulationAudit.fingerprint(sim)
	_check("diagnostic_trace_append_moves_commitment_hash",
		str(fp2["commitment_sha256"]) != str(fp3["commitment_sha256"]))
	_check("trace_only_append_leaves_state_hash",
		str(fp2["state_sha256"]) == str(fp3["state_sha256"]))
