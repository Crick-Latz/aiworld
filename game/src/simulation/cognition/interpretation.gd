class_name Interpretation
extends RefCounted
## 解释竞争（P1.5 第六条）：事件不再自动得出唯一结论。
## "欧恩拒绝了我"产生多个候选解释（自私/他也快饿死/不信任我/储备应急/讨厌我），
## 权重由观察者的信念×心智模型×人格动力×当下情绪决定——
## 误会、偏见、纠正、重新理解由此才成为可能。
## 关键：解释分布整体保留为认知状态；主导解释只用于行为偏置，不是定论。

## 拒绝事件的候选解释。返回 {candidates: [{id,label,weight}...], dominant: id}
static func interpret_refusal(se: Dictionary, dyn: Dictionary) -> Dictionary:
	var ctx: Dictionary = se["context"]
	var believed_rich: float = ctx["believed_rich"]            # 我以为他粮多(+)/没粮(−)
	var believed_generous: float = ctx["believed_generous"]
	var trust_f: float = clampf(float(ctx["trust_toward_counterpart"]) / 400.0, -1.0, 1.0)
	var hostility: float = dyn["hostility_attribution_bias"]
	var scarcity_sal: float = dyn["scarcity_salience"]

	# 基础先验（均匀）× 认知证据调制；高共情者给人善意的怀疑（empathy 抑制敌意归因）
	var empathy_damp := 1.0 - float(dyn.get("empathy", 0.5)) * 0.3
	var w_selfish := 0.20 * (1.0 + maxf(0.0, believed_rich) * 1.4 + maxf(0.0, -believed_generous) * 0.8) * (1.0 + hostility * 0.8) * (1.0 - maxf(0.0, believed_generous) * 0.4) * empathy_damp
	var w_starving := 0.20 * (1.0 + maxf(0.0, -believed_rich) * 2.2 + (1.0 - hostility) * 0.3) * (1.0 + scarcity_sal * 0.3)
	var w_distrusts := 0.20 * (1.0 + maxf(0.0, -trust_f) * 1.6) * (1.0 + hostility * 0.5)
	var w_reserve := 0.20 * (1.0 + maxf(0.0, -believed_generous) * 0.4 + maxf(0.0, believed_generous) * 0.6) * (1.0 - hostility * 0.4)
	var w_dislikes := 0.20 * (1.0 + hostility * 1.2 + maxf(0.0, -trust_f) * 0.6)

	var cands := [
		{"id": "selfish", "motive": "SELF_INTEREST", "label": "他就是自私", "weight": w_selfish},
		{"id": "also_starving", "motive": "INCAPABLE", "label": "他自己也没粮", "weight": w_starving},
		{"id": "distrusts_me", "motive": "DISTRUST", "label": "他不信任我", "weight": w_distrusts},
		{"id": "saving_reserve", "motive": "SELF_PRESERVATION", "label": "他在为将来存粮", "weight": w_reserve},
		{"id": "dislikes_me", "motive": "DISLIKE", "label": "他讨厌我", "weight": w_dislikes},
	]
	return _normalize(cands, dyn)

## 接受/被帮助事件的候选解释
static func interpret_acceptance(se: Dictionary, dyn: Dictionary) -> Dictionary:
	var ctx: Dictionary = se["context"]
	var believed_generous: float = ctx["believed_generous"]
	var trust_f: float = clampf(float(ctx["trust_toward_counterpart"]) / 400.0, -1.0, 1.0)
	var hostility: float = dyn["hostility_attribution_bias"]

	var w_generous := 0.30 * (1.0 + maxf(0.0, believed_generous) * 1.2 + trust_f * 0.5) * (1.2 - hostility * 0.6)
	var w_pity: float = 0.25 * (1.0 + float(ctx["own_hunger"]) * 0.8) * (1.0 + hostility * 0.3)
	var w_expects_return := 0.25 * (1.0 + maxf(0.0, -trust_f) * 0.8 + hostility * 0.4)
	var w_genuine_bond := 0.20 * (1.0 + trust_f * 1.2) * (1.2 - hostility * 0.8)

	var cands := [
		{"id": "generous", "motive": "ALTRUISTIC", "label": "他心地慷慨", "weight": w_generous},
		{"id": "pities_me", "motive": "AFFECTION", "label": "他可怜我", "weight": w_pity},
		{"id": "expects_return", "motive": "STRATEGIC", "label": "他想要回报", "weight": w_expects_return},
		{"id": "genuine_bond", "motive": "AFFECTION", "label": "他真把我当同伴", "weight": w_genuine_bond},
	]
	return _normalize(cands, dyn)

## 归一化 + 低容忍者权重锐化（更早下结论），高容忍者保持平缓
static func _normalize(cands: Array, dyn: Dictionary) -> Dictionary:
	var total := 0.0
	var sharp := 1.0 + float(dyn.get("ambiguity_intolerance", 0.4)) * 1.5
	for c in cands:
		c["weight"] = pow(maxf(float(c["weight"]), 0.001), sharp)  # 锐化：拉大强弱差距
		total += float(c["weight"])
	for c in cands:
		c["weight"] = float(c["weight"]) / total
	var dominant := ""
	var best := -1.0
	for c in cands:
		if float(c["weight"]) > best:
			best = float(c["weight"])
			dominant = str(c["id"])
	return {"candidates": cands, "dominant": dominant}

## 解释分布的不确定度（归一化熵）：0=已下结论，1=完全不知道他为什么
## 这是「我不知道」的量化——认识行动的触发源
static func entropy(interp: Dictionary) -> float:
	if interp.is_empty():
		return 0.0
	var cands: Array = interp.get("candidates", [])
	if cands.size() <= 1:
		return 0.0
	var h := 0.0
	for c in cands:
		var w := float(c.get("weight", 0.0))
		if w > 0.0001:
			h -= w * log(w) / log(float(cands.size()))
	return clampf(h, 0.0, 1.0)

## 取某解释的权重（无则 0）
static func weight_of(interp: Dictionary, id: String) -> float:
	if interp.is_empty():
		return 0.0
	for c in interp.get("candidates", []):
		if str(c["id"]) == id:
			return float(c["weight"])
	return 0.0

## 敌意解释的合计权重（selfish + distrusts_me + dislikes_me）
static func hostility_weight(interp: Dictionary) -> float:
	return weight_of(interp, "selfish") + weight_of(interp, "distrusts_me") + weight_of(interp, "dislikes_me")
