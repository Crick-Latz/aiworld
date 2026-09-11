class_name DecisionEngine
extends RefCounted
## 决策引擎 v3（P1.5）：
##   1. ConsiderationSet（有限理性：真实的人不会列举世界所有动作——
##      由效用筛出"此刻想到的事"，其余根本没被考虑）
##   2. DO_NOTHING 是正常行为（反 hyper-activity：人不是总想干点什么）
##   3. Softmax 受限随机选择（τ 由人格动力控制）
##   4. Intention persistence（承诺强度由 PersonalityDynamics 决定，不再是固定 85%）
##   5. DecisionTrace v3：感知/解释/考虑集/忽略集/预测 全程留痕——
##      观察者能回答"他为什么这么做"甚至"他哪里判断错了"

const CONSIDERATION_SIZE := 7  # 此刻心里能装下的选项数

static func decide(actor: Dictionary, world: Dictionary, rng: RandomNumberGenerator, agency: Dictionary = {}) -> Dictionary:
	actor.erase("_execution_receipt")
	var intentions: IntentionManager = actor.get("intentions", null)
	var p: PersonalityProfile = actor.get("personality", null)
	var tick: int = world.get("tick", 0)
	var dyn := PersonalityDynamics.dynamics(p, actor.get("sensitivities", {}), actor.get("norms", {}))

	# 全量候选 → 考虑集（此刻"想到的"）
	var all_actions: Array = ActionRegistry.get_available_actions(actor, world)
	all_actions.append(_do_nothing())

	# P6.2 AgencyActionBridge：grounding 必须基于本次决策的合法候选全表（纯函数，无 RNG）
	var agency_ground := {"grounded_candidates": [], "rejected_proposals": [], "future_subgoals": []}
	var agency_mode := str(agency.get("mode", "OFF"))
	if agency_mode != "OFF" and not (agency.get("proposals", []) as Array).is_empty():
		agency_ground = AgencyActionBridge.ground(agency.get("proposals", []), all_actions, tick, str(actor.get("id", "")))

	# P6.3B-1 §五：当前执行步骤的合法候选（PlanStepActionAdapter 匹配）。
	# 默认仍保持 Registry utility 原值；P6.3B-4 的独立开关开启后，PlanStepValueModel
	# 才允许根问题的因果价值有限度地补足当前步骤 utility。候选身份/target/duration/
	# recipe_id 不变，也仍需经过原 Consideration Set + softmax。
	var exec_salient: Array = []
	var exec_value_rows: Array = []
	var exec_match: Dictionary = {}
	var exec_step_info: Dictionary = agency.get("execution_step", {})
	var causal_step_value_enabled := bool(agency.get("causal_step_value_enabled", false))
	if agency_mode == "LIVE_BRIDGE" and typeof(exec_step_info) == TYPE_DICTIONARY and not exec_step_info.is_empty():
		exec_match = PlanStepActionAdapter.match_candidates(
			exec_step_info.get("step", {}), all_actions, agency.get("ctx", {}),
			agency.get("catalog", null), agency.get("items", null))
		for c in exec_match.get("candidates", []):
			var key := AgencyActionBridge.candidate_key(c)
			var original_utility := float(c.get("utility", 0.0))
			var effective_utility := original_utility
			if causal_step_value_enabled:
				var valuation := PlanStepValueModel.assess(actor, exec_step_info, c)
				effective_utility = float(valuation.get("effective_utility", original_utility))
				var value_row := valuation.duplicate(true)
				value_row["candidate_key"] = key
				exec_value_rows.append(value_row)
				if not is_equal_approx(effective_utility, original_utility):
					var effective_candidate: Dictionary = c.duplicate(true)
					effective_candidate["utility"] = effective_utility
					_replace_candidate_by_key(all_actions, key, effective_candidate)
			exec_salient.append({
				"candidate_key": key,
				"original_utility": original_utility,
				"effective_utility": effective_utility,
				"plan_id": str(exec_step_info.get("plan_id", "")),
				"problem_id": str(exec_step_info.get("root_goal", "")),
				"execution": true,
			})

	# P7.0：当前信息子目标的合法搜索/询问候选属于 agency-salient。
	# 它们仍沿用 ActionRegistry 的效用并经过同一 softmax，不获得强制执行权。
	var information_goal: Dictionary = agency.get("information_goal", {})
	var information_salient: Array = []
	if agency_mode == "LIVE_BRIDGE" and not information_goal.is_empty():
		var goal_id := str(information_goal.get("goal_id", ""))
		for candidate in all_actions:
			if str(candidate.get("information_goal_id", "")) != goal_id:
				continue
			information_salient.append({
				"candidate_key": AgencyActionBridge.candidate_key(candidate),
				"original_utility": float(candidate.get("utility", 0.0)),
				"effective_utility": float(candidate.get("utility", 0.0)),
				"plan_id": str(information_goal.get("parent_plan_id", "")),
				"problem_id": str(information_goal.get("root_goal", "")),
				"information": true,
			})

	# P7.1B：材料请求候选沿用同一个考虑集和 softmax，只获得显著性，不获得强制效用。
	var material_state: Dictionary = agency.get("material_request", {})
	var material_salient: Array = []
	if agency_mode == "LIVE_BRIDGE" and not material_state.is_empty():
		var material_candidate: Dictionary = material_state.get("candidate", {})
		if not material_candidate.is_empty():
			material_salient.append({"candidate_key": AgencyActionBridge.candidate_key(material_candidate),
				"original_utility": float(material_candidate.get("utility", 0.0)),
				"effective_utility": float(material_candidate.get("utility", 0.0)),
				"plan_id": str((material_state.get("request", {}) as Dictionary).get("parent_plan_id", "")),
				"problem_id": str((material_state.get("request", {}) as Dictionary).get("root_goal", "")),
				"material_request": true})

	# 意图坚持 vs 机会成本：承诺强度决定"懒得重想"的概率，
	# 但当前最优效用远超在执行意图（紧迫差距）时强制重估——
	# 饿到极限的人不会因为"决定过要休息"就饿死在存粮上。
	var continue_p := 0.5 + float(dyn["commitment_strength"]) * 0.45  # 0.72..0.95
	var continuation := {}
	if intentions != null and intentions.has_intention():
		continuation = intentions.matching_candidate(all_actions)
		if continuation.is_empty():
			# 动作已结束后的新决策边界：旧承诺不能绕过当前合法性。
			intentions.clear_intention()
	if intentions != null and intentions.has_intention():
		var cur_u := float(continuation.get("utility", 0.0))
		var best_u := 0.0
		for a in all_actions:
			best_u = maxf(best_u, float(a.get("utility", 0.0)))
		var urgency_gap := best_u - cur_u
		if urgency_gap <= 0.35 and rng.randf() > 1.0 - continue_p:
			var continued := intentions.continue_action(continuation)
			_write_execution_receipt(actor, agency, exec_match, continued, "INTENTION_CONTINUE")
			return continued
	if all_actions.is_empty():
		return {"action": "wait", "target": null, "utility": 0.0, "desc": "什么也不做"}

	var considered: Array = []
	var ignored: Array = []
	# 显著性规则：值得想的事（效用达标）全部进入考虑；长尾弱选项被忽略。
	# 这模拟"此刻想到什么"而非硬截断——中效用的社交行为不会被系统性挤出。
	var sorted := all_actions.duplicate()
	sorted.sort_custom(func(a, b): return float(a.get("utility", 0.0)) > float(b.get("utility", 0.0)))
	for a in sorted:
		if considered.size() < CONSIDERATION_SIZE or float(a.get("utility", 0.0)) >= 0.3:
			considered.append(a)
		else:
			ignored.append(a)

	# P6.2 §4（唯一允许的行为影响）：LIVE_BRIDGE 下，agency-salient 候选保证进入 Consideration Set。
	# 不改 utility、不保证选中；挤位只挤出最低效用的非 salient 非 do_nothing 候选；
	# 若已在 considered → 完全不动（候选数/顺序/RNG 与 OFF 逐位一致）。
	# P6.2-R1 §3：显式记录每个 grounded 候选处置（ALREADY_CONSIDERED/SWAPPED_IN/NOT_INSERTED）
	# 与 swapped_in/evicted key——首次分歧归因的数据来源。
	var agency_already_count := 0
	var agency_swapped_keys: Array = []
	var agency_evicted_keys: Array = []
	var agency_candidate_status: Array = []
	# P6.3B-1：salient 池 = grounded 候选 + 当前执行步骤候选（同一挤位/驱逐规则）
	var salient_pool: Array = (agency_ground["grounded_candidates"] as Array).duplicate()
	salient_pool.append_array(exec_salient)
	salient_pool.append_array(information_salient)
	salient_pool.append_array(material_salient)
	if agency_mode == "LIVE_BRIDGE" and not salient_pool.is_empty():
		var salient := {}
		for gc in salient_pool:
			salient[str(gc["candidate_key"])] = gc
		var wanted: Array = salient_pool.duplicate()
		wanted.sort_custom(func(a, b):
			if float(a["original_utility"]) != float(b["original_utility"]):
				return float(a["original_utility"]) > float(b["original_utility"])
			return str(a["candidate_key"]) < str(b["candidate_key"]))
		for gc in wanted:
			var key := str(gc["candidate_key"])
			var already := false
			for c in considered:
				if AgencyActionBridge.candidate_key(c) == key:
					already = true
					break
			if already:
				agency_already_count += 1
				agency_candidate_status.append({"candidate_key": key, "status": "ALREADY_CONSIDERED"})
				continue
			var salient_action := {}
			for c in ignored:
				if AgencyActionBridge.candidate_key(c) == key:
					salient_action = c
					break
			if salient_action.is_empty():
				agency_candidate_status.append({"candidate_key": key, "status": "NOT_INSERTED", "reason": "NOT_IN_ALL_ACTIONS"})
				continue
			if considered.size() >= CONSIDERATION_SIZE:
				var victim_idx := -1
				var victim_u := 1e9
				for ci in range(considered.size()):
					var ca: Dictionary = considered[ci]
					if str(ca.get("action", "")) == "do_nothing":
						continue
					if salient.has(AgencyActionBridge.candidate_key(ca)):
						continue
					var cu := float(ca.get("utility", 0.0))
					if cu < victim_u:
						victim_u = cu
						victim_idx = ci
				if victim_idx < 0:
					agency_candidate_status.append({"candidate_key": key, "status": "NOT_INSERTED", "reason": "NO_EVICTABLE_VICTIM"})
					continue
				var evicted_key := AgencyActionBridge.candidate_key(considered[victim_idx])
				ignored.append(considered[victim_idx])
				considered.remove_at(victim_idx)
				agency_evicted_keys.append(evicted_key)
			considered.append(salient_action)
			ignored.erase(salient_action)
			agency_swapped_keys.append(key)
			var ev_note := ""
			if agency_evicted_keys.size() > 0:
				ev_note = str(agency_evicted_keys[agency_evicted_keys.size() - 1])
			agency_candidate_status.append({"candidate_key": key, "status": "SWAPPED_IN", "evicted": ev_note})	# Softmax 选择（受限理性）
	var tau := _compute_tau(p, actor, dyn)
	var chosen: Dictionary = _softmax_select(considered, tau, rng)

	# DecisionTrace v3
	var trace := {
		"actor_id": str(actor.get("id", "")),
		"tick": tick,
		"selected": str(chosen.get("action", "")),
		"top_candidates": {},
		"considered_actions": [],
		"ignored_actions": [],
		"perceived_state": _perceived_state(actor),
		"reason": _generate_reason(chosen, actor, world),
	}
	# P6.2-R2：considered 候选 key（双侧证据——观察元数据，不进 digest）
	trace["considered_keys"] = considered.map(func(c): return AgencyActionBridge.candidate_key(c))
	for a in considered:
		trace["top_candidates"][str(a["action"])] = float(a["utility"])
		trace["considered_actions"].append(str(a["action"]))
	for a in ignored:
		trace["ignored_actions"].append(str(a["action"]))
	# 最近一次认知转移的解释（"他对这件事的理解"进入决策留痕）
	var last_transition: Dictionary = actor.get("last_transition", {})
	if not last_transition.is_empty():
		var interp: Dictionary = last_transition.get("interpretation", {})
		if not interp.is_empty():
			trace["candidate_interpretations"] = interp.get("candidates", [])
			trace["dominant_interpretation"] = interp.get("dominant", "")
	# 社会行动的预测（"他预期会发生什么"）
	if str(chosen.get("action", "")) == "request_share" and chosen.has("target_actor"):
		trace["predicted_outcomes"] = ActionForecaster.forecast_request(actor, str(chosen["target_actor"]))
	# DecisionTrace v4（P1.6 #33）：不确定/认识价值/声明/证据全程留痕
	trace["uncertainties"] = (actor.get("open_questions", []) as Array).duplicate(true)
	trace["epistemic_goals"] = []
	for a2 in considered:
		if ["ask_reason", "observe_person", "ask_third_party"].has(str(a2.get("action", ""))):
			trace["epistemic_goals"].append({"action": str(a2.get("action", "")), "expected_information_gain": float(a2.get("utility", 0.0))})
	trace["claims_received_count"] = (actor.get("claims_received", []) as Array).size()
	# P6.2 §5：AgencyTrace 升级——只记录真实进入该次决策的数据（SHADOW/LIVE 才有）
	if agency_mode != "OFF":
		var chosen_key: String = AgencyActionBridge.candidate_key(chosen)
		var agency_selected = null
		for gc in agency_ground["grounded_candidates"]:
			if str(gc["candidate_key"]) == chosen_key:
				agency_selected = {
					"candidate_key": chosen_key,
					"plan_ids": [str(gc["plan_id"])],
					"problem_ids": [str(gc["problem_id"])],
					"knowledge_refs": gc["knowledge_refs"],
					"belief_refs": gc["belief_refs"],
				}
		trace["agency_mode"] = agency_mode
		trace["agency_context_hash"] = str(agency.get("context_hash", ""))
		trace["agency_activated_problems"] = (agency.get("problems", []) as Array).duplicate()
		trace["agency_grounded_candidates"] = agency_ground["grounded_candidates"]
		trace["agency_rejected_proposals"] = agency_ground["rejected_proposals"]
		trace["agency_future_subgoals"] = agency_ground["future_subgoals"]
		trace["agency_selected"] = agency_selected
		trace["agency_grounded_already_considered_count"] = agency_already_count
		trace["agency_swapped_in_keys"] = agency_swapped_keys
		trace["agency_evicted_keys"] = agency_evicted_keys
		trace["agency_candidate_status"] = agency_candidate_status
		if not information_goal.is_empty():
			var info_keys: Array = information_salient.map(func(row): return str(row.get("candidate_key", "")))
			trace["agency_information"] = {
				"goal": information_goal.duplicate(true),
				"candidate_keys": info_keys,
				"selected": info_keys.has(chosen_key),
				"selected_candidate_key": chosen_key if info_keys.has(chosen_key) else "",
			}
		# P6.3B-1 §八：执行步骤匹配留痕（selected=false 时带 blocker_reason）。
		# decision_tick 显式携带本次决策的 sim tick——新鲜性校验用（trace["tick"] 来自
		# world["tick"]，在 step 末更新，决策时会滞后一位）
		if not exec_step_info.is_empty():
			var chosen_key2 := AgencyActionBridge.candidate_key(chosen)
			var exec_selected := false
			for e2 in exec_salient:
				if str(e2["candidate_key"]) == chosen_key2:
					exec_selected = true
			trace["agency_execution"] = {
				"run_id": str(exec_step_info.get("run_id", "")),
				"plan_id": str(exec_step_info.get("plan_id", "")),
				"step_id": str((exec_step_info.get("step", {}) as Dictionary).get("step_id", "")),
				"candidate_keys": exec_salient.map(func(e3): return str(e3["candidate_key"])),
				"selected": exec_selected,
				"candidate_key": chosen_key2 if exec_selected else "",
				"blocker_reason": str(exec_match.get("blocker_reason", "")),
				"skip": bool(exec_match.get("skip", false)),
				"decision_tick": int(agency.get("decision_tick", tick)),
				"utility_mode": "CAUSAL_STEP_VALUE" if causal_step_value_enabled else "REGISTRY_ONLY",
				"candidate_values": exec_value_rows.duplicate(true),
			}
	var lt4: Dictionary = actor.get("last_transition", {})
	trace["evidence_for"] = lt4.get("belief_updates", {})
	trace["belief_change"] = lt4.get("relationship_delta", {})
	actor["last_decision_trace"] = trace

	if intentions != null:
		intentions.set_intention(chosen, tick)

	_write_execution_receipt(actor, agency, exec_match, chosen, "SOFTMAX")
	return chosen

## Physical-action receipt, not a new cognitive deliberation trace. No RNG or scoring.
static func _write_execution_receipt(actor: Dictionary, agency: Dictionary, matched: Dictionary,
		chosen: Dictionary, selection_mode: String) -> void:
	var step_info: Dictionary = agency.get("execution_step", {})
	if agency.get("mode", "OFF") != "LIVE_BRIDGE" or step_info.is_empty(): return
	var selected := false
	var key := AgencyActionBridge.candidate_key(chosen)
	for candidate in matched.get("candidates", []):
		if AgencyActionBridge.candidate_key(candidate) == key: selected = true
	actor["_execution_receipt"] = {
		"actor_id": str(actor.get("id", "")), "decision_tick": agency.get("decision_tick", -1),
		"run_id": step_info.get("run_id", ""), "step_id": step_info.get("step", {}).get("step_id", ""),
		"selected": selected, "candidate_key": key if selected else "",
		"chosen_key": key, "selection_mode": selection_mode,
		"blocker_reason": matched.get("blocker_reason", "")}

static func _replace_candidate_by_key(actions: Array, key: String, replacement: Dictionary) -> void:
	for i in range(actions.size()):
		if AgencyActionBridge.candidate_key(actions[i]) == key:
			actions[i] = replacement
			return

## 不行动是合法行为：观察、发呆、任由事情发生
static func _do_nothing() -> Dictionary:
	return {"action": "do_nothing", "target": null, "utility": 0.06, "desc": "什么也不做", "duration": 1}

## 感知状态快照（他以为的世界，非真实世界）
static func _perceived_state(actor: Dictionary) -> Dictionary:
	var p: PersonalityProfile = actor.get("personality", null)
	var out := {
		"hunger": float(actor.get("needs", {}).get("hunger", 0)) / 1000.0,
		"emotions": {},
	}
	if p != null:
		for key in ["anger", "fear", "sadness", "guilt"]:
			var v: float = p.emotions.get(key, 0.0)
			if absf(v) > 0.05:
				out["emotions"][key] = v
	var tom: TheoryOfMind = actor.get("tom", null)
	if tom != null:
		out["tom"] = tom.snapshot()
	return out

## τ 计算：谨慎/承诺高 → τ 低（行为稳定）；冲动/疲劳/情绪混乱 → τ 高
static func _compute_tau(p: PersonalityProfile, actor: Dictionary, dyn: Dictionary) -> float:
	var base := 0.15
	base -= float(p.traits.get("caution", 0.5)) * 0.05
	base -= float(dyn.get("commitment_strength", 0.7)) * 0.03
	var energy: float = float(actor.get("needs", {}).get("energy", 1000)) / 1000.0
	if energy < 0.3:
		base += (0.3 - energy) * 0.3
	base += float(p.emotions.get("fear", 0.0)) * 0.1 + float(p.emotions.get("anger", 0.0)) * 0.1
	return maxf(base, 0.05)

## Softmax 选择：不是永远选效用最高的，是按概率选
static func _softmax_select(actions: Array, tau: float, rng: RandomNumberGenerator) -> Dictionary:
	var utils: Array = []
	for a in actions:
		utils.append(float(a.get("utility", 0.0)))
	var max_u := 0.0
	for u in utils:
		max_u = maxf(max_u, u)
	var probs: Array = []
	var sum := 0.0
	for u in utils:
		var prob := exp((u - max_u) / tau)
		probs.append(prob)
		sum += prob
	for i in probs.size():
		probs[i] /= sum
	var roll := rng.randf()
	var cumul := 0.0
	for i in probs.size():
		cumul += float(probs[i])
		if roll <= cumul:
			return actions[i]
	return actions[actions.size() - 1]

## 生成人类可读的决策原因
static func _generate_reason(action: Dictionary, actor: Dictionary, world: Dictionary) -> String:
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return "未知原因"
	var action_name := str(action.get("action", ""))
	var needs: Dictionary = actor.get("needs", {})
	var emotions: Dictionary = p.emotions

	var reasons: Array = []
	var hunger: float = float(needs.get("hunger", 0)) / 1000.0
	if hunger > 0.6:
		reasons.append("非常饥饿")
	var energy: float = float(needs.get("energy", 1000)) / 1000.0
	if energy < 0.3:
		reasons.append("很疲惫")
	if emotions.get("fear", 0.0) > 0.5:
		reasons.append("感到恐惧")
	if emotions.get("anger", 0.0) > 0.5:
		reasons.append("正在愤怒")
	# 认知层的解释进入原因（"因为我觉得他自私"这类理由）
	var lt: Dictionary = actor.get("last_transition", {})
	if not lt.is_empty():
		var interp: Dictionary = lt.get("interpretation", {})
		if not interp.is_empty() and str(lt.get("counterpart", "")) != "":
			var dom := str(interp.get("dominant", ""))
			if dom != "":
				var labels := {"selfish": "觉得他自私", "also_starving": "知道他也没粮", "distrusts_me": "觉得他不信任我",
					"generous": "觉得他慷慨", "genuine_bond": "把他当同伴", "expects_return": "觉得他想要回报",
					"saving_reserve": "觉得他在存粮", "dislikes_me": "觉得他讨厌我", "pities_me": "觉得他可怜我"}
				if labels.has(dom):
					reasons.append(labels[dom])
	if reasons.is_empty():
		reasons.append("基于当前需求和个人倾向")
	return str(action.get("desc", action_name)) + "（" + "、".join(reasons) + "）"
