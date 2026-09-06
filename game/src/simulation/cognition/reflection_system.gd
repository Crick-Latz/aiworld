class_name ReflectionSystem
extends RefCounted
## 反思系统 v2（P1.5 第三刀）：从"事件计数器"升级为"解释竞争 + 新证据修正"。
##
## 记忆里已经带着当刻的解释分布（CognitiveTransition 写入）。
## 反思做的事：
##   1. 聚合对每个人的解释证据（敌意系/温暖系/匮乏系）
##   2. 引入记忆之后的新证据（ToM 当前状态——他后来是否被看见空手而归）
##   3. 解释竞争 → 主导框架；与已存记恨对照：
##      - 敌意主导 且 无记恨 → 形成记恨（写入信念/ToM）
##      - 匮乏主导 且 有记恨 → 推翻记恨（"我可能错怪了他"——信念修正事件）
##   4. 描述性规范总结（"这里的人不分东西"）
##   5. 个人规范只在特定动力下缓慢变化（高 reactance → 被现实打击反而更坚持）
## 不再存在"拒绝 >= 2 → 记恨"的计数规则。

const REFLECT_INTERVAL := 48  # 每 48 tick（= 2 天游戏时间）反思一次

static func reflect(actor: Dictionary, tick: int) -> Dictionary:
	var mems: Array = actor.get("memories", [])
	var tom: TheoryOfMind = actor.get("tom", null)
	var bs: BeliefStore = actor.get("beliefs", null)
	var me := str(actor.get("id", ""))
	var names: Dictionary = actor.get("display_names", {})
	var dyn := PersonalityDynamics.dynamics(actor.get("personality", null),
		actor.get("sensitivities", {}), actor.get("norms", {}))
	var insights: Array = []
	var grudges: Dictionary = actor.get("grudges", {})

	# 1-2. 聚合解释证据（记忆内 + 记忆后的新证据）
	var frames := {}  # other_id -> {hostile: float, warm: float, scarcity: float, refusals: int, helps: int}
	for m in mems:
		var counterpart := str(m.get("counterpart_id", ""))
		if counterpart == "" or counterpart == me:
			continue
		if not frames.has(counterpart):
			frames[counterpart] = {"hostile": 0.0, "warm": 0.0, "scarcity": 0.0, "refusals": 0, "helps": 0}
		var f: Dictionary = frames[counterpart]
		var interp: Dictionary = m.get("interpretation", {})
		var type := str(m.get("type", ""))
		if type == "food_request_refused":
			f["refusals"] = int(f["refusals"]) + 1
			if not interp.is_empty():
				f["hostile"] = float(f["hostile"]) + Interpretation.hostility_weight(interp)
				f["scarcity"] = float(f["scarcity"]) + Interpretation.weight_of(interp, "also_starving")
		elif type == "food_request_accepted" or type == "shared_food_to_me":
			f["helps"] = int(f["helps"]) + 1
			if not interp.is_empty():
				f["warm"] = float(f["warm"]) + Interpretation.weight_of(interp, "generous") \
					+ Interpretation.weight_of(interp, "genuine_bond")

	var name_of := func(oid: String) -> String:
		return str(names.get(oid, oid))

	# 3. 解释竞争 + 记恨形成/推翻
	for oid in frames:
		var f: Dictionary = frames[oid]
		var rumination: float = dyn["rumination"]
		# 新证据：他后来被看见空手而归（has_food 已转负）→ 匮乏框架加权
		var scarcity_now := 0.0
		if tom != null and tom.raw_belief(oid, "has_food") < -0.3:
			scarcity_now = 0.8
		var hostile_score := float(f["hostile"]) * rumination
		var warm_score := float(f["warm"])
		var scarcity_score := (float(f["scarcity"]) + scarcity_now) * 1.2

		if hostile_score > 0.5 and hostile_score > scarcity_score and not grudges.has(oid):
			# 敌意主导 → 形成记恨
			grudges[oid] = {"tick": tick, "frame": "hostile", "strength": clampf(hostile_score, 0.0, 1.5)}
			if tom != null:
				tom.add_evidence(oid, "generous", -1.0, 0.25 * float(dyn["betrayal_learning_rate"]), -1, tick)
				tom.add_evidence(oid, "reliable", -1.0, 0.15 * float(dyn["betrayal_learning_rate"]), -1, tick)
			if bs != null:
				bs.update_confidence("%s 不肯帮我" % name_of.call(oid), 0.75, 0.4)
			insights.append("想来想去，%s 那些拒绝不是没有原因的——他就是没把我当同伴" % name_of.call(oid))
		elif scarcity_score > hostile_score and grudges.has(oid) and str(grudges[oid].get("frame", "")) == "hostile":
			# 匮乏证据反超 → 推翻记恨（信念修正！）
			grudges.erase(oid)
			if tom != null:
				tom.weaken(oid, "generous", 0.5)
				tom.weaken(oid, "reliable", 0.3)
			if bs != null:
				bs.update_confidence("%s 不肯帮我" % name_of.call(oid), 0.15, 0.6)
			insights.append("回想起来，%s 那几天好像真的什么都没打到……我也许错怪了他" % name_of.call(oid))
		elif warm_score > 0.8 and not grudges.has(oid):
			# 温暖主导 → 感念 + 亲近
			if tom != null:
				tom.add_evidence(oid, "generous", 1.0, 0.2 * float(dyn["positive_learning_rate"]), -1, tick)
			if bs != null:
				bs.update_confidence("%s 靠得住" % name_of.call(oid), 0.8, 0.4)
			insights.append("这几天多亏了%s，他是真的把我当同伴" % name_of.call(oid))

	actor["grudges"] = grudges

	# 4. 描述性规范总结（对"风气"的判断，不动个人规范）
	var norms: Dictionary = actor.get("norms", {})
	var desc: Dictionary = norms.get("descriptive", {})
	var ds: float = float(desc.get("sharing", 0.5))
	if ds < 0.25:
		insights.append("这座岛上没人在乎别人死活……谁都只顾自己")
	elif ds > 0.75:
		insights.append("这里的人愿意互相搭把手，跟以前船上不一样")
	# 5. 个人规范：只有高 reactance 的人在目睹自私风气后反而更坚持分享
	var personal: Dictionary = norms.get("personal", {})
	if ds < 0.3 and float(dyn["norm_reactance"]) > 0.7:
		personal["sharing"] = clampf(float(personal.get("sharing", 0.5)) + 0.02, 0.0, 1.0)
		insights.append("正因为这里的人都这么自私，我才更觉得同伴之间就该互相分享")

	return {"insights": insights, "frames": frames}
