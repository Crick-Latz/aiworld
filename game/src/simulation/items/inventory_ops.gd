class_name InventoryOps
extends RefCounted
## P6.3A InventoryOps——纯函数库存事务。
## 原子性：材料不足/输出无效时库存完全不变；成功时一次性提交输入与输出。
## canonical：字典插入顺序不影响 hash 与比较（Gate J）。

## 归一化：去掉 ≤0 项，int 化
static func normalize(inv: Dictionary) -> Dictionary:
	var out := {}
	for k in inv:
		var n = inv[k]
		if typeof(n) in [TYPE_INT, TYPE_FLOAT] and int(n) > 0:
			out[str(k)] = int(n)
	return out

## 材料需求检查（requirements: item_id -> 正整数）
static func has_requirements(inv: Dictionary, requirements: Dictionary) -> bool:
	for item_id in requirements:
		var need := int(requirements[item_id])
		if int(inv.get(str(item_id), 0)) < need:
			return false
	return true

## 预览事务（不改变库存）：成功返回 {ok:true, result}，失败 {ok:false, reason}
static func preview_transaction(inv: Dictionary, ingredients: Dictionary, outputs: Dictionary, catalog: ItemCatalog) -> Dictionary:
	var norm := normalize(inv)
	if not has_requirements(norm, ingredients):
		return {"ok": false, "reason": "INSUFFICIENT_MATERIALS"}
	for item_id in outputs:
		if not catalog.has(str(item_id)):
			return {"ok": false, "reason": "UNKNOWN_OUTPUT_ITEM"}
	# P6.3A-R1：保留未触及键的原类型（不 normalize 全表——旧代码只改特定键，float 值保留）
	var result := inv.duplicate()
	for item_id in ingredients:
		result[str(item_id)] = int(inv.get(str(item_id), 0)) - int(ingredients[item_id])
		if int(result[str(item_id)]) <= 0:
			result.erase(str(item_id))
	for item_id in outputs:
		result[str(item_id)] = int(result.get(str(item_id), 0)) + int(outputs[item_id])
	return {"ok": true, "result": result}

## 执行事务：失败时原库存逐位不变（原子）；成功时提交
static func consume_and_grant(inv: Dictionary, recipe: Dictionary, catalog: ItemCatalog) -> Dictionary:
	var pv := preview_transaction(inv, recipe.get("ingredients", {}), recipe.get("outputs", {}), catalog)
	if not bool(pv.get("ok", false)):
		return {"ok": false, "reason": pv.get("reason", "?"), "inventory": inv}
	return {"ok": true, "inventory": pv["result"],
		"consumed_items": (recipe.get("ingredients", {}) as Dictionary).duplicate(),
		"produced_items": (recipe.get("outputs", {}) as Dictionary).duplicate()}

## 稳定 canonical（key 排序——与插入顺序无关）
static func canonical_hash(inv: Dictionary) -> String:
	var norm := normalize(inv)
	var keys: Array = norm.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append(str(k) + "=" + str(int(norm[k])))
	return str(hash(",".join(parts)))

## 库存能力派生：持有物品实际提供的能力（唯一权威路径）
static func capabilities_of_inventory(inv: Dictionary, catalog: ItemCatalog) -> Array:
	var out: Array = []
	var norm := normalize(inv)
	for item_id in norm:
		for cap in catalog.capabilities_of(str(item_id)):
			if not out.has(str(cap)):
				out.append(str(cap))
	out.sort()
	return out

## 库存标签派生（AgencyContextBuilder 用）
static func tags_of_inventory(inv: Dictionary, catalog: ItemCatalog) -> Array:
	var out: Array = []
	var norm := normalize(inv)
	for item_id in norm:
		for tag in catalog.tags_of(str(item_id)):
			if not out.has(str(tag)):
				out.append(str(tag))
	out.sort()
	return out
