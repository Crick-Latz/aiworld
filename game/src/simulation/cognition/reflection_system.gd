class_name ReflectionSystem
extends RefCounted
## 反思系统（P1）：把情景记忆（"第 3 天他拒绝了我"）蒸馏成语义信念
## （"欧恩不肯帮我"）与 ToM 更新。信念影响后续决策 → 角色弧光：
##   两天内被同一人拒绝 ≥2 次 → ToM.reliable/generous ↓↓，写入 BeliefStore
##   被同一人帮助 ≥2 次 → ToM.generous ↑↑，写入"他靠得住"
## 反思是延迟发生的——人总是事后才想明白。这就是"当天忍气吞声，
## 两天后记恨在心"的机制来源。

const REFLECT_INTERVAL := 48  # 每 48 tick（= 2 天游戏时间）反思一次
const REFUSAL_GRUDGE_THRESHOLD := 2  # 被拒 ≥2 次才记恨（一次可能是误会）

## 对单个 actor 执行反思。返回 { insights: Array[String], tom_delta: {other_id: {key: delta}} }
## insights 是人类可读的领悟（供事件流展示）；记忆本身不删除——人记得事实，改变的是解释。
static func reflect(actor: Dictionary, tick: int) -> Dictionary:
	var mems: Array = actor.get("memories", [])
	var tom: TheoryOfMind = actor.get("tom", null)
	var bs: BeliefStore = actor.get("beliefs", null)
	var me := str(actor.get("id", ""))
	var insights: Array = []
	var tom_delta := {}

	# 统计：谁拒绝过我 / 谁帮助过我（按记忆里的对手方）
	var refused_by := {}
	var helped_by := {}
	for m in mems:
		var t := str(m.get("type", ""))
		var counterpart := str(m.get("counterpart_id", ""))
		if counterpart == "" or counterpart == me:
			continue
		if t == "food_request_refused":
			refused_by[counterpart] = int(refused_by.get(counterpart, 0)) + 1
		elif t == "food_request_accepted" or t == "shared_food_to_me":
			helped_by[counterpart] = int(helped_by.get(counterpart, 0)) + 1

	var names: Dictionary = actor.get("display_names", {})
	var name_of := func(oid: String) -> String:
		return str(names.get(oid, oid))

	# 记恨：重复拒绝 → 不可靠/不慷慨
	for oid in refused_by:
		if int(refused_by[oid]) >= REFUSAL_GRUDGE_THRESHOLD:
			if tom != null:
				tom.update(oid, "reliable", -0.2, tick)
				tom.update(oid, "generous", -0.2, tick)
				if not tom_delta.has(oid):
					tom_delta[oid] = {}
				tom_delta[oid]["reliable"] = -0.2
				tom_delta[oid]["generous"] = -0.2
			if bs != null:
				bs.update_confidence("%s 不肯帮我" % name_of.call(oid), 0.75, 0.4)
			insights.append("回想起来，%s 已经拒绝我 %d 次了……这样的人靠不住" % [name_of.call(oid), int(refused_by[oid])])

	# 感念：重复帮助 → 可靠/慷慨
	for oid in helped_by:
		if int(helped_by[oid]) >= 2:
			if tom != null:
				tom.update(oid, "generous", 0.25, tick)
				tom.update(oid, "reliable", 0.2, tick)
				if not tom_delta.has(oid):
					tom_delta[oid] = {}
				tom_delta[oid]["generous"] = 0.25
				tom_delta[oid]["reliable"] = 0.2
			if bs != null:
				bs.update_confidence("%s 靠得住" % name_of.call(oid), 0.8, 0.4)
			insights.append("这几天多亏了%s，他是真的把我当同伴" % name_of.call(oid))

	return {"insights": insights, "tom_delta": tom_delta}
