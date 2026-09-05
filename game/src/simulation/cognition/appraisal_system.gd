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
		"self_agency": str(event.get("actor_id", "")) == str(actor.get("id", "")),
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
		# ── P1 社会事件：同一事件，不同角色评价不同 ──
		"food_request_refused":
			# P2: 规范决定拒绝的道德重量——"同伴就该分享"的人视拒绝为背叛；
			# "人得自立"的人觉得拒绝理所当然
			var norms_p: Dictionary = actor.get("norms", {})
			var sharing_p: float = float(norms_p.get("sharing", 0.5))
			var self_rel_p: float = float(norms_p.get("self_reliance", 0.5))
			# 被拒者：目标受阻 + 规范被违反的强度由自己的分享规范决定
			if str(event.get("proposer_id", "")) == str(actor.get("id", "")):
				appraisal["goal_congruence"] = -0.7
				appraisal["expectedness"] = -0.3
				appraisal["norm_violation"] = 0.2 + sharing_p * 0.6
				appraisal["controllability"] = 0.2
			# 拒绝者本人：分享规范高 → 内疚；自立规范高 → 理直气壮
			elif appraisal["self_agency"]:
				appraisal["goal_congruence"] = -0.2
				appraisal["norm_violation"] = 0.2 + sharing_p * 0.6 - self_rel_p * 0.3
		"food_request_accepted":
			# 求助成功者：如释重负
			if str(event.get("proposer_id", "")) == str(actor.get("id", "")):
				appraisal["goal_congruence"] = 0.7
				appraisal["expectedness"] = -0.4
			# 分享者：利他满足感
			elif appraisal["self_agency"]:
				appraisal["goal_congruence"] = 0.3 + float(p.traits.get("altruism", 0.5)) * 0.3
		"food_requested":
			# 有人向我开口：轻微的决策压力；自立规范高的人觉得被冒犯
			if str(event.get("target_id", "")) == str(actor.get("id", "")):
				var self_rel_t: float = float(actor.get("norms", {}).get("self_reliance", 0.5))
				appraisal["goal_congruence"] = -0.05 - self_rel_t * 0.15
				appraisal["controllability"] = 0.8

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
