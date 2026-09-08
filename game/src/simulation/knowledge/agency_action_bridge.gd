class_name AgencyActionBridge
extends RefCounted
## P6.2 §3 AgencyActionBridge——把主观 PlanProposal grounding 到 ActionRegistry 已生成的
## 合法候选上。纯函数核心（无缓存/无状态）。
## 硬规则：只 grounding READY+EXISTING_ACTION；utility 一律沿用 ActionRegistry 原值
##（禁止 agency 加分/重复插入）；Planner 与 Registry 不一致 → fail closed（稳定 reason code）；
## FUTURE/BLOCKED 只进 inert subgoal；candidate key 稳定可排序；refs 去重排序。

## 规则 → 既有行动映射（P6.2-R1 §2.11：唯一契约位置——shadow runner/island/诊断测试一律复用本表）
const RULE_TO_ACTION := {
	"berry_patch_food": "forage_berries",
	"spring_water": "drink_water",
	"build_shelter": "build_shelter",
	"fish_food": "fish",
	"wood_structure": "gather_wood",
}

## 步骤执行标注（EXISTING_ACTION/FUTURE_CAPABILITY/BLOCKED——只标记不执行）
## P6.2-R1：从 shadow runner / island 中抽出的共享纯函数
static func annotate_steps(proposals: Array) -> void:
	for p in proposals:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		var existing := str(RULE_TO_ACTION.get(str(p.get("via_rule", "")), ""))
		for st in p.get("steps", []):
			if typeof(st) != TYPE_DICTIONARY:
				continue
			var kind := str(st.get("kind", ""))
			if kind == "MAIN":
				if existing != "":
					st["step_execution_status"] = "EXISTING_ACTION"
					st["existing_action"] = existing
				else:
					st["step_execution_status"] = "FUTURE_CAPABILITY"
			elif kind == "SUBGOAL":
				st["step_execution_status"] = "BLOCKED"
			else:
				st["step_execution_status"] = "FUTURE_CAPABILITY"

## 输入：planner proposals（含 steps 标注）、该 actor 的 ActionRegistry 合法候选全表
## 输出：grounded_candidates / rejected_proposals / future_subgoals
static func ground(proposals: Array, valid_actions: Array, tick: int, actor_id: String) -> Dictionary:
	var grounded: Array = []
	var rejected: Array = []
	var futures: Array = []
	var seen_keys := {}
	for p in proposals:
		if typeof(p) != TYPE_DICTIONARY:
			continue  # PR：畸形输入安静拒绝
		var plan_id := str(p.get("plan_id", ""))
		var problem_id := str(p.get("root_goal", ""))
		if plan_id == "":
			continue
		var refs_k := _sorted_unique(p.get("knowledge_refs", []))
		var refs_b := _sorted_unique(p.get("belief_refs", []))
		if str(p.get("status", "")) != "READY":
			rejected.append({"problem_id": problem_id, "plan_id": plan_id,
				"reason_code": "NOT_READY",
				"missing_requirements": p.get("missing_requirements", []),
				"knowledge_refs": refs_k, "belief_refs": refs_b})
			# BLOCKED → inert subgoal（缺项即子目标方向）
			for m in p.get("missing_requirements", []):
				futures.append({"problem_id": problem_id, "plan_id": plan_id,
					"capability_or_requirement": str(m), "status": "INERT_UNTIL_P6_3"})
			continue
		var action_name := str(RULE_TO_ACTION.get(str(p.get("via_rule", "")), ""))
		if action_name == "":
			rejected.append({"problem_id": problem_id, "plan_id": plan_id,
				"reason_code": "NO_MAPPING", "missing_requirements": [],
				"knowledge_refs": refs_k, "belief_refs": refs_b})
			continue
		var matched := _match_action(action_name, valid_actions)
		if matched.is_empty():
			rejected.append({"problem_id": problem_id, "plan_id": plan_id,
				"reason_code": "NOT_IN_REGISTRY", "missing_requirements": [],
				"knowledge_refs": refs_k, "belief_refs": refs_b})
			continue
		var key := candidate_key(matched)
		if seen_keys.has(key):
			rejected.append({"problem_id": problem_id, "plan_id": plan_id,
				"reason_code": "DUPLICATE_KEY", "missing_requirements": [],
				"knowledge_refs": refs_k, "belief_refs": refs_b})
			continue
		seen_keys[key] = true
		grounded.append({
			"candidate_key": key,
			"action": str(matched.get("action", "")),
			"target": matched.get("target", null),
			"target_actor": matched.get("target_actor", ""),
			"problem_id": problem_id,
			"plan_id": plan_id,
			"via_rule": str(p.get("via_rule", "")),
			"knowledge_refs": refs_k,
			"belief_refs": refs_b,
			"utility_source": "ACTION_REGISTRY",
			"original_utility": float(matched.get("utility", 0.0)),
		})
		# READY 计划中的 FUTURE_CAPABILITY 步骤也进 inert（§4：只入 trace）
		for st in p.get("steps", []):
			if str(st.get("step_execution_status", "")) == "FUTURE_CAPABILITY":
				futures.append({"problem_id": problem_id, "plan_id": plan_id,
					"capability_or_requirement": str(st.get("description", "")).substr(0, 40),
					"status": "INERT_UNTIL_P6_3"})
	# 稳定排序（与输入顺序无关）
	grounded.sort_custom(func(a, b): return str(a["candidate_key"]) < str(b["candidate_key"]))
	return {"tick": tick, "actor_id": actor_id,
		"grounded_candidates": grounded, "rejected_proposals": rejected,
		"future_subgoals": futures}

## 候选 key：行动 + 目标（稳定、可排序、与字典迭代序无关）
static func candidate_key(action: Dictionary) -> String:
	var t = action.get("target", null)
	var ta := str(action.get("target_actor", ""))
	var tgt := "-"
	if ta != "":
		tgt = ta
	elif typeof(t) == TYPE_VECTOR2I:
		tgt = "%d,%d" % [int(t.x), int(t.y)]
	return "%s@%s" % [str(action.get("action", "")), tgt]

## 同名行动取 utility 最高者（ActionRegistry 的原值原目标——绝不构造新行动）
static func _match_action(action_name: String, valid_actions: Array) -> Dictionary:
	var best := {}
	var best_u := -1.0
	for a in valid_actions:
		if typeof(a) != TYPE_DICTIONARY or str(a.get("action", "")) != action_name:
			continue
		var u := float(a.get("utility", 0.0))
		if u > best_u:
			best_u = u
			best = a
	return best

static func _sorted_unique(arr: Array) -> Array:
	var seen := {}
	var out: Array = []
	for v in arr:
		var s := str(v)
		if not seen.has(s):
			seen[s] = true
			out.append(s)
	out.sort()
	return out

## P6.2 §1/PO：分歧互斥分类（决策时真值 trace + current_action）
## 已实现类别：ACTION_GAP / IGNORED_BY_CONSIDERATION / CONSIDERED_NOT_SELECTED /
##       INTENTION_PERSISTED / ACTION_IN_PROGRESS / BETWEEN_ACTIONS / NO_EQUIVALENT_EXECUTION / MATCHED_SELECTED
## （P6.2-R1：目标不匹配类未实现即删——不留半实现）
static func classify_divergence(cur_action_variants: Variant, action_name: String,
		trace: Dictionary, current_tick: int) -> String:
	if typeof(cur_action_variants) != TYPE_DICTIONARY:
		return "BETWEEN_ACTIONS"
	var cur_action := str(cur_action_variants.get("action", ""))
	if cur_action == action_name:
		return "ACTION_IN_PROGRESS"
	var trace_tick := int(trace.get("tick", -1))
	if trace_tick < current_tick and cur_action != "":
		return "INTENTION_PERSISTED"
	var selected := str(trace.get("selected", ""))
	if selected == action_name:
		return "MATCHED_SELECTED"
	if (trace.get("considered_actions", []) as Array).has(action_name):
		return "CONSIDERED_NOT_SELECTED"
	if (trace.get("ignored_actions", []) as Array).has(action_name):
		return "IGNORED_BY_CONSIDERATION"
	return "ACTION_GAP"
