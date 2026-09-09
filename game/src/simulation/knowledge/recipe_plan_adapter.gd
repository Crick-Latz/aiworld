class_name RecipePlanAdapter
extends RefCounted
## P6.3B-0-R3 §三/§四——capability → recipe 数据驱动解析 + 确定性排序。
## knowledge 侧，经注入的 Catalog 工作。禁止硬编码物品名。
## R3：outputs/ingredients keys 排序后遍历；known_refs 去重排序。

## 查找能提供目标 capability 的已知配方（确定性）。
static func find_recipe_for_capability(capability: String, known_recipe_refs: Array,
		catalog: RecipeCatalog, items: ItemCatalog) -> Dictionary:
	# R3 §四：known_refs 去重排序
	var sorted_refs: Array = _sorted_unique_refs(known_recipe_refs)
	for rid in sorted_refs:
		var recipe: Dictionary = catalog.spec(str(rid))
		if recipe.is_empty():
			continue
		var outputs: Dictionary = recipe.get("outputs", {})
		# R3 §四：outputs keys 排序后遍历
		var out_keys: Array = outputs.keys()
		out_keys.sort()
		for out_item in out_keys:
			var caps: Array = items.capabilities_of(str(out_item))
			if caps.has(capability):
				return {
					"recipe_id": str(rid),
					"output_item": str(out_item),
					"ingredients": (recipe.get("ingredients", {}) as Dictionary).duplicate(),
					"capability": capability,
				}
	return {}

## 材料缺口 = required - possessed（R3 §四：ingredients keys 排序）。
static func missing_ingredients(ingredients: Dictionary, possessed_items: Dictionary) -> Dictionary:
	var out := {}
	var ing_keys: Array = ingredients.keys()
	ing_keys.sort()
	for item_id in ing_keys:
		var required := int(ingredients[item_id])
		var have := int(possessed_items.get(str(item_id), 0))
		var gap := required - have
		if gap > 0:
			out[str(item_id)] = gap
	return out

## 检查材料是否有主观来源。
static func has_source_for(item_id: String, known_source_tags: Array, items: ItemCatalog) -> bool:
	var tags: Array = items.tags_of(item_id)
	for tag in tags:
		if known_source_tags.has(str(tag)):
			return true
	return false

## 构建结构化 blocker（R3 §三：不从字符串恢复语义）
static func make_blocker(reason_code: String, item_id: String, capability: String,
		quantity: int, knowledge_refs: Array = [], belief_refs: Array = []) -> Dictionary:
	return {
		"reason_code": reason_code,
		"item_id": item_id,
		"capability": capability,
		"quantity": quantity,
		"knowledge_refs": PlanStepSpec._sorted_unique(knowledge_refs),
		"belief_refs": PlanStepSpec._sorted_unique(belief_refs),
	}

## R4 §二：blocker 验证——固定字段 + reason-specific invariant
static func validate_blocker(b: Variant) -> bool:
	if typeof(b) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = b
	for f in ["reason_code", "item_id", "capability", "quantity", "knowledge_refs", "belief_refs"]:
		if not d.has(f):
			return false
	if typeof(d["reason_code"]) != TYPE_STRING or str(d["reason_code"]) == "":
		return false
	if typeof(d["item_id"]) != TYPE_STRING:
		return false
	if typeof(d["capability"]) != TYPE_STRING:
		return false
	if typeof(d["quantity"]) != TYPE_INT or int(d["quantity"]) < 0:
		return false
	for rk in ["knowledge_refs", "belief_refs"]:
		var rv: Variant = d[rk]
		if typeof(rv) != TYPE_ARRAY:
			return false
		for v in (rv as Array):
			if typeof(v) != TYPE_STRING or str(v) == "":
				return false
	var rc := str(d["reason_code"])
	match rc:
		"UNKNOWN_RECIPE":
			return str(d["item_id"]) == "" and str(d["capability"]) != "" and int(d["quantity"]) == 0
		"UNKNOWN_SOURCE":
			return str(d["item_id"]) != "" and str(d["capability"]) == "" and int(d["quantity"]) > 0
		"MISSING_CAPABILITY":
			return str(d["item_id"]) == "" and str(d["capability"]) != "" and int(d["quantity"]) == 0
		"INVALID_PLAN_STEPS":
			return str(d["item_id"]) == "" and str(d["capability"]) == "" and int(d["quantity"]) == 0
	return false

static func _sorted_unique_refs(arr: Array) -> Array:
	var seen := {}
	var out: Array = []
	for v in arr:
		if typeof(v) != TYPE_STRING or str(v) == "":
			continue
		if not seen.has(str(v)):
			seen[str(v)] = true
			out.append(str(v))
	out.sort()
	return out
