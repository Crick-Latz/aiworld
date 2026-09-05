class_name AppraisalSystem
extends RefCounted
## 情绪评价系统（阶段 C，FAtiMA）：情绪不是随机 buff，是角色对事件
## 与自身目标关系的评价结果。同一事件，不同角色产生不同情绪。
##
## Appraisal Vector: goal_congruence / expectedness / controllability / agency / norm_violation
## → 产生 anger / fear / joy / sadness / guilt
##
## 例：薇拉发现欧恩藏食物
##   goal_congruence = -0.8（威胁"合作"目标）
##   expectedness = -0.6（出乎意料）
##   agency = "npc_oun"（欧恩干的）
##   norm_violation = 0.9（违反"应该分享"的规范）
##   → anger ↑↑, trust(欧恩) ↓
## 但卡德加评价同一事件：
##   goal_congruence = -0.6（也威胁"团结"但反应较轻）
##   conflict_avoidance = high
##   → 不当众指责，选择私聊

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
	}

	# 事件类型 → 评价维度
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
		"shared_food":
			appraisal["goal_congruence"] = 0.5 + float(p.traits.get("altruism", 0.5)) * 0.3
		"ruins_loot":
			appraisal["goal_congruence"] = 0.7
			appraisal["expectedness"] = -0.5
		"ruins_empty":
			appraisal["goal_congruence"] = -0.3
			appraisal["expectedness"] = -0.2

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

	return changes
