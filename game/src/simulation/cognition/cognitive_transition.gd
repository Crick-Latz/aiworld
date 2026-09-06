class_name CognitiveTransition
extends RefCounted
## 认知转移管线（P1.5 第三条）——人物状态变化的统一入口。
##
##   ObjectiveEvent → Perception(目击过滤在模拟层)
##     → SubjectiveEvent（我当时知道什么/以为什么）
##     → Memory Retrieval（相关旧记忆）
##     → Appraisal（情境化评价向量）
##     → Interpretation（多解释竞争，权重由信念×动力×情绪决定）
##     → Belief Update（证据累积，可被削弱）
##     → Emotion Update（由评价向量产生，速率由人格动力控制）
##     → Relationship Update（由解释权重决定维度增量，非固定数值）
##     → Goal/Intention Update（敌意主导→回避倾向；温暖主导→接近倾向）
##
## 禁止任何事件绕过本管线直接修改人物状态。

# 拒绝/接受/请求/分享/社交化 走完整解释链；其余事件走证据+评价
const FULL_INTERP_TYPES := ["food_request_refused", "food_request_accepted", "food_requested", "shared_food"]

static func process(observer: Dictionary, event: Dictionary, ctx: Dictionary) -> Dictionary:
	var me := str(observer.get("id", ""))
	var type := str(event.get("type", ""))
	var tick := int(event.get("tick", 0))
	var seq := int(event.get("seq", 0))
	var relationships = ctx.get("relationships", null)
	var p: PersonalityProfile = observer.get("personality", null)
	if p == null:
		return {}

	# 1-2. 主观事件 + 记忆检索（与对手方相关的最近记忆）
	var se := SubjectiveEvent.build(observer, event, relationships)
	var retrieved := _retrieve_memories(observer, str(se["counterpart_id"]), type)

	# 3. 人格动力（控制更新速率）
	var dyn := PersonalityDynamics.dynamics(p, observer.get("sensitivities", {}), observer.get("norms", {}))

	var summary := {"type": type, "seq": seq, "tick": tick, "counterpart": se["counterpart_id"],
		"retrieved_count": retrieved.size(), "interpretation": {}, "emotion_changes": {},
		"relationship_delta": {}, "belief_updates": {}}

	# 4-6. 解释（完整链类型）或直接评价
	var appraisal := {}
	var interp := {}
	var role := str(se["role"])
	if type == "food_request_refused" and role == "proposer":
		interp = Interpretation.interpret_refusal(se, dyn)
		appraisal = _appraisal_my_refusal(se, interp)
	elif type == "food_request_refused" and role == "actor":
		appraisal = _appraisal_my_refusing(observer, dyn)  # 我拒绝了别人：规范自检
	elif (type == "food_request_accepted" and role == "proposer") or (type == "shared_food" and role == "recipient"):
		interp = Interpretation.interpret_acceptance(se, dyn)
		appraisal = _appraisal_received_help(se, interp)
	else:
		appraisal = AppraisalSystem.appraise(event, observer)  # 非社交/第三方目击：沿用通用评价
	se["interpretation"] = interp
	summary["interpretation"] = interp

	# 7. 情绪：评价向量 → 情绪增量 × 上升速率（人格动力）
	var changes: Dictionary = AppraisalSystem.appraisal_to_emotions(appraisal, p)
	for key in changes:
		var v := float(changes[key]) * float(dyn["emotion_rise"])
		p.adjust_emotion(key, v)
		summary["emotion_changes"][key] = v

	# 8. 信念更新：证据累积（解释加权），替换旧固定增量
	var belief_updates := _update_beliefs(observer, se, interp, dyn, seq, tick)
	# P1.6 注意力：正在观察此人时，证据权重×1.5（观察是有收获的）
	var watching: String = str((observer.get("observing", {}) as Dictionary).get("about", ""))
	if watching != "" and watching == str(se["counterpart_id"]):
		for key in belief_updates:
			belief_updates[key] = float(belief_updates[key]) * 1.5
	summary["belief_updates"] = belief_updates

	# 9. 关系更新：由解释权重决定，四维分立，无固定常数
	var rel_delta := _update_relationships(observer, se, interp, dyn, relationships)
	summary["relationship_delta"] = rel_delta

	# 10. 描述性规范更新：目击他人分享/拒绝 → "这里的人通常……"（个人规范不动）
	_update_descriptive_norms(observer, event, se)

	# 11. 目标/倾向更新：敌意主导 → 回避；温暖主导 → 接近
	_update_social_stance(observer, se, interp, dyn)

	# P1.6 认识问题：解释不确定度高 + 事关重大 → 角色意识到「我不知道为什么」
	if not interp.is_empty() and Interpretation.entropy(interp) > 0.72:
		var stakes := clampf(float(se["context"]["own_hunger"]) * 0.6 + 0.35, 0.0, 1.0)
		if stakes > 0.45:
			_open_question(observer, se, interp, stakes, tick)

	# 12. 主观记忆写入（带解释，供反思用）
	_write_memory(observer, event, se, interp, appraisal)

	observer["last_transition"] = summary
	return summary

# ── 评价向量构造（情境化：同样的拒绝，认知背景不同向量不同）──

## 我（proposer）被拒：以为他粮多+高分享规范 → 背叛感(norm_violation↑期望落差↑)；
## 以为他也没粮 → 理解（norm_violation↓expectedness↑goal_congruence 缓和）
static func _appraisal_my_refusal(se: Dictionary, interp: Dictionary) -> Dictionary:
	var ctx: Dictionary = se["context"]
	var believed_rich: float = ctx["believed_rich"]
	var hunger: float = ctx["own_hunger"]
	var personal_sharing: float = ctx["personal_sharing"]
	var hostility_w: float = Interpretation.hostility_weight(interp)
	var shortage_w: float = Interpretation.weight_of(interp, "also_starving")

	var v := {
		"goal_congruence": 0.0, "expectedness": 0.0, "controllability": 0.2,
		"agency": se["counterpart_id"], "norm_violation": 0.0,
		"self_agency": false,
	}
	# 目标受阻：饿得越狠，打击越大
	v["goal_congruence"] = -(0.35 + hunger * 0.45)
	# 规范违反感：我以为他粮多 + 我认为人该分享 → 他的拒绝是对我价值观的冒犯
	v["norm_violation"] = clampf(maxf(0.0, believed_rich) * (0.3 + personal_sharing * 0.6) + hostility_w * 0.3, 0.0, 1.0)
	# 意料之外：我以为他粮多且慷慨 → 拒绝出乎意料；以为他没粮 → 意料之中
	v["expectedness"] = clampf(maxf(0.0, -believed_rich) * 0.8 + shortage_w * 0.5, -1.0, 0.5)
	return v

## 我拒绝了别人：规范自检（内疚来源）。个人分享规范高 → 自责；自立规范高 → 理直气壮
static func _appraisal_my_refusing(observer: Dictionary, dyn: Dictionary) -> Dictionary:
	var personal: Dictionary = (observer.get("norms", {}) as Dictionary).get("personal", {})
	var sharing: float = float(personal.get("sharing", 0.5))
	var self_rel: float = float(personal.get("self_reliance", 0.5))
	return {
		"goal_congruence": -0.25,
		"expectedness": 0.0,
		"controllability": 0.9,
		"agency": str(observer.get("id", "")),
		"norm_violation": clampf(0.1 + sharing * 0.6 - self_rel * 0.35, 0.0, 1.0),
		"self_agency": true,
	}

## 我被帮助了：如释重负 + 对善意的感念（解释影响温度）
static func _appraisal_received_help(se: Dictionary, interp: Dictionary) -> Dictionary:
	var ctx: Dictionary = se["context"]
	var hunger: float = ctx["own_hunger"]
	var bond_w: float = Interpretation.weight_of(interp, "genuine_bond") + Interpretation.weight_of(interp, "generous")
	var return_w: float = Interpretation.weight_of(interp, "expects_return")
	return {
		"goal_congruence": clampf(0.35 + hunger * 0.35 + bond_w * 0.3 - return_w * 0.2, 0.0, 1.0),
		"expectedness": -0.3,
		"controllability": 0.6,
		"agency": se["counterpart_id"],
		"norm_violation": 0.0,
		"self_agency": false,
	}

# ── 信念更新：解释加权证据 ──

static func _update_beliefs(observer: Dictionary, se: Dictionary, interp: Dictionary, dyn: Dictionary, seq: int, tick: int) -> Dictionary:
	var tom: TheoryOfMind = observer.get("tom", null)
	if tom == null:
		return {}
	var other := str(se["counterpart_id"])
	if other == "" or other == str(observer.get("id", "")):
		return {}
	var updates := {}
	var type := str(se["type"])
	var role := str(se["role"])

	if type == "food_request_refused" and role == "proposer":
		# 被拒：按解释分布累积证据
		var neg_rate: float = dyn["betrayal_learning_rate"]
		tom.add_evidence(other, "generous", -1.0, Interpretation.weight_of(interp, "selfish") * 0.5 * neg_rate, seq, tick)
		tom.add_evidence(other, "reliable", -1.0, Interpretation.weight_of(interp, "distrusts_me") * 0.3 * neg_rate, seq, tick)
		tom.add_evidence(other, "has_food", -1.0, Interpretation.weight_of(interp, "also_starving") * 0.5, seq, tick)
		updates["generous"] = -Interpretation.weight_of(interp, "selfish") * 0.5 * neg_rate
		updates["has_food"] = -Interpretation.weight_of(interp, "also_starving") * 0.5
	elif type == "food_request_accepted" and role == "proposer":
		var pos_rate: float = dyn["positive_learning_rate"]
		tom.add_evidence(other, "generous", 1.0, (Interpretation.weight_of(interp, "generous") + Interpretation.weight_of(interp, "genuine_bond")) * 0.5 * pos_rate, seq, tick)
		tom.add_evidence(other, "reliable", 1.0, 0.25 * pos_rate, seq, tick)
		updates["generous"] = Interpretation.weight_of(interp, "generous") * 0.5 * pos_rate
	elif type == "shared_food" and role == "recipient":
		var pos_rate2: float = dyn["positive_learning_rate"]
		tom.add_evidence(other, "generous", 1.0, 0.4 * pos_rate2, seq, tick)
		updates["generous"] = 0.4 * pos_rate2
	elif type == "food_requested":
		# P1.6 感知门：他开口要食物 = 他饿的最强可观察证据（本人陈述 > 面色推测）
		tom.add_evidence(other, "hungry", 1.0, 0.5, seq, tick)
		updates["hungry"] = 0.5
	elif type == "ate_food":
		# 看见他吃东西 = 不那么饿了（反向证据，同样只是感知）
		tom.add_evidence(other, "hungry", -1.0, 0.3, seq, tick)
		updates["hungry"] = -0.3
	elif type == "foraged" or type == "fished" or type == "ruins_loot" or type == "explored_found":
		# 直接知觉证据：看见他获得食物（非解释，知觉）
		var sal: float = 0.2 + float(dyn["scarcity_salience"]) * 0.15
		tom.add_evidence(other, "has_food", 1.0, sal, seq, tick)
		updates["has_food"] = sal
	elif type == "foraged_empty" or type == "fished_empty" or type == "ruins_empty":
		var sal2: float = 0.1 + float(dyn["scarcity_salience"]) * 0.1
		tom.add_evidence(other, "has_food", -1.0, sal2, seq, tick)
		# 关键修正通道：看见他空手而归 → 削弱"他自私"旧结论（他可能真没粮）
		tom.weaken(other, "generous", 0.06)
		updates["has_food"] = -sal2
	return updates

# ── 关系更新：解释权重 → 四维增量 ──

static func _update_relationships(observer: Dictionary, se: Dictionary, interp: Dictionary, dyn: Dictionary, relationships) -> Dictionary:
	if relationships == null:
		return {}
	var me := str(observer.get("id", ""))
	var other := str(se["counterpart_id"])
	if other == "" or other == me:
		return {}
	var type := str(se["type"])
	var role := str(se["role"])
	var delta := {}
	# 陪伴效应：共同度过的时间积累善意（相处的熟悉感，非事件性增减）
	if type == "socialized":
		relationships.adjust(me, other, "benevolence", 15.0 * float(dyn["positive_learning_rate"]))
		delta["benevolence"] = 15.0 * float(dyn["positive_learning_rate"])

	if type == "food_request_refused" and role == "proposer":
		# 被拒者视角：敌意解释权重 → 善意下降；"不信任我" → 我也不信他（可靠↓）
		var host := Interpretation.hostility_weight(interp)
		var shortage := Interpretation.weight_of(interp, "also_starving")
		var neg_rate: float = dyn["betrayal_learning_rate"]
		var d_ben := -160.0 * host * neg_rate * (1.0 - shortage * 0.6)  # 他也快饿死 → 不怪他
		var d_rel := -80.0 * Interpretation.weight_of(interp, "distrusts_me") * neg_rate
		if absf(d_ben) > 1.0:
			relationships.adjust(me, other, "benevolence", d_ben)
			delta["benevolence"] = d_ben
		if absf(d_rel) > 1.0:
			relationships.adjust(me, other, "reliability", d_rel)
			delta["reliability"] = d_rel
	elif type == "food_request_accepted" and role == "proposer":
		var warm := Interpretation.weight_of(interp, "generous") + Interpretation.weight_of(interp, "genuine_bond")
		var pos_rate: float = dyn["positive_learning_rate"]
		var d_ben := 180.0 * warm * pos_rate
		if d_ben > 1.0:
			relationships.adjust(me, other, "benevolence", d_ben)
			delta["benevolence"] = d_ben
		# 感到亏欠（pities/expects_return 解释强 → 义务感重）
		var oblig := 60.0 * (Interpretation.weight_of(interp, "expects_return") + Interpretation.weight_of(interp, "pities_me") * 0.5)
		if oblig > 1.0:
			relationships.adjust(me, other, "obligation", oblig)
			delta["obligation"] = oblig
	elif type == "shared_food" and role == "recipient":
		relationships.adjust(me, other, "benevolence", 120.0 * dyn["positive_learning_rate"])
		relationships.adjust(me, other, "obligation", 40.0 * dyn["positive_learning_rate"])
		delta["benevolence"] = 120.0 * dyn["positive_learning_rate"]
		delta["obligation"] = 40.0 * dyn["positive_learning_rate"]
	return delta

# ── 描述性规范（我以为这里的人通常怎么做）──

static func _update_descriptive_norms(observer: Dictionary, event: Dictionary, se: Dictionary) -> void:
	var norms: Dictionary = observer.get("norms", {})
	if not norms.has("descriptive"):
		return
	var desc: Dictionary = norms["descriptive"]
	var type := str(event.get("type"))
	var me := str(observer.get("id", ""))
	# 只从目击他人的行为学习"风气"，自己的行为不算
	if str(event.get("actor_id", "")) == me:
		return
	if type == "shared_food" or type == "food_request_accepted":
		desc["sharing"] = clampf(float(desc.get("sharing", 0.5)) + 0.05, 0.0, 1.0)
	elif type == "food_request_refused":
		desc["sharing"] = clampf(float(desc.get("sharing", 0.5)) - 0.05, 0.0, 1.0)

# ── 社会倾向（目标层钩子：接近/回避）──

static func _update_social_stance(observer: Dictionary, se: Dictionary, interp: Dictionary, dyn: Dictionary) -> void:
	var other := str(se["counterpart_id"])
	if other == "" or other == str(observer.get("id", "")):
		return
	var stance: Dictionary = observer.get("social_stance", {})
	if interp.is_empty():
		return
	var host := Interpretation.hostility_weight(interp)
	var warm := Interpretation.weight_of(interp, "generous") + Interpretation.weight_of(interp, "genuine_bond")
	var type := str(se["type"])
	var role := str(se["role"])
	if type == "food_request_refused" and role == "proposer":
		# 敌意权重超过 0.5 且超过温暖 → 产生回避倾向（强度=敌意×恐惧敏感）
		if host > 0.5:
			var strength := host * (0.5 + float(observer["personality"].emotions.get("fear", 0.0)) * 0.5)
			stance[other] = clampf(float(stance.get(other, 0.0)) + strength, -1.0, 1.0)
	elif (type == "food_request_accepted" or type == "shared_food") and (role == "proposer" or role == "recipient"):
		if warm > 0.4:
			stance[other] = clampf(float(stance.get(other, 0.0)) - warm * 0.5, -1.0, 1.0)  # 负值 = 亲近
	observer["social_stance"] = stance

# ── 记忆：主观化 + 解释归档 ──

const IMPORTANT_TYPES := ["explored_hurt", "explored_found", "ruins_loot", "shared_food",
	"weather_storm", "food_requested", "food_request_accepted", "food_request_refused"]

static func _write_memory(observer: Dictionary, event: Dictionary, se: Dictionary, interp: Dictionary, appraisal: Dictionary) -> void:
	var type := str(event.get("type", ""))
	if not IMPORTANT_TYPES.has(type):
		return
	var me := str(observer.get("id", ""))
	var mem := {
		"seq": int(event.get("seq", 0)),
		"tick": int(event.get("tick", 0)),
		"type": _my_perspective_type(str(event.get("actor_id", "")), me, type, str(event.get("to_id", ""))),
		"text": str(event.get("text", "")),
		"actor_id": str(event.get("actor_id", "")),
		"counterpart_id": str(se["counterpart_id"]),
		"interpretation": interp.duplicate(true) if not interp.is_empty() else {},
		"appraisal_goal_congruence": float(appraisal.get("goal_congruence", 0.0)),
	}
	var mems: Array = observer.get("memories", [])
	mems.append(mem)
	if mems.size() > 20:
		mems.pop_front()

static func _my_perspective_type(actor_id: String, me: String, type: String, to_id: String) -> String:
	if actor_id == me:
		if type == "shared_food":
			return "i_shared_food"
		if type == "food_request_accepted":
			return "i_shared_on_request"
		if type == "food_request_refused":
			return "i_refused_request"
	if me == to_id and type == "shared_food":
		return "shared_food_to_me"
	return type

## P1.6：把「我想弄清楚」登记为 open question（不重复堆叠，更新熵与利害）
static func _open_question(observer: Dictionary, se: Dictionary, interp: Dictionary, stakes: float, tick: int) -> void:
	var qs: Array = observer.get("open_questions", [])
	var about := str(se["counterpart_id"])
	for q in qs:
		if str(q.get("about", "")) == about and str(q.get("kind", "")) == "why_refused":
			q["entropy"] = Interpretation.entropy(interp)
			q["stakes"] = stakes
			q["tick"] = tick
			return
	qs.append({"about": about, "kind": "why_refused", "entropy": Interpretation.entropy(interp),
		"stakes": stakes, "tick": tick, "expires": tick + 120})
	observer["open_questions"] = qs

static func _retrieve_memories(observer: Dictionary, counterpart: String, type: String) -> Array:
	var mems: Array = observer.get("memories", [])
	var out: Array = []
	for m in mems:
		if str(m.get("counterpart_id", "")) == counterpart and counterpart != "":
			out.append(m)
	return out
