class_name DecisionEngine
extends RefCounted
## 决策引擎（阶段 B，M06）：每 tick 从 ActionRegistry 获取所有可选行动，
## 按 Utility AI 效用评分选最高分执行。不做任何预设剧情。
## 决策结果 = 性格(PersonalityProfile) × 身体状态 × 情绪 × 需求 × 环境 × 认知
## 的综合效用计算——没有人告诉 NPC 该做什么，是它自己"想"做的。

static func decide(actor: Dictionary, world: Dictionary) -> Dictionary:
	var actions: Array = ActionRegistry.get_available_actions(actor, world)
	if actions.is_empty():
		return {"action": "wait", "target": null, "utility": 0.0, "desc": "无事可做"}

	# 评分并选最高
	var best: Dictionary = actions[0]
	for a in actions:
		if float(a.get("utility", 0.0)) > float(best.get("utility", 0.0)):
			best = a

	# 加入少量随机性（在合理选项间选择，不是随机剧情）
	# 取效用 > best * 0.8 的所有行动，从中随机选一个
	var candidates: Array = actions.filter(func(a): return float(a["utility"]) >= float(best["utility"]) * 0.8)
	if candidates.size() > 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(actor.get("id", "")) + str(world.get("tick", 0)))
		best = candidates[rng.randi_range(0, candidates.size() - 1)]

	return best
