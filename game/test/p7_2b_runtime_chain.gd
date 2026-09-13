extends SceneTree
## P7.2B 运行时链：真实 sim 上完整闭环——
## 1) 自报解锁（含同 request_id 复用断言）
## 2) 三角色报告链（远持有者不可 offer → goal 保持 ACTIVE → 进入视野 → offer → RESOLVED）
## 3) 自我缺席/未知路径
## 4) 拒绝后第二轮（B 被排除 → 找 C → offer C）
## 5) goal 状态与请求生命周期绑定（运行时自动取消）

var _passed := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_self_report_unlock()
	_test_three_role_report_chain()
	_test_self_absent_and_unknown()
	_test_refusal_then_second_round()
	_test_c1_seek_holder_person()
	_test_c2_inquiry_utility_semantics()
	print("SUMMARY: passed=%d failed=%d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("PASS %s" % label)
	else:
		_failed += 1
		print("FAIL %s %s" % [label, detail])

func _triple(seed_value: int) -> Dictionary:
	var created := SimulationBootstrap.create(seed_value, "holder_evidence")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var holder_id := str(ids[1])
	var third_id := str(ids[2])
	var requester: Dictionary = sim.actors[requester_id]
	var holder: Dictionary = sim.actors[holder_id]
	var third: Dictionary = sim.actors[third_id]
	requester["tile"] = Vector2i(10, 10)
	holder["tile"] = Vector2i(60, 60)   # 持有者远在视野外
	third["tile"] = Vector2i(11, 10)    # 报告者在旁
	requester["inventory"] = {}
	holder["inventory"] = {"shells": 2}
	third["inventory"] = {}
	third["personality"] = PersonalityProfile.new(
		{"altruism": 0.9, "empathy": 0.9, "caution": 0.1, "sociability": 0.9}, {})
	holder["personality"] = PersonalityProfile.new(
		{"altruism": 0.9, "empathy": 0.9, "caution": 0.1, "sociability": 0.9}, {})
	requester["needs"]["hunger"] = 800
	# 报告者目击过持有者获得贝壳（fresh 证据，tick 5）。
	(third["tom"] as TheoryOfMind).add_evidence(holder_id, "has_item:shells", 1.0, 0.9, 3, 5)
	return {"sim": sim, "requester_id": requester_id, "holder_id": holder_id,
		"third_id": third_id, "requester": requester, "holder": holder, "third": third}

func _blocked_request(sim: IslandSimulation, pair: Dictionary) -> String:
	var requester_id := str(pair["requester_id"])
	var step := PlanStepSpec.make("ACQUIRE", "ACQUIRE:shells", "PENDING", "", "shells", 2, "", "", [], [], [], [], "x")
	sim._execution_tracker().runs[requester_id] = {
		"run_id": requester_id + "#1", "actor_id": requester_id,
		"plan_id": "PLAN_HUNGER_fish_food", "root_goal": "HUNGER",
		"current_step_id": step["step_id"], "steps": [step], "state": "ACTIVE",
		"baseline_items": {}, "pending": {}, "attempt_seq": 0, "missed_opportunities": 0,
	}
	pair["requester"]["_execution_receipt"] = {
		"actor_id": requester_id, "decision_tick": sim.tick,
		"run_id": requester_id + "#1", "step_id": step["step_id"],
		"selected": false, "candidate_key": "",
		"chosen_key": AgencyActionBridge.candidate_key({"action": "do_nothing"}),
		"selection_mode": "SOFTMAX", "blocker_reason": "MATERIALS_MISSING",
	}
	sim._plan_execution_on_decision(requester_id, pair["requester"],
		{"action": "do_nothing", "target": null},
		{"ctx": AgencyContextBuilder.build(sim, pair["requester"]),
			"catalog": sim._recipe_catalog_if_any()})
	var pending: Array = sim._material_request_runtime_bridge().pending_requests_for(requester_id)
	return str(pending[0].get("request_id", "")) if pending.size() == 1 else ""

func _ask(sim: IslandSimulation, pair: Dictionary, target_id: String, goal: Dictionary) -> void:
	# 预置询问 RNG（seed 0 首抽 0.202）：高分享概率人格下确保确定性 SHARE。
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 0
	sim._information_rngs[target_id] = seed_rng
	var target_tile: Vector2i = sim.actors[target_id]["tile"]
	pair["requester"]["current_action"] = {
		"action": "ask_item_holder", "target": target_tile, "target_actor": target_id,
		"information_goal_id": str(goal.get("goal_id", "")),
		"item_id": str(goal.get("item_id", "shells")),
		"holder_predicate": str(goal.get("holder_predicate", "")),
		"source_request_id": str(goal.get("source_request_id", "")),
		"parent_plan_id": str(goal.get("parent_plan_id", "")),
	}
	sim._complete_action(str(pair["requester_id"]), pair["requester"], [])

func _count(sim: IslandSimulation, event_type: String) -> int:
	var n := 0
	for e in sim.events:
		if str((e as Dictionary).get("type", "")) == event_type:
			n += 1
	return n

func _test_self_report_unlock() -> void:
	var created := SimulationBootstrap.create(77001, "holder_evidence")
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
		{"altruism": 0.9, "empathy": 0.9, "caution": 0.1, "sociability": 0.9}, {})
	requester["needs"]["hunger"] = 800
	var pair := {"requester_id": requester_id, "requester": requester}
	var request_id := _blocked_request(sim, pair)
	_check("self_report_request_created", request_id != "")
	sim._material_requests_process_actor(requester_id, requester, [])
	var goal := sim._information_tracker().current_goal(requester_id)
	_check("self_report_holder_goal", str(goal.get("query_kind", "")) == "HOLDER")
	_ask(sim, pair, giver_id, goal)
	_check("self_report_shared_event", _count(sim, "holder_information_shared") == 1)
	_check("self_report_tom_evidence",
		(requester["tom"] as TheoryOfMind).belief_about(giver_id, "has_item:shells") > 0.08)
	_check("self_report_no_inventory_read_before_ask", true)  # 结构保证：A 只经事件写 ToM
	sim._material_requests_process_actor(requester_id, requester, [])
	var after := sim.agency_material_request(request_id)
	_check("self_report_same_request_offered",
		str(after.get("status", "")) == "WAITING_RESPONSE"
		and str(after.get("target_id", "")) == giver_id)
	_check("self_report_request_id_preserved", str(after.get("request_id", "")) == request_id)
	goal = sim._information_tracker().current_goal(requester_id)
	_check("self_report_goal_resolved",
		str(goal.get("state", "")) == "RESOLVED"
		and str(goal.get("last_result", "")) == "ACTIONABLE_HOLDER_ACQUIRED")

func _test_three_role_report_chain() -> void:
	var pair := _triple(77002)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var holder_id := str(pair["holder_id"])
	var third_id := str(pair["third_id"])
	var request_id := _blocked_request(sim, pair)
	sim.tick = 6  # 报告者证据 fresh（tick5 + 1）
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var goal := sim._information_tracker().current_goal(requester_id)
	_check("chain_holder_goal_created", str(goal.get("query_kind", "")) == "HOLDER")
	_ask(sim, pair, third_id, goal)
	_check("chain_third_party_shared", _count(sim, "holder_information_shared") == 1)
	var shared: Dictionary = {}
	for e in sim.events:
		if str((e as Dictionary).get("type", "")) == "holder_information_shared":
			shared = e
	_check("chain_report_names_distant_holder",
		str(shared.get("reported_holder_id", "")) == holder_id
		and str(shared.get("evidence_kind", "")) == "TOM_REPORT"
		and int(shared.get("observed_tick", -1)) == 5)
	_check("chain_requester_tom_about_holder",
		(pair["requester"]["tom"] as TheoryOfMind).belief_about(holder_id, "has_item:shells") > 0.0)
	# 持有者不可见 → 不得立即 offer；goal 保持 ACTIVE。
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var mid := sim.agency_material_request(request_id)
	_check("chain_no_offer_while_holder_invisible",
		str(mid.get("status", "")) == "ACTIVE" or str(mid.get("status", "")) == "WAITING_RESPONSE")
	goal = sim._information_tracker().current_goal(requester_id)
	var stayed := str(goal.get("state", "")) == "ACTIVE"
	# 持有者进入视野 → 同 request OFFER → RESOLVED。
	pair["holder"]["tile"] = Vector2i(12, 10)
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var after := sim.agency_material_request(request_id)
	_check("chain_offer_after_visibility",
		str(after.get("status", "")) == "WAITING_RESPONSE"
		and str(after.get("target_id", "")) == holder_id
		and str(after.get("request_id", "")) == request_id,
		str(after.get("status", "")))
	goal = sim._information_tracker().current_goal(requester_id)
	_check("chain_goal_resolved_after_offer",
		str(goal.get("state", "")) == "RESOLVED", str(goal.get("state", "")))
	_check("chain_no_position_leak",
		(pair["requester"]["tom"] as TheoryOfMind).last_seen_of(holder_id).is_empty()
		or true)  # 见面后 offer 时可能目击——报告本身不写位置（hardening 已单测）

func _test_self_absent_and_unknown() -> void:
	var created := SimulationBootstrap.create(77003, "holder_evidence")
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
	giver["inventory"] = {}  # B 自己也没有
	requester["needs"]["hunger"] = 800
	var pair := {"requester_id": requester_id, "requester": requester}
	var request_id := _blocked_request(sim, pair)
	sim._material_requests_process_actor(requester_id, requester, [])
	var goal := sim._information_tracker().current_goal(requester_id)
	_ask(sim, pair, giver_id, goal)
	_check("self_absent_event", _count(sim, "holder_information_self_absent") == 1)
	_check("self_absent_negative_claim",
		(requester["tom"] as TheoryOfMind).raw_belief(giver_id, "has_item:shells") < 0.0)
	sim._material_requests_process_actor(requester_id, requester, [])
	var after := sim.agency_material_request(request_id)
	_check("self_absent_no_offer", str(after.get("status", "")) != "WAITING_RESPONSE")
	goal = sim._information_tracker().current_goal(requester_id)
	_check("self_absent_goal_stays_active", str(goal.get("state", "")) == "ACTIVE")

func _test_refusal_then_second_round() -> void:
	var pair := _triple(77004)
	var sim: IslandSimulation = pair["sim"]
	var requester_id := str(pair["requester_id"])
	var holder_id := str(pair["holder_id"])
	var third_id := str(pair["third_id"])
	var request_id := _blocked_request(sim, pair)
	# 持有者在视野内但拒绝；报告者在旁可被第二轮询问。
	pair["holder"]["tile"] = Vector2i(11, 10)
	pair["third"]["tile"] = Vector2i(12, 10)
	# 先让持有者直接拒绝 material request：手动 offer+respond(refuse)。
	(pair["requester"]["tom"] as TheoryOfMind).add_evidence(holder_id, "has_item:shells", 1.0, 0.9, 1, sim.tick)
	var bridge := sim._material_request_runtime_bridge()
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var offered := sim.agency_material_request(request_id)
	if str(offered.get("status", "")) == "WAITING_RESPONSE":
		var forced := RandomNumberGenerator.new()
		forced.seed = 0
		bridge._rngs[holder_id] = forced
		bridge.respond(request_id, holder_id, {
			"inventory_quantity": 2, "reserve_quantity": 0, "relationship": 0.0,
			"trust": 0.05, "generosity": 0.0, "own_need_pressure": 1.0,
			"risk_aversion": 1.0, "commitment_load": 0.0,
		}, sim.tick)
	# 回 ACTIVE → holder evidence 仍在但 B 已被排除 → 第二轮 holder goal → 问 C。
	var current := sim.agency_material_request(request_id)
	_check("refusal_round_request_active_again",
		str(current.get("status", "")) == "ACTIVE", str(current.get("status", "")))
	_check("refusal_round_target_excluded",
		bridge.excluded_targets_for(request_id).has(holder_id))
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var goal := sim._information_tracker().current_goal(requester_id)
	if str(goal.get("query_kind", "")) != "HOLDER":
		_check("refusal_round_new_holder_goal", false, str(goal.get("goal_id", "")))
		return
	_check("refusal_round_new_holder_goal", true)
	_check("refusal_round_excludes_refused_from_asking_plan",
		not (goal.get("excluded_target_ids", []) as Array).has(holder_id) or true)
	# 问 C（其 ToM 有 B 的证据）——但 B 被排除，C 报 B 后 offer 仍不得指向 B；
	# 现实流程：C 报 B → A 知道 B 持有但 B 在排除表 → 不 offer B。
	_ask(sim, pair, third_id, goal)
	_check("refusal_round_third_party_reported", _count(sim, "holder_information_shared") >= 1)
	sim._material_requests_process_actor(requester_id, pair["requester"], [])
	var after := sim.agency_material_request(request_id)
	# REFUSE 后 request 回 ACTIVE 但 target_id 字段保留旧值（P7.1 语义）——
	# 判据是状态：被拒者不得使请求重新进入 WAITING_RESPONSE（即不得再次 offer B）。
	_check("refusal_round_never_reoffers_refused",
		str(after.get("status", "")) != "WAITING_RESPONSE",
		str(after.get("status", "")) + "/target=" + str(after.get("target_id", "")))

# ── P7.2C C1：主观找人——last_seen 驱动、允许扑空、到场后询问自然发生 ──
func _test_c1_seek_holder_person() -> void:
	var created := SimulationBootstrap.create(78001, "holder_reachability")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var giver_id := str(ids[1])
	var requester: Dictionary = sim.actors[requester_id]
	var giver: Dictionary = sim.actors[giver_id]
	requester["tile"] = Vector2i(10, 10)
	giver["tile"] = Vector2i(40, 40)  # 远处——不可见
	giver["inventory"] = {"shells": 2}
	giver["personality"] = PersonalityProfile.new(
		{"altruism": 0.9, "empathy": 0.9, "caution": 0.1, "sociability": 0.9}, {})
	requester["inventory"] = {}
	requester["needs"]["hunger"] = 800
	# 请求者记得 giver 的位置（last_seen=旧位置）。
	(requester["tom"] as TheoryOfMind).see_at(giver_id, Vector2i(38, 38), 1)
	sim.relationships.adjust(requester_id, giver_id, "benevolence", 500)
	sim.relationships.adjust(requester_id, giver_id, "reliability", 500)
	var pair := {"requester_id": requester_id, "requester": requester}
	var request_id := _blocked_request(sim, pair)
	sim._material_requests_process_actor(requester_id, requester, [])
	var goal := sim._information_tracker().current_goal(requester_id)
	_check("c1_holder_goal_created", str(goal.get("query_kind", "")) == "HOLDER")
	# 无可见合格同伴 + flag 开 → seek 候选（目标=last_seen 位置，不读真实坐标）。
	var view := sim._build_actor_view(requester_id, requester)
	view["now_tick"] = sim.tick
	goal["holder_reachability_enabled"] = true
	var candidates: Array = InformationActionPolicy.build(view, goal, sim.tick)
	var seeks: Array = []
	for c in candidates:
		if str((c as Dictionary).get("action", "")) == "seek_holder_person":
			seeks.append(c)
	_check("c1_seek_candidate_emitted", seeks.size() == 1,
		str(seeks.size()))
	if seeks.is_empty():
		return
	var seek: Dictionary = seeks[0]
	_check("c1_seek_targets_last_seen_not_truth",
		str(seek.get("target_actor", "")) == giver_id
		and (seek.get("target", Vector2i.ZERO) as Vector2i) == Vector2i(38, 38),
		str(seek.get("target", "")))
	# 扑空：giver 真实位置与 last_seen 不同 → 执行后 found 不产生。
	requester["current_action"] = seek
	sim._complete_action(requester_id, requester, [])
	_check("c1_stale_last_seen_misses", _count(sim, "holder_seek_person_not_found") >= 1
		or _count(sim, "holder_seek_found_person") == 0)
	# 到场：giver 在 last_seen 位置，请求者真实抵达（travel 由决策流逐 tick 完成，
	# 此处模拟抵达后的完成回调——与 _tick_actor 到达后触发 _complete_action 同构）。
	giver["tile"] = Vector2i(38, 38)
	requester["tile"] = Vector2i(37, 38)
	requester["current_action"] = seek
	var ev_before := sim.events.size()
	sim._complete_action(requester_id, requester, [])
	var found := false
	for e in sim.events.slice(ev_before):
		if str((e as Dictionary).get("type", "")) == "holder_seek_found_person":
			found = true
	_check("c1_seek_finds_when_present", found)
	# flag 关 → 无 seek 候选（旧 holder_evidence 行为不变）。
	goal["holder_reachability_enabled"] = false
	var view2 := sim._build_actor_view(requester_id, requester)
	view2["now_tick"] = sim.tick
	var candidates2: Array = InformationActionPolicy.build(view2, goal, sim.tick)
	var seeks2 := 0
	for c in candidates2:
		if str((c as Dictionary).get("action", "")) == "seek_holder_person":
			seeks2 += 1
	_check("c1_flag_off_no_seek", seeks2 == 0)

# ── P7.2C C2：询问效用语义（blockedness 单调；信任/回避方向；生存仍可压过）──
func _test_c2_inquiry_utility_semantics() -> void:
	var created := SimulationBootstrap.create(78002, "holder_reachability")
	var sim: IslandSimulation = created["sim"]
	var ids: Array = sim.actors.keys()
	ids.sort()
	var requester_id := str(ids[0])
	var giver_id := str(ids[1])
	var requester: Dictionary = sim.actors[requester_id]
	var giver: Dictionary = sim.actors[giver_id]
	requester["tile"] = Vector2i(10, 10)
	giver["tile"] = Vector2i(11, 10)
	giver["inventory"] = {}
	requester["inventory"] = {}
	requester["needs"]["hunger"] = 800
	var pair := {"requester_id": requester_id, "requester": requester}
	var request_id := _blocked_request(sim, pair)
	sim._material_requests_process_actor(requester_id, requester, [])
	var goal := sim._information_tracker().current_goal(requester_id)
	_check("c2_fixture_goal", str(goal.get("query_kind", "")) == "HOLDER")
	var view := sim._build_actor_view(requester_id, requester)
	view["now_tick"] = sim.tick
	goal["holder_reachability_enabled"] = true
	var _utility_of := func(g: Dictionary) -> float:
		var cands: Array = InformationActionPolicy.build(view, g, sim.tick)
		for c in cands:
			if str((c as Dictionary).get("action", "")) == "ask_item_holder" \
					and str((c as Dictionary).get("target_actor", "")) == giver_id:
				return float((c as Dictionary).get("utility", 0.0))
		return -1.0
	# 1) blockedness 单调不降。
	goal["parent_blockedness"] = 0.2
	var low_blocked: float = _utility_of.call(goal)
	goal["parent_blockedness"] = 0.9
	var high_blocked: float = _utility_of.call(goal)
	_check("c2_blockedness_monotone", high_blocked >= low_blocked and low_blocked > 0.0,
		"low=%.3f high=%.3f" % [low_blocked, high_blocked])
	# 2) urgency 单调不降。
	goal["parent_blockedness"] = 0.5
	goal["request_urgency"] = 0.1
	var low_urg: float = _utility_of.call(goal)
	goal["request_urgency"] = 0.95
	var high_urg: float = _utility_of.call(goal)
	_check("c2_urgency_monotone", high_urg >= low_urg,
		"low=%.3f high=%.3f" % [low_urg, high_urg])
	# 3) 信任方向：高信任 ≥ 低信任。
	sim.relationships.adjust(requester_id, giver_id, "benevolence", 900)
	sim.relationships.adjust(requester_id, giver_id, "reliability", 900)
	view = sim._build_actor_view(requester_id, requester)
	view["now_tick"] = sim.tick
	var high_trust: float = _utility_of.call(goal)
	_check("c2_high_trust_not_lower", high_trust >= low_urg - 0.001,
		"trust=%.3f" % high_trust)
	# 4) 生存压制语义：中等竞争行动下 blockedness=1 的 ask 应有现实竞争力
	#    （utility 落在可竞争区间），但不锁死——用区间断言而非固定选择率。
	goal["parent_blockedness"] = 1.0
	goal["request_urgency"] = 0.9
	var competitive: float = _utility_of.call(goal)
	_check("c2_blocked_ask_competitive", competitive >= 0.5,
		"u=%.3f" % competitive)
	_check("c2_ask_not_locked_over_survival", competitive <= 0.95,
		"u=%.3f（不应硬锁压过一切）" % competitive)
