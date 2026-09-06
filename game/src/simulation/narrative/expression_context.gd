class_name ExpressionContextBuilder
extends RefCounted
## P3c-1 三时间尺度表达上下文（Long-horizon Expression & Character Continuity）：
##   L — Long-term Identity Anchor  ："这个人通常怎么说话"（PersonalityProfile/LifeHistory/SelfIdentity）
##   M — Mid-term Adaptive Register ："他最近和这个人相处成什么样"（关系轨迹/义务/承诺/角色）
##   S — Short-term Moment State    ："他现在为什么这么说"（情绪/需求/当前 SpeechAct）
##
## 全部 READ-ONLY 从冻结认知层派生——Dialogue 不写回 cognition。
## History influences register, NOT propositions（第 9 条）：
##   过去冲突 → 更冷淡/更简短/更防御——但不自动新增"你上次也拒绝过我"。
##   要翻旧账必须由 cognition 真正产生 REMIND_PAST_EVENT SpeechAct。

## ── L：Identity Anchor ──
static func identity_anchor(speaker: Dictionary) -> Dictionary:
	var p: PersonalityProfile = speaker.get("personality", null)
	if p == null:
		return {}
	var t: Dictionary = p.traits
	return {
		"base_directness": _n(t.get("action_bias", 0.5)),
		"base_expressiveness": _n(t.get("expressiveness", 0.5)),
		"base_politeness": _n(t.get("conflict_avoidance", 0.5)),
		"base_verbosity": _n(t.get("sociability", 0.5)),
		"base_formality": _n(t.get("caution", 0.5)),
		"base_guardedness": _n(1.0 - float(t.get("expressiveness", 0.5))),
	}

## ── M：Adaptive Register（actor-target 特定，从现有关系派生）──
static func adaptive_register(speaker: Dictionary, target_id: String, relationships, tick: int) -> Dictionary:
	if relationships == null or target_id == "":
		return {}
	var speaker_id := str(speaker.get("id", ""))
	var trust := clampf(float(relationships.composite_trust(speaker_id, target_id)) / 800.0, -1.0, 1.0)
	var bene := clampf(float(relationships.get_dim(speaker_id, target_id, "benevolence")) / 800.0, -1.0, 1.0)
	var oblig := clampf(float(relationships.get_dim(speaker_id, target_id, "obligation")) / 800.0, 0.0, 1.0)
	var fear := clampf(float(relationships.get_dim(speaker_id, target_id, "fear")) / 800.0, 0.0, 1.0)
	var stance := clampf(float(speaker.get("social_stance", {}).get(target_id, 0.0)), 0.0, 1.0)
	# ToM"他慷慨吗"影响语气（对信任的人更放松）
	var believed_generous := 0.0
	var tom: TheoryOfMind = speaker.get("tom", null)
	if tom != null:
		believed_generous = tom.belief_about(target_id, "generous")
	return {
		"warmth": clampf(0.5 + bene * 0.4 + believed_generous * 0.1, 0.0, 1.0),
		"guardedness": clampf(0.3 + fear * 0.4 + stance * 0.3 - bene * 0.2, 0.0, 1.0),
		"obligation_weight": oblig,
		"trust_level": clampf(0.5 + trust * 0.5, 0.0, 1.0),
	}

## ── S：Moment State ──
static func moment_state(speaker: Dictionary, speech_act: Dictionary) -> Dictionary:
	var p: PersonalityProfile = speaker.get("personality", null)
	var needs: Dictionary = speaker.get("needs", {})
	var urgency := clampf(float(needs.get("hunger", 0)) / 1000.0, 0.0, 1.0)
	var anger := 0.0
	var sadness := 0.0
	if p != null:
		anger = clampf(float(p.emotions.get("anger", 0.0)), 0.0, 1.0)
		sadness = clampf(float(p.emotions.get("sadness", 0.0)), 0.0, 1.0)
	var act := str(speech_act.get("act_type", ""))
	return {
		"anger": anger,
		"sadness": sadness,
		"urgency": urgency,
		"is_high_stakes": _is_high_stakes(act),
	}

static func _is_high_stakes(act: String) -> bool:
	return ["PROMISE", "CONFRONT", "PROPOSE_RULE", "COUNTER_PROPOSE_RULE",
		"OPPOSE_RULE", "ACCEPT_REQUEST", "REFUSE_REQUEST"].has(act)

## ── 合成：Effective Expression Profile ──
## Effective = Identity Anchor + Mid-term Adaptation + Moment Modifier（全确定性）
static func effective_profile(anchor: Dictionary, adaptive: Dictionary, moment: Dictionary) -> Dictionary:
	var d_base: float = anchor.get("base_directness", 0.5)
	var e_base: float = anchor.get("base_expressiveness", 0.5)
	var p_base: float = anchor.get("base_politeness", 0.5)
	var v_base: float = anchor.get("base_verbosity", 0.5)
	var g_base: float = anchor.get("base_guardedness", 0.5)

	var warmth: float = adaptive.get("warmth", 0.5)
	var guarded: float = adaptive.get("guardedness", 0.3)
	var oblig: float = adaptive.get("obligation_weight", 0.0)
	var trust: float = adaptive.get("trust_level", 0.5)

	var anger: float = moment.get("anger", 0.0)
	var urgency: float = moment.get("urgency", 0.0)

	return {
		"directness": clampf(d_base + anger * 0.2 - urgency * 0.1, 0.0, 1.0),
		"warmth": clampf(warmth + oblig * 0.15 - anger * 0.3, 0.0, 1.0),
		"guardedness": clampf(g_base * 0.5 + guarded * 0.5, 0.0, 1.0),
		"politeness": clampf(p_base + trust * 0.15 - anger * 0.2, 0.0, 1.0),
		"verbosity": clampf(v_base - urgency * 0.3 + e_base * 0.2, 0.0, 1.0),
		"emotional_openness": clampf(e_base * 0.6 + (1.0 - g_base) * 0.2 - guarded * 0.2, 0.0, 1.0),
		"hesitation": clampf(g_base * 0.4 + (1.0 - trust) * 0.3, 0.0, 1.0),
	}

## ── Semantic Bounds（第 8 条：跟 ExpressionContext 一起走）──
static func semantic_bounds(speech_act: Dictionary, ir_claims: Array) -> Dictionary:
	var allowed: Array = []
	for p in speech_act.get("propositions", []):
		allowed.append(str(p.get("predicate", "")))
	return {
		"allowed_claim_predicates": allowed,
		"forbidden": [
			"不得添加 SpeechAct 命题之外的事实性内容",
			"不得引用未经系统批准的过去事件",
			"不得添加新承诺/威胁/因果断言",
		],
	}

## ── FAST/SLOW Expression Mode（第 16-19 条）──
static func expression_mode(speech_act: Dictionary) -> String:
	var act := str(speech_act.get("act_type", ""))
	# SLOW：高意义言语
	if _is_high_stakes(act):
		return "SLOW"
	var tone: Dictionary = speech_act.get("emotional_tone", {})
	if float(tone.get("anger", 0.0)) > 0.5:
		return "SLOW"
	return "FAST"

## ── 完整构建 ──
static func build(speaker: Dictionary, target_id: String, speech_act: Dictionary, relationships, tick: int) -> Dictionary:
	var anchor := identity_anchor(speaker)
	var adaptive := adaptive_register(speaker, target_id, relationships, tick)
	var moment := moment_state(speaker, speech_act)
	var effective := effective_profile(anchor, adaptive, moment)
	var mode := expression_mode(speech_act)
	return {
		"identity_anchor": anchor,
		"adaptive_register": adaptive,
		"moment_state": moment,
		"effective_profile": effective,
		"expression_mode": mode,
		"semantic_bounds": semantic_bounds(speech_act, []),
	}

static func _n(v) -> float:
	return clampf(float(v), 0.0, 1.0)
