class_name SocialSystem
extends RefCounted
## 社会提案协议：一次社交互动 = 两次独立决策 + 两次独立预测。
##   提议者：基于需求 + ToM（"他应该有食物"）发起，预期效用经 ActionForecaster 计算
##   目标：  库存 + 信任 + 人格 + 个人/命令性规范 + 预测的社会成本/收益 独立回应
## 本类只做纯评估，不改世界状态——效果应用在 IslandSimulation 层（保持模块边界）。
## P1.5：目标决策时产出 reactions_forecast（预测），由模拟层记录并事后验证（预测误差学习）。

const MIN_FOOD_TO_SPARE := 2  # 少于 2 份时"分享"就威胁自身生存

## 目标评估是否接受食物请求。
## 返回 { accepted, weight, reason, reactions_forecast }
static func evaluate_food_request(target: Dictionary, proposer: Dictionary, trust_toward_proposer: int, rng: RandomNumberGenerator) -> Dictionary:
	var inv_food := int(target.get("inventory", {}).get("food", 0))
	var p: PersonalityProfile = target.get("personality", null)
	var proposer_id := str(proposer.get("id", ""))
	if p == null:
		return {"accepted": false, "weight": 0.0, "reason": "……", "reactions_forecast": {}}
	# 预测他的反应（记录下来，24 tick 后对照实际 → 修正响应模型）
	var forecast := ActionForecaster.forecast_reactions(target, proposer_id)
	if inv_food < MIN_FOOD_TO_SPARE:
		return {"accepted": false, "weight": 0.0, "reason": "自己也不够吃", "reactions_forecast": forecast}

	var needs: Dictionary = target.get("needs", {})
	var altruism := p.effective_trait("altruism", needs)
	var empathy := p.effective_trait("empathy", needs)
	var own_hunger := clampf(float(needs.get("hunger", 0)) / 1000.0, 0.0, 1.0)
	var trust_f := clampf(float(trust_toward_proposer) / 400.0, -1.0, 1.0)

	# ToM：目标对提议者的"可靠"认知
	var tom: TheoryOfMind = target.get("tom", null)
	var reliable := 0.0
	if tom != null:
		reliable = tom.belief_about(proposer_id, "reliable")

	# 一阶心智：看得见的苦处才打动人
	var proposer_hunger := clampf(float(proposer.get("needs", {}).get("hunger", 0)) / 1000.0, 0.0, 1.0)
	var visible_need := proposer_hunger * empathy

	# 规范三层：personal（我该分享）+ injunctive（大家会谴责自私）
	var norms: Dictionary = target.get("norms", {})
	var personal: Dictionary = norms.get("personal", norms)  # 旧扁平格式兼容
	var sharing_norm: float = float(personal.get("sharing", 0.5))
	var self_reliance_norm: float = float(personal.get("self_reliance", 0.5))
	var injunctive: float = float(norms.get("injunctive", {}).get("sharing", 0.5))

	# 预测后果的社会权衡（P1.5 第二刀）：拒绝的预期社会成本 / 接受的预期收益
	var refusal_cost := ActionForecaster.refusal_social_cost(target, p, proposer_id)
	var accept_gain := ActionForecaster.acceptance_social_gain(target, proposer_id)

	var weight := 0.25 + altruism * 0.35 + empathy * 0.1 + trust_f * 0.25 + reliable * 0.1 \
		+ visible_need * 0.3 - own_hunger * 0.55 \
		+ sharing_norm * 0.2 + injunctive * 0.1 - self_reliance_norm * 0.12 \
		+ accept_gain * 0.25 - refusal_cost * 0.35

	# 受限理性：不是硬阈值，带噪声的倾向
	var roll := rng.randf()
	var accepted := roll < clampf(weight, 0.0, 0.95)
	var reason := ""
	if accepted:
		reason = "看他还挺惨的" if visible_need > 0.3 else "反正还有富余"
	else:
		if trust_f < -0.3:
			reason = "不想惯着他"
		elif own_hunger > 0.6:
			reason = "自己也快饿晕了"
		else:
			reason = "犹豫了一下还是收回了手"
	return {"accepted": accepted, "weight": clampf(weight, -1.0, 1.0), "reason": reason, "reactions_forecast": forecast}

## 提议者挑选请求目标：ToM"他应该有食物" + 信任过滤 + 回避倾向过滤。
static func pick_request_target(proposer: Dictionary, nearby_infos: Array, trust_of: Dictionary) -> String:
	var tom: TheoryOfMind = proposer.get("tom", null)
	if tom == null or nearby_infos.is_empty():
		return ""
	var stance: Dictionary = proposer.get("social_stance", {})
	var best_id := ""
	var best_score := 0.1
	for o in nearby_infos:
		var oid := str(o.get("id", ""))
		if oid == "":
			continue
		var t := int(trust_of.get(oid, 0))
		if t <= RelationshipStore.TRUST_THRESHOLD_LOW:
			continue
		if float(stance.get(oid, 0.0)) > 0.6:
			continue  # 我已倾向回避此人，饿死也不求他（解释系统写入的倾向）
		var has_food := tom.raw_belief(oid, "has_food")  # 挑目标看证据方向；把握程度进预测器
		var trust_f := clampf(float(t) / 400.0, -1.0, 1.0)
		var score := has_food * 0.65 + trust_f * 0.35
		if score > best_score:
			best_score = score
			best_id = oid
	return best_id
