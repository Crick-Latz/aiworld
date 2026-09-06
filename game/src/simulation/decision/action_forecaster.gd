class_name ActionForecaster
extends RefCounted
## 行动预测器（P1.5 第二刀）：决策从"评价动作本身"改为"评价自己预测的后果"。
## 所有预测只使用行动者自己的信念/心智模型（可能错）——
## 预测错误是一切社会学习的原料：误判 → 反馈 → 修正。

## 求助者预测：我向他开口，被接受的概率多大？
## 基于 ToM：我以为他慷慨吗？我以为他有粮吗？（都不是真的——是我以为）
static func forecast_request(actor: Dictionary, target_id: String) -> Dictionary:
	var tom: TheoryOfMind = actor.get("tom", null)
	var believed_generous := 0.0
	var believed_rich := 0.0
	if tom != null:
		believed_generous = tom.belief_about(target_id, "generous")
		believed_rich = tom.belief_about(target_id, "has_food")
	var trust_f: float = clampf(float((actor.get("trust_of", {}) as Dictionary).get(target_id, 0)) / 400.0, -1.0, 1.0)
	var accept_p := clampf(0.25 + maxf(0.0, believed_generous) * 0.45 + maxf(0.0, believed_rich) * 0.25 + trust_f * 0.15, 0.05, 0.9)
	return {"accept_prob": accept_p, "refuse_prob": 1.0 - accept_p}

## 求助的期望效用：接受→缓解饥饿；被拒→白开口（窘迫+预期中的敌意解读）
static func request_expected_utility(actor: Dictionary, p: PersonalityProfile, hunger_norm: float, target_id: String) -> float:
	var f := forecast_request(actor, target_id)
	var gain := UtilityCurves.quadratic(hunger_norm) * float(f["accept_prob"]) * 2.2
	# 预期被拒的成本：窘迫 + 若我已倾向往坏处解释他，被拒更痛
	var dyn := PersonalityDynamics.dynamics(p, actor.get("sensitivities", {}), actor.get("norms", {}))
	var refuse_cost := 0.04 + float(dyn["hostility_attribution_bias"]) * 0.1
	var cost := refuse_cost * float(f["refuse_prob"])
	return gain - cost

## 目标视角（我准备拒绝/接受时）：预测他会怎么反应。
## 基于我的响应模型（历史预测误差修正过的），初始 0.5 = 我不确定。
static func forecast_reactions(decider: Dictionary, proposer_id: String) -> Dictionary:
	var tom: TheoryOfMind = decider.get("tom", null)
	if tom == null:
		return {}
	return {
		"asks_me_again": tom.response_belief(proposer_id, "asks_me_again"),
		"asks_other": tom.response_belief(proposer_id, "asks_other"),
		"avoids_me": tom.response_belief(proposer_id, "avoids_me"),
		"shares_with_me": tom.response_belief(proposer_id, "shares_with_me"),
	}

## 拒绝的预期社会成本：他若回避我/记恨 → 我失去一个潜在合作者。
## 社交性强/怕冲突的人对此更敏感；相信"他会理解"的人成本更低。
static func refusal_social_cost(decider: Dictionary, p: PersonalityProfile, proposer_id: String) -> float:
	var reactions := forecast_reactions(decider, proposer_id)
	var sociability := p.effective_trait("sociability", decider.get("needs", {}))
	var conflict_avoid := p.effective_trait("conflict_avoidance", decider.get("needs", {}))
	# 他回避我的概率 × 我在乎关系的程度 + 他不再找我 × 社交需求
	var cost := float(reactions.get("avoids_me", 0.5)) * (0.3 + conflict_avoid * 0.4)
	cost += float(reactions.get("asks_other", 0.5)) * sociability * 0.2
	return cost  # 0..~0.9

## 接受的预期收益：他感激 → 未来互惠（我相信他会回报吗？）
static func acceptance_social_gain(decider: Dictionary, proposer_id: String) -> float:
	var reactions := forecast_reactions(decider, proposer_id)
	return float(reactions.get("shares_with_me", 0.5)) * 0.5 + float(reactions.get("asks_me_again", 0.5)) * 0.15
