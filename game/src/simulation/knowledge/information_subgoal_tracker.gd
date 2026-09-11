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
	if action_name not in ["search_resource_source", "ask_resource_source"]:
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
	for ref in evidence_refs:
		_add_unique(goal["evidence_refs"], ref)
	goal["last_result"] = result

	if _context_has_source(ctx_after, goal.get("source_kinds", [])):
		var refs := _belief_refs(ctx_after, goal.get("source_kinds", []))
		for ref in refs:
			_add_unique(goal["evidence_refs"], ref)
		_resolve(goal, at_tick, result, goal["evidence_refs"])
	elif int(goal.get("attempts", 0)) >= MAX_ATTEMPTS:
		_transition(goal, STATE_FAILED, at_tick, "ATTEMPT_LIMIT")
		goal["retry_after_tick"] = at_tick + RETRY_COOLDOWN_TICKS
	else:
		_trace(goal, "ATTEMPT_COMPLETED", at_tick, {"result": result,
			"event_refs": evidence_refs.duplicate()})
	goals[actor_id] = goal
	return goal.duplicate(true)

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
	for key in extra:
		row[key] = extra[key]
	traces.append(row)

static func _add_unique(array: Array, value: String) -> void:
	if value != "" and not array.has(value):
		array.append(value)
