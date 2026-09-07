class_name AgencyShadowRunner
extends RefCounted
## P6.1 §16-17/§26-27 Shadow Runner——"新脑子"接真实 NPC，但只观察不行动。
## PlanProposal：记录/分析/比较；绝不执行、不改 Goal/Intention、不进 DecisionEngine、
## 不改 Utility、不改 World（RH/RF/RJ 门）。由外部驱动（sim.tick 后调 observe(sim)），
## island_simulation/decision_engine 零改动——ON/OFF 不变性由结构保证。
##
## 触发（§14 bounded slow path）：问题新激活 OR 每 24 tick 周期复核 OR context hash 变化。
## 其余 tick 走 context_hash → 缓存提案。

const REVIEW_INTERVAL := 24

## Plan Step 执行标注（§27）：只标记，不执行
const RULE_EXISTING_ACTIONS := {
	"berry_patch_food": "forage_berries",
	"spring_water": "drink_water",
	"build_shelter": "build_shelter",
	"fish_food": "fish",
	"wood_structure": "gather_wood",
}

var records: Array = []
var cache := {}           # actor_id -> {hash, problems, proposals}
var planner_calls := 0
var cache_hits := 0
var shadow_plans_generated := 0
var _last_activated := {} # actor_id -> problems

func observe(sim) -> void:
	for id in sim.actors:
		var actor: Dictionary = sim.actors[id]
		var problems: Array = ProblemActivationAdapter.activate(actor)
		var newly := _newly_activated(str(id), problems)
		var cached: Dictionary = cache.get(str(id), {})
		if not newly.is_empty() or int(sim.tick) % REVIEW_INTERVAL == 0 or cached.is_empty():
			_plan_for(sim, str(id), actor, problems)
		else:
			# 便宜路径：context hash 变了才重规划（材料/知识实质变化）
			var ctx := AgencyContextBuilder.build(sim, actor)
			var h := AgencyContextBuilder.context_hash(ctx)
			if h != str(cached.get("hash", "")):
				_plan_with_ctx(sim, str(id), actor, ctx, problems)
			else:
				cache_hits += 1
		_last_activated[str(id)] = problems.duplicate()

func _plan_for(sim, id: String, actor: Dictionary, problems: Array) -> void:
	var ctx := AgencyContextBuilder.build(sim, actor)
	_plan_with_ctx(sim, id, actor, ctx, problems)

func _plan_with_ctx(sim, id: String, actor: Dictionary, ctx: Dictionary, problems: Array) -> void:
	planner_calls += 1
	var store: WorldKnowledgeStore = _pack()
	var hash := AgencyContextBuilder.context_hash(ctx)
	var ready := 0
	var blocked := 0
	var proposal_ids: Array = []
	var missing: Array = []
	var knowledge_refs: Array = []
	var belief_refs: Array = []
	for problem in problems:
		var plans: Array = MeansEndsPlanner.propose_plans(str(problem), store, ctx)
		var trace: Dictionary = MeansEndsPlanner.last_trace
		for k in trace.get("retrieved_knowledge", []):
			if not knowledge_refs.has(k):
				knowledge_refs.append(k)
		for p in plans:
			shadow_plans_generated += 1
			proposal_ids.append(str(p.get("plan_id", "")))
			for m in p.get("missing_requirements", []):
				if not missing.has(m):
					missing.append(m)
			for b in p.get("belief_refs", []):
				if not belief_refs.has(b):
					belief_refs.append(b)
			if str(p.get("status", "")) == "READY":
				ready += 1
			else:
				blocked += 1
			_annotate_steps(p)
	# ShadowAgencyRecord（§17）：含实际行为对照——只比较，不反馈
	var cur_v = actor.get("current_action", {})
	var cur: Dictionary = cur_v if typeof(cur_v) == TYPE_DICTIONARY else {}
	records.append({
		"tick": int(sim.tick), "actor_id": id,
		"problems": problems.duplicate(),
		"context_hash": hash,
		"proposal_ids": proposal_ids, "ready_count": ready, "blocked_count": blocked,
		"missing_requirements": missing,
		"knowledge_refs": knowledge_refs, "belief_refs": belief_refs,
		"proposals_cache": _slim_proposals(problems, store, ctx),
		"actual_selected_action": str(cur.get("action", "")),
		"actual_goal": _top_goal_id(actor),
		"actual_intention": str(cur.get("desc", "")),
	})
	cache[str(id)] = {"hash": hash, "problems": problems.duplicate()}

func _slim_proposals(problems: Array, store: WorldKnowledgeStore, ctx: Dictionary) -> Array:
	var out: Array = []
	for problem in problems:
		for p in MeansEndsPlanner.propose_plans(str(problem), store, ctx):
			_annotate_steps(p)
			out.append({
				"plan_id": p.get("plan_id", ""), "root_goal": p.get("root_goal", ""),
				"via_rule": p.get("via_rule", ""), "status": p.get("status", ""),
				"missing": p.get("missing_requirements", []),
				"belief_refs": p.get("belief_refs", []),
				"steps": p.get("steps", []),
			})
	return out

## §27：给步骤标 EXISTING_ACTION / FUTURE_CAPABILITY / BLOCKED——只标记，不映射执行
func _annotate_steps(p: Dictionary) -> void:
	var via := str(p.get("via_rule", ""))
	var existing := str(RULE_EXISTING_ACTIONS.get(via, ""))
	for st in p.get("steps", []):
		var kind := str(st.get("kind", ""))
		if kind == "MAIN":
			st["step_execution_status"] = "EXISTING_ACTION" if existing != "" else "FUTURE_CAPABILITY"
			if existing != "":
				st["existing_action"] = existing
		elif kind == "SUBGOAL":
			st["step_execution_status"] = "BLOCKED"
		else:
			st["step_execution_status"] = "FUTURE_CAPABILITY"

func _top_goal_id(actor: Dictionary) -> String:
	var gm = actor.get("goal_manager", null)
	if gm == null:
		return ""
	var tg: Dictionary = gm.top_goal()
	return str(tg.get("id", ""))

func _newly_activated(id: String, problems: Array) -> Array:
	var prev: Array = _last_activated.get(id, [])
	var out: Array = []
	for p in problems:
		if not prev.has(p):
			out.append(p)
	return out

var _pack_store: WorldKnowledgeStore = null

func _pack() -> WorldKnowledgeStore:
	if _pack_store == null:
		_pack_store = KnowledgePack.load_island_pack()
	return _pack_store

## 汇总（Pilot 用）
func stats() -> Dictionary:
	var by_problem := {}
	var top_missing := {}
	var divergence: Array = []
	for r in records:
		for p in r.get("problems", []):
			var slot: Dictionary = by_problem.get(p, {"ready": 0, "blocked": 0, "no_plan": 0})
			if r.get("ready_count", 0) == 0 and r.get("blocked_count", 0) == 0:
				slot["no_plan"] += 1
			else:
				slot["ready"] += int(r.get("ready_count", 0))
				slot["blocked"] += int(r.get("blocked_count", 0))
			by_problem[p] = slot
		for m in r.get("missing_requirements", []):
			top_missing[m] = int(top_missing.get(m, 0)) + 1
		# §35：有 READY 方案但实际行为不相关 → 有价值分歧
		if int(r.get("ready_count", 0)) > 0 and str(r.get("actual_selected_action", "")) in ["explore", "rest", "do_nothing", "socialize", ""]:
			divergence.append(r)
	return {
		"records": records.size(), "planner_calls": planner_calls, "cache_hits": cache_hits,
		"shadow_plans_generated": shadow_plans_generated,
		"by_problem": by_problem, "top_missing": top_missing,
		"divergence_count": divergence.size(),
	}
