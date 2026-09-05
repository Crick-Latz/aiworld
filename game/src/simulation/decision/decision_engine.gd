class_name DecisionEngine
extends RefCounted
## 决策引擎 v2（阶段 C）：
##   1. Intention persistence（BDI：不每 tick 重新做人）
##   2. Softmax 随机选择（受限理性，不是永远选最大）
##   3. DecisionTrace（每次行动记录原因，观察者可回答"他为什么这么做"）
##   4. 人格控制的 τ（谨慎的人行为稳定，冲动的人行为难预测）

static func decide(actor: Dictionary, world: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var intentions: IntentionManager = actor.get("intentions", null)
	var p: PersonalityProfile = actor.get("personality", null)
	var tick: int = world.get("tick", 0)

	# 如果有正在执行的意图，先检查是否应该继续
	if intentions != null and intentions.has_intention():
		var current_util := float(intentions.current_intention.get("utility", 0.0))
		# 意图执行中：小概率重新评估（模拟"想一想是不是该换"）
		if rng.randf() > 0.15:
			intentions.reinforce()
			return intentions.current_intention

	# 重新评估：获取所有可选行动
	var actions: Array = ActionRegistry.get_available_actions(actor, world)
	if actions.is_empty():
		return {"action": "wait", "target": null, "utility": 0.0, "desc": "观察周围"}

	# Softmax 选择（受限理性）
	var tau := _compute_tau(p, actor)
	var chosen: Dictionary = _softmax_select(actions, tau, rng)

	# 记录 DecisionTrace
	var trace := {
		"actor_id": str(actor.get("id", "")),
		"tick": tick,
		"selected": str(chosen.get("action", "")),
		"top_candidates": {},
		"reason": _generate_reason(chosen, actor, world),
	}
	for a in actions:
		trace["top_candidates"][str(a["action"])] = float(a["utility"])
	actor["last_decision_trace"] = trace

	# 设置意图
	if intentions != null:
		intentions.set_intention(chosen, tick)

	return chosen

## τ 计算：谨慎/韧性高 → τ 低（行为稳定）；冲动/疲劳/情绪混乱 → τ 高（行为难预测）
static func _compute_tau(p: PersonalityProfile, actor: Dictionary) -> float:
	var base := 0.15
	var caution: float = p.traits.get("caution", 0.5)
	var resilience: float = p.traits.get("resilience", 0.5)
	base -= caution * 0.05
	base -= resilience * 0.03
	# 疲劳增加冲动
	var energy: float = float(actor.get("needs", {}).get("energy", 1000)) / 1000.0
	if energy < 0.3:
		base += (0.3 - energy) * 0.3
	# 情绪混乱增加 τ
	var fear: float = p.emotions.get("fear", 0.0)
	var anger: float = p.emotions.get("anger", 0.0)
	base += fear * 0.1 + anger * 0.1
	return maxf(base, 0.05)  # τ 最低 0.05，确保不是完全确定

## Softmax 选择：不是永远选效用最高的，是按概率选
static func _softmax_select(actions: Array, tau: float, rng: RandomNumberGenerator) -> Dictionary:
	var utils: Array = []
	for a in actions:
		utils.append(float(a.get("utility", 0.0)))
	# 计算 softmax 概率
	var max_u := 0.0
	for u in utils:
		max_u = maxf(max_u, u)
	var probs: Array = []
	var sum := 0.0
	for u in utils:
		var p := exp((u - max_u) / tau)
		probs.append(p)
		sum += p
	# 归一化
	for i in probs.size():
		probs[i] /= sum
	# 按概率选择
	var roll := rng.randf()
	var cumul := 0.0
	for i in probs.size():
		cumul += float(probs[i])
		if roll <= cumul:
			return actions[i]
	return actions[actions.size() - 1]

## 生成人类可读的决策原因
static func _generate_reason(action: Dictionary, actor: Dictionary, world: Dictionary) -> String:
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return "未知原因"
	var action_name := str(action.get("action", ""))
	var needs: Dictionary = actor.get("needs", {})
	var emotions: Dictionary = p.emotions

	var reasons: Array = []
	var hunger: float = float(needs.get("hunger", 0)) / 1000.0
	if hunger > 0.6:
		reasons.append("非常饥饿")
	var energy: float = float(needs.get("energy", 1000)) / 1000.0
	if energy < 0.3:
		reasons.append("很疲惫")
	if emotions.get("fear", 0.0) > 0.5:
		reasons.append("感到恐惧")
	if emotions.get("anger", 0.0) > 0.5:
		reasons.append("正在愤怒")
	if reasons.is_empty():
		reasons.append("基于当前需求和个人倾向")
	return str(action.get("desc", action_name)) + "（" + "、".join(reasons) + "）"
