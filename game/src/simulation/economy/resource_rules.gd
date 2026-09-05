class_name ResourceRules
extends RefCounted
## 物品与资源规则（OBS-02，M07）：库存、转移校验与执行、工作消耗。
## 只做纯校验/提案，不直接写状态——由 StorySimulation 统一提交。

# 转移前置校验：返回 {ok, code, message}。amount 必须是正整数（Variant 防御）。
static func validate_transfer(actors: Dictionary, from_id: String, to_id: String,
		item: String, amount, max_range: int) -> Dictionary:
	if typeof(amount) != TYPE_INT or amount <= 0:
		return {"ok": false, "code": "E_COMMAND_FORBIDDEN", "message": "数量必须是正整数"}
	if not (actors.has(from_id) and actors.has(to_id)):
		return {"ok": false, "code": "E_REFERENCE_BROKEN", "message": "交易方不存在"}
	if not item.is_valid_identifier() and item.find(" ") >= 0:
		return {"ok": false, "code": "E_COMMAND_FORBIDDEN", "message": "物品 ID 非法"}
	var from_a: Dictionary = actors[from_id]
	var to_a: Dictionary = actors[to_id]
	var have: int = int(from_a["inventory"].get(item, 0))
	if have < amount:
		return {"ok": false, "code": "E_PRECONDITION", "message": "库存不足（有 %d 要 %d）" % [have, amount]}
	var d := _manhattan(from_a["tile"], to_a["tile"])
	if d > max_range:
		return {"ok": false, "code": "E_PRECONDITION", "message": "距离 %d 超出交互范围 %d" % [d, max_range]}
	return {"ok": true, "code": "OK", "message": ""}

# 执行转移（调用方已完成全部校验与幂等检查）
static func apply_transfer(actors: Dictionary, from_id: String, to_id: String, item: String, amount: int) -> void:
	var from_inv: Dictionary = actors[from_id]["inventory"]
	var to_inv: Dictionary = actors[to_id]["inventory"]
	from_inv[item] = int(from_inv.get(item, 0)) - amount
	to_inv[item] = int(to_inv.get(item, 0)) + amount

# 工作前置：执行者在目标 POI 交互范围内且持有足额材料
static func validate_work(actor: Dictionary, poi_tile: Vector2i, item: String, needed: int, max_range: int) -> Dictionary:
	var d := _manhattan(actor["tile"], poi_tile)
	if d > max_range:
		return {"ok": false, "code": "E_PRECONDITION", "message": "不在工作地点范围内（距离 %d）" % d}
	var have: int = int(actor["inventory"].get(item, 0))
	if have < needed:
		return {"ok": false, "code": "E_PRECONDITION", "message": "材料不足（有 %d 需 %d）" % [have, needed]}
	return {"ok": true, "code": "OK", "message": ""}

static func consume(actor: Dictionary, item: String, amount: int) -> void:
	var inv: Dictionary = actor["inventory"]
	inv[item] = int(inv.get(item, 0)) - amount

static func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)
