class_name RecipeCatalog
extends RefCounted
## P6.3A RecipeCatalog——配方规格的加载/验证/查询。
## 与 ItemCatalog 连接：ingredients/outputs 引用必须已注册（或同包先注册）。
## 与 KnowledgeRule 连接：knowledge_refs 引用世界包中的知识 id（缺失只警告不拒绝——
##   知识可后续加载；但 resolver 在运行时 fail-closed：ref 不在已知集即不可制作）。
## 验证：数量必须有限正整数；不允许空输出；重复 recipe_id 拒绝。

var recipes := {}        # recipe_id -> RecipeSpec
var rejected: Array = []
var _items: ItemCatalog
var _compat_index := {}  # compat_action -> recipe_id（唯一索引——重复在加载时拒绝）

func _init(items: ItemCatalog) -> void:
	_items = items

static func load_default(items: ItemCatalog) -> RecipeCatalog:
	var cat := RecipeCatalog.new(items)
	cat.load_file("res://data/items/recipes.json")
	return cat

func load_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("RecipeCatalog: missing " + path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_reject("bad_json", path)
		return
	var recipes_arr = parsed.get("recipes", [])
	if typeof(recipes_arr) != TYPE_ARRAY:
		_reject("recipes_not_array", str(path))
		return
	for spec in recipes_arr:
		_register(spec)

func _register(spec: Variant) -> void:
	if typeof(spec) != TYPE_DICTIONARY:
		_reject("not_dict", "?")
		return
	var rid := str(spec.get("recipe_id", ""))
	if rid == "":
		_reject("missing_id", "?")
		return
	if recipes.has(rid):
		_reject("duplicate_id", rid)
		return
	var ings: Variant = _valid_counts(spec.get("ingredients", {}), rid, "ingredient")
	if ings == null:
		return
	var outs: Variant = _valid_counts(spec.get("outputs", {}), rid, "output")
	if outs == null:
		return
	if (outs as Dictionary).is_empty():
		_reject("empty_outputs", rid)
		return
	var krefs = spec.get("knowledge_refs", [])
	if typeof(krefs) != TYPE_ARRAY:
		_reject("bad_knowledge_refs", rid)
		return
	for kref in krefs:
		if typeof(kref) != TYPE_STRING or str(kref) == "":
			_reject("bad_knowledge_ref_entry", rid)
			return
	var reqs = spec.get("required_capabilities", [])
	if typeof(reqs) != TYPE_ARRAY:
		_reject("bad_capabilities", rid)
		return
	for cap in reqs:
		if typeof(cap) != TYPE_STRING or not CapabilitySpec.has(str(cap)):
			_reject("unknown_capability", rid + ":" + str(cap))
			return
	var dur: Variant = spec.get("duration_ticks", 1)
	if typeof(dur) not in [TYPE_INT, TYPE_FLOAT] or float(dur) <= 0.0 or is_nan(float(dur)) or is_inf(float(dur)) or float(dur) != floorf(float(dur)):
		_reject("bad_duration", rid)
		return
	var compat := str(spec.get("compat_action", ""))
	if compat != "" and _compat_index.has(compat):
		_reject("duplicate_compat_action", compat)
		return
	if compat != "":
		_compat_index[compat] = rid
	recipes[rid] = {
		"recipe_id": rid,
		"knowledge_refs": (spec.get("knowledge_refs", []) as Array).duplicate(),
		"ingredients": ings,
		"outputs": outs,
		"required_capabilities": (reqs as Array).duplicate(),
		"duration_ticks": int(dur),
		"compat_action": compat,
	}

## 数量验证：有限正整数（JSON 整数/可整除浮点），且 item 引用存在
func _valid_counts(v: Variant, rid: String, kind: String) -> Variant:
	if typeof(v) != TYPE_DICTIONARY:
		_reject("bad_" + kind + "s", rid)
		return null
	var out := {}
	for item_id in v:
		if not _items.has(str(item_id)):
			_reject("unknown_item_ref", rid + ":" + str(item_id))
			return null
		var n = v[item_id]
		if typeof(n) not in [TYPE_INT, TYPE_FLOAT]:
			_reject("bad_count_type", rid + ":" + str(item_id))
			return null
		var fn := float(n)
		if is_nan(fn) or is_inf(fn) or fn <= 0.0 or fn != floorf(fn) or fn > 1e9:
			_reject("bad_count_value", rid + ":" + str(item_id))
			return null
		out[str(item_id)] = int(fn)
	return out

func has(recipe_id: String) -> bool:
	return recipes.has(recipe_id)

func spec(recipe_id: String) -> Dictionary:
	return recipes.get(recipe_id, {})

## 稳定排序的 recipe_id 列表（确定性）
func all_ids_sorted() -> Array:
	var ids: Array = recipes.keys()
	ids.sort()
	return ids

## compat action → recipe（迁移兼容：旧 action 名映射到通用 recipe_id）
func by_compat_action(action_name: String) -> Dictionary:
	# 唯一索引直查（不再 O(n) 无序遍历）
	var rid := str(_compat_index.get(action_name, ""))
	if rid != "":
		return recipes.get(rid, {})
	return {}

## 主要输出：item_id 稳定排序首个（不依赖 Dictionary 迭代序）
func primary_output(recipe: Dictionary) -> String:
	var outs: Array = (recipe.get("outputs", {}) as Dictionary).keys()
	if outs.is_empty():
		return ""
	outs.sort()
	return str(outs[0])

func _reject(reason: String, id: String) -> void:
	rejected.append({"reason": reason, "id": id})
