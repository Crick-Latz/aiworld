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
	_test_real_registry_fulfillment()
	_test_pending_view_invisibility()
	_test_terminal_view_synchronization()
	_test_remote_creditor_violation()
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
	var trust_before := sim.relationships.composite_trust(giver_id, requester_id)
	sim._commitments_check_due()
	_check("overdue_commitment_violated_once",
		str((sim.obligations[0] as Dictionary).get("status", "")) == CommitmentContract.STATUS_VIOLATED
		and _count_events(sim, CommitmentContract.EVENT_COMMITMENT_VIOLATED) == 1)
	var violated_event: Dictionary = _last_event(sim, CommitmentContract.EVENT_COMMITMENT_VIOLATED)
	_check("violation_event_addresses_creditor",
		str(violated_event.get("to_id", "")) == giver_id
		and str(violated_event.get("actor_id", "")) == requester_id)
	# P7.2A：违约认知由 runtime _emit 通道完成（相邻债权人目击处理一次）——不再手工补刀。
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

# ── P7.2A A：真实 ActionRegistry → Adapter → 决策身份 → _complete_action 全链 ──
func _test_real_registry_fulfillment() -> void:
	var pair := _pair(74010, 0.2)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var request := {"request_id": "material:a:r:shells", "requester_id": requester_id,
		"target_id": giver_id, "item_id": "shells", "requested_quantity": 2,
		"parent_plan_id": "P", "parent_run_id": requester_id + "#r", "blocker_step_id": "CRAFT:s"}
	var bridge := sim._commitment_runtime_bridge()
	var created: Dictionary = bridge.open_commitment_for_request(sim.obligations, request,
		{"object": "shells", "quantity": 2, "due_tick": sim.tick + 240}, sim.tick)
	var cid := str((created["commitment"] as Dictionary).get("commitment_id", ""))
	bridge.activate_from_transfer(sim.obligations, {"request_id": "material:a:r:shells", "accepted_quantity": 2}, {
		"event_id": "transfer:real:1", "type": "ITEM_TRANSFER_COMPLETED",
		"request_id": "material:a:r:shells", "item_id": "shells", "quantity": 2,
		"from_actor_id": giver_id, "to_actor_id": requester_id, "evidence_kind": "WORLD_MUTATION",
	}, sim.tick)
	sim._refresh_obligation_views(requester_id, giver_id)
	pair["requester"]["inventory"] = {"shells": 2}
	# 1) obligation plan READY。
	var prepare: Dictionary = sim._agency_prepare(requester_id, pair["requester"])
	var obligation_plans: Array = []
	for proposal in (prepare.get("proposals", []) as Array):
		if str((proposal as Dictionary).get("root_goal", "")) == "OBLIGATION":
			obligation_plans.append(proposal)
	var plan: Dictionary = obligation_plans[0] if obligation_plans.size() == 1 else {}
	_check("registry_fixture_plan_ready",
		str(plan.get("plan_id", "")) == "PLAN_OBLIGATION_" + cid, str(plan.get("plan_id", "")))
	# 2) 真实 ActionRegistry 产生 repay_debt 候选（quantity=2、库存=2）。
	var world := {"tick": sim.tick, "weather": "clear", "hour": 12}
	var candidates: Array = ActionRegistry.get_available_actions(pair["requester"], world)
	var repay_candidates: Array = []
	for c in candidates:
		if str((c as Dictionary).get("action", "")) == "repay_debt":
			repay_candidates.append(c)
	_check("registry_generates_commitment_repay_candidate",
		repay_candidates.size() == 1
		and str((repay_candidates[0] as Dictionary).get("target_actor", "")) == giver_id
		and str(((repay_candidates[0] as Dictionary).get("obligation", {}) as Dictionary).get("commitment_id", "")) == cid,
		str(repay_candidates.size()))
	# 3) PlanStepActionAdapter 按 commitment_id 匹配同承诺。
	var main_step: Dictionary = {}
	for s in (plan.get("steps", []) as Array):
		if str((s as Dictionary).get("kind", "")) == "MAIN":
			main_step = s
	var matched: Dictionary = PlanStepActionAdapter.match_candidates(main_step, candidates,
		AgencyContextBuilder.build(sim, pair["requester"]))
	_check("adapter_matches_same_commitment",
		(matched.get("candidates", []) as Array).size() == 1
		and str(matched.get("blocker_reason", "x")) == "",
		str(matched.get("blocker_reason", "")))
	# 4) 决策身份建立 + _complete_action 走完真实结算与计划完成。
	var chosen: Dictionary = repay_candidates[0]
	var run := {
		"run_id": requester_id + "#r2", "actor_id": requester_id,
		"plan_id": str(plan.get("plan_id", "")), "root_goal": "OBLIGATION",
		"current_step_id": str(main_step.get("step_id", "")),
		"steps": plan.get("steps", []), "state": "ACTIVE",
		"baseline_items": {}, "pending": {}, "attempt_seq": 0, "missed_opportunities": 0,
	}
	sim._execution_tracker().runs[requester_id] = run
	pair["requester"]["_execution_receipt"] = {
		"actor_id": requester_id, "decision_tick": sim.tick,
		"run_id": run["run_id"], "step_id": run["current_step_id"],
		"selected": true, "candidate_key": AgencyActionBridge.candidate_key(chosen),
		"chosen_key": AgencyActionBridge.candidate_key(chosen),
		"selection_mode": "SOFTMAX", "blocker_reason": "",
	}
	sim._plan_execution_on_decision(requester_id, pair["requester"], chosen,
		{"ctx": AgencyContextBuilder.build(sim, pair["requester"]),
			"catalog": sim._recipe_catalog_if_any()})
	var giver_before := int((pair["giver"]["inventory"] as Dictionary).get("shells", 0))
	pair["requester"]["current_action"] = chosen
	sim._complete_action(requester_id, pair["requester"], [])
	_check("real_path_settles_and_fulfills",
		str((sim.obligations[0] as Dictionary).get("status", "")) == CommitmentContract.STATUS_FULFILLED
		and int((pair["requester"]["inventory"] as Dictionary).get("shells", 0)) == 0
		and int((pair["giver"]["inventory"] as Dictionary).get("shells", 0)) == giver_before + 2
		and _count_events(sim, CommitmentContract.EVENT_COMMITMENT_FULFILLED) == 1)
	var run_after: Dictionary = sim.agency_plan_run(requester_id)
	_check("real_path_completes_obligation_run",
		str(run_after.get("state", "")) == "COMPLETED", str(run_after.get("state", "")))
	# 5) 数量门槛：库存 1 < quantity 2 → 不产生承诺型 repay 候选。
	var pair2 := _pair(74011, 0.2)
	var sim2: IslandSimulation = pair2["sim"]
	var r2 := str(pair2["requester_id"])
	var g2 := str(pair2["giver_id"])
	var b2 := sim2._commitment_runtime_bridge()
	var c2: Dictionary = b2.open_commitment_for_request(sim2.obligations,
		{"request_id": "m2", "requester_id": r2, "target_id": g2, "item_id": "shells"},
		{"object": "shells", "quantity": 2, "due_tick": sim2.tick + 240}, sim2.tick)
	b2.activate_from_transfer(sim2.obligations, {"request_id": "m2", "accepted_quantity": 2}, {
		"event_id": "t2", "type": "ITEM_TRANSFER_COMPLETED", "request_id": "m2",
		"item_id": "shells", "quantity": 2, "from_actor_id": g2, "to_actor_id": r2,
		"evidence_kind": "WORLD_MUTATION",
	}, sim2.tick)
	sim2._refresh_obligation_views(r2, g2)
	pair2["requester"]["inventory"] = {"shells": 1}
	var candidates2: Array = ActionRegistry.get_available_actions(pair2["requester"], {"tick": sim2.tick})
	var repay2: Array = []
	for c in candidates2:
		if str((c as Dictionary).get("action", "")) == "repay_debt":
			repay2.append(c)
	_check("insufficient_quantity_blocks_registry_candidate",
		repay2.is_empty() and str((c2["commitment"] as Dictionary).get("status", "")) == CommitmentContract.STATUS_ACTIVE,
		str(repay2.size()))

# ── P7.2A B：PENDING 不进入任何债务视图、不产生行动、不计负担 ──
func _test_pending_view_invisibility() -> void:
	var pair := _pair(74012, 0.2)
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
		_check("pending_fixture_produced_counter", false,
			str(sim.agency_material_request(request_id).get("status", "")))
		return
	# B 走远 → A 接受条款建 PENDING，但即时转移被距离阻断。
	pair["giver"]["tile"] = Vector2i(60, 60)
	pair["requester"]["inventory"] = {"shells": 2}  # 有货也不该能"提前还未成立的债"
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	if (sim.obligations as Array).is_empty():
		_check("pending_fixture_created_pending", false, "no commitment")
		return
	_check("pending_not_in_debtor_view",
		(pair["requester"].get("my_obligations", []) as Array).is_empty())
	_check("pending_not_in_creditor_view",
		(pair["giver"].get("owed_to_me", []) as Array).is_empty())
	var candidates: Array = ActionRegistry.get_available_actions(pair["requester"], {"tick": sim.tick})
	var repay: Array = []
	for c in candidates:
		if str((c as Dictionary).get("action", "")) == "repay_debt":
			repay.append(c)
	_check("pending_creates_no_repay_candidate", repay.is_empty(), str(repay.size()))
	_check("pending_not_in_commitment_load",
		sim._commitment_runtime_bridge().tracker.active_count_for_load(sim.obligations, requester_id) == 0)

# ── P7.2A B：状态转移同步双方视图 ──
func _test_terminal_view_synchronization() -> void:
	var pair := _pair(74013, 0.2)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var giver_id := str(pair["giver_id"])
	var bridge := sim._commitment_runtime_bridge()
	var created: Dictionary = bridge.open_commitment_for_request(sim.obligations,
		{"request_id": "m3", "requester_id": requester_id, "target_id": giver_id, "item_id": "shells"},
		{"object": "shells", "quantity": 2, "due_tick": sim.tick + 240}, sim.tick)
	var cid := str((created["commitment"] as Dictionary).get("commitment_id", ""))
	sim._refresh_obligation_views(requester_id, giver_id)
	_check("views_sync_pending_stays_invisible",
		(pair["requester"].get("my_obligations", []) as Array).is_empty())
	bridge.activate_from_transfer(sim.obligations, {"request_id": "m3", "accepted_quantity": 2}, {
		"event_id": "t3", "type": "ITEM_TRANSFER_COMPLETED", "request_id": "m3",
		"item_id": "shells", "quantity": 2, "from_actor_id": giver_id, "to_actor_id": requester_id,
		"evidence_kind": "WORLD_MUTATION",
	}, sim.tick)
	sim._refresh_obligation_views(requester_id, giver_id)
	_check("activation_enters_both_views",
		(pair["requester"].get("my_obligations", []) as Array).size() == 1
		and (pair["giver"].get("owed_to_me", []) as Array).size() == 1)
	# 履约 → 双方视图出清。
	pair["requester"]["inventory"] = {"shells": 2}
	sim._do_repay(requester_id, pair["requester"],
		{"target_actor": giver_id, "object": "shells", "obligation": sim.obligations[0]}, [])
	_check("fulfilled_leaves_both_views",
		(pair["requester"].get("my_obligations", []) as Array).is_empty()
		and (pair["giver"].get("owed_to_me", []) as Array).is_empty())
	# 第二笔 → 违约 → 双方视图出清。
	var second: Dictionary = bridge.open_commitment_for_request(sim.obligations,
		{"request_id": "m4", "requester_id": requester_id, "target_id": giver_id, "item_id": "shells"},
		{"object": "shells", "quantity": 1, "due_tick": sim.tick + 240}, sim.tick)
	bridge.activate_from_transfer(sim.obligations, {"request_id": "m4", "accepted_quantity": 1}, {
		"event_id": "t4", "type": "ITEM_TRANSFER_COMPLETED", "request_id": "m4",
		"item_id": "shells", "quantity": 1, "from_actor_id": giver_id, "to_actor_id": requester_id,
		"evidence_kind": "WORLD_MUTATION",
	}, sim.tick)
	sim._refresh_obligation_views(requester_id, giver_id)
	(sim.obligations[1] as Dictionary)["due_tick"] = sim.tick - 1
	sim.tick += 1
	sim._commitments_check_due()
	_check("violated_leaves_both_views",
		str((second["commitment"] as Dictionary).get("status", "")) == CommitmentContract.STATUS_VIOLATED
		and (pair["requester"].get("my_obligations", []) as Array).is_empty()
		and (pair["giver"].get("owed_to_me", []) as Array).is_empty())
	# 第三笔 → 取消 → 视图出清。
	var third: Dictionary = bridge.open_commitment_for_request(sim.obligations,
		{"request_id": "m5", "requester_id": requester_id, "target_id": giver_id, "item_id": "shells"},
		{"object": "shells", "quantity": 1, "due_tick": sim.tick + 240}, sim.tick)
	sim._refresh_obligation_views(requester_id, giver_id)
	bridge.cancel_for_request(sim.obligations, "m5", "SOURCE_REQUEST_FAILED", sim.tick + 1)
	sim._commitments_on_request_terminal({"request_id": "m5"}, "SOURCE_REQUEST_FAILED", "TEST")
	_check("cancelled_leaves_both_views",
		str((third["commitment"] as Dictionary).get("status", "")) == CommitmentContract.STATUS_CANCELLED
		and (pair["requester"].get("my_obligations", []) as Array).is_empty())

# ── P7.2A C：远距离债权人直接得知违约（无位置泄漏；第三方不变；单次处理）──
func _test_remote_creditor_violation() -> void:
	var created := SimulationBootstrap.create(74014, "commitment")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var debtor_id := str(ids[0])
	var creditor_id := str(ids[1])
	var third_id := str(ids[2])
	var debtor: Dictionary = sim.actors[debtor_id]
	var creditor: Dictionary = sim.actors[creditor_id]
	var third: Dictionary = sim.actors[third_id]
	debtor["tile"] = Vector2i(10, 10)
	creditor["tile"] = Vector2i(60, 60)  # 远离：不可见、不可听
	third["tile"] = Vector2i(70, 70)     # 更远的无关第三方
	creditor["inventory"] = {"shells": 3}  # 全额盈余 → 后续合作概率有效取值
	var bridge := sim._commitment_runtime_bridge()
	var rec: Dictionary = bridge.open_commitment_for_request(sim.obligations,
		{"request_id": "mr", "requester_id": debtor_id, "target_id": creditor_id, "item_id": "shells",
			"parent_plan_id": "P", "parent_run_id": "r", "blocker_step_id": "CRAFT:s"},
		{"object": "shells", "quantity": 1, "due_tick": 50}, 10)
	bridge.activate_from_transfer(sim.obligations, {"request_id": "mr", "accepted_quantity": 1}, {
		"event_id": "tr", "type": "ITEM_TRANSFER_COMPLETED", "request_id": "mr",
		"item_id": "shells", "quantity": 1, "from_actor_id": creditor_id, "to_actor_id": debtor_id,
		"evidence_kind": "WORLD_MUTATION",
	}, 12)
	sim._refresh_obligation_views(debtor_id, creditor_id)
	var trust_before := sim.relationships.composite_trust(creditor_id, debtor_id)
	var third_trust_before := sim.relationships.composite_trust(third_id, debtor_id)
	var third_memories_before := (third.get("memories", []) as Array).size()
	var creditor_memories_before := (creditor.get("memories", []) as Array).size()
	sim.tick = 51
	sim._commitments_check_due()
	sim._commitments_check_due()  # 第二次不得重复处理
	_check("remote_violation_event_emitted_once",
		_count_events(sim, CommitmentContract.EVENT_COMMITMENT_VIOLATED) == 1)
	var trust_after := sim.relationships.composite_trust(creditor_id, debtor_id)
	_check("remote_creditor_consequence_without_witness",
		trust_after < trust_before, "%d -> %d" % [trust_before, trust_after])
	_check("remote_creditor_memory_records_consequence",
		(creditor.get("memories", []) as Array).size() > creditor_memories_before)
	_check("remote_creditor_gains_no_position_knowledge",
		(creditor["tom"] as TheoryOfMind).last_seen_of(debtor_id).is_empty(),
		str((creditor["tom"] as TheoryOfMind).last_seen_of(debtor_id)))
	_check("unrelated_far_third_party_unchanged",
		sim.relationships.composite_trust(third_id, debtor_id) == third_trust_before
		and (third.get("memories", []) as Array).size() == third_memories_before
		and (third["tom"] as TheoryOfMind).last_seen_of(debtor_id).is_empty())
	_check("remote_violated_leaves_views",
		str((rec["commitment"] as Dictionary).get("status", "")) == CommitmentContract.STATUS_VIOLATED
		and (debtor.get("my_obligations", []) as Array).is_empty()
		and (creditor.get("owed_to_me", []) as Array).is_empty())
	# runtime 后的后续合作概率：远债权人视角 p_violated < p_baseline（同一 roll）。
	var policy := ResponsePolicy.new()
	var request := {"request_id": "mx", "requester_id": debtor_id, "target_id": creditor_id,
		"item_id": "shells", "requested_quantity": 1, "urgency": 0.8}
	var ctx_after := sim._material_recipient_context(creditor_id, debtor_id, "shells")
	var p_after := float(policy.evaluate(request, ctx_after, 0.5).get("accept_probability", -1.0))
	var fresh := SimulationBootstrap.create(74014, "commitment")
	var fsim: IslandSimulation = fresh["sim"]
	var fids: Array = fsim.actors.keys()
	fids.sort()
	fsim.actors[str(fids[1])]["inventory"] = {"shells": 3}
	var p_base := float(policy.evaluate(request, fsim._material_recipient_context(str(fids[1]), str(fids[0]), "shells"), 0.5).get("accept_probability", -1.0))
	_check("remote_violation_lowers_future_cooperation", p_after < p_base,
		"base=%.4f after=%.4f" % [p_base, p_after])
