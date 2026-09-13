class_name PlanExecutionTracker
extends RefCounted
## P6.3B-1 §四/§六/§七/§八 + R1 PlanExecutionTracker——每 actor 至多一个活动计划 run。
## 铁律：不直接加库存、不调 _do_craft、不推进世界——只观察与记录；
## run_id = actor_id#单调序号（确定性）；完成回调核对行动身份（run_id+attempt_id），
## 旧 run/旧尝试/重复通知/他人通知一律不推进。
##
## ── run 状态机（R1 §三）──
## ACTIVE    ──其他行动被选──→ SUSPENDED（保留 run/步骤/pending 清空）
## SUSPENDED ──本步骤候选再次被选──→ ACTIVE（同一 run_id/root_goal；先转态再挂 pending）
## ACTIVE/SUSPENDED ──连续错过执行机会超限──→ CANCELLED(NO_PROGRESS_TIMEOUT) + 计划进冷却
## ACTIVE/SUSPENDED ──计划从 proposals 消失──→ CANCELLED(PLAN_DISAPPEARED)
## ACTIVE    ──决策时前提类 blocker──→ BLOCKED(reason) + 计划进冷却
## ACTIVE    ──MAIN 成功事件──→ COMPLETED(GOAL_ACTION_SUCCEEDED)
## 终态 = CANCELLED / BLOCKED / COMPLETED：run 留在 runs 中作记录；
##   之后每次决策都尝试 _select_new_run（冷却挡住刚取消/刚阻断的同计划；
##   COMPLETED 不冷却——新的需求周期可再次执行同一计划）。

const RUN_STATES := ["ACTIVE", "SUSPENDED", "BLOCKED", "COMPLETED", "CANCELLED"]
## 这些 blocker 表示步骤前提已失效 → run BLOCKED（其余只记录，交超时裁决）
const PREMISE_BLOCKERS := ["MATERIALS_MISSING", "MISSING_CAPABILITY_FOR_CRAFT",
	"RECIPE_NOT_KNOWN", "UNKNOWN_RECIPE", "SUBGOAL_INERT", "UNKNOWN_KIND",
	"MALFORMED_STEP", "NO_ITEM_ACTION_MAPPING", "CAPABILITY_MISSING"]

var no_progress_timeout := 16  # missed decision opportunities; also cooldown ticks after cancellation
var runs := {}          # actor_id -> run state（每 actor 只留最新 run；历史在 traces）
var traces: Array = []  # 执行 trace（§八 schema）
var _run_seq := {}      # actor_id -> 已创建 run 数
var _cooldown := {}     # actor_id -> {plan_id: 可重选 tick}（§七 避免超时/阻断后同计划立即重选=忙等）

## 决策前调用：有效 run 延续 / 终态重选 → 自动推进已满足步骤。
## SUSPENDED 与 ACTIVE 同样提供当前步骤（暂停≠退出考虑集——真实恢复入口）。
## 返回 {run_id, plan_id, root_goal, step, valuation_context}（无可执行步骤时为空）。
func prepare_decision(actor_id: String, proposals: Array, ctx: Dictionary, tick: int, adoption: Dictionary = {}) -> Dictionary:
	var run: Dictionary = runs.get(actor_id, {})
	var prefer_goal := ""
	# 有效 run = ACTIVE/SUSPENDED；终态（CANCELLED/BLOCKED/COMPLETED）每次决策都尝试重选
	var valid := not run.is_empty() and str(run.get("state", "")) in ["ACTIVE", "SUSPENDED"]
	var subjective := str(adoption.get("mode", "")) == "SUBJECTIVE"
	var selected_id := str(adoption.get("selected_plan_id", ""))
	if subjective and valid and selected_id != str(run.get("plan_id", "")):
		_transition(run, tick, "CANCELLED", "COMMITMENT_RECONSIDERED", run.get("current_step_id", ""), "")
		_set_cooldown(actor_id, str(run.get("plan_id", "")), tick)
		valid = false
	if valid and not _plan_still_proposed(run, proposals):
		prefer_goal = str(run.get("root_goal", ""))
		_transition(run, tick, "CANCELLED", "PLAN_DISAPPEARED", run.get("current_step_id", ""), "")
		valid = false
	if not valid:
		if not run.is_empty():
			prefer_goal = str(run.get("root_goal", ""))
		if subjective and selected_id == "":
			return {}
		run = _select_new_run(actor_id, proposals, ctx, tick, prefer_goal, selected_id if subjective else "")
		if run.is_empty():
			return {}
	if subjective:
		run["commitment"] = adoption.duplicate(true)
	# §六 决策前重查前提 + 自动推进（USE 能力在场跳过；ACQUIRE 库存达标跳过）
	var step: Dictionary = _advance_satisfied(run, ctx, tick)
	if str(run.get("state", "")) not in ["ACTIVE", "SUSPENDED"]:
		return {}
	if step.is_empty():
		return {}
	return {
		"run_id": str(run["run_id"]), "plan_id": str(run["plan_id"]),
		"root_goal": str(run["root_goal"]), "step": step,
		"valuation_context": _valuation_context(run),
	}

## 决策后调用：记录选中（或未选中）的步骤候选——"被选中"不算完成，只挂 pending。
## 返回行动身份 {run_id, step_id, attempt_id, candidate_key}（未选中返回 {}）——
## 行动完成时必须带回同一身份才能推进（R1 §四）。
func on_decision(actor_id: String, decision: Dictionary, exec_info: Dictionary, tick: int) -> Dictionary:
	var run: Dictionary = runs.get(actor_id, {})
	if run.is_empty() or str(run.get("state", "")) not in ["ACTIVE", "SUSPENDED"]:
		return {}
	if exec_info.is_empty():
		return {}  # 意图坚持早退路径——pending 保持原状（同一行动尝试继续）
	if typeof(exec_info.get("run_id")) != TYPE_STRING or exec_info["run_id"] != run["run_id"]:
		return {}  # Same step in another run is not this decision.
	var step_id := str(exec_info.get("step_id", ""))
	if step_id != str(run.get("current_step_id", "")):
		return {}
	var ckey := str(exec_info.get("candidate_key", ""))
	if bool(exec_info.get("selected", false)):
		if ckey == "" or ckey != AgencyActionBridge.candidate_key(decision):
			return {}
		var was := str(run.get("state", ""))
		var attempt := int(run.get("attempt_seq", 0)) + 1
		run["attempt_seq"] = attempt
		run["missed_opportunities"] = 0
		if was == "SUSPENDED":
			# R1 §二：先转态（_transition 会清 pending），再写入本次身份——顺序不可反
			_transition(run, tick, "ACTIVE", "RUN_RESUMED", step_id, ckey)
		else:
			_note(run, tick, "STEP_CANDIDATE_SELECTED", step_id, ckey)
		run["pending"] = {
			"step_id": step_id,
			"candidate_key": ckey,
			"action_name": str(decision.get("action", "")),
			"tick": tick,
			"attempt_id": attempt,
		}
		run["selected_candidate_key"] = ckey
		return {"actor_id": actor_id, "run_id": str(run["run_id"]), "step_id": step_id,
			"attempt_id": attempt, "candidate_key": ckey}
	run["pending"] = {}
	run["selected_candidate_key"] = ""
	var reason := str(exec_info.get("blocker_reason", ""))
	if reason != "":
		_note(run, tick, "STEP_NO_CANDIDATE", step_id, "", "", reason)
		# §六 前提失效（材料被消耗/配方未知/子目标惰性）→ 不得沿用旧 READY
		if PREMISE_BLOCKERS.has(reason):
			_transition(run, tick, "BLOCKED", reason, step_id, "")
			_set_cooldown(actor_id, str(run.get("plan_id", "")), tick)
	else:
		# Count actual decision opportunities, not elapsed world ticks. A long
		# unrelated action can span many ticks without giving this plan a chance.
		var missed := int(run.get("missed_opportunities", 0)) + 1
		run["missed_opportunities"] = missed
		if missed > no_progress_timeout:
			_transition(run, tick, "CANCELLED", "NO_PROGRESS_TIMEOUT", step_id, "")
			_set_cooldown(actor_id, str(run.get("plan_id", "")), tick)
		elif str(run.get("state", "")) == "ACTIVE":
			_transition(run, tick, "SUSPENDED", "OTHER_ACTION_CHOSEN", step_id,
				AgencyActionBridge.candidate_key(decision))
		else:
			_note(run, tick, "STEP_CANDIDATE_NOT_SELECTED", step_id,
				AgencyActionBridge.candidate_key(decision), "missed_opportunities=%d" % missed)
	return {}

## 行动完成回调（R1 §四）：核对行动身份（actor 内的 in-flight 身份由 sim 在行动启动时
## 从 on_decision 返回值存下、完成时原样带回）——run_id/attempt_id/step_id/candidate_key
## 全部一致才继续；旧 run、旧尝试、重复通知、他人通知一律拒绝。相同动作+相同地点+相同
## step_id 不等于同一次行动。
func on_action_complete(actor_id: String, action: Dictionary, event_segment: Array,
		inventory: Dictionary, tick: int, identity: Dictionary = {}) -> Dictionary:
	var run: Dictionary = runs.get(actor_id, {})
	if run.is_empty() or str(run.get("state", "")) != "ACTIVE":
		return {}
	if identity.is_empty():
		return {}  # 无行动身份——常规行为，不属于任何步骤尝试
	for field in ["actor_id", "run_id", "step_id", "candidate_key"]:
		if typeof(identity.get(field)) != TYPE_STRING or identity[field] == "":
			return {}
	if identity["actor_id"] != actor_id or typeof(identity.get("attempt_id")) != TYPE_INT:
		return {}
	if str(identity.get("run_id", "")) != str(run.get("run_id", "")):
		return {}  # 旧 run 的完成——不推进新计划（M/碰撞）
	var pending: Dictionary = run.get("pending", {})
	if pending.is_empty():
		return {}  # 无在飞尝试（已推进/已中断）
	if int(identity.get("attempt_id", -1)) != int(pending.get("attempt_id", -2)):
		return {}  # 旧尝试/重复完成——只认最新一次选中
	var key := AgencyActionBridge.candidate_key(action)
	if key != str(pending.get("candidate_key", "")):
		return {}  # 完成的行动不是选中的那个候选
	var step_id := str(pending.get("step_id", ""))
	if identity["step_id"] != step_id or identity["candidate_key"] != key:
		return {}
	if step_id != str(run.get("current_step_id", "")):
		return {}  # 已推进过——重复通知幂等（K 门）
	var step: Dictionary = _step_by_id(run, step_id)
	if step.is_empty():
		return {}
	var refs := _event_refs(event_segment)
	# A completed attempt is consumed even when it did not satisfy the step.
	# Repeating an intention later starts a different physical action, not this attempt.
	run["pending"] = {}
	_note(run, tick, "STEP_ATTEMPT_FINISHED", step_id, key)
	match str(step.get("kind", "")):
		"ACQUIRE":
			return _complete_acquire(run, step, event_segment, inventory, tick, refs)
		"CRAFT":
			return _complete_craft(run, step, event_segment, tick, refs)
		"MAIN":
			return _complete_main(run, step, event_segment, tick, refs)
	return {}

## §六 ACQUIRE：库存实际数量 ≥ 基线+缺口（缺口≠最终库存阈值）。
## 需 3、基线 1、缺口 2：拥有 2 时仍未满足——拥有 3 才完成。
func _complete_acquire(run: Dictionary, step: Dictionary, event_segment: Array,
		inventory: Dictionary, tick: int, refs: Array) -> Dictionary:
	var item_id := str(step.get("item_id", ""))
	var required := int((run.get("baseline_items", {}) as Dictionary).get(item_id, 0)) + int(step.get("quantity", 0))
	var have := int(inventory.get(item_id, 0))
	if have >= required:
		_step_done(run, step, tick, refs)
		_advance(run, tick)
		return {"advanced": true, "item_id": item_id, "have": have, "required": required}
	_note(run, tick, "STEP_ATTEMPTED_NOT_SATISFIED", str(step.get("step_id", "")),
		str(run.get("selected_candidate_key", "")), "have=%d required=%d" % [have, required])
	return {"advanced": false, "item_id": item_id, "have": have, "required": required}

## §六 CRAFT：实际成功的 crafted 事件（recipe_id 匹配 + 事务产出证明）才完成。
func _complete_craft(run: Dictionary, step: Dictionary, event_segment: Array,
		tick: int, refs: Array) -> Dictionary:
	var rid := str(step.get("recipe_id", ""))
	var out_item := str(step.get("item_id", ""))
	for e in event_segment:
		var ed: Dictionary = e
		if str(ed.get("type", "")) != "crafted":
			continue
		if str(ed.get("actor_id", "")) != str(run.get("actor_id", "")):
			continue
		if str(ed.get("recipe_id", "")) != rid:
			continue
		var produced: Dictionary = ed.get("produced_items", {})
		if not produced.has(out_item) or int(produced[out_item]) <= 0:
			continue
		_step_done(run, step, tick, refs)
		_advance(run, tick)
		return {"advanced": true, "recipe_id": rid}
	_note(run, tick, "CRAFT_NOT_CONFIRMED", str(step.get("step_id", "")), str(run.get("selected_candidate_key", "")), rid)
	return {"advanced": false, "recipe_id": rid}

## §六 MAIN：实际行动完成且对应成功结果事件 → 计划 COMPLETED（仅被选中不算）。
func _complete_main(run: Dictionary, step: Dictionary, event_segment: Array,
		tick: int, refs: Array) -> Dictionary:
	var action_name := str(step.get("action_name", ""))
	var success := str(PlanStepActionAdapter.MAIN_SUCCESS_EVENTS.get(action_name, ""))
	if success == "":
		return {"advanced": false}
	for e in event_segment:
		var ed: Dictionary = e
		if str(ed.get("type", "")) == success and str(ed.get("actor_id", "")) == str(run.get("actor_id", "")):
			# P7.2：绑定承诺的履约步只认同一 commitment 的终态事件（身份不漂移）。
			var step_commitment := str(step.get("commitment_id", ""))
			if step_commitment != "" and str(ed.get("commitment_id", "")) != step_commitment:
				continue
			_step_done(run, step, tick, refs)
			run["completion_event_refs"] = (run.get("completion_event_refs", []) as Array) + refs
			_transition(run, tick, "COMPLETED", "GOAL_ACTION_SUCCEEDED", str(step.get("step_id", "")), "")
			return {"advanced": true, "plan_completed": true}
	_note(run, tick, "MAIN_NOT_SUCCEEDED", str(step.get("step_id", "")), str(run.get("selected_candidate_key", "")), action_name)
	return {"advanced": false}

## A successful material transfer grants one revalidation opportunity. It never
## restores the run directly and never bypasses a still-missing blocker.
func request_parent_revalidation(actor_id: String, plan_id: String, tick: int,
		transfer_event_id: String, parent_run_id: String, blocker_step_id: String) -> Dictionary:
	var run: Dictionary = runs.get(actor_id, {})
	if run.is_empty() or str(run.get("plan_id", "")) != plan_id:
		return {}
	if str(run.get("run_id", "")) != parent_run_id:
		return {}
	if str(run.get("current_step_id", "")) != blocker_step_id:
		return {}
	if str(run.get("state", "")) != "BLOCKED":
		return {}
	var token := {
		"actor_id": actor_id,
		"plan_id": plan_id,
		"root_goal": str(run.get("root_goal", "")),
		"step_id": str(run.get("current_step_id", "")),
		"transfer_event_id": transfer_event_id,
		"requested_tick": tick,
	}
	run["parent_revalidation_pending"] = token.duplicate(true)
	runs[actor_id] = run
	if _cooldown.has(actor_id):
		(_cooldown[actor_id] as Dictionary).erase(plan_id)
	_trace(run, tick, "PARENT_PLAN_REVALIDATION_REQUESTED",
		"BLOCKED", "BLOCKED", str(run.get("current_step_id", "")), "", [], transfer_event_id)
	return token

## Consume the one-shot opportunity after proposals are rebuilt from current
## subjective state. A plan that is still blocked or no longer proposed fails closed.
func consume_parent_revalidation(actor_id: String, proposals: Array, tick: int) -> Dictionary:
	var run: Dictionary = runs.get(actor_id, {})
	if run.is_empty():
		return {}
	var token: Dictionary = run.get("parent_revalidation_pending", {})
	if token.is_empty():
		return {}
	run["parent_revalidation_pending"] = {}
	var plan_id := str(token.get("plan_id", ""))
	var ready := false
	for proposal in proposals:
		if typeof(proposal) != TYPE_DICTIONARY:
			continue
		if str(proposal.get("plan_id", "")) == plan_id and str(proposal.get("status", "")) == "READY":
			ready = true
			break
	runs[actor_id] = run
	if not ready or str(run.get("plan_id", "")) != plan_id:
		_trace(run, tick, "PARENT_PLAN_REVALIDATION_REJECTED",
			"BLOCKED", "BLOCKED", str(run.get("current_step_id", "")), "", [], "PLAN_STILL_BLOCKED_OR_REPLACED")
		return {"ok": false, "reason": "PLAN_STILL_BLOCKED_OR_REPLACED", "plan_id": plan_id}
	_trace(run, tick, "PARENT_PLAN_REVALIDATED",
		"BLOCKED", "BLOCKED", str(run.get("current_step_id", "")), "", [], str(token.get("transfer_event_id", "")))
	return {"ok": true, "reason": "PARENT_PLAN_REVALIDATED", "plan_id": plan_id,
		"transfer_event_id": str(token.get("transfer_event_id", ""))}

# ── 内部 ──

func _valuation_context(run: Dictionary) -> Dictionary:
	var plan: Dictionary = run.get("plan_snapshot", {})
	var steps: Array = run.get("steps", [])
	var idx := _step_index_of(run, str(run.get("current_step_id", "")))
	return {
		"expected_benefit": float(plan.get("expected_benefit", 0.0)),
		"estimated_cost": float(plan.get("estimated_cost", 0.0)),
		"estimated_risk": float(plan.get("estimated_risk", 0.0)),
		"confidence": float(plan.get("confidence", 0.0)),
		"step_index": maxi(idx, 0),
		"step_count": steps.size(),
	}

func _select_new_run(actor_id: String, proposals: Array, ctx: Dictionary, tick: int,
		prefer_goal: String = "", adopted_plan_id: String = "") -> Dictionary:
	# §四 固定公开排序：先延续上一 root_goal（目标连续性），再 root_goal 升序 → plan_id 升序；
	# 只选 READY（可执行）计划；冷却中的 plan_id（刚超时取消）跳过——避免无限忙等。
	# P7.2 例外：带 resolvable blocker 注解的 BLOCKED_PLAN 可入场——材料缺口本就要
	# 靠 P7.0/P7.1 在执行期解决（注解只在 commitment profile 由模拟层附加，旧 profile 无）。
	var eligible: Array = []
	for p in proposals:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		if adopted_plan_id != "" and str(p.get("plan_id", "")) != adopted_plan_id:
			continue
		if str(p.get("status", "")) != "READY" and not _resolvably_blocked(p):
			continue
		if _in_cooldown(actor_id, str(p.get("plan_id", "")), tick):
			continue
		eligible.append(p)
	if eligible.is_empty():
		return {}
	eligible.sort_custom(func(a, b):
		var pa := 0 if str(a.get("root_goal", "")) == prefer_goal else 1
		var pb := 0 if str(b.get("root_goal", "")) == prefer_goal else 1
		if pa != pb:
			return pa < pb
		if str(a.get("root_goal", "")) != str(b.get("root_goal", "")):
			return str(a.get("root_goal", "")) < str(b.get("root_goal", ""))
		return str(a.get("plan_id", "")) < str(b.get("plan_id", "")))
	var plan: Dictionary = eligible[0]
	var steps: Array = (plan.get("steps", []) as Array).duplicate(true)
	var run := {
		"run_id": "%s#%d" % [actor_id, _next_seq(actor_id)],
		"actor_id": actor_id,
		"plan_id": str(plan.get("plan_id", "")),
		"root_goal": str(plan.get("root_goal", "")),
		"plan_snapshot": plan.duplicate(true),
		"steps": steps,
		"current_step_id": _first_step_id(steps),
		"state": "ACTIVE",
		"started_tick": tick,
		"last_progress_tick": tick,
		"selected_candidate_key": "",
		"completion_event_refs": [],
		"reason_code": "",
		"pending": {},
		"attempt_seq": 0,
		"missed_opportunities": 0,
		"baseline_items": (ctx.get("possessed_items", {}) as Dictionary).duplicate(true),
	}
	runs[actor_id] = run
	_trace(run, tick, "RUN_STARTED", "", "ACTIVE", run["current_step_id"], "", [])
	return run

func _plan_still_proposed(run: Dictionary, proposals: Array) -> bool:
	for p in proposals:
		if typeof(p) == TYPE_DICTIONARY and str(p.get("plan_id", "")) == str(run.get("plan_id", "")):
			return true
	return false

## P7.2：BLOCKED_PLAN 是否带有"材料缺口可解"注解（由 commitment profile 的
## 模拟层按角色主观证据附加）。注解缺位时恒 false——旧路径行为不变。
func _resolvably_blocked(plan: Dictionary) -> bool:
	if str(plan.get("status", "")) != "BLOCKED_PLAN":
		return false
	var resolution: Dictionary = plan.get("blocker_resolution", {})
	return bool(resolution.get("resolvable", false))

## §六 决策前重查：USE（能力在场跳过）/ACQUIRE（库存达标跳过）逐个推进；
## 越过末步 → COMPLETED；CRAFT 前提失效由 adapter blocker 在 on_decision 裁决。
func _advance_satisfied(run: Dictionary, ctx: Dictionary, tick: int) -> Dictionary:
	var items: Dictionary = ctx.get("possessed_items", {})
	var caps: Array = ctx.get("possessed_capabilities", [])
	var guard := 0
	while guard < 64:
		guard += 1
		# R1 §二：SUSPENDED 同样参与前提重查/自动推进（暂停≠退出考虑集）
		if str(run.get("state", "")) not in ["ACTIVE", "SUSPENDED"]:
			return {}
		var sid := str(run.get("current_step_id", ""))
		var step := _step_by_id(run, sid)
		if step.is_empty():
			_transition(run, tick, "COMPLETED", "ALL_STEPS_DONE", sid, "")
			return {}
		match str(step.get("kind", "")):
			"USE":
				if caps.has(str(step.get("capability", ""))):
					_step_done(run, step, tick, [])
					_advance(run, tick)
					continue
				return step
			"ACQUIRE":
				var item_id := str(step.get("item_id", ""))
				var required := int((run.get("baseline_items", {}) as Dictionary).get(item_id, 0)) + int(step.get("quantity", 0))
				if int(items.get(item_id, 0)) >= required:
					_step_done(run, step, tick, [])
					_advance(run, tick)
					continue
				return step
			"SUBGOAL":
				# P7.2：SUBGOAL(find X) 的"找到"= 自己已持有足量 X——材料到位即越过，
				# 不再永久 INERT。help 型 SUBGOAL（无 item_id）不受影响。
				# 旧 profile 下 SUBGOAL 步骤从未进入 run（CRAFT 计划因 blocker 不被采纳），
				# 此分支对它们惰性。
				var sub_item := str(step.get("item_id", ""))
				if sub_item != "":
					var sub_required := int((run.get("baseline_items", {}) as Dictionary).get(sub_item, 0)) + int(step.get("quantity", 0))
					if int(items.get(sub_item, 0)) >= sub_required:
						_step_done(run, step, tick, [])
						_advance(run, tick)
						continue
				return step
			_:
				return step
	return {}

func _advance(run: Dictionary, tick: int) -> void:
	var idx := _step_index_of(run, str(run.get("current_step_id", "")))
	var next_id := ""
	var steps: Array = run.get("steps", [])
	for i in range(idx + 1, steps.size()):
		next_id = str((steps[i] as Dictionary).get("step_id", ""))
		break
	if next_id == "":
		_transition(run, tick, "COMPLETED", "ALL_STEPS_DONE", str(run.get("current_step_id", "")), "")
		return
	run["current_step_id"] = next_id
	run["last_progress_tick"] = tick
	run["missed_opportunities"] = 0
	run["pending"] = {}
	_note(run, tick, "STEP_ADVANCED", next_id, "")

func _step_done(run: Dictionary, step: Dictionary, tick: int, refs: Array) -> void:
	run["last_progress_tick"] = tick
	run["missed_opportunities"] = 0
	_trace(run, tick, "STEP_COMPLETED", str(run.get("state", "")), str(run.get("state", "")),
		str(step.get("step_id", "")), str(run.get("selected_candidate_key", "")) if not refs.is_empty() else "", refs)

func _step_by_id(run: Dictionary, step_id: String) -> Dictionary:
	for st in run.get("steps", []):
		if str((st as Dictionary).get("step_id", "")) == step_id:
			return st
	return {}

func _step_index_of(run: Dictionary, step_id: String) -> int:
	var steps: Array = run.get("steps", [])
	for i in steps.size():
		if str((steps[i] as Dictionary).get("step_id", "")) == step_id:
			return i
	return -1

func _first_step_id(steps: Array) -> String:
	if steps.is_empty():
		return ""
	return str((steps[0] as Dictionary).get("step_id", ""))

func _next_seq(actor_id: String) -> int:
	var n := int(_run_seq.get(actor_id, 0)) + 1
	_run_seq[actor_id] = n
	return n

func _set_cooldown(actor_id: String, plan_id: String, tick: int) -> void:
	if not _cooldown.has(actor_id):
		_cooldown[actor_id] = {}
	(_cooldown[actor_id] as Dictionary)[plan_id] = tick + no_progress_timeout

func _in_cooldown(actor_id: String, plan_id: String, tick: int) -> bool:
	var cd: Dictionary = _cooldown.get(actor_id, {})
	return cd.has(plan_id) and tick < int(cd[plan_id])

func _transition(run: Dictionary, tick: int, state_after: String, reason: String,
		step_id: String, candidate_key: String) -> void:
	var before := str(run.get("state", ""))
	run["state"] = state_after
	run["reason_code"] = reason
	run["pending"] = {}
	# R1 §五：event = 转移类型（RUN_*），reason_code = 具体原因——语义分离；
	# ACTIVE 只会从 SUSPENDED 进入（选中恢复）→ RUN_RESUMED
	var ev := "RUN_RESUMED" if state_after == "ACTIVE" else "RUN_" + state_after
	_trace(run, tick, ev, before, state_after, step_id, candidate_key, [], reason)

func _note(run: Dictionary, tick: int, event: String, step_id: String,
		candidate_key: String, detail: String = "", reason: String = "") -> void:
	_trace(run, tick, event, str(run.get("state", "")), str(run.get("state", "")), step_id, candidate_key, [], reason)
	if detail != "":
		traces[traces.size() - 1]["detail"] = detail

func _trace(run: Dictionary, tick: int, event: String, state_before: String,
		state_after: String, step_id: String, candidate_key: String, refs: Array,
		reason: String = "") -> void:
	traces.append(_trace_base(run, tick, event, state_before, state_after, step_id, candidate_key, refs, reason))

func _trace_base(run: Dictionary, tick: int, event: String, state_before: String,
		state_after: String, step_id: String, candidate_key: String, refs: Array = [],
		reason: String = "") -> Dictionary:
	return {
		"tick": tick,
		"actor_id": str(run.get("actor_id", "")),
		"run_id": str(run.get("run_id", "")),
		"plan_id": str(run.get("plan_id", "")),
		"root_goal": str(run.get("root_goal", "")),
		"step_id": step_id,
		"candidate_key": candidate_key,
		"state_before": state_before,
		"attempt_id": int(run.get("attempt_seq", 0)) if candidate_key != "" else 0,
		"state_after": state_after,
		"event": event,
		"reason_code": reason,
		"source_event_refs": (refs as Array).duplicate(),
	}

func _event_refs(segment: Array) -> Array:
	var out: Array = []
	for e in segment:
		if typeof(e) == TYPE_DICTIONARY and (e as Dictionary).has("seq"):
			out.append(int(e["seq"]))
	return out

## Admission policy sees the same cooldown gate as execution.
func adoption_candidates(actor_id: String, proposals: Array, tick: int) -> Array:
	var out: Array = []
	for proposal in proposals:
		if typeof(proposal) == TYPE_DICTIONARY and not _in_cooldown(actor_id, str(proposal.get("plan_id", "")), tick):
			out.append(proposal)
	return out
