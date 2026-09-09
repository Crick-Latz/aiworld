class_name PlanStepSpec
extends RefCounted
## P6.3B-0-R1 §四——PlanStep 契约：13 字段全验证 + kind 不变量。
## description 仅显示——执行判断不得读取或解析。
## PlanStep 不读取 WorldState/GeneratedMap/他人真实库存。
## step_id 在同一 plan 内唯一且确定；乱序输入产生同一结果。

const KINDS := ["ACQUIRE", "CRAFT", "MAIN", "SUBGOAL", "USE"]
const STATUSES := ["PENDING", "INERT_UNTIL_P6_3B_1"]
const FIELDS := ["step_id", "kind", "status", "action_name", "item_id", "quantity",
	"recipe_id", "capability", "requires", "provides", "knowledge_refs", "belief_refs", "description"]

## 验证全部 13 个字段存在且类型精确（R1 §四）
static func validate(step: Variant) -> bool:
	if typeof(step) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = step
	# 全字段存在性
	for f in FIELDS:
		if not d.has(f):
			return false
	# 类型精确
	if typeof(d["step_id"]) != TYPE_STRING or str(d["step_id"]) == "":
		return false
	if typeof(d["kind"]) != TYPE_STRING or not KINDS.has(str(d["kind"])):
		return false
	if typeof(d["status"]) != TYPE_STRING or not STATUSES.has(str(d["status"])):
		return false
	if typeof(d["action_name"]) != TYPE_STRING:
		return false
	if typeof(d["item_id"]) != TYPE_STRING:
		return false
	if typeof(d["quantity"]) != TYPE_INT or int(d["quantity"]) < 0:
		return false
	if typeof(d["recipe_id"]) != TYPE_STRING:
		return false
	if typeof(d["capability"]) != TYPE_STRING:
		return false
	if typeof(d["description"]) != TYPE_STRING:
		return false
	# 四个 refs 数组：每个元素必须是非空 String（不用 str() 伪装）
	for refs_key in ["requires", "provides", "knowledge_refs", "belief_refs"]:
		var refs: Variant = d[refs_key]
		if typeof(refs) != TYPE_ARRAY:
			return false
		for v in (refs as Array):
			if typeof(v) != TYPE_STRING or str(v) == "":
				return false
	# kind-specific invariants（R1 §四）
	var kind := str(d["kind"])
	match kind:
		"ACQUIRE":
			if str(d["item_id"]) == "" or int(d["quantity"]) <= 0:
				return false
		"CRAFT":
			if str(d["recipe_id"]) == "" or int(d["quantity"]) <= 0 or str(d["capability"]) == "":
				return false
		"MAIN":
			if str(d["action_name"]) == "":
				return false
		"SUBGOAL":
			var has_any := str(d["item_id"]) != "" or str(d["capability"]) != "" or str(d["action_name"]) != ""
			if not has_any:
				return false
		"USE":
			if str(d["capability"]) == "":
				return false
	return true

## 构建规范化 PlanStep（字段类型固定、refs 去重排序）
static func make(kind: String, step_id: String, status: String = "PENDING",
		action_name: String = "", item_id: String = "", quantity: int = 0,
		recipe_id: String = "", capability: String = "",
		requires: Array = [], provides: Array = [],
		knowledge_refs: Array = [], belief_refs: Array = [],
		description: String = "") -> Dictionary:
	return {
		"step_id": step_id,
		"kind": kind,
		"status": status,
		"action_name": action_name,
		"item_id": item_id,
		"quantity": quantity,
		"recipe_id": recipe_id,
		"capability": capability,
		"requires": _sorted_unique(requires),
		"provides": _sorted_unique(provides),
		"knowledge_refs": _sorted_unique(knowledge_refs),
		"belief_refs": _sorted_unique(belief_refs),
		"description": description,
	}

## 确定性 step_id：kind + 关键标识字段
static func step_id_for(kind: String, key_field: String = "", key_value: String = "") -> String:
	if key_value == "":
		return kind + ":0"
	return kind + ":" + key_field + ":" + key_value

## 验证整个 plan 的所有步骤：全部 validate + step_id 唯一。任一失败返回 false。
static func validate_plan_steps(steps: Array) -> bool:
	var seen := {}
	for st in steps:
		if not validate(st):
			return false
		var sid := str((st as Dictionary).get("step_id", ""))
		if seen.has(sid):
			return false
		seen[sid] = true
	return true

static func _sorted_unique(arr: Array) -> Array:
	var seen := {}
	var out: Array = []
	for v in arr:
		if typeof(v) != TYPE_STRING:
			continue
		var s := str(v)
		if s != "" and not seen.has(s):
			seen[s] = true
			out.append(s)
	out.sort()
	return out
