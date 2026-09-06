class_name Claim
extends RefCounted
## 声明 ≠ 事实（P1.6 第 14 条）：NPC 说的话只是证据源之一。
## 听者按 说话者可靠度 × 先验一致性 加权更新信念，绝不直接采信为真相。
## 这是以后谣言/欺骗/宣传/秘密的地基。

## 构造一条结构化声明。proposition = {subject, predicate, value(-1..1), label}
static func build(speaker_id: String, proposition: Dictionary, tick: int) -> Dictionary:
	return {
		"speaker": speaker_id,
		"proposition": {
			"subject": str(proposition.get("subject", speaker_id)),
			"predicate": str(proposition.get("predicate", "")),
			"value": clampf(float(proposition.get("value", 0.0)), -1.0, 1.0),
			"label": str(proposition.get("label", "")),
		},
		"tick": tick,
		"sincerity_unknown": true,  # 听者不知道说话者是否诚实
	}

## 听者处理声明：返回 {weight, updates}；同时归档到听者的 claims_received。
## weight 由 说话者可靠度(ToM reliable) + 关系信任 + 表达清晰度 决定。
static func listen(listener: Dictionary, claim: Dictionary, relationships) -> Dictionary:
	var speaker := str(claim.get("speaker", ""))
	var tom: TheoryOfMind = listener.get("tom", null)
	var prop: Dictionary = claim.get("proposition", {})
	if tom == null or speaker == "" or str(prop.get("predicate", "")) == "":
		return {"weight": 0.0, "updates": {}}

	# 可靠度：无证据时给中性偏低的默认（陌生人的话打七折起步）
	var reliability := 0.3
	var r_belief: float = tom.belief_about(speaker, "reliable")
	if absf(r_belief) > 0.05:
		reliability = clampf(0.3 + r_belief * 0.5, 0.05, 0.95)
	# 关系信任加成
	var trust_f := 0.0
	if relationships != null:
		trust_f = clampf(float(relationships.composite_trust(str(listener.get("id", "")), speaker)) / 400.0, -1.0, 1.0)
	# 说话者表达能力（说不清楚的话可信度打折）
	var speaker_express := 0.5
	if listener.has("display_names"):
		pass  # 表达力在生成侧用；此处简化
	var weight := clampf(0.2 + reliability * 0.5 + trust_f * 0.25, 0.05, 0.9)

	# 按权重写入 ToM（subject 可能是说话者自己，也可能是第三人）
	var subject := str(prop.get("subject", speaker))
	var predicate := str(prop.get("predicate", ""))
	var value: float = float(prop.get("value", 0.0))
	if predicate != "":
		tom.add_evidence(subject, predicate, 1.0 if value >= 0.0 else -1.0, absf(value) * weight, -1, int(claim.get("tick", 0)))
	# 归档：听者记得「谁说过什么」——未来反证时可回溯
	var claims: Array = listener.get("claims_received", [])
	claims.append({"speaker": speaker, "proposition": prop.duplicate(), "tick": int(claim.get("tick", 0)), "weight": weight})
	if claims.size() > 12:
		claims.pop_front()
	listener["claims_received"] = claims
	return {"weight": weight, "updates": {"subject": subject, "predicate": predicate, "weight": weight}}
