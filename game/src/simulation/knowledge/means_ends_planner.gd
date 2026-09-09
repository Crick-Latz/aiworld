class_name MeansEndsPlanner
extends RefCounted
## P6.0 + P6.3B-0-R4 Means-Ends Planner.
## R1: CRAFT.recipe_id from RecipeCatalog (RecipePlanAdapter data-driven),
## known_recipe_refs knowledge gate, ALL steps via PlanStepSpec, possessed_items
## for ACQUIRE gap calc, plan-level step validation (fail-closed).
## R4: resolver 直接返回结构化 blockers——在发现问题的位置立即构造，
## 无字符串前缀/split 恢复语义；UNKNOWN_SOURCE 带精确缺口量。
##
## Knowledge proposes; Planner constructs means; DecisionEngine chooses; World executes.

const MAX_DEPTH := 3
const MAX_BRANCHES := 5

static var last_trace := {}

static func propose_plans(problem_id: String, store: WorldKnowledgeStore, ctx: Dictionary,
		catalog: RecipeCatalog = null, items: ItemCatalog = null) -> Array:
	last_trace = {
		"problem": problem_id,
		"retrieved_knowledge": [],
		"considered_capabilities": [],
		"candidate_means": [],
		"missing_requirements": [],
		"generated_plan_ids": [],
		"_store": store,
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
	var known_recipe_refs: Array = ctx.get("known_recipe_refs", [])
	var possessed_items: Dictionary = ctx.get("possessed_items", {})
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
				continue
			_last_trace_add("candidate_means", str(rule["id"]))
			for k in rule.get("knowledge_required", []):
				_last_trace_add("retrieved_knowledge", str(k))
			var plan := _build_plan(problem_id, str(resource_tag), rule, store, available, ctx,
				possessed_caps, all_subject_tags, known_recipe_refs, possessed_items,
				sources_by_tag, catalog, items, 0)
			if not plan.is_empty():
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

static func _build_plan(problem_id: String, resource_tag: String, rule: Dictionary,
		store: WorldKnowledgeStore, available: Dictionary, ctx: Dictionary,
		possessed_caps: Array, all_subject_tags: Array, known_recipe_refs: Array,
		possessed_items: Dictionary, sources_by_tag: Dictionary,
		catalog: RecipeCatalog, items: ItemCatalog, depth: int) -> Dictionary:
	last_trace["_all_subject_tags"] = all_subject_tags
	var steps: Array = []
	var blockers: Array = []
	var blocker_seen := {}
	var knowledge_refs: Array = rule.get("knowledge_required", []).duplicate()
	var cost := float(rule.get("estimated_effort", 1.0))
	var risk := 0.0
	for r in rule.get("risks", []):
		risk += 0.1
	for req in rule.get("requirements", []):
		var cap := str(req)
		_last_trace_add("considered_capabilities", cap)
		if possessed_caps.has(cap):
			steps.append(PlanStepSpec.make("USE",
				PlanStepSpec.step_id_for("USE", "cap", cap),
				"PENDING", "", "", 0, "", cap, [], [cap], [], [],
				"以现有能力 %s" % cap))
			continue
		var resolved: Dictionary = _resolve_cap(cap, known_recipe_refs, possessed_items,
			sources_by_tag, catalog, items, depth + 1)
		steps.append_array(resolved["steps"])
		for blk in resolved["blockers"]:
			var bkey := _blocker_key(blk)
			if not blocker_seen.has(bkey):
				blocker_seen[bkey] = true
				blockers.append(blk)
		for k in resolved["knowledge_refs"]:
			if not knowledge_refs.has(k):
				knowledge_refs.append(k)
		cost += float(resolved["extra_cost"])
	# R4 §一：求助子目标直接读结构化 blocker（不 split 字符串）
	var social_steps: Array = []
	for blk in blockers.duplicate():
		var need := _blocker_need(blk)
		if need == "":
			continue
		var helper := _find_peer_with(need, ctx)
		if helper != "":
			social_steps.append(PlanStepSpec.make("SUBGOAL",
				PlanStepSpec.step_id_for("SUBGOAL", "help", helper + ":" + need),
				"INERT_UNTIL_P6_3B_1", "request_help", "", 0, "", need,
				[], [need], [], [],
				"向 %s 求助（%s）" % [helper, need]))
	var main_action := str(AgencyActionBridge.RULE_TO_ACTION.get(str(rule["id"]), str(rule["id"])))
	steps.append(PlanStepSpec.make("MAIN",
		PlanStepSpec.step_id_for("MAIN", "rule", str(rule["id"])),
		"PENDING", main_action, "", 0, "", "", [], [], [], [],
		"以 %s 缓解 %s" % [str(rule["id"]), problem_id]))
	var plan_id := "PLAN_%s_%s" % [problem_id, str(rule["id"])]
	var em := _expertise_multiplier(rule, ctx.get("expertise_tags", []), store)
	var all_steps: Array = steps + social_steps
	# R3 §四：同 item_id 的 ACQUIRE 聚合 quantity（构建阶段合并，不是删除）
	all_steps = _aggregate_acquires(all_steps)
	# R3 §四：重复 step_id 不静默丢弃——validate 检测到重复即 BLOCKED
	var steps_ok := PlanStepSpec.validate_plan_steps(all_steps)
	var status := "READY"
	if not blockers.is_empty():
		status = "BLOCKED_PLAN"
	elif not steps_ok:
		status = "BLOCKED_PLAN"
		blockers.append(RecipePlanAdapter.make_blocker("INVALID_PLAN_STEPS", "", "", 0))
	# R4 §一：missing_requirements 从 blockers 派生（仅显示/统计用；语义唯一来源是 blockers）
	var missing: Array = []
	for blk in blockers:
		var need := _blocker_need(blk)
		if need != "" and not missing.has(need):
			missing.append(need)
	return {
		"plan_id": plan_id, "root_goal": problem_id,
		"target_resource": resource_tag, "via_rule": str(rule["id"]),
		"steps": all_steps, "missing_requirements": missing, "blockers": blockers,
		"status": status,
		"expected_benefit": 1.0, "estimated_cost": cost * em["cost"],
		"estimated_risk": risk, "confidence": clampf(0.7 * em["confidence"], 0.05, 0.95),
		"knowledge_refs": knowledge_refs, "belief_refs": [],
	}

## R4 §一：blocker 去重键（reason + item + capability + quantity）
static func _blocker_key(blk: Variant) -> String:
	if typeof(blk) != TYPE_DICTIONARY:
		return "MALFORMED"
	var d: Dictionary = blk
	return "%s|%s|%s|%d" % [str(d.get("reason_code", "")), str(d.get("item_id", "")),
		str(d.get("capability", "")), int(d.get("quantity", 0))]

## R4 §一：blocker 的"所缺之物"——UNKNOWN_SOURCE → item_id；
## UNKNOWN_RECIPE/MISSING_CAPABILITY → capability；INVALID_PLAN_STEPS → reason_code。
static func _blocker_need(blk: Variant) -> String:
	if typeof(blk) != TYPE_DICTIONARY:
		return ""
	var d: Dictionary = blk
	var rc := str(d.get("reason_code", ""))
	match rc:
		"UNKNOWN_SOURCE":
			return str(d.get("item_id", ""))
		"INVALID_PLAN_STEPS":
			return rc
		_:
			return str(d.get("capability", ""))

## R3 §四：同 item_id 的 ACQUIRE 步骤聚合 quantity——构建阶段合并，不删除。
## R4 §六：四个 refs 数组全部合并去重排序（不只 belief_refs）。
static func _aggregate_acquires(steps: Array) -> Array:
	var acquires_by_item := {}
	var out: Array = []
	for st in steps:
		if str((st as Dictionary).get("kind", "")) == "ACQUIRE":
			var iid := str((st as Dictionary).get("item_id", ""))
			if acquires_by_item.has(iid):
				var existing: Dictionary = acquires_by_item[iid]
				existing["quantity"] = int(existing["quantity"]) + int((st as Dictionary).get("quantity", 0))
				for refs_key in ["requires", "provides", "knowledge_refs", "belief_refs"]:
					var merged: Array = []
					for v in existing.get(refs_key, []):
						if not merged.has(v):
							merged.append(v)
					for v in (st as Dictionary).get(refs_key, []):
						if not merged.has(v):
							merged.append(v)
					merged.sort()
					existing[refs_key] = merged
			else:
				acquires_by_item[iid] = (st as Dictionary).duplicate()
				out.append(acquires_by_item[iid])
		else:
			out.append(st)
	return out

static func _resolve_cap(capability: String, known_recipe_refs: Array,
		possessed_items: Dictionary, sources_by_tag: Dictionary,
		catalog: RecipeCatalog, items: ItemCatalog, depth: int) -> Dictionary:
	# R4 §一：resolver 契约——{steps, blockers, knowledge_refs, extra_cost}
	var out := {"steps": [], "blockers": [], "knowledge_refs": [], "extra_cost": 0.0}
	if depth > MAX_DEPTH:
		(out["blockers"] as Array).append(RecipePlanAdapter.make_blocker(
			"MISSING_CAPABILITY", "", capability, 0))
		return out
	if catalog != null and items != null:
		return _resolve_via_catalog(capability, known_recipe_refs, possessed_items, sources_by_tag, catalog, items, out)
	var all_tags: Array = last_trace.get("_all_subject_tags", [])
	return _resolve_via_store(capability, sources_by_tag, all_tags, out, depth)

static func _resolve_via_catalog(capability: String, known_recipe_refs: Array,
		possessed_items: Dictionary, sources_by_tag: Dictionary,
		catalog: RecipeCatalog, items: ItemCatalog, out: Dictionary) -> Dictionary:
	var recipe: Dictionary = RecipePlanAdapter.find_recipe_for_capability(
		capability, known_recipe_refs, catalog, items)
	if recipe.is_empty():
		# R4 §一：无已知配方——发现位置直接构造 blocker（不产字符串再恢复）
		(out["blockers"] as Array).append(RecipePlanAdapter.make_blocker(
			"UNKNOWN_RECIPE", "", capability, 0))
		return out
	var rid := str(recipe.get("recipe_id", ""))
	var ings: Dictionary = recipe.get("ingredients", {})
	(out["knowledge_refs"] as Array).append(rid)
	out["extra_cost"] = 2.0
	var blocked := false
	var gaps: Dictionary = RecipePlanAdapter.missing_ingredients(ings, possessed_items)
	for iid in gaps:
		var gap := int(gaps[iid])
		var brefs: Array = []
		for tg in items.tags_of(iid):
			for s in sources_by_tag.get(tg, []):
				brefs.append(str(s.get("belief_ref", "")))
		if brefs.size() > 0:
			(out["steps"] as Array).append(PlanStepSpec.make("ACQUIRE",
				PlanStepSpec.step_id_for("ACQUIRE", "item", iid),
				"PENDING", "", iid, gap, "", "", [iid], [], [], brefs,
				"取得 %s ×%d" % [iid, gap]))
		else:
			# R4 §一：材料无主观来源——UNKNOWN_SOURCE 带精确缺口量
			(out["blockers"] as Array).append(RecipePlanAdapter.make_blocker(
				"UNKNOWN_SOURCE", iid, "", gap))
			(out["steps"] as Array).append(PlanStepSpec.make("SUBGOAL",
				PlanStepSpec.step_id_for("SUBGOAL", "find", iid),
				"INERT_UNTIL_P6_3B_1", "", iid, gap, "", "", [iid], [], [], [],
				"寻找 %s" % iid))
			blocked = true
	if not blocked:
		var oi := str(recipe.get("output_item", ""))
		(out["steps"] as Array).append(PlanStepSpec.make("CRAFT",
			PlanStepSpec.step_id_for("CRAFT", "recipe", rid),
			"PENDING", "", oi, 1, rid, capability, [], [capability], [rid], [],
			"制作 %s（获得 %s）" % [oi, capability]))
	return out

static func _resolve_via_store(capability: String, sources_by_tag: Dictionary, all_tags: Array, out: Dictionary, depth: int) -> Dictionary:
	var store: WorldKnowledgeStore = last_trace.get("_store", null)
	if store == null:
		(out["blockers"] as Array).append(RecipePlanAdapter.make_blocker(
			"MISSING_CAPABILITY", "", capability, 0))
		return out
	var pool: Array = store.rules_providing_capability(capability, {})
	if pool.is_empty():
		(out["blockers"] as Array).append(RecipePlanAdapter.make_blocker(
			"MISSING_CAPABILITY", "", capability, 0))
		return out
	var tool: Dictionary = pool[0]
	for k in tool.get("knowledge_required", []):
		(out["knowledge_refs"] as Array).append(str(k))
	out["extra_cost"] = float(tool.get("estimated_effort", 1.0))
	var blocked := false
	for mat in tool.get("subject_tags", []):
		var ms := str(mat)
		if all_tags.has(ms):
			(out["steps"] as Array).append(PlanStepSpec.make("ACQUIRE",
				PlanStepSpec.step_id_for("ACQUIRE", "item", ms),
				"PENDING", "", ms, 1, "", "", [ms], [], [], [],
				"取得 %s" % ms))
		else:
			(out["blockers"] as Array).append(RecipePlanAdapter.make_blocker(
				"MISSING_CAPABILITY", "", ms, 0))
			(out["steps"] as Array).append(PlanStepSpec.make("SUBGOAL",
				PlanStepSpec.step_id_for("SUBGOAL", "find", ms),
				"INERT_UNTIL_P6_3B_1", "", ms, 1, "", "", [ms], [], [], [],
				"寻找 %s" % ms))
			blocked = true
	for treq in tool.get("requirements", []):
		var sub := _resolve_cap(str(treq), [], {}, sources_by_tag, null, null, depth + 1)
		(out["steps"] as Array).append_array(sub["steps"])
		for blk in sub["blockers"]:
			if not (out["blockers"] as Array).has(blk):
				(out["blockers"] as Array).append(blk)
		blocked = true
	# R2 §二.6：fallback 不产生 CRAFT（无 RecipeCatalog → 不能给真实 recipe_id）
	(out["blockers"] as Array).append(RecipePlanAdapter.make_blocker(
		"UNKNOWN_RECIPE", "", capability, 0))
	return out

static func _find_peer_with(need: String, ctx: Dictionary) -> String:
	var peers: Array = ctx.get("known_peers", [])
	for peer in peers:
		for tag in peer.get("expertise_tags", []):
			if str(tag) == need or CapabilitySpec.domain_of(need) == str(tag):
				return str(peer.get("id", ""))
	return ""

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

static func _last_trace_add(key: String, value: String) -> void:
	var arr: Array = last_trace.get(key, [])
	if not arr.has(value):
		arr.append(value)
	last_trace[key] = arr
