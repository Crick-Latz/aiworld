class_name SocialSystem
extends RefCounted
## 社会提案协议（P1）：一次社交互动 = 两次独立决策。
##   提议者：基于自己的需求 + 对目标的 ToM 信念（"他应该有食物"）发起请求
##   目标：  基于自己的库存 + 对提议者的信任/ToM + 人格（利他/共情/自身饥饿）回应
## 拒绝不是"失败"，是戏剧的开始：拒绝 → 提议者愤怒/悲伤 → 信任下降
## → 下次不再找他 → 关系裂痕。接受则相反。没有任何剧本，全是各自立场的涌现。
##
## 本类只做纯评估，不改世界状态——效果应用在 IslandSimulation 层（保持模块边界）。

const MIN_FOOD_TO_SPARE := 2  # 少于 2 份时"分享"就威胁自身生存

## 目标评估是否接受食物请求。
## 返回 { accepted: bool, weight: float, reason: String }
## weight 是接受倾向（0..1 概率化前的值），reason 供 DecisionTrace/事件文案用。
static func evaluate_food_request(target: Dictionary, proposer: Dictionary, trust_toward_proposer: int, rng: RandomNumberGenerator) -> Dictionary:
	var inv_food := int(target.get("inventory", {}).get("food", 0))
	if inv_food < MIN_FOOD_TO_SPARE:
		return {"accepted": false, "weight": 0.0, "reason": "自己也不够吃"}
	var p: PersonalityProfile = target.get("personality", null)
	if p == null:
		return {"accepted": false, "weight": 0.0, "reason": "……"}

	var needs: Dictionary = target.get("needs", {})
	var altruism := p.effective_trait("altruism", needs)
	var empathy := p.effective_trait("empathy", needs)
	var own_hunger := clampf(float(needs.get("hunger", 0)) / 1000.0, 0.0, 1.0)
	var trust_f := clampf(float(trust_toward_proposer) / 400.0, -1.0, 1.0)

	# ToM：目标对提议者的"可靠"认知（他是不是蹭吃蹭喝的人）
	var tom: TheoryOfMind = target.get("tom", null)
	var reliable := 0.0
	if tom != null:
		reliable = tom.belief_about(str(proposer.get("id", "")), "reliable")

	# 一阶心智：如果目标看得见提议者真的很饿（需求字段在场），共情放大
	var proposer_hunger := clampf(float(proposer.get("needs", {}).get("hunger", 0)) / 1000.0, 0.0, 1.0)
	var visible_need := proposer_hunger * empathy  # 看得见的苦处才打动人

	# P2: 内化规范——"同伴该分享"的人拒绝时过不了自己那关；
	# "人得自立"的人觉得纵容乞食反而是害他
	var norms: Dictionary = target.get("norms", {})
	var sharing_norm: float = float(norms.get("sharing", 0.5))
	var self_reliance_norm: float = float(norms.get("self_reliance", 0.5))

	var weight := 0.25 + altruism * 0.4 + empathy * 0.1 + trust_f * 0.3 + reliable * 0.15 \
		+ visible_need * 0.3 - own_hunger * 0.6 \
		+ sharing_norm * 0.25 - self_reliance_norm * 0.15

	# 受限理性：不是硬阈值，带噪声的倾向（同一处境不同 roll 可能不同回应）
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
	return {"accepted": accepted, "weight": clampf(weight, -1.0, 1.0), "reason": reason}

## 提议者挑选请求目标：ToM"他应该有食物" + 信任过滤。
## 返回 target_id 或 ""（没人值得开口）。
static func pick_request_target(proposer: Dictionary, nearby_infos: Array, trust_of: Dictionary) -> String:
	var tom: TheoryOfMind = proposer.get("tom", null)
	if tom == null or nearby_infos.is_empty():
		return ""
	var best_id := ""
	var best_score := 0.1  # 低于这个值不值得开口
	for o in nearby_infos:
		var oid := str(o.get("id", ""))
		if oid == "":
			continue
		var t := int(trust_of.get(oid, 0))
		if t <= RelationshipStore.TRUST_THRESHOLD_LOW:
			continue  # 深度不信任的人，饿死也不求他（除非……这是 P2 的钩子）
		var has_food := tom.belief_about(oid, "has_food")
		var trust_f := clampf(float(t) / 400.0, -1.0, 1.0)
		var score := has_food * 0.65 + trust_f * 0.35
		if score > best_score:
			best_score = score
			best_id = oid
	return best_id
