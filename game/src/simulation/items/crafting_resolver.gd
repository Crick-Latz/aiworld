class_name CraftingResolver
extends RefCounted
## P6.3A CraftingResolver——主观视角的制作候选生成。
## 输入：NPC 已知 knowledge_refs（主观）+ 自己的 inventory + 自己的 capabilities + RecipeCatalog。
## 不读取：未观察世界资源、他人真实库存、上帝视角知识、他人 LifeHistory/ToM。
## fail-closed：配方 knowledge_refs 未全部在已知集 → 不产生候选（材料足够也不行）。
## 确定性：输出按 recipe_id 排序。

## 返回候选数组：[{recipe_id, compat_action, duration_ticks, missing(空——能制作才返回), outputs}]
static func craft_candidates(inv: Dictionary, known_recipe_refs: Array, capabilities: Array,
		catalog: RecipeCatalog, items: ItemCatalog) -> Array:
	var out: Array = []
	for rid in catalog.all_ids_sorted():
		var recipe: Dictionary = catalog.spec(str(rid))
		# 1) 知识门：known_recipe_refs 元素是 recipe_id
		#（known_recipe_refs() 已在世界包层核对过其全部 knowledge_refs）
		if not known_recipe_refs.has(str(rid)):
			continue
		# 2) 能力门：配方要求的制作能力
		var caps_ok := true
		for cap in recipe.get("required_capabilities", []):
			if not capabilities.has(str(cap)):
				caps_ok = false
				break
		if not caps_ok:
			continue
		# 3) 材料门
		if not InventoryOps.has_requirements(inv, recipe.get("ingredients", {})):
			continue
		out.append({
			"recipe_id": str(rid),
			"compat_action": str(recipe.get("compat_action", "")),
			"duration_ticks": int(recipe.get("duration_ticks", 1)),
			"outputs": (recipe.get("outputs", {}) as Dictionary).duplicate(),
		})
	return out

## 诊断版（不产生候选，返回缺失原因——L/K/M 门用）
static func diagnose(inv: Dictionary, known_recipe_refs: Array, capabilities: Array,
		catalog: RecipeCatalog) -> Dictionary:
	var out := {}
	for rid in catalog.all_ids_sorted():
		var recipe2: Dictionary = catalog.spec(str(rid))
		var miss: Array = []
		if not known_recipe_refs.has(str(rid)):
			miss.append("knowledge:recipe_unknown")
		for cap in recipe2.get("required_capabilities", []):
			if not capabilities.has(str(cap)):
				miss.append("capability:" + str(cap))
		var ings: Dictionary = recipe2.get("ingredients", {})
		for item_id in ings:
			var have := int(inv.get(str(item_id), 0))
			var need := int(ings[item_id])
			if have < need:
				miss.append("material:" + str(item_id) + "(" + str(have) + "/" + str(need) + ")")
		miss.sort()
		out[str(rid)] = {"craftable": miss.is_empty(), "missing": miss}
	return out
