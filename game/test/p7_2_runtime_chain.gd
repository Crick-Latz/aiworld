extends SceneTree
## P7.2 运行时链集成测试：真实 IslandSimulation（commitment profile）上
## 交换型 counter → PENDING → 转移激活 → 义务计划 → 真实履约结算 → 认知后果
## → 下一次合作概率变化。含条款误解、请求者拒绝、转移失败取消、违约路径、
## 旧 profile 兼容。

const Contract = preload("res://src/simulation/material_request/material_request_contract.gd")
const CommitmentContract = preload("res://src/simulation/commitment/commitment_contract.gd")
const ResponsePolicy = preload("res://src/simulation/material_request/material_request_response_policy.gd")
const ResourceSpec = preload("res://src/simulation/social/resource_spec.gd")

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_profile_flags_and_compat()
	var main := _test_full_exchange_chain()
	_test_terms_mismatch_path()
	_test_requester_decline_path()
	_test_transfer_failure_cancels_pending()
	_test_violation_path_and_consequence()
	_test_cognition_semantics_mapping(main)
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])

func _pair(seed_value: int, giver_caution: float = 0.2) -> Dictionary:
	# 校准夹具：B 有 2 枚贝壳（部分盈余）+ 利他高 + 自身需求 0.4 + 对 A 可靠性
	# 信念偏负 → estimate_promise_value < 0.35 → 部分盈余 counter 携带交换条款。
	var created := SimulationBootstrap.create(seed_value, "commitment")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var giver_id := str(ids[1])
	sim.actors.erase(str(ids[2]))
	var requester: Dictionary = sim.actors[requester_id]
	var giver: Dictionary = sim.actors[giver_id]
	requester["tile"] = Vector2i(10, 10)
	giver["tile"] = Vector2i(11, 10)
	requester["inventory"] = {}
	giver["inventory"] = {"shells": 2}
	giver["personality"] = PersonalityProfile.new(
		{"altruism": 0.9, "empathy": 0.9, "caution": giver_caution}, {})
	giver["needs"]["hunger"] = 800  # own_need_pressure = 0.4 → 既压低接受率又要求回报
	requester["needs"]["hunger"] = 800  # 需求紧迫 → 愿意承诺
	requester["norms"] = {"personal": {"reciprocity": 0.8, "sharing": 0.5}}
	giver["norms"] = {"personal": {"reciprocity": 0.8, "sharing": 0.3}}
	# A 主观上知道 B 持有贝壳（offer 目标与再获得性判断的证据）。
	(requester["tom"] as TheoryOfMind).add_evidence(
		giver_id, "has_item:shells", 1.0, 1.0, -1, sim.tick)
	# B 对 A：中性偏正关系（+200）+ 三次可靠性负面证据 → 承诺估值压到交换线以下。
	sim.relationships.adjust(giver_id, requester_id, "benevolence", 300)
	sim.relationships.adjust(giver_id, requester_id, "reliability", 300)
	for i in 5:
		(giver["tom"] as TheoryOfMind).add_evidence(
			requester_id, "reliable", -1.0, 0.8, -1, sim.tick)
	# A 对 B 高信任（承诺条款验证与后续履约动机）。
	sim.relationships.adjust(requester_id, giver_id, "benevolence", 1000)
	sim.relationships.adjust(requester_id, giver_id, "reliability", 1000)
	return {"sim": sim, "requester_id": requester_id, "giver_id": giver_id,
		"requester": requester, "giver": giver}

func _blocked_run(requester_id: String) -> Dictionary:
	var step := PlanStepSpec.make("ACQUIRE", "ACQUIRE:shells", "PENDING", "", "shells", 3,
		"", "", [], [], [], [], "取得 shells")
	return {
		"run_id": requester_id + "#1", "actor_id": requester_id,
		"plan_id": "PLAN_HUNGER_fish_food", "root_goal": "HUNGER",
		"current_step_id": step["step_id"], "steps": [step], "state": "ACTIVE",
		"baseline_items": {}, "pending": {}, "attempt_seq": 0, "missed_opportunities": 0,
	}

func _open_request(sim: IslandSimulation, pair: Dictionary) -> String:
	var requester_id := str(pair["requester_id"])
	sim._execution_tracker().runs[requester_id] = _blocked_run(requester_id)
	var receipt := {
		"actor_id": requester_id, "decision_tick": sim.tick,
		"run_id": requester_id + "#1", "step_id": "ACQUIRE:shells",
		"selected": false, "candidate_key": "",
		"chosen_key": AgencyActionBridge.candidate_key({"action": "do_nothing"}),
		"selection_mode": "SOFTMAX", "blocker_reason": "MATERIALS_MISSING",
	}
	pair["requester"]["_execution_receipt"] = receipt
	sim._plan_execution_on_decision(requester_id, pair["requester"],
		{"action": "do_nothing", "target": null},
		{"ctx": AgencyContextBuilder.build(sim, pair["requester"]),
			"catalog": sim._recipe_catalog_if_any()})
	var pending: Array = sim._material_request_runtime_bridge().pending_requests_for(requester_id)
	return str(pending[0].get("request_id", "")) if pending.size() == 1 else ""

func _force_accept_roll(sim: IslandSimulation, giver_id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0
	sim._material_request_runtime_bridge()._rngs[giver_id] = rng

func _test_profile_flags_and_compat() -> void:
	var commitment := SimulationBootstrap.create(73001, "commitment")
	var material := SimulationBootstrap.create(73001, "material_request")
	var information := SimulationBootstrap.create(73001, "information")
	var framework := SimulationBootstrap.create(73001, "framework")
	_check("commitment_profile_enables_everything",
		bool(commitment.get("ok", false))
		and (commitment["sim"] as IslandSimulation).agency_commitment_consequences_enabled
		and (commitment["sim"] as IslandSimulation).agency_material_requests_enabled)
	_check("old_profiles_keep_commitments_off",
		(not (material["sim"] as IslandSimulation).agency_commitment_consequences_enabled)
		and (not (information["sim"] as IslandSimulation).agency_commitment_consequences_enabled)
		and (not (framework["sim"] as IslandSimulation).agency_commitment_consequences_enabled))
	# flag off：真实决策入口不注解、无义务计划产生（旧路径零改动）。
	var pair := _pair(73002)
	pair["sim"].agency_commitment_consequences_enabled = false
	pair["requester"]["needs"]["hunger"] = 800  # 触发问题 → 产生真实提案
	var prepare: Dictionary = pair["sim"]._agency_prepare(
		str(pair["requester_id"]), pair["requester"])
	var annotated := 0
	var obligation_proposals := 0
	for proposal in (prepare.get("proposals", []) as Array):
		if (proposal as Dictionary).has("blocker_resolution"):
			annotated += 1
		if str((proposal as Dictionary).get("root_goal", "")) == "OBLIGATION":
			obligation_proposals += 1
	_check("flag_off_adds_no_resolution_annotation", annotated == 0,
		"annotated=%d proposals=%d" % [annotated, (prepare.get("proposals", []) as Array).size()])
	_check("flag_off_emits_no_obligation_plans", obligation_proposals == 0
		and (pair["sim"] as IslandSimulation)._commitment_obligation_plans(
			str(pair["requester_id"]), pair["requester"]).is_empty())

func _test_full_exchange_chain() -> Dictionary:
	var pair := _pair(73003, 0.2)  # B 不苛求回款窗口 → A 的期限估计能覆盖
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var request_id := _open_request(sim, pair)
	_check("blocked_run_creates_material_request", request_id != "", request_id)
	var giver_shells_before := int((pair["giver"]["inventory"] as Dictionary).get("shells", 0))
	# A 发出 offer → B 应答（fixture 保证交换型 counter）。
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var request := sim.agency_material_request(request_id)
	_check("offer_reaches_subjective_holder",
		str(request.get("status", "")) == Contract.STATUS_WAITING_RESPONSE
		and str(request.get("target_id", "")) == giver_id, str(request))
	var forced := RandomNumberGenerator.new()
	forced.seed = 0
	sim._material_request_runtime_bridge()._rngs[giver_id] = forced
	sim._material_requests_process_actor(giver_id, pair["giver"], [])
	request = sim.agency_material_request(request_id)
	var counter: Dictionary = request.get("last_counter", {})
	_check("giver_counters_with_exchange_terms",
		str(request.get("status", "")) == Contract.STATUS_WAITING_REQUESTER
		and bool(counter.get("requires_exchange", false))
		and str((counter.get("terms", {}) as Dictionary).get("promise_object", "")) == "shells",
		str(request.get("response_reason", "")))
	_check("negotiation_so_far_mutated_no_inventory",
		int((pair["giver"]["inventory"] as Dictionary).get("shells", 0)) == giver_shells_before
		and int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == 0)
	# A 处理 counter → 接受承诺条款 → counter accepted → 立即尝试转移。
	var obligations_before := (sim.obligations as Array).size()
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var ledger: Array = sim.obligations
	_check("accepted_exchange_creates_commitment_and_activates",
		ledger.size() == obligations_before + 1
		and str((ledger[ledger.size() - 1] as Dictionary).get("status", "")) == CommitmentContract.STATUS_ACTIVE
		and str((ledger[ledger.size() - 1] as Dictionary).get("source_request_id", "")) == request_id
		and str((ledger[ledger.size() - 1] as Dictionary).get("source_transfer_event_id", "")) != "",
		str(ledger))
	var commitment: Dictionary = ledger[ledger.size() - 1]
	_check("matching_transfer_activates_commitment",
		str(commitment.get("status", "")) == Contract.STATUS_ACTIVE
		and int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == 2,
		str(commitment))
	_check("world_saw_commitment_events",
		_count_events(sim, "COMMITMENT_CREATED") == 1
		and _count_events(sim, "COMMITMENT_ACTIVATED") == 1)
	# 激活后：父计划消失不得抹掉债务（义务独立于父计划生命周期）。
	sim._execution_tracker().runs.erase(requester_id)
	_check("parent_run_loss_keeps_active_debt",
		str((sim.obligations[0] as Dictionary).get("status", "")) == Contract.STATUS_ACTIVE)
	# ACTIVE 承诺 → 履约计划进入提案（已有足量 → 单步 GIVE）。
	var prepare: Dictionary = sim._agency_prepare(requester_id, pair["requester"])
	var obligation_plans: Array = []
	for proposal in (prepare.get("proposals", []) as Array):
		if str((proposal as Dictionary).get("root_goal", "")) == "OBLIGATION":
			obligation_plans.append(proposal)
	_check("active_commitment_yields_obligation_plan",
		obligation_plans.size() == 1
		and str((obligation_plans[0] as Dictionary).get("plan_id", "")).begins_with("PLAN_OBLIGATION_"),
		str(obligation_plans.size()))
	var plan_steps: Array = (obligation_plans[0] as Dictionary).get("steps", [])
	_check("sufficient_stock_plan_is_single_give",
		plan_steps.size() == 1 and str((plan_steps[0] as Dictionary).get("kind", "")) == "MAIN"
		and str((plan_steps[0] as Dictionary).get("action_name", "")) == "repay_debt"
		and str((plan_steps[0] as Dictionary).get("commitment_id", "")) != "",
		str(plan_steps))
	# 缺货版义务计划：ACQUIRE 在前（可自然进入 P7.0/P7.1 路径）。
	pair["requester"]["inventory"] = {"shells": 1}
	var prepare_missing: Dictionary = sim._agency_prepare(requester_id, pair["requester"])
	var missing_plans: Array = []
	for proposal in (prepare_missing.get("proposals", []) as Array):
		if str((proposal as Dictionary).get("root_goal", "")) == "OBLIGATION":
			missing_plans.append(proposal)
	var missing_steps: Array = (missing_plans[0] as Dictionary).get("steps", [])
	_check("missing_stock_plan_starts_with_acquire",
		missing_steps.size() == 2
		and str((missing_steps[0] as Dictionary).get("kind", "")) == "ACQUIRE"
		and str((missing_steps[1] as Dictionary).get("kind", "")) == "MAIN",
		str(missing_steps))
	# 真实履约结算：一次性转移 + FULFILLED。
	pair["requester"]["inventory"] = {"shells": 2}
	var shells_giver_before := int((pair["giver"]["inventory"] as Dictionary).get("shells", 0))
	sim._do_repay(requester_id, pair["requester"], {
		"target_actor": giver_id, "object": "shells", "obligation": sim.obligations[0],
	}, [])
	_check("settlement_fulfills_with_single_transfer",
		str((sim.obligations[0] as Dictionary).get("status", "")) == CommitmentContract.STATUS_FULFILLED
		and int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == 0
		and int((pair["giver"]["inventory"] as Dictionary).get("shells", 0)) == shells_giver_before + 2)
	_check("fulfilled_emits_evidence_events",
		_count_events(sim, CommitmentContract.EVENT_COMMITMENT_TRANSFER_COMPLETED) == 1
		and _count_events(sim, CommitmentContract.EVENT_COMMITMENT_FULFILLED) == 1)
	# 终态后重复结算被拒。
	var shells_before_repeat := int((pair["requester"]["inventory"] as Dictionary).get("shells", 0))
	sim._do_repay(requester_id, pair["requester"], {
		"target_actor": giver_id, "object": "shells", "obligation": sim.obligations[0],
	}, [])
	_check("repeat_settlement_rejected",
		int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == shells_before_repeat)
	_check("fulfilled_commitment_leaves_recipient_load",
		float(sim._material_recipient_context(giver_id, requester_id, "shells")["commitment_load"]) == 0.0)
	return pair

func _test_terms_mismatch_path() -> void:
	var pair := _pair(73004, 0.9)  # B 极谨慎 → 要求更短回款窗口
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var request_id := _open_request(sim, pair)
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var forced := RandomNumberGenerator.new()
	forced.seed = 0
	sim._material_request_runtime_bridge()._rngs[giver_id] = forced
	sim._material_requests_process_actor(giver_id, pair["giver"], [])
	var request := sim.agency_material_request(request_id)
	if str(request.get("status", "")) != Contract.STATUS_WAITING_REQUESTER:
		_check("mismatch_fixture_produced_counter", false, str(request.get("status", "")))
		return
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	_check("terms_mismatch_creates_no_debt",
		(sim.obligations as Array).is_empty()
		and _count_events(sim, CommitmentContract.EVENT_COMMITMENT_TERMS_MISMATCH) == 1
		and int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == 0,
		str(sim.obligations))
	_check("mismatch_keeps_request_searching_not_terminal",
		str(sim.agency_material_request(request_id).get("status", "")) == Contract.STATUS_ACTIVE
		or str(sim.agency_material_request(request_id).get("status", "")) == Contract.STATUS_WAITING_RESPONSE,
		str(sim.agency_material_request(request_id).get("status", "")))

func _test_requester_decline_path() -> void:
	var pair := _pair(73005, 0.2)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var request_id := _open_request(sim, pair)
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var forced := RandomNumberGenerator.new()
	forced.seed = 0
	sim._material_request_runtime_bridge()._rngs[giver_id] = forced
	sim._material_requests_process_actor(giver_id, pair["giver"], [])
	# A 已有三笔在身承诺（负担拉满）+ 互惠规范弱 → 不愿再作未来承诺。
	for i in 3:
		var seeded := CommitmentContract.make(
			"commitment:%s:%d:wood" % [requester_id, i + 1], requester_id, giver_id,
			"wood", 1, sim.tick, sim.tick + 200, CommitmentContract.SOURCE_MATERIAL_REQUEST,
			"material:%s:%d:wood" % [requester_id, i], {"object": "wood", "quantity": 1, "due_tick": sim.tick + 200})
		seeded["status"] = CommitmentContract.STATUS_ACTIVE
		sim.obligations.append(seeded)
	(pair["requester"]["norms"] as Dictionary)["personal"] = {"reciprocity": 0.3, "sharing": 0.5}
	pair["requester"]["my_obligations"] = (sim as IslandSimulation)._obligations_of(requester_id)
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	_check("overloaded_requester_declines_exchange",
		(sim.obligations as Array).size() == 3  # 只有预置三笔，没有新承诺
		and _count_events(sim, "MATERIAL_COUNTER_REJECTED") >= 1
		and int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == 0,
		str((sim.obligations as Array).size()))

func _test_transfer_failure_cancels_pending() -> void:
	var pair := _pair(73006, 0.2)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var request_id := _open_request(sim, pair)
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var forced := RandomNumberGenerator.new()
	forced.seed = 0
	sim._material_request_runtime_bridge()._rngs[giver_id] = forced
	sim._material_requests_process_actor(giver_id, pair["giver"], [])
	if str(sim.agency_material_request(request_id).get("status", "")) != Contract.STATUS_WAITING_REQUESTER:
		_check("failure_fixture_produced_counter", false,
			str(sim.agency_material_request(request_id).get("status", "")))
		return
	# B 先走远 → A 接受条款建立 PENDING，但即时转移因距离被跳过。
	pair["giver"]["tile"] = Vector2i(60, 60)
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	if (sim.obligations as Array).is_empty():
		_check("failure_fixture_created_pending", false, "no commitment created")
		return
	_check("pending_created_when_transfer_deferred",
		str((sim.obligations[0] as Dictionary).get("status", "")) == CommitmentContract.STATUS_PENDING_ACTIVATION,
		str(sim.obligations[0]))
	# B 回到身边但库存已被掏空 → 转移失败 → 承诺取消（无对价不成债）。
	pair["giver"]["tile"] = Vector2i(11, 10)
	(pair["giver"]["inventory"] as Dictionary)["shells"] = 0
	var current := sim.agency_material_request(request_id)
	if str(current.get("status", "")) != Contract.STATUS_WAITING_TRANSFER:
		_check("failure_fixture_reached_transfer", false, str(current.get("status", "")))
		return
	sim._material_requests_try_transfer(requester_id, pair["requester"], current, [])
	var commitment: Dictionary = sim.obligations[0]
	_check("failed_transfer_cancels_commitment",
		str(commitment.get("status", "")) == CommitmentContract.STATUS_CANCELLED
		and str(commitment.get("terminal_reason", "")) == "SOURCE_TRANSFER_FAILED"
		and int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == 0,
		str(commitment))
	_check("cancelled_commitment_not_in_load",
		not CommitmentContract.counts_toward_load(commitment))

func _test_violation_path_and_consequence() -> void:
	# 同一 dyad 上分别测：违约 → 认知下降 → 合作概率下降；并做阈值翻转。
	# B 对 A 起点为负向关系 + 低互惠 → 违约后的承诺估值降到交换线以下，
	# 使同一 roll 在两种历史下产生 REFUSE / ACCEPT 的翻转。
	var pair := _pair(73007, 0.2)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	sim.relationships.adjust(giver_id, requester_id, "benevolence", -600)
	sim.relationships.adjust(giver_id, requester_id, "reliability", -600)
	(pair["giver"]["norms"] as Dictionary)["personal"] = {"reciprocity": 0.2, "sharing": 0.3}
	(pair["giver"]["inventory"] as Dictionary)["shells"] = 3  # 全额盈余 → 阈值翻转走 ACCEPT/REFUSE 主路径
	var request := {"request_id": "material:x:1:shells", "requester_id": requester_id,
		"target_id": giver_id, "item_id": "shells", "requested_quantity": 3, "urgency": 0.8}
	var baseline_context := sim._material_recipient_context(giver_id, requester_id, "shells")
	var policy := ResponsePolicy.new()
	var p0 := float(policy.evaluate(request, baseline_context, 0.5).get("accept_probability", -1.0))
	# 构造一笔到期未履约的 ACTIVE 承诺 → 违约事件 → 债权人认知。
	var violated := CommitmentContract.make("commitment:%s:9:shells" % requester_id,
		requester_id, giver_id, "shells", 1, 0, 50,
		CommitmentContract.SOURCE_MATERIAL_REQUEST, "material:x:1:shells",
		{"object": "shells", "quantity": 1, "due_tick": 50})
	violated["status"] = CommitmentContract.STATUS_ACTIVE
	violated["activated_tick"] = 1
	sim.obligations.append(violated)
	sim.tick = 51
	sim._commitments_check_due()
	_check("overdue_commitment_violated_once",
		str((sim.obligations[0] as Dictionary).get("status", "")) == CommitmentContract.STATUS_VIOLATED
		and _count_events(sim, CommitmentContract.EVENT_COMMITMENT_VIOLATED) == 1)
	var violated_event: Dictionary = _last_event(sim, CommitmentContract.EVENT_COMMITMENT_VIOLATED)
	_check("violation_event_addresses_creditor",
		str(violated_event.get("to_id", "")) == giver_id
		and str(violated_event.get("actor_id", "")) == requester_id)
	# 债权人亲历违约 → 认知/关系变化 → 合作概率下降（同一 roll 对照）。
	var giver: Dictionary = pair["giver"]
	var trust_before := sim.relationships.composite_trust(giver_id, requester_id)
	CognitiveTransition.process(giver, violated_event, {"relationships": sim.relationships, "tick": sim.tick})
	var trust_after := sim.relationships.composite_trust(giver_id, requester_id)
	_check("violation_lowers_creditor_trust", trust_after < trust_before,
		"%d -> %d" % [trust_before, trust_after])
	var after_violation := sim._material_recipient_context(giver_id, requester_id, "shells")
	var p_violated := float(policy.evaluate(request, after_violation, 0.5).get("accept_probability", -1.0))
	_check("violated_history_lowers_cooperation", p_violated < p0,
		"p0=%.4f p_violated=%.4f" % [p0, p_violated])
	# 阈值翻转：同一 roll 落在两个概率之间 → 违约后 REFUSE。
	var roll := (p_violated + p0) * 0.5
	var verdict_violated := str(policy.evaluate(request, after_violation, roll).get("outcome", ""))
	_check("threshold_roll_refuses_after_violation", verdict_violated == Contract.OUTCOME_REFUSE,
		"roll=%.4f %s" % [roll, verdict_violated])
	# 履约历史（独立 dyad）→ 概率上升 + 同 roll 接受。
	var fulfilled_pair := _pair(73008, 0.2)
	var fsim: IslandSimulation = fulfilled_pair["sim"]
	var f_requester := str(fulfilled_pair["requester_id"])
	var f_giver := str(fulfilled_pair["giver_id"])
	var f_request := {"request_id": "material:y:1:shells", "requester_id": f_requester,
		"target_id": f_giver, "item_id": "shells", "requested_quantity": 3, "urgency": 0.8}
	var f_base := float(policy.evaluate(f_request,
		fsim._material_recipient_context(f_giver, f_requester, "shells"), 0.5).get("accept_probability", -1.0))
	var kept := CommitmentContract.make("commitment:%s:1:shells" % f_requester,
		f_requester, f_giver, "shells", 1, 0, 500,
		CommitmentContract.SOURCE_MATERIAL_REQUEST, "material:y:1:shells",
		{"object": "shells", "quantity": 1, "due_tick": 500})
	kept["status"] = CommitmentContract.STATUS_ACTIVE
	kept["activated_tick"] = 1
	fsim.obligations.append(kept)
	var fulfilled_event := {
		"type": CommitmentContract.EVENT_COMMITMENT_FULFILLED,
		"actor_id": f_requester, "to_id": f_giver,
		"object_id": "shells", "commitment_id": kept["commitment_id"],
		"tick": fsim.tick, "seq": 9001,
	}
	CognitiveTransition.process(fulfilled_pair["giver"], fulfilled_event,
		{"relationships": fsim.relationships, "tick": fsim.tick})
	kept["status"] = CommitmentContract.STATUS_FULFILLED
	var f_after := float(policy.evaluate(f_request,
		fsim._material_recipient_context(f_giver, f_requester, "shells"), 0.5).get("accept_probability", -1.0))
	_check("fulfilled_history_raises_cooperation", f_after > f_base,
		"base=%.4f after=%.4f" % [f_base, f_after])
	var f_roll := (f_base + f_after) * 0.5
	var verdict_fulfilled := str(policy.evaluate(f_request,
		fsim._material_recipient_context(f_giver, f_requester, "shells"), f_roll).get("outcome", ""))
	_check("same_roll_accepts_after_fulfillment",
		verdict_fulfilled == Contract.OUTCOME_ACCEPT or verdict_fulfilled == Contract.OUTCOME_COUNTER,
		"roll=%.4f %s" % [f_roll, verdict_fulfilled])

func _test_cognition_semantics_mapping(main_pair: Dictionary) -> void:
	var sim: IslandSimulation = main_pair["sim"]
	var event := _last_event(sim, CommitmentContract.EVENT_COMMITMENT_FULFILLED)
	var sem: Dictionary = ResourceSpec.semantics_of(event)
	_check("fulfilled_maps_to_promise_semantics",
		str(sem.get("act", "")) == "PROMISE" and str(sem.get("response", "")) == "FULFILLED",
		str(sem))
	var se := SubjectiveEvent.build(main_pair["giver"], event, sim.relationships)
	_check("creditor_role_is_recipient", str(se.get("role", "")) == "recipient", str(se.get("role", "")))

func _count_events(sim: IslandSimulation, event_type: String) -> int:
	var count := 0
	for e in sim.events:
		if str((e as Dictionary).get("type", "")) == event_type:
			count += 1
	return count

func _last_event(sim: IslandSimulation, event_type: String) -> Dictionary:
	var found: Dictionary = {}
	for e in sim.events:
		if str((e as Dictionary).get("type", "")) == event_type:
			found = e
	return found
