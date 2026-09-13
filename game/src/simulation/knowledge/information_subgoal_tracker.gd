class_name InformationSubgoalTracker
extends RefCounted
## P7.0：把 Planner 的 UNKNOWN_SOURCE blocker 转成可执行信息子目标。
## 本类只读取 PlanProposal、actor 自身需求和 SubjectiveAgencyContext；不读取地图真值。

const STATE_ACTIVE := "ACTIVE"
const STATE_RESOLVED := "RESOLVED"
const STATE_FAILED := "FAILED"
const STATE_CANCELLED := "CANCELLED"
const MAX_ATTEMPTS := 8
const RETRY_COOLDOWN_TICKS := 24

const ROOT_NEED := {
	"HUNGER": "hunger",
	"THIRST": "thirst",
	"ISOLATION": "social",
}

var goals := {}          # actor_id -> current/last information goal
var traces: Array = []   # append-only diagnostic trace
var _serials := {}       # actor_id -> deterministic generation counter

func prepare(actor_id: String, proposals: Array, ctx: Dictionary,
		self_state: Dictionary, at_tick: int, items: ItemCatalog) -> Dictionary:
	var current: Dictionary = goals.get(actor_id, {})
	if not current.is_empty() and str(current.get("state", "")) == STATE_ACTIVE:
		# P7.2B-R1：query-kind 分发。HOLDER 目标的生命周期只由 source material
		# request 驱动（resolve_holder_goal / cancel_holder_goal / _holder_goals_sync_all），
		# 普通 SOURCE prepare 不得用 _candidate_still_present（UNKNOWN_SOURCE 语义）
		# 取消它——那曾把 507/556 个 HOLDER goal 以 PARENT_BLOCKER_REMOVED 误杀。
		if str(current.get("query_kind", "SOURCE")) == "HOLDER":
			return current.duplicate(true)
		if _context_has_source(ctx, current.get("source_kinds", [])):
			_resolve(current, at_tick, "SOURCE_BELIEF_AVAILABLE", _belief_refs(ctx, current.get("source_kinds", [])))
			goals[actor_id] = current
			return {}
		if not _candidate_still_present(current, proposals):
			_transition(current, STATE_CANCELLED, at_tick, "PARENT_BLOCKER_REMOVED")
			goals[actor_id] = current
			return {}
		return current.duplicate(true)

	if not current.is_empty() and str(current.get("state", "")) == STATE_FAILED \
			and at_tick < int(current.get("retry_after_tick", 0)):
		return {}

	var candidates := _candidates(proposals, self_state, items)
	# Planner 与 context 通常来自同一次构造；这里仍做 fail-closed 复核，
	# 防止陈旧 proposal 在已有来源信念时重新生成信息子目标。
	var actionable: Array = []
	for candidate in candidates:
		if not _context_has_source(ctx, candidate.get("source_kinds", [])):
			actionable.append(candidate)
	if actionable.is_empty():
		return {}
	var selected: Dictionary = actionable[0]
	var serial := int(_serials.get(actor_id, 0)) + 1
	_serials[actor_id] = serial
	var goal := {
		"goal_id": "INFO:%s:%d:%s:%s" % [actor_id, serial, selected["plan_id"], selected["item_id"]],
		"actor_id": actor_id,
		"state": STATE_ACTIVE,
		"parent_plan_id": selected["plan_id"],
		"root_goal": selected["root_goal"],
		"item_id": selected["item_id"],
		"quantity": selected["quantity"],
		"source_kinds": selected["source_kinds"],
		"score": selected["score"],
		"created_tick": at_tick,
		"updated_tick": at_tick,
		"last_attempt_tick": -1,
		"attempts": 0,
		"search_failures": 0,
		"asks": 0,
		"refusals": 0,
		"stale_reports": 0,
		"unknown_responses": 0,
		"tried_tiles": [],
		"asked_actor_ids": [],
		"evidence_refs": [],
		"last_result": "",
		"retry_after_tick": -1,
	}
	goals[actor_id] = goal
	_trace(goal, "GOAL_CREATED", at_tick, {"candidate_count": actionable.size()})
	return goal.duplicate(true)

func on_action_complete(actor_id: String, action: Dictionary, event_segment: Array,
		ctx_after: Dictionary, at_tick: int) -> Dictionary:
	var goal: Dictionary = goals.get(actor_id, {})
	if goal.is_empty() or str(goal.get("state", "")) != STATE_ACTIVE:
		return {}
	if str(action.get("information_goal_id", "")) != str(goal.get("goal_id", "")):
		return goal.duplicate(true)
	var action_name := str(action.get("action", ""))
	if action_name not in ["search_resource_source", "ask_resource_source", "ask_item_holder"]:
		return goal.duplicate(true)

	goal["attempts"] = int(goal.get("attempts", 0)) + 1
	goal["last_attempt_tick"] = at_tick
	goal["updated_tick"] = at_tick
	if action_name == "search_resource_source":
		var target = action.get("target", null)
		if typeof(target) == TYPE_VECTOR2I:
			_add_unique(goal["tried_tiles"], SpatialBeliefMap.key(target.x, target.y))
	else:
		goal["asks"] = int(goal.get("asks", 0)) + 1
		_add_unique(goal["asked_actor_ids"], str(action.get("target_actor", "")))

	var result := "NO_EVIDENCE"
	var evidence_refs: Array = []
	for event in event_segment:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var kind := str(event.get("type", ""))
		if str(event.get("information_goal_id", "")) != str(goal.get("goal_id", "")):
			continue
		var event_id := int(event.get("seq", -1))
		if event_id >= 0:
			evidence_refs.append("event:%d" % event_id)
		match kind:
			"source_search_found": result = "SEARCH_FOUND"
			"source_search_failed":
				result = "SEARCH_EMPTY"
				goal["search_failures"] = int(goal.get("search_failures", 0)) + 1
			"source_information_shared": result = "REPORT_SHARED"
			"source_information_refused":
				result = "REPORT_REFUSED"
				goal["refusals"] = int(goal.get("refusals", 0)) + 1
			"source_information_stale":
				result = "REPORT_STALE"
				goal["stale_reports"] = int(goal.get("stale_reports", 0)) + 1
			"source_information_unknown":
				result = "REPORT_UNKNOWN"
				goal["unknown_responses"] = int(goal.get("unknown_responses", 0)) + 1
			"source_information_missed": result = "TARGET_MISSED"
			"action_target_unreachable": result = "TARGET_UNREACHABLE"
			"action_target_missed": result = "TARGET_MISSED"
			# P7.2B-R1：HOLDER 询问结果落账（attempts/asks/asked_actor_ids 走通用路径，
			# 此处补结果分类与各类计数）。
			"holder_information_shared": result = "HOLDER_REPORT_SHARED"
			"holder_information_refused":
				result = "HOLDER_REPORT_REFUSED"
				goal["refusals"] = int(goal.get("refusals", 0)) + 1
			"holder_information_stale":
				result = "HOLDER_REPORT_STALE"
				goal["stale_reports"] = int(goal.get("stale_reports", 0)) + 1
			"holder_information_unknown":
				result = "HOLDER_REPORT_UNKNOWN"
				goal["unknown_responses"] = int(goal.get("unknown_responses", 0)) + 1
			"holder_information_self_absent": result = "HOLDER_SELF_ABSENT"
			"holder_information_missed": result = "TARGET_MISSED"
	for ref in evidence_refs:
		_add_unique(goal["evidence_refs"], ref)
	goal["last_result"] = result

	if _context_has_source(ctx_after, goal.get("source_kinds", [])):
		var refs := _belief_refs(ctx_after, goal.get("source_kinds", []))
		for ref in refs:
			_add_unique(goal["evidence_refs"], ref)
		_resolve(goal, at_tick, result, goal["evidence_refs"])
	elif str(goal.get("query_kind", "SOURCE")) != "HOLDER" and int(goal.get("attempts", 0)) >= MAX_ATTEMPTS:
		# P7.2B-R1.1：HOLDER 不因通用 MAX_ATTEMPTS 进 FAILED——终止权唯一归
		# request/run/step/gap contract；问尽当前对象后保持 ACTIVE 等待环境变化。
		# SOURCE 的 ATTEMPT_LIMIT 冷却语义逐位不变。
		_transition(goal, STATE_FAILED, at_tick, "ATTEMPT_LIMIT")
		goal["retry_after_tick"] = at_tick + RETRY_COOLDOWN_TICKS
	else:
		_trace(goal, "ATTEMPT_COMPLETED", at_tick, {"result": result,
			"event_refs": evidence_refs.duplicate()})
	goals[actor_id] = goal
	return goal.duplicate(true)

# ── P7.2B：FIND_HOLDER 信息目标（绑定 source material request） ──

## NO_SUBJECTIVE_TARGET → 创建/复用 HOLDER 目标。并发纪律：
## A 同 source_request_id 的 ACTIVE HOLDER → 复用（不重建）；
## B 同 parent_plan_id+item 的 ACTIVE SOURCE → 取消（MATERIAL_REQUEST_NEEDS_HOLDER）后切换；
## C 其他 ACTIVE 目标 → 不覆盖（单目标纪律）。
func prepare_holder(actor_id: String, request: Dictionary, at_tick: int,
		excluded_target_ids: Array = [], request_urgency: float = 0.5) -> Dictionary:
	var current: Dictionary = goals.get(actor_id, {})
	if not current.is_empty() and str(current.get("state", "")) == STATE_ACTIVE:
		if str(current.get("query_kind", "SOURCE")) == "HOLDER" \
				and str(current.get("source_request_id", "")) == str(request.get("request_id", "")):
			current["excluded_target_ids"] = excluded_target_ids.duplicate()
			current["request_urgency"] = clampf(request_urgency, 0.0, 1.0)
			current["updated_tick"] = at_tick
			goals[actor_id] = current
			return current.duplicate(true)
		if str(current.get("query_kind", "SOURCE")) == "SOURCE" \
				and str(current.get("parent_plan_id", "")) == str(request.get("parent_plan_id", "")) \
				and str(current.get("item_id", "")) == str(request.get("item_id", "")):
			_transition(current, STATE_CANCELLED, at_tick, "MATERIAL_REQUEST_NEEDS_HOLDER")
		else:
			return {}  # 情况 C：别的目标在身——不抢
	var item_id := str(request.get("item_id", ""))
	if item_id == "":
		return {}
	var serial := int(_serials.get(actor_id, 0)) + 1
	_serials[actor_id] = serial
	var goal := {
		"goal_id": "INFO:HOLDER:%s:%d:%s" % [actor_id, serial, item_id],
		"query_kind": "HOLDER",
		"actor_id": actor_id,
		"state": STATE_ACTIVE,
		"source_request_id": str(request.get("request_id", "")),
		"parent_plan_id": str(request.get("parent_plan_id", "")),
		"parent_run_id": str(request.get("parent_run_id", "")),
		"blocker_step_id": str(request.get("blocker_step_id", "")),
		"root_goal": str(request.get("root_goal", "")),
		"item_id": item_id,
		"holder_predicate": TheoryOfMind.possession_predicate(item_id),
		"request_urgency": clampf(request_urgency, 0.0, 1.0),
		"created_tick": at_tick,
		"updated_tick": at_tick,
		"last_attempt_tick": -1,
		"attempts": 0,
		"asks": 0,
		"refusals": 0,
		"stale_reports": 0,
		"unknown_responses": 0,
		"asked_actor_ids": [],
		"excluded_target_ids": excluded_target_ids.duplicate(),
		"evidence_refs": [],
		"last_result": "",
		"retry_after_tick": -1,
	}
	goals[actor_id] = goal
	_trace(goal, "HOLDER_GOAL_CREATED", at_tick, {
		"source_request_id": goal["source_request_id"],
		"parent_run_id": goal["parent_run_id"],
		"blocker_step_id": goal["blocker_step_id"],
	})
	return goal.duplicate(true)

## HOLDER 目标的唯一 RESOLVED 条件：同 source_request_id 的 material request
## 真实发出了 MATERIAL_REQUEST_OFFERED（学到传闻 ≠ 找到可交互目标）。
func resolve_holder_goal(actor_id: String, source_request_id: String, at_tick: int,
		evidence_ref: String = "") -> Dictionary:
	var goal: Dictionary = goals.get(actor_id, {})
	if goal.is_empty() or str(goal.get("state", "")) != STATE_ACTIVE:
		return {}
	if str(goal.get("query_kind", "SOURCE")) != "HOLDER" \
			or str(goal.get("source_request_id", "")) != source_request_id:
		return {}
	if evidence_ref != "":
		_add_unique(goal["evidence_refs"], evidence_ref)
	_resolve(goal, at_tick, "ACTIONABLE_HOLDER_ACQUIRED", goal["evidence_refs"])
	_trace(goal, "HOLDER_GOAL_RESOLVED", at_tick, {"reason_code": "ACTIONABLE_HOLDER_ACQUIRED"})
	goals[actor_id] = goal
	return goal.duplicate(true)

## source request 终局/身份漂移 → HOLDER 目标跟随取消（不得复活父请求）。
func cancel_holder_goal(actor_id: String, reason: String, at_tick: int) -> Dictionary:
	var goal: Dictionary = goals.get(actor_id, {})
	if goal.is_empty() or str(goal.get("state", "")) != STATE_ACTIVE:
		return {}
	if str(goal.get("query_kind", "SOURCE")) != "HOLDER":
		return {}
	_transition(goal, STATE_CANCELLED, at_tick, reason)
	_trace(goal, "HOLDER_GOAL_CANCELLED", at_tick, {"reason_code": reason})
	goals[actor_id] = goal
	return goal.duplicate(true)

## 每周期同步：目标引用的 request 是否仍活着且仍缺货（由 sim 提供 mismatch 原因）。
func holder_goal_still_valid(actor_id: String, mismatch_reason: String, current_gap: int) -> String:
	var goal: Dictionary = goals.get(actor_id, {})
	if goal.is_empty() or str(goal.get("state", "")) != STATE_ACTIVE:
		return ""
	if str(goal.get("query_kind", "SOURCE")) != "HOLDER":
		return ""
	if mismatch_reason != "":
		return mismatch_reason  # PARENT_RUN_CHANGED / BLOCKER_CHANGED / REQUEST_GONE
	if current_gap <= 0:
		return "GAP_CLOSED"
	return ""

func current_goal(actor_id: String) -> Dictionary:
	return (goals.get(actor_id, {}) as Dictionary).duplicate(true)

func trace_snapshot() -> Array:
	return traces.duplicate(true)

func _candidates(proposals: Array, self_state: Dictionary, items: ItemCatalog) -> Array:
	var out: Array = []
	var seen := {}
	if items == null:
		return out
	for proposal in proposals:
		if typeof(proposal) != TYPE_DICTIONARY:
			continue
		var plan: Dictionary = proposal
		var plan_id := str(plan.get("plan_id", ""))
		var root_goal := str(plan.get("root_goal", ""))
		if plan_id == "" or not ROOT_NEED.has(root_goal):
			continue
		var pressure := _pressure(self_state, root_goal)
		if pressure <= 0.05:
			continue
		for blocker in plan.get("blockers", []):
			if not RecipePlanAdapter.validate_blocker(blocker) \
					or str(blocker.get("reason_code", "")) != "UNKNOWN_SOURCE":
				continue
			var item_id := str(blocker.get("item_id", ""))
			var source_kinds := source_kinds_for_item(item_id, items)
			if source_kinds.is_empty():
				continue
			var identity := plan_id + "|" + item_id
			if seen.has(identity):
				continue
			seen[identity] = true
			var benefit := maxf(float(plan.get("expected_benefit", 0.0)), 0.0)
			var confidence := clampf(float(plan.get("confidence", 0.0)), 0.0, 1.0)
			var cost := maxf(float(plan.get("estimated_cost", 1.0)), 0.25)
			out.append({
				"plan_id": plan_id,
				"root_goal": root_goal,
				"item_id": item_id,
				"quantity": int(blocker.get("quantity", 0)),
				"source_kinds": source_kinds,
				"score": pressure * maxf(benefit, 0.1) * confidence / cost,
			})
	out.sort_custom(func(a, b):
		if not is_equal_approx(float(a["score"]), float(b["score"])):
			return float(a["score"]) > float(b["score"])
		if str(a["plan_id"]) != str(b["plan_id"]):
			return str(a["plan_id"]) < str(b["plan_id"])
		return str(a["item_id"]) < str(b["item_id"]))
	return out

static func source_kinds_for_item(item_id: String, items: ItemCatalog) -> Array:
	var out: Array = []
	if items == null or not items.has(item_id):
		return out
	var item_tags: Array = items.tags_of(item_id)
	var kinds: Array = AgencyContextBuilder.SOURCE_KIND_TAGS.keys()
	kinds.sort()
	for kind in kinds:
		if item_tags.has(str(AgencyContextBuilder.SOURCE_KIND_TAGS[kind])):
			out.append(str(kind))
	return out

static func _pressure(self_state: Dictionary, root_goal: String) -> float:
	var need_key := str(ROOT_NEED.get(root_goal, ""))
	if need_key == "":
		return 0.0
	return clampf(float(self_state.get("needs", {}).get(need_key, 0.0)) / 1000.0, 0.0, 1.0)

static func _context_has_source(ctx: Dictionary, source_kinds: Array) -> bool:
	var tags := {}
	for kind in source_kinds:
		tags[str(AgencyContextBuilder.SOURCE_KIND_TAGS.get(str(kind), ""))] = true
	for source in ctx.get("known_sources", []):
		if tags.has(str(source.get("tag", ""))) and float(source.get("confidence", 0.0)) > 0.0:
			return true
	return false

static func _belief_refs(ctx: Dictionary, source_kinds: Array) -> Array:
	var tags := {}
	for kind in source_kinds:
		tags[str(AgencyContextBuilder.SOURCE_KIND_TAGS.get(str(kind), ""))] = true
	var refs: Array = []
	for source in ctx.get("known_sources", []):
		if tags.has(str(source.get("tag", ""))):
			var ref := str(source.get("belief_ref", ""))
			if ref != "" and not refs.has(ref):
				refs.append(ref)
	refs.sort()
	return refs

static func _candidate_still_present(goal: Dictionary, proposals: Array) -> bool:
	for proposal in proposals:
		if typeof(proposal) != TYPE_DICTIONARY or str(proposal.get("plan_id", "")) != str(goal.get("parent_plan_id", "")):
			continue
		for blocker in proposal.get("blockers", []):
			if RecipePlanAdapter.validate_blocker(blocker) \
					and str(blocker.get("reason_code", "")) == "UNKNOWN_SOURCE" \
					and str(blocker.get("item_id", "")) == str(goal.get("item_id", "")):
				return true
	return false

func _resolve(goal: Dictionary, at_tick: int, reason: String, refs: Array) -> void:
	for ref in refs:
		_add_unique(goal["evidence_refs"], str(ref))
	_transition(goal, STATE_RESOLVED, at_tick, reason)
	goal["resolved_tick"] = at_tick

func _transition(goal: Dictionary, state: String, at_tick: int, reason: String) -> void:
	goal["state"] = state
	goal["updated_tick"] = at_tick
	goal["last_result"] = reason
	_trace(goal, "GOAL_" + state, at_tick, {"reason_code": reason})

func _trace(goal: Dictionary, event_name: String, at_tick: int, extra: Dictionary = {}) -> void:
	var row := {
		"event": event_name,
		"tick": at_tick,
		"actor_id": str(goal.get("actor_id", "")),
		"goal_id": str(goal.get("goal_id", "")),
		"parent_plan_id": str(goal.get("parent_plan_id", "")),
		"root_goal": str(goal.get("root_goal", "")),
		"item_id": str(goal.get("item_id", "")),
		"state": str(goal.get("state", "")),
		"attempts": int(goal.get("attempts", 0)),
	}
	# P7.2B-R1：HOLDER 行附身份字段（query_kind/source_request_id/parent_run_id/
	# blocker_step_id），可按字段归属（goal_id 前缀为稳定后备）。SOURCE 行保持
	# 旧形状逐字节不变——旧 profile 的 information trace 哈希不受影响。
	if str(goal.get("query_kind", "SOURCE")) == "HOLDER":
		row["query_kind"] = "HOLDER"
		row["source_request_id"] = str(goal.get("source_request_id", ""))
		row["parent_run_id"] = str(goal.get("parent_run_id", ""))
		row["blocker_step_id"] = str(goal.get("blocker_step_id", ""))
	for key in extra:
		row[key] = extra[key]
	traces.append(row)

static func _add_unique(array: Array, value: String) -> void:
	if value != "" and not array.has(value):
		array.append(value)

## P7.2B：报告应用/审计事件的附加 trace 行（由 sim 在证据写入时调用）。
func trace_holder_report(actor_id: String, goal_id: String, row: Dictionary) -> void:
	var entry := row.duplicate(true)
	entry["actor_id"] = actor_id
	entry["goal_id"] = goal_id
	entry["query_kind"] = "HOLDER"
	entry["state"] = str((goals.get(actor_id, {}) as Dictionary).get("state", ""))
	traces.append(entry)
