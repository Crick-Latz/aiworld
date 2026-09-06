class_name PersonalityDynamics
extends RefCounted
## 人格动力（P1.5 第九条）：性格不再直接控制行为倍率，
## 而是控制认知更新过程——证据改变信念的速度、情绪起落的速度、
## 信任形成与崩塌的速度、敌意归因的倾向、反刍与承诺的强度。
##
## 同一事件落在不同动力参数的人身上，"学到的东西"不同——
## 这比"愤怒数值不同"深一层。

static func dynamics(p: PersonalityProfile, sensitivities: Dictionary, norms: Dictionary) -> Dictionary:
	var t: Dictionary = p.traits
	var em: Dictionary = p.emotions
	var betrayal_sens: float = float(sensitivities.get("betrayal_sensitivity", 0.0))
	var scarcity_sens: float = float(sensitivities.get("food_loss_sensitivity", 0.0))
	var trust_open: float = float(em.get("trust_open", 0.5))
	var anger: float = float(em.get("anger", 0.0))

	return {
		"empathy": float(t.get("empathy", 0.5)),
		# 负面证据改变信念的速度：多疑/被背叛过/正愤怒的人学得快
		"betrayal_learning_rate": clampf(0.25 + (1.0 - trust_open) * 0.35 + betrayal_sens * 0.3 + anger * 0.15, 0.1, 1.0),
		# 正面证据改变信念的速度：高共情者更愿意相信善意
		"positive_learning_rate": clampf(0.2 + float(t.get("empathy", 0.5)) * 0.3 + trust_open * 0.2, 0.1, 1.0),
		# 宽恕：韧性强的人负面信念衰减快
		"forgiveness_rate": clampf(0.04 + float(t.get("resilience", 0.5)) * 0.1, 0.02, 0.3),
		# 敌意归因偏置：愤怒 + 低信任开放度 + 被背叛史 → 更容易把事往坏处解释
		"hostility_attribution_bias": clampf(anger * 0.35 + (1.0 - trust_open) * 0.25 + betrayal_sens * 0.3 + (1.0 - float(t.get("empathy", 0.5))) * 0.15, 0.0, 1.0),
		# 情绪上升/消退速率：表达力高的人情绪起伏大，韧性强的人消退快
		"emotion_rise": clampf(0.7 + float(t.get("expressiveness", 0.5)) * 0.6, 0.5, 1.6),
		"emotion_fade": clampf(0.8 + float(t.get("resilience", 0.5)) * 0.6, 0.5, 1.6),
		# 反刍：低韧性+高悲伤的人会反复咀嚼旧账（反思时旧记忆权重高）
		"rumination": clampf(0.3 + (1.0 - float(t.get("resilience", 0.5))) * 0.4 + float(em.get("sadness", 0.0)) * 0.3, 0.1, 1.0),
		# 承诺强度：意图坚持度（DecisionEngine 的 continue 概率）
		"commitment_strength": clampf(0.7 + float(t.get("pragmatism", 0.5)) * 0.2 + float(t.get("caution", 0.5)) * 0.15, 0.5, 1.0),
		# 规范自义性：个人规范被现实打击后反而更坚持（"正因他自私，我更要分享"）
		"norm_reactance": clampf(0.3 + (1.0 - float(t.get("pragmatism", 0.5))) * 0.4 + trust_open * 0.2, 0.1, 1.0),
		# 匮乏敏感（来自人生经历）：对食物证据的注意放大
		"scarcity_salience": clampf(0.3 + scarcity_sens * 0.6, 0.1, 1.0),
		# P1.6 认识驱动：好奇+反刍的人想弄清楚；务实的人不在乎为什么
		"epistemic_drive": clampf(0.15 + float(t.get("curiosity", 0.5)) * 0.5 + float(t.get("expressiveness", 0.5)) * 0.15 + betrayal_sens * 0.25 + (1.0 - trust_open) * 0.15, 0.05, 1.0),  # 好奇+多疑都驱动认识
		# 不确定容忍：务实+高冲突回避的人能忍受「不知道」
		"uncertainty_tolerance": clampf(float(t.get("pragmatism", 0.5)) * 0.5 + float(t.get("conflict_avoidance", 0.5)) * 0.3, 0.1, 1.0),
		# 不确定性容忍：低容忍的人解释权重更极端（更早下结论）
		"ambiguity_intolerance": clampf(0.4 + float(t.get("caution", 0.5)) * 0.3 + anger * 0.2, 0.1, 1.0),
	}
