class_name AppraisalSystem
extends RefCounted
## 情绪评价系统（FAtiMA 式）：情绪不是随机 buff，是角色对事件
## 与自身目标关系的评价结果。
##
## P1.5 职责收缩：本类只负责 (1) 非社会事件的通用评价向量 (2) 向量→情绪的转换。
## 社会事件（请求/拒绝/接受/分享）的情境化评价与解释已移入 CognitiveTransition——
## 因为它们必须经过"我当时知道什么、以为什么"的主观化步骤。
##
## Appraisal Vector: goal_congruence / expectedness / controllability / agency / norm_violation
## → anger / fear / joy / sadness / guilt

static func appraise(event: Dictionary, actor: Dictionary) -> Dictionary:
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return {}
	var type := str(event.get("type", ""))
	var appraisal := {
		"goal_congruence": 0.0,
		"expectedness": 0.0,
		"controllability": 0.5,
		"agency": str(event.get("actor_id", "")),
		"norm_violation": 0.0,
		"self_agency": str(event.get("actor_id", "")) == str(actor.get("id", "")),
	}

	match type:
		"weather_storm":
			appraisal["goal_congruence"] = -0.5
			appraisal["controllability"] = 0.0
			appraisal["expectedness"] = -0.4
		"explored_hurt":
			appraisal["goal_congruence"] = -0.7
			appraisal["controllability"] = 0.3
		"explored_found":
			appraisal["goal_congruence"] = 0.6
			appraisal["expectedness"] = -0.3
		"ruins_loot":
			appraisal["goal_congruence"] = 0.7
			appraisal["expectedness"] = -0.5
		"ruins_empty":
			appraisal["goal_congruence"] = -0.3
			appraisal["expectedness"] = -0.2
		"foraged", "fished":
			appraisal["goal_congruence"] = 0.5
			appraisal["expectedness"] = -0.2
		"foraged_empty", "fished_empty":
			appraisal["goal_congruence"] = -0.25
			appraisal["expectedness"] = -0.1
		"ate_food":
			appraisal["goal_congruence"] = 0.3
		"socialized":
			appraisal["goal_congruence"] = 0.4
		"shared_food":
			# 分享者自己的满足（受助者的评价在 Transition 的解释链里）
			appraisal["goal_congruence"] = 0.4 + float(p.traits.get("altruism", 0.5)) * 0.3

	# 性格修饰评价
	var empathy := p.effective_trait("empathy", {})
	appraisal["empathy_amplifier"] = empathy

	return appraisal

## 评价 → 情绪变化
static func appraisal_to_emotions(appraisal: Dictionary, personality: PersonalityProfile) -> Dictionary:
	var changes := {}
	var goal_cong: float = appraisal.get("goal_congruence", 0.0)
	var norm_violation: float = appraisal.get("norm_violation", 0.0)
	var expectedness: float = appraisal.get("expectedness", 0.0)
	var empathy: float = appraisal.get("empathy_amplifier", 0.5)

	if goal_cong > 0.3:
		changes["joy"] = goal_cong * 0.3 * (1.0 - expectedness)  # 意外的好事更开心
	if goal_cong < -0.3:
		changes["sadness"] = -goal_cong * 0.2
		if norm_violation > 0.3:
			changes["anger"] = norm_violation * 0.4 * (0.5 + empathy)  # 违反规范+高共情 → 愤怒
		if appraisal.get("controllability", 0.5) < 0.3:
			changes["fear"] = -goal_cong * 0.3  # 不可控的坏事 → 恐惧
	# 内疚：是我干的（self_agency）且违反了自己的规范 → 越有共情越自责
	if bool(appraisal.get("self_agency", false)) and norm_violation > 0.4 and goal_cong <= -0.2:
		changes["guilt"] = norm_violation * 0.3 * empathy

	return changes
