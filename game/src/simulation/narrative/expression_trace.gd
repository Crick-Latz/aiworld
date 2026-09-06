class_name ExpressionTrace
extends RefCounted
## P3c-2 表达留痕 + 声音指纹：
##   ExpressionTrace——"为什么这句话听起来是这样"（与 DecisionTrace"为什么做这件事"平行，两条链分开）
##   VoiceFingerprint——结构化声音参数快照（不是从文本 NLP 反推，是 Renderer 的输入参数）
## 两者都只做 READ——不记录 LLM chain-of-thought，只记录结构化影响因素。

static func build(speech_act: Dictionary, ec: Dictionary) -> Dictionary:
	return {
		"speech_id": str(speech_act.get("speech_id", "")),
		"act_type": str(speech_act.get("act_type", "")),
		"identity_anchor": ec.get("identity_anchor", {}),
		"adaptive_factors": ec.get("adaptive_register", {}),
		"moment_factors": ec.get("moment_state", {}),
		"expression_mode": str(ec.get("expression_mode", "FAST")),
		"effective_profile": ec.get("effective_profile", {}),
		"allowed_claim_predicates": ec.get("semantic_bounds", {}).get("allowed_claim_predicates", []),
		"tick": int(speech_act.get("tick", 0)),
	}

## VoiceFingerprint：6 维度结构化声音快照（用于 Observer drill-down / 防回归监控）
static func voice_fingerprint(ec: Dictionary) -> Dictionary:
	var eff: Dictionary = ec.get("effective_profile", {})
	return {
		"directness": float(eff.get("directness", 0.5)),
		"expressiveness": float(eff.get("emotional_openness", 0.5)),
		"verbosity": float(eff.get("verbosity", 0.5)),
		"politeness": float(eff.get("politeness", 0.5)),
		"guardedness": float(eff.get("guardedness", 0.5)),
		"warmth": float(eff.get("warmth", 0.5)),
	}

## 防回归指标（第 47 条）：anchor deviation / context adaptation delta
static func anchor_deviation(anchor: Dictionary, effective: Dictionary) -> float:
	## Identity Anchor 与 Effective Profile 的偏差（0=完全稳定，1=完全被 context 覆盖）
	var max_dev := 0.0
	var pairs := {"base_directness": "directness", "base_expressiveness": "emotional_openness",
		"base_politeness": "politeness", "base_verbosity": "verbosity", "base_guardedness": "guardedness"}
	for a_key in pairs:
		var e_key := str(pairs[a_key])
		if anchor.has(a_key) and effective.has(e_key):
			max_dev = maxf(max_dev, absf(float(anchor[a_key]) - float(effective[e_key])))
	return max_dev

static func context_adaptation_delta(ec_trusted: Dictionary, ec_feared: Dictionary) -> float:
	## 同一说话者对不同目标的表达差异（非零=有适应能力）
	var t: Dictionary = ec_trusted.get("effective_profile", {})
	var f: Dictionary = ec_feared.get("effective_profile", {})
	var max_delta := 0.0
	for key in ["warmth", "guardedness", "politeness"]:
		if t.has(key) and f.has(key):
			max_delta = maxf(max_delta, absf(float(t[key]) - float(f[key])))
	return max_delta
