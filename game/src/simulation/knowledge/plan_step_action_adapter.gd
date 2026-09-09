class_name PlanStepActionAdapter
extends RefCounted
## P6.3B-1 §五 PlanStepActionAdapter——把当前执行步骤匹配到本次 ActionRegistry
## 已生成的合法候选。纯函数：不扫描隐藏地图、不构造新行动、不改 utility/target。
## 映射集中在此（禁止散落 actor/item name 分支）；无合法候选 → 明确 blocker_reason。

## ACQUIRE：item_id → 既有采集行动（第一版显式表——只接通现有行动）
const ACQUIRE_ITEM_TO_ACTION := {
	"wood": "gather_wood",
	"shells": "gather_shells",
}

## MAIN：action_name → 成功结果事件类型（完成判定用——"被选中"不算完成）
const MAIN_SUCCESS_EVENTS := {
	"fish": "fished",
	"forage_berries": "foraged",
	"drink_water": "drank",
	"build_shelter": "shelter_built",
	"gather_wood": "gathered_wood",
	"gather_shells": "gathered_shells",
}

## ACQUIRE：item_id → 实得事件类型（材料落袋证明）
const ACQUIRE_GAIN_EVENTS := {
	"wood": "gathered_wood",
	"shells": "gathered_shells",
}

## 匹配当前步骤的合法候选。
## 返回 {candidates: Array, skip: bool, blocker_reason: String}——
## skip=true 表示步骤已满足无需行动（USE 且主观能力在场）；
## candidates 为空且 skip=false 时 blocker_reason 非空（明确阻断原因）。
static func match_candidates(step: Dictionary, valid_actions: Array, ctx: Dictionary,
		catalog: RecipeCatalog = null, items: ItemCatalog = null) -> Dictionary:
	var kind := str(step.get("kind", ""))
	match kind:
		"ACQUIRE":
			return _match_acquire(step, valid_actions, ctx, items)
		"CRAFT":
			return _match_craft(step, valid_actions, ctx, catalog)
		"MAIN":
			return _match_main(step, valid_actions)
		"USE":
			var cap := str(step.get("capability", ""))
			if cap != "" and (ctx.get("possessed_capabilities", []) as Array).has(cap):
				return {"candidates": [], "skip": true, "blocker_reason": ""}
			return {"candidates": [], "skip": false, "blocker_reason": "CAPABILITY_MISSING"}
		"SUBGOAL":
			# 子目标保持阻塞——不凭空创造行动（P6.3B-2 议题）
			return {"candidates": [], "skip": false, "blocker_reason": "SUBGOAL_INERT"}
	return {"candidates": [], "skip": false, "blocker_reason": "UNKNOWN_KIND"}

static func _match_acquire(step: Dictionary, valid_actions: Array, ctx: Dictionary,
		items: ItemCatalog) -> Dictionary:
	var item_id := str(step.get("item_id", ""))
	var action_name := str(ACQUIRE_ITEM_TO_ACTION.get(item_id, ""))
	if action_name == "":
		return {"candidates": [], "skip": false, "blocker_reason": "NO_ITEM_ACTION_MAPPING"}
	# 主观来源检查：物品标签 ∩ ctx 已知来源标签（绝不信世界真值）
	if not _ctx_knows_source_of(item_id, ctx, items):
		return {"candidates": [], "skip": false, "blocker_reason": "NO_KNOWN_SOURCE"}
	var out: Array = []
	for c in valid_actions:
		if typeof(c) != TYPE_DICTIONARY or str(c.get("action", "")) != action_name:
			continue
		# 候选目标必须对应自己的已知来源（Registry 已保证——此处复核，不扫隐藏地图）
		if not _target_in_known_sources(c, item_id, ctx, items):
			continue
		out.append(c)
	if out.is_empty():
		return {"candidates": [], "skip": false, "blocker_reason": "NO_REGISTRY_CANDIDATE"}
	return {"candidates": out, "skip": false, "blocker_reason": ""}

## CRAFT：精确匹配 candidate.recipe_id；先做主观前提诊断（未知配方/能力不足/材料不足）
static func _match_craft(step: Dictionary, valid_actions: Array, ctx: Dictionary,
		catalog: RecipeCatalog) -> Dictionary:
	var rid := str(step.get("recipe_id", ""))
	if rid == "":
		return {"candidates": [], "skip": false, "blocker_reason": "MALFORMED_STEP"}
	if catalog == null or not catalog.has(rid):
		return {"candidates": [], "skip": false, "blocker_reason": "UNKNOWN_RECIPE"}
	if not (ctx.get("known_recipe_refs", []) as Array).has(rid):
		return {"candidates": [], "skip": false, "blocker_reason": "RECIPE_NOT_KNOWN"}
	var recipe: Dictionary = catalog.spec(rid)
	for cap in recipe.get("required_capabilities", []):
		if not (ctx.get("possessed_capabilities", []) as Array).has(str(cap)):
			return {"candidates": [], "skip": false, "blocker_reason": "MISSING_CAPABILITY_FOR_CRAFT"}
	if not InventoryOps.has_requirements(ctx.get("possessed_items", {}), recipe.get("ingredients", {})):
		return {"candidates": [], "skip": false, "blocker_reason": "MATERIALS_MISSING"}
	var out: Array = []
	for c in valid_actions:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		if str(c.get("action", "")) != str(recipe.get("compat_action", "")):
			continue
		# 精确匹配 recipe_id——不看输出物能力猜
		if str(c.get("recipe_id", "")) != rid:
			continue
		out.append(c)
	if out.is_empty():
		return {"candidates": [], "skip": false, "blocker_reason": "NO_REGISTRY_CANDIDATE"}
	return {"candidates": out, "skip": false, "blocker_reason": ""}

## MAIN：按步骤行动名匹配（planner 已把 via_rule 映射为 action_name）
static func _match_main(step: Dictionary, valid_actions: Array) -> Dictionary:
	var action_name := str(step.get("action_name", ""))
	if action_name == "":
		return {"candidates": [], "skip": false, "blocker_reason": "MALFORMED_STEP"}
	var out: Array = []
	for c in valid_actions:
		if typeof(c) == TYPE_DICTIONARY and str(c.get("action", "")) == action_name:
			out.append(c)
	if out.is_empty():
		return {"candidates": [], "skip": false, "blocker_reason": "NO_REGISTRY_CANDIDATE"}
	return {"candidates": out, "skip": false, "blocker_reason": ""}

## 步骤可执行性总检（tracker 决策前重查当前步骤前提用）
static func step_blocker(step: Dictionary, ctx: Dictionary,
		catalog: RecipeCatalog = null, items: ItemCatalog = null) -> String:
	return str(match_candidates(step, [], ctx, catalog, items).get("blocker_reason", ""))

static func _ctx_knows_source_of(item_id: String, ctx: Dictionary, items: ItemCatalog) -> bool:
	if items == null:
		return false
	var known_tags: Array = ctx.get("known_source_tags", [])
	for tag in items.tags_of(item_id):
		if known_tags.has(str(tag)):
			return true
	return false

## 候选目标 ∈ 该物品标签的主观已知来源 tile 集
static func _target_in_known_sources(candidate: Dictionary, item_id: String,
		ctx: Dictionary, items: ItemCatalog) -> bool:
	if items == null:
		return false
	var t = candidate.get("target", null)
	if typeof(t) != TYPE_VECTOR2I:
		return true  # 无地点目标的候选不受此约束
	var item_tags: Array = items.tags_of(item_id)
	for s in ctx.get("known_sources", []):
		var sd: Dictionary = s
		if not item_tags.has(str(sd.get("tag", ""))):
			continue
		if _tile_of_source_id(str(sd.get("source_id", ""))) == t:
			return true
	return false

## source_id "tree|3,4" → Vector2i(3, 4)
static func _tile_of_source_id(source_id: String) -> Vector2i:
	var idx := source_id.rfind("|")
	if idx < 0:
		return Vector2i(-1, -1)
	var parts := source_id.substr(idx + 1).split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0].strip_edges()), int(parts[1].strip_edges()))
