class_name TemplateDialogueRenderer
extends RefCounted
## P3b-2 确定性台词模板（deterministic fallback）：
## 每个 SpeechAct 类型 → 固定模板句（带角色风格修饰）。
## 不是最终品质——是 LLM 不可用时的保底 + Text Invariance 测试的基线。

## 角色风格映射（从人格特质推导表面措辞，不影响语义）
static func render(speech_act: Dictionary, speaker_name: String, language: String = "zh", ec: Dictionary = {}) -> Dictionary:
	if speech_act.is_empty():
		return {"ok": false, "code": "E_ACT_EMPTY", "text": ""}
	var act := str(speech_act.get("act_type", ""))
	var tone: Dictionary = speech_act.get("emotional_tone", {})
	var express: float = float(tone.get("expressiveness", 0.5))
	var politeness: float = float(tone.get("politeness", 0.5))
	var anger: float = float(tone.get("anger", 0.0))
	# P3c-4：ExpressionContext 的 effective_profile 覆盖 tone（有 ec 时用合成值）
	var eff: Dictionary = ec.get("effective_profile", {})
	if not eff.is_empty():
		express = float(eff.get("emotional_openness", express))
		politeness = float(eff.get("politeness", politeness))
		var warmth: float = float(eff.get("warmth", 0.5))
		var guarded: float = float(eff.get("guardedness", 0.3))
		# warm → 更长的安慰语；guarded → 更短更硬
		if warmth > 0.6 and guarded < 0.3:
			politeness = maxf(politeness, 0.7)
		elif guarded > 0.6:
			politeness = minf(politeness, 0.3)
			express = minf(express, 0.2)
	var text := ""

	match act:
		"ASK_REASON":
			if anger >= 0.5:
				text = "你到底为什么？"
			elif not eff.is_empty() and float(eff.get("guardedness", 0.3)) > 0.6:
				text = "……为什么。"
			else:
				text = "你为什么这么做？"
		"ANSWER_REASON":
			text = "我自己也没多少了。" if express < 0.4 else "说实话，我自己也快不够吃了。"
		"DEFLECT":
			text = "……没什么好说的。"
		"REQUEST":
			text = "能分我一点吗？"
		"ACCEPT_REQUEST":
			text = "好，拿去吧。"
		"REFUSE_REQUEST":
			var reason := _first_prop(speech_act, "REFUSAL_REASON")
			if reason != "" and reason.find("不够") != -1:
				if politeness >= 0.6:
					text = "我也想帮你，可现在真的拿不出来。"
				elif eff.is_empty() and express < 0.4:
					text = "我自己也没多少了。"
				elif not eff.is_empty() and float(eff.get("warmth", 0.5)) > 0.6:
					text = "这次真不行。我欠你的，我记着。"
				else:
					text = "不行，我自己也不够吃。"
			else:
				text = "我不能答应。"
		"THANK":
			text = "谢谢。"
		"PROMISE":
			text = "这份情我记下，以后报答。"
		"REMIND_PROMISE":
			text = "你上次答应过我的。"
		"PROPOSE_RULE":
			text = "我提议：以后找到的%s，拿出一份放到公共储备。" % _resource_name(speech_act)
		"SUPPORT_RULE":
			text = "我同意。"
		"OPPOSE_RULE":
			text = "这个比例太高了，我反对。"
		"COUNTER_PROPOSE_RULE":
			text = "要不改少一点？"
		"CONFRONT":
			text = "约定呢？你怎么能这样？"
		"WARN":
			text = "别再这样了。"
		"REPORT_INFORMATION":
			text = "有件事你应该知道。"
		_:
			return {"ok": false, "code": "E_ACT_UNKNOWN", "text": ""}

	# P3c-3：AddressPolicy 称呼
	var addr := ""
	if ec.has("_target_name") and ec.has("_address_mode"):
		addr = SurfaceHistory.address_text(str(ec.get("_address_mode", "")), str(ec.get("_target_name", "")))
	var text_out := text
	if addr != "" and text.find("你") == -1:
		text_out = "%s，%s" % [addr, text.to_lower()]
	return {"ok": true, "text": "%s%s" % [speaker_name, text_out] if language == "zh" else text_out,
		"speech_id": str(speech_act.get("speech_id", "")),
		"claim_ids": _prop_claim_ids(speech_act),
		"renderer": "template-dialogue", "schema_version": "dialogue-output-1.0"}

static func _first_prop(sa: Dictionary, predicate: String) -> String:
	for p in sa.get("propositions", []):
		if str(p.get("predicate", "")) == predicate:
			return str(p.get("reason", ""))
	return ""

static func _resource_name(sa: Dictionary) -> String:
	for p in sa.get("propositions", []):
		if str(p.get("predicate", "")) == "PROPOSES_RULE":
			return str(p.get("object", "食物"))
	return "食物"

static func _prop_claim_ids(sa: Dictionary) -> Array:
	# 从 propositions 提取可引 id（第一版用 seq 做伪 claim id）
	var out: Array = []
	for p in sa.get("propositions", []):
		for ev in p.get("source_event_ids", []):
			out.append("PROP_E%d" % int(ev))
	return out
