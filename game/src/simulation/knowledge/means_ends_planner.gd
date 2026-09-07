class_name MeansEndsPlanner
extends RefCounted
## P6.0 §16-20 Means–Ends Planner——"会想办法"的核心。
## 输入：问题 + actor 主观状态（ctx：已见材料/已有物品/已有能力/专业知识/认识的伙伴）
## 输出：PlanProposal 列表（含 BLOCKED_PLAN）——只提议，不执行，不碰世界。
##
## 铁律：
##   Knowledge proposes possibilities; Planner constructs means;
##   DecisionEngine chooses; World rules execute.
##   知识≠信念≠持有（§13）：know(Gun→Threaten) 不产生 THREATEN_WITH_GUN，
##   除非主观状态确认"我有枪"。
##
## ctx（主观状态，全部由调用方从 Belief/Spatial/inventory 派生——planner 不读世界）：
##   { possessed_tags: []        —— 我持有的物品/材料标签（WOOD/SHARP_STONE/GUN...）
##     known_source_tags: []     —— 我知道存在的环境来源（BERRY_PATCH/SPRING/ANIMAL...）
##     possessed_capabilities: []—— 我当前具备的能力（来自持有物+身体）
##     expertise_tags: []        —— LifeHistory 派生专业域
##     known_peers: [ {id, expertise_tags: [], trust: float} ] }
##
## 确定性：无随机；同输入同输出（KM）。深度 MAX_DEPTH=3，分支 MAX_BRANCHES=5（§19）。

const MAX_DEPTH := 3
const MAX_BRANCHES := 5

## AgencyTrace（§27）：结构化留痕——"为什么想到了造长矛"可回溯，不靠 LLM 事后编理由
static var last_trace := {}

static func propose_plans(problem_id: String, store: WorldKnowledgeStore, ctx: Dictionary) -> Array:
	last_trace = {
		"problem": problem_id,
		"retrieved_knowledge": [],
		"considered_capabilities": [],
		"candidate_means": [],
		"missing_requirements": [],
		"generated_plan_ids": [],
	}
	var plans: Array = []
	var satisfied: Array = ProblemSpec.satisfied_by(problem_id)
	if satisfied.is_empty():
		last_trace["missing_requirements"] = ["UNKNOWN_PROBLEM"]
		return plans
	var available: Dictionary = store.available_for(ctx.get("expertise_tags", []))
	var possessed_caps: Array = ctx.get("possessed_capabilities", [])
	var possessed_tags: Array = ctx.get("possessed_tags", [])
	var known_sources: Array = ctx.get("known_source_tags", [])
	# P6.1 §18：rich known_sources → 主观依据（belief_ref）按标签归档
	var sources_by_tag := {}
	for s in ctx.get("known_sources", []):
		var tag := str(s.get("tag", ""))
		if not sources_by_tag.has(tag):
			sources_by_tag[tag] = []
		(sources_by_tag[tag] as Array).append(s)
	var all_subject_tags: Array = possessed_tags.duplicate()
	for t in known_sources:
		if not all_subject_tags.has(t):
			all_subject_tags.append(t)
	var n_plans := 0
	for resource_tag in satisfied:
		for rule in store.rules_producing(str(resource_tag), available):
			if n_plans >= MAX_BRANCHES:
				break
			if not AffordanceRule.matches(rule, all_subject_tags):
				continue  # 主观世界里没有此物——知识再多也不能凭空用（PK-B/C）
			_last_trace_add("candidate_means", str(rule["id"]))
			for k in rule.get("knowledge_required", []):
				_last_trace_add("retrieved_knowledge", str(k))
			var plan := _build_plan_for_rule(problem_id, str(resource_tag), rule, store, available, ctx, possessed_caps, all_subject_tags, 0)
			if not plan.is_empty():
				# belief_refs：本规则用到的已知来源（"为什么他认为附近有浆果"可回溯）
				var plan_beliefs: Array = []
				for tag in rule.get("subject_tags", []):
					for s in sources_by_tag.get(str(tag), []):
						var ref := str(s.get("belief_ref", ""))
						if ref != "" and not plan_beliefs.has(ref):
							plan_beliefs.append(ref)
				plan["belief_refs"] = plan_beliefs
				plans.append(plan)
				last_trace["generated_plan_ids"].append(str(plan["plan_id"]))
				n_plans += 1
	return plans

## 递归构造：资源 → 规则 → 能力缺口 → 找提供该能力的工具规则 → 材料缺口 → 子目标/阻塞
static func _build_plan_for_rule(problem_id: String, resource_tag: String, rule: Dictionary,
		store: WorldKnowledgeStore, available: Dictionary, ctx: Dictionary,
		possessed_caps: Array, all_subject_tags: Array, depth: int) -> Dictionary:
	var steps: Array = []
	var missing: Array = []
	var knowledge_refs: Array = rule.get("knowledge_required", []).duplicate()
	var cost := float(rule.get("estimated_effort", 1.0))
	var risk := 0.0
	for r in rule.get("risks", []):
		risk += 0.1
	# 1) 规则自身需要的能力：已有则记录；缺则递归解析（工具化/材料化，深度限制内）
	for req in rule.get("requirements", []):
		var cap := str(req)
		_last_trace_add("considered_capabilities", cap)
		if possessed_caps.has(cap):
			steps.append(_step("USE", "以现有能力 %s 运用 %s" % [cap, str(rule["id"])], [], [cap]))
			continue
		var resolved: Dictionary = _resolve_capability(cap, store, available, all_subject_tags, depth + 1)
		steps.append_array(resolved["steps"])
		for m in resolved["missing"]:
			if not missing.has(m):
				missing.append(m)
		for k in resolved["knowledge_refs"]:
			if not knowledge_refs.has(k):
				knowledge_refs.append(k)
		cost += float(resolved["extra_cost"])
	# 2) 社会路线（§22-23）：能力缺口若可由已知伙伴的专业补足 → REQUEST_HELP/COOPERATE 候选。
	#    不从 missing 中移除——单人视角仍缺；社交只是候选路径，不强制合作。
	var social_steps: Array = []
	if not missing.is_empty():
		for m in missing.duplicate():
			var helper := _find_peer_with(str(m), ctx)
			if helper != "":
				social_steps.append(_step("REQUEST_HELP", "向 %s 求助（其或具备 %s）" % [helper, str(m)], [], []))
	# 3) 主行动
	steps.append(_step("MAIN", "以 %s 获得 %s（缓解 %s）" % [str(rule["id"]), resource_tag, problem_id], [], []))
	var plan_id := "PLAN_%s_%s" % [problem_id, str(rule["id"])]
	var expertise_multiplier := _expertise_multiplier(rule, ctx.get("expertise_tags", []), store)
	return {
		"plan_id": plan_id,
		"root_goal": problem_id,
		"target_resource": resource_tag,
		"via_rule": str(rule["id"]),
		"steps": steps + social_steps,
		"missing_requirements": missing,
		"status": "BLOCKED_PLAN" if not missing.is_empty() else "READY",
		"expected_benefit": 1.0,
		"estimated_cost": cost * expertise_multiplier["cost"],
		"estimated_risk": risk,
		"confidence": clampf(0.7 * expertise_multiplier["confidence"], 0.05, 0.95),
		"knowledge_refs": knowledge_refs,
		"belief_refs": [],  # 主观依据由调用方在接线时回填（P6.2）
	}

## 能力解析（递归）：已有→USE；可工具化→CRAFT（其材料与前置能力再递归）；
## 不可解→missing 具名（未知材料用材料名，深度耗尽/无工具用能力名）
static func _resolve_capability(capability: String, store: WorldKnowledgeStore, available: Dictionary,
		all_subject_tags: Array, depth: int) -> Dictionary:
	var out := {"steps": [], "missing": [], "knowledge_refs": [], "extra_cost": 0.0}
	if depth > MAX_DEPTH:
		out["missing"] = [capability]
		return out
	var tool := _find_tool_for_capability(capability, store, available, all_subject_tags)
	if tool.is_empty():
		out["missing"] = [capability]
		return out
	for k in tool.get("knowledge_required", []):
		(out["knowledge_refs"] as Array).append(str(k))
	out["extra_cost"] = float(tool.get("estimated_effort", 1.0))
	var blocked := false
	for mat in tool.get("subject_tags", []):
		if not _is_material_tag(str(mat)):
			continue
		if all_subject_tags.has(str(mat)):
			(out["steps"] as Array).append(_step("ACQUIRE", "取得 %s" % str(mat), [str(mat)], []))
		else:
			# §20：缺料不凭空补——具名阻塞 + 搜索子目标（材料=全所需 AND）
			(out["missing"] as Array).append(str(mat))
			(out["steps"] as Array).append(_step("SUBGOAL", "寻找 %s" % str(mat), [], []))
			blocked = true
	for treq in tool.get("requirements", []):
		var sub: Dictionary = _resolve_capability(str(treq), store, available, all_subject_tags, depth + 1)
		(out["steps"] as Array).append_array(sub["steps"])
		for m in sub["missing"]:
			if not (out["missing"] as Array).has(m):
				(out["missing"] as Array).append(m)
			blocked = true
		for k in sub["knowledge_refs"]:
			if not (out["knowledge_refs"] as Array).has(k):
				(out["knowledge_refs"] as Array).append(k)
		out["extra_cost"] = float(out["extra_cost"]) + float(sub["extra_cost"])
	if not blocked:
		(out["steps"] as Array).append(_step("CRAFT", "制作 %s（获得 %s）" % [str(tool["id"]), capability], [], [capability]))
	return out

## 工具化检索：谁提供这个能力（材料是否主观可见由解析层具名判定——未知材料 → BLOCKED+SUBGOAL，不静默丢弃）
static func _find_tool_for_capability(capability: String, store: WorldKnowledgeStore, available: Dictionary, all_subject_tags: Array) -> Dictionary:
	var pool: Array = store.rules_providing_capability(capability, available)
	if not pool.is_empty():
		return pool[0]
	return {}

## 伙伴检索：已知伙伴的专业域覆盖缺口（数据驱动；不强制合作，只给候选）
static func _find_peer_with(missing_item: String, ctx: Dictionary) -> String:
	var peers: Array = ctx.get("known_peers", [])
	for peer in peers:
		for tag in peer.get("expertise_tags", []):
			if str(tag) == missing_item or CapabilitySpec.domain_of(missing_item) == str(tag):
				return str(peer.get("id", ""))
	return ""

## 专业度影响估计值，不影响规则集（KF/§30）—— woodworking 经验 → 造物 cost↓ confidence↑
static func _expertise_multiplier(rule: Dictionary, expertise_tags: Array, store: WorldKnowledgeStore) -> Dictionary:
	var mult := {"cost": 1.0, "confidence": 1.0}
	var rule_caps: Array = rule.get("provides_capabilities", [])
	for tag in expertise_tags:
		var domain := str(tag)
		for cap in rule_caps:
			if CapabilitySpec.domain_of(str(cap)) == domain:
				mult["cost"] = 0.75
				mult["confidence"] = 1.25
				return mult
	return mult

static func _is_material_tag(tag: String) -> bool:
	# 材料 = 非资源产出物（WOOD/SHARP_STONE/BINDING 类）；产出标签（FOOD/WATER...）不算
	var product_tags := ["FOOD", "WATER", "SHELTER", "HEAT_SOURCE", "SAFETY", "ESCAPE_MEANS", "STORAGE", "TOOL", "COMPANY", "CONTACT", "RESOURCE", "INSULATION"]
	return not product_tags.has(tag)

static func _step(kind: String, description: String, requires: Array, provides: Array) -> Dictionary:
	return {"kind": kind, "description": description, "requires": requires, "provides": provides}

static func _last_trace_add(key: String, value: String) -> void:
	var arr: Array = last_trace.get(key, [])
	if not arr.has(value):
		arr.append(value)
	last_trace[key] = arr
