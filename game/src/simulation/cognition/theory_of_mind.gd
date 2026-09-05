class_name TheoryOfMind
extends RefCounted
## 一阶心智理论（P1）：角色对其他角色的主观认知模型。
## 与 RelationshipStore（情感性信任）互补：ToM 是认知性的预测模型——
##   "欧恩有食物吗？"（资源推断，决定我向谁开口）
##   "欧恩慷慨吗？"（行为倾向，决定我预期被拒绝的概率）
##   "欧恩可靠吗？"（承诺兑现史，决定我是否信他的话）
## 全部是 -1..1 的置信信念，从亲眼观察更新——所以可能是错的。
## 信息是有成本的：只有目击者才更新（World Truth ≠ Character Belief）。

# other_id -> { "has_food": float, "generous": float, "reliable": float, "last_updated": int }
var _models := {}

func belief_about(other_id: String, key: String) -> float:
	if _models.has(other_id) and _models[other_id].has(key):
		return float(_models[other_id][key])
	return 0.0  # 未知 = 中性，不是善意也不是恶意

func update(other_id: String, key: String, delta: float, tick: int) -> void:
	if not _models.has(other_id):
		_models[other_id] = {"has_food": 0.0, "generous": 0.0, "reliable": 0.0, "last_updated": tick}
	var m: Dictionary = _models[other_id]
	m[key] = clampf(float(m.get(key, 0.0)) + delta, -1.0, 1.0)
	m["last_updated"] = tick

## 从目击事件更新模型。由模拟层在"目击者循环"里调用。
static func observe(tom: TheoryOfMind, event: Dictionary) -> void:
	if tom == null:
		return
	var type := str(event.get("type", ""))
	var who := str(event.get("actor_id", ""))
	if who == "":
		return  # 世界事件（天气等）没有主体
	var tick := int(event.get("tick", 0))
	match type:
		"foraged", "fished", "ruins_loot", "explored_found":
			tom.update(who, "has_food", 0.35, tick)
		"foraged_empty", "fished_empty", "ruins_empty":
			tom.update(who, "has_food", -0.15, tick)
		"shared_food":
			tom.update(who, "generous", 0.4, tick)
			tom.update(who, "has_food", -0.2, tick)
		"food_request_accepted":
			tom.update(who, "generous", 0.2, tick)
			tom.update(who, "reliable", 0.2, tick)
			tom.update(who, "has_food", -0.2, tick)
		"food_request_refused":
			tom.update(who, "generous", -0.35, tick)
			tom.update(who, "reliable", -0.1, tick)

## 信念随时间衰减（旧印象淡忘，回到中性）
func decay(before_tick: int, fade_days: int) -> void:
	for other_id in _models:
		var m: Dictionary = _models[other_id]
		if int(m["last_updated"]) < before_tick - fade_days * 24:
			for key in ["has_food", "generous", "reliable"]:
				m[key] = float(m[key]) * 0.98
				if absf(float(m[key])) < 0.02:
					m[key] = 0.0

func model_of(other_id: String) -> Dictionary:
	if _models.has(other_id):
		return _models[other_id].duplicate()
	return {"has_food": 0.0, "generous": 0.0, "reliable": 0.0, "last_updated": -1}

func snapshot() -> Dictionary:
	return _models.duplicate(true)
