class_name NpcBrainViewModel
extends RefCounted
## UI-R2：NPC 大脑观察器 presentation builder。
## 只做 READ / TRANSFORM / FORMAT：从 island 观察会话的公开字段与公开方法组装
## 大脑 ViewModel（schema 0.3）；禁止 mutate 任何模拟状态、禁止触碰 _private tracker。
## 每个字段带 provenance：objective(事实) / subjective(主观) / derived(推导)。
## 字段真实性依据 docs/ui/UI_R2_DATA_INVENTORY.md（编码前实码勘察）。

const PROV_OBJECTIVE := "objective"
const PROV_SUBJECTIVE := "subjective"
const PROV_DERIVED := "derived"

## 性能上限（§44）：4Hz 刷新不遍历全量历史
const MAX_MEMORY_ROWS := 30
const MAX_SOCIAL_EVENTS := 40
const MAX_TOM_PREDICATES_PER_PERSON := 20
const EVENT_SCAN_LIMIT := 300
const MAX_RELATIONS := 12

const TRAIT_LABELS := {
	"resilience": "韧性", "curiosity": "好奇", "action_bias": "行动", "caution": "谨慎",
	"empathy": "共情", "sociability": "社交", "altruism": "利他", "expressiveness": "表达",
	"conflict_avoidance": "避冲突", "pragmatism": "务实",
}
const EMOTION_LABELS := {"joy": "喜悦", "fear": "担忧", "anger": "愤怒", "sadness": "悲伤", "guilt": "内疚"}
const NEED_LABELS := {"hunger": "饥饿", "thirst": "口渴", "fatigue": "疲劳", "social": "孤独"}

## 社会页事件类型前缀（按真实 type 命名，见 INVENTORY §11）
const SOCIAL_EVENT_PREFIXES := ["MATERIAL_REQUEST", "COMMITMENT", "INFORMATION", "HOLDER",
	"shared_food", "food_request", "promise", "PROMISE", "transfer", "TRANSFER"]

## 唯一入口：组装选中角色的大脑 ViewModel。
static func build(sim, actor_id: String) -> Dictionary:
	var a: Dictionary = sim.actors.get(actor_id, {})
	if a.is_empty():
		return {}
	var out := _identity(sim, a, actor_id)
	out["state"] = _state(a)
	out["needs"] = _needs(a)
	out["emotions"] = _emotions(a)
	out["personality"] = _personality(a)
	out["decision"] = _decision(sim, a)
	out["plan"] = _plan(a)
	out["mind"] = _mind(sim, a, actor_id)
	out["relationships"] = _relationships(sim, actor_id)
	out["memories"] = _memories(a)
	out["social"] = _social(sim, actor_id)
	out["why_chain"] = _why_chain(a, out)
	# R1 兼容字段（HUD 旧键名继续可用；正式结构以新键为准）
	_compat_fields(out)
	return out

# ————— identity / state —————

static func _identity(sim, a: Dictionary, actor_id: String) -> Dictionary:
	return {
		"id": actor_id,
		"display_name": str(a.get("display_name", actor_id)),
		"status_text": str(a.get("activity", "—")),
		"location_text": "(%d, %d)" % [a["tile"].x, a["tile"].y],
		"provenance": PROV_OBJECTIVE,
	}

static func _state(a: Dictionary) -> Dictionary:
	var items: Array = []
	for item in a.get("inventory", {}):
		var n: int = int(a["inventory"][item])
		if n > 0:
			items.append({"id": str(item), "count": n, "provenance": PROV_OBJECTIVE})
	return {
		"activity": str(a.get("activity", "—")),
		"inventory_items": items,
		"provenance": PROV_OBJECTIVE,
	}

## needs：hunger/thirst/social 越高越急；energy 越高越好 → fatigue = 1000-energy（DERIVED 换算）
static func _needs(a: Dictionary) -> Dictionary:
	var needs: Dictionary = a.get("needs", {})
	var rows: Array = []
	var hunger := int(needs.get("hunger", 0))
	var thirst := int(needs.get("thirst", 0))
	var fatigue := 1000 - int(needs.get("energy", 1000))
	var social := int(needs.get("social", 0))
	rows.append({"key": "hunger", "label": NEED_LABELS["hunger"], "value": hunger,
		"frac": clampf(hunger / 1000.0, 0.0, 1.0), "provenance": PROV_OBJECTIVE})
	rows.append({"key": "thirst", "label": NEED_LABELS["thirst"], "value": thirst,
		"frac": clampf(thirst / 1000.0, 0.0, 1.0), "provenance": PROV_OBJECTIVE})
	rows.append({"key": "fatigue", "label": NEED_LABELS["fatigue"], "value": fatigue,
		"frac": clampf(fatigue / 1000.0, 0.0, 1.0), "provenance": PROV_DERIVED,
		"derived_note": "fatigue = 1000 - energy"})
	rows.append({"key": "social", "label": NEED_LABELS["social"], "value": social,
		"frac": clampf(social / 1000.0, 0.0, 1.0), "provenance": PROV_OBJECTIVE})
	rows.sort_custom(func(x, y): return float(x["frac"]) > float(y["frac"]))
	return {"rows": rows, "provenance": PROV_OBJECTIVE}

static func _emotions(a: Dictionary) -> Dictionary:
	var p: PersonalityProfile = a.get("personality", null)
	var rows: Array = []
	var dominant := {"label": "平静", "value": 0.0}
	if p != null:
		for key in ["joy", "fear", "anger", "sadness", "guilt"]:
			var v: float = p.emotions.get(key, 0.0)
			rows.append({"key": key, "label": EMOTION_LABELS[key], "value": v})
			if absf(v) > absf(float(dominant["value"])):
				dominant = {"label": EMOTION_LABELS[key], "value": v}
	return {"rows": rows, "dominant": dominant, "provenance": PROV_SUBJECTIVE}

static func _personality(a: Dictionary) -> Dictionary:
	var p: PersonalityProfile = a.get("personality", null)
	var traits: Array = []
	var beliefs: Array = []
	if p != null:
		for key in TRAIT_LABELS:
			traits.append({"key": key, "label": TRAIT_LABELS[key],
				"value": float(p.traits.get(key, 0.5)), "provenance": PROV_OBJECTIVE})
		for text in p.beliefs:
			# beliefs schema：{text: {weight, source_event}}——不是 string→float
			var entry: Dictionary = p.beliefs[text]
			beliefs.append({"text": str(text), "weight": float(entry.get("weight", 0.5)),
				"provenance": PROV_SUBJECTIVE})
	return {"traits": traits, "beliefs": beliefs, "provenance": PROV_SUBJECTIVE}

# ————— decision（真实 trace schema，见 INVENTORY §4） —————

static func _decision(sim, a: Dictionary) -> Dictionary:
	var trace: Dictionary = a.get("last_decision_trace", {})
	var intention: Dictionary = _current_intention(a)
	var chosen := str(trace.get("selected", ""))
	var candidates: Array = []
	# top_candidates：真实候选效用表（softmax 输入）——按效用降序，标记 chosen
	var tops: Dictionary = trace.get("top_candidates", {})
	var actions: Array = tops.keys()
	actions.sort_custom(func(x, y): return float(tops[x]) > float(tops[y]))
	for act in actions:
		candidates.append({
			"action": str(act), "utility": float(tops[act]),
			"chosen": str(act) == chosen, "provenance": PROV_SUBJECTIVE})
	var blocker := ""
	var next_step := ""
	if not intention.is_empty():
		next_step = str(intention.get("desc", intention.get("action", "")))
	if trace.has("agency_execution"):
		var ex: Dictionary = trace["agency_execution"]
		var br := str(ex.get("blocker_reason", ""))
		if br != "":
			blocker = br
	return {
		"chosen": chosen,
		"reason": str(trace.get("reason", "")),
		"current_action": str(a.get("activity", "—")),
		"blocker": blocker,
		"next_step": next_step,
		"candidates": candidates,
		"considered_count": (trace.get("considered_actions", []) as Array).size(),
		"dominant_interpretation": str(trace.get("dominant_interpretation", "")),
		"decision_tick": int(trace.get("agency_execution", {}).get("decision_tick", trace.get("tick", 0))),
		"provenance": PROV_SUBJECTIVE,
	}

# ————— plan（竖向 flow 数据；步骤级数据来自 trace.agency_execution，不读 _plan_tracker） —————

static func _plan(a: Dictionary) -> Dictionary:
	var trace: Dictionary = a.get("last_decision_trace", {})
	var intention: Dictionary = _current_intention(a)
	var nodes: Array = []
	# ROOT GOAL
	if trace.has("active_goal"):
		nodes.append({"kind": "ROOT_GOAL", "label": str(trace.get("goal_desc", trace["active_goal"])),
			"value": "优先级 %.2f" % float(trace.get("goal_priority", 0.0)),
			"status": "ACTIVE", "provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE"})
	# PLAN / CURRENT STEP / BLOCKER
	if trace.has("agency_execution"):
		var ex: Dictionary = trace["agency_execution"]
		if str(ex.get("plan_id", "")) != "":
			nodes.append({"kind": "PLAN", "label": "计划 %s" % str(ex["plan_id"]),
				"value": "运行 %s" % str(ex.get("run_id", "")),
				"status": "ACTIVE" if bool(ex.get("selected", false)) else "PENDING",
				"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE"})
		if str(ex.get("step_id", "")) != "":
			var blocked := str(ex.get("blocker_reason", "")) != ""
			nodes.append({"kind": "STEP", "label": "步骤 %s" % str(ex["step_id"]),
				"value": str(ex.get("blocker_reason", "")),
				"status": "BLOCKED" if blocked else "ACTIVE",
				"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE"})
		if str(ex.get("blocker_reason", "")) != "":
			nodes.append({"kind": "BLOCKER", "label": str(ex["blocker_reason"]),
				"value": "", "status": "BLOCKED",
				"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE"})
	# SUBGOAL / 信息目标
	if trace.has("agency_information"):
		var info: Dictionary = trace["agency_information"]
		var goal: Dictionary = info.get("goal", {})
		if not goal.is_empty():
			nodes.append({"kind": "SUBGOAL",
				"label": "信息目标 %s" % str(goal.get("kind", goal.get("query_kind", ""))),
				"value": "状态 %s" % str(goal.get("status", "")),
				"status": "ACTIVE" if str(goal.get("status", "")) == "ACTIVE" else "PENDING",
				"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE"})
	# 意图兜底
	if nodes.is_empty() and not intention.is_empty():
		nodes.append({"kind": "INTENTION", "label": str(intention.get("desc", intention.get("action", ""))),
			"value": "承诺度 %.0f%%" % (float(intention.get("commitment", 0.0)) * 100.0),
			"status": "ACTIVE", "provenance": PROV_SUBJECTIVE, "source_kind": "INTENTION"})
	return {
		"goal": {"desc": str(trace.get("goal_desc", "")), "priority": float(trace.get("goal_priority", 0.0)),
			"provenance": PROV_SUBJECTIVE},
		"intention": intention,
		"execution": trace.get("agency_execution", {}),
		"nodes": nodes,
		"provenance": PROV_SUBJECTIVE,
	}

static func _current_intention(a: Dictionary) -> Dictionary:
	var im: IntentionManager = a.get("intentions", null)
	if im != null and im.has_intention():
		return im.current_intention.duplicate(true)
	return {}

# ————— mind（open questions + ToM 动态谓词知识） —————

static func _mind(sim, a: Dictionary, actor_id: String) -> Dictionary:
	var tom: TheoryOfMind = a.get("tom", null)
	var subjects: Array = []
	if tom != null:
		var snap: Dictionary = tom.snapshot()
		for other_id in snap:
			var rows: Array = []
			var predicates: Array = (snap[other_id] as Dictionary).keys()
			predicates.sort()
			var count := 0
			for predicate in predicates:
				if count >= MAX_TOM_PREDICATES_PER_PERSON:
					break
				var key := str(predicate)
				var label := _predicate_label(key)
				rows.append({
					"predicate": key, "label": label,
					"value": float(snap[other_id][predicate]),
					"confidence": tom.confidence_of(other_id, key),
					"last_evidence_tick": tom.last_evidence_tick(other_id, key),
					"provenance": PROV_SUBJECTIVE})
				count += 1
			var last_seen: Dictionary = tom.last_seen_of(other_id)
			var entry := {
				"other_id": str(other_id),
				"other_name": _display_name_of(sim, str(other_id)),
				"rows": rows,
				"last_seen": {"tile": last_seen.get("tile", Vector2i.ZERO),
					"tick": int(last_seen.get("tick", -1))} if not last_seen.is_empty() else {},
				"provenance": PROV_SUBJECTIVE}
			subjects.append(entry)
		subjects.sort_custom(func(x, y): return (x["rows"] as Array).size() > (y["rows"] as Array).size())
	var open_questions: Array = []
	for q in a.get("open_questions", []):
		open_questions.append({
			"about": str(q.get("about", "")),
			"about_name": _display_name_of(sim, str(q.get("about", ""))),
			"kind": str(q.get("kind", "")),
			"entropy": float(q.get("entropy", 0.0)),
			"stakes": float(q.get("stakes", 0.0)),
			"tick": int(q.get("tick", 0)),
			"source_event_ids": (q.get("source_event_ids", []) as Array).duplicate(),
			"provenance": PROV_SUBJECTIVE})
	return {
		"open_questions": open_questions,
		"tom_subjects": subjects,
		"prediction_error": tom.mean_prediction_error() if tom != null else 0.0,
		"provenance": PROV_SUBJECTIVE,
	}

## 谓词可读名：has_item:shells → 持有 shells；其余原样
static func _predicate_label(key: String) -> String:
	if key.begins_with("has_item:"):
		return "持有 " + key.trim_prefix("has_item:")
	return key

# ————— relationships（R1 两层分离结构保持） —————

static func _relationships(sim, actor_id: String) -> Dictionary:
	var rows: Array = []
	var selected = sim.actors.get(actor_id, {})
	var tom: TheoryOfMind = selected.get("tom", null) if not selected.is_empty() else null
	var count := 0
	for oid in sim.actors:
		if oid == actor_id or count >= MAX_RELATIONS:
			continue
		count += 1
		var row := {
			"other_id": str(oid),
			"other_name": str(sim.actors[oid]["display_name"]),
			"trust": int(sim.relationships.get_trust(actor_id, oid)),
			"benevolence": int(sim.relationships.get_dim(actor_id, oid, "benevolence")),
			"reliability": int(sim.relationships.get_dim(actor_id, oid, "reliability")),
			"obligation": int(sim.relationships.get_dim(actor_id, oid, "obligation")),
			"fear": int(sim.relationships.get_dim(actor_id, oid, "fear")),
			"change": "",
			"provenance": PROV_OBJECTIVE}
		if tom != null:
			var m: Dictionary = tom.model_of(oid)
			row["tom"] = {
				"has_food": float(m.get("has_food", 0.0)),
				"generous": float(m.get("generous", 0.0)),
				"reliable": float(m.get("reliable", 0.0))}
		rows.append(row)
	return {"rows": rows, "provenance": PROV_OBJECTIVE}

# ————— memories（卡片 + derived day/importance） —————

static func _memories(a: Dictionary) -> Dictionary:
	var rows: Array = []
	var mems: Array = a.get("memories", [])
	for i in range(mems.size() - 1, maxi(-1, mems.size() - 1 - MAX_MEMORY_ROWS), -1):
		var m: Dictionary = mems[i]
		rows.append({
			"seq": int(m.get("seq", 0)),
			"tick": int(m.get("tick", 0)),
			"day": int(m.get("tick", 0)) / 24 + 1, # DERIVED：岛 sim 1 tick = 1 小时
			"text": str(m.get("text", "")),
			"type": str(m.get("type", "")),
			"counterpart": str(m.get("counterpart_id", "")),
			"derived_importance": absf(float(m.get("appraisal_goal_congruence", 0.0))),
			"interpretation": m.get("interpretation", {}),
			"provenance": PROV_SUBJECTIVE})
	return {"rows": rows, "provenance": PROV_SUBJECTIVE}

# ————— social（承诺台账只读过滤 + 事件尾部派生） —————

static func _social(sim, actor_id: String) -> Dictionary:
	var display_name := _display_name_of(sim, actor_id)
	var commitments: Array = []
	for record in sim.obligations:
		var debtor := str(record.get("debtor_id", record.get("debtor", "")))
		var creditor := str(record.get("creditor_id", record.get("creditor", "")))
		if debtor != actor_id and creditor != actor_id:
			continue
		commitments.append({
			"commitment_id": str(record.get("commitment_id", "")),
			"direction": "我欠" if debtor == actor_id else "欠我",
			"counterpart_name": _display_name_of(sim, creditor if debtor == actor_id else debtor),
			"object": str(record.get("object_id", record.get("object", ""))),
			"quantity": int(record.get("quantity", 0)),
			"status": str(record.get("status", "")),
			"due_tick": int(record.get("due_tick", -1)),
			"source_request_id": str(record.get("source_request_id", "")),
			"provenance": PROV_OBJECTIVE})
	# 事件尾部派生（≤EVENT_SCAN_LIMIT，从尾部直到够数即停）
	var requests: Array = []
	var holder_events: Array = []
	var social_events: Array = []
	var events: Array = sim.events
	for i in range(events.size() - 1, maxi(-1, events.size() - 1 - EVENT_SCAN_LIMIT), -1):
		var e: Dictionary = events[i]
		var etype := str(e.get("type", ""))
		var row := {"day": int(e.get("day", 1)), "seq": int(e.get("seq", 0)),
			"text": str(e.get("text", "")), "type": etype}
		if etype.begins_with("MATERIAL_REQUEST") and requests.size() < MAX_SOCIAL_EVENTS:
			requests.append(row)
		elif (etype.begins_with("INFORMATION") or etype.begins_with("HOLDER")) and holder_events.size() < MAX_SOCIAL_EVENTS:
			holder_events.append(row)
		var is_social := false
		for prefix in SOCIAL_EVENT_PREFIXES:
			if etype.begins_with(prefix):
				is_social = true
				break
		if is_social and social_events.size() < MAX_SOCIAL_EVENTS:
			social_events.append(row)
		if requests.size() >= MAX_SOCIAL_EVENTS and social_events.size() >= MAX_SOCIAL_EVENTS:
			break
	return {
		"commitments": commitments,
		"recent_requests": requests,
		"holder_events": holder_events,
		"recent_social_events": social_events,
		"display_name": display_name,
		"provenance": PROV_OBJECTIVE}

# ————— why chain（确定性；只串真实存在的数据；每节点带 source） —————

static func _why_chain(a: Dictionary, built: Dictionary) -> Array:
	var chain: Array = []
	var top_need: Dictionary = {}
	for row in (built["needs"] as Dictionary)["rows"]:
		if top_need.is_empty() or float(row["frac"]) > float(top_need["frac"]):
			top_need = row
	if not top_need.is_empty() and float(top_need["frac"]) > 0.05:
		chain.append({"label": "%s升高（%d）" % [str(top_need["label"]), int(top_need["value"])],
			"provenance": str(top_need["provenance"]), "source_kind": "ACTOR_NEED",
			"source_ref": "needs." + str(top_need["key"])})
	var trace: Dictionary = a.get("last_decision_trace", {})
	if trace.has("goal_desc"):
		chain.append({"label": "当前目标：%s" % str(trace["goal_desc"]),
			"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
			"source_ref": "last_decision_trace.goal_desc"})
	var intention: Dictionary = (built["plan"] as Dictionary)["intention"]
	if not intention.is_empty():
		chain.append({"label": "意图：%s（承诺度 %.0f%%）" % [
			str(intention.get("desc", intention.get("action", ""))),
			float(intention.get("commitment", 0.0)) * 100.0],
			"provenance": PROV_SUBJECTIVE, "source_kind": "INTENTION",
			"source_ref": "intentions.current_intention"})
	if trace.has("agency_execution") and str(trace["agency_execution"].get("step_id", "")) != "":
		var ex: Dictionary = trace["agency_execution"]
		chain.append({"label": "步骤：%s" % str(ex["step_id"]),
			"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
			"source_ref": "last_decision_trace.agency_execution.step_id"})
		if str(ex.get("blocker_reason", "")) != "":
			chain.append({"label": "阻塞：%s" % str(ex["blocker_reason"]),
				"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
				"source_ref": "last_decision_trace.agency_execution.blocker_reason"})
	if trace.has("agency_information") and not (trace["agency_information"] as Dictionary).get("goal", {}).is_empty():
		var goal: Dictionary = trace["agency_information"]["goal"]
		chain.append({"label": "信息目标：%s（%s）" % [str(goal.get("kind", goal.get("query_kind", ""))), str(goal.get("status", ""))],
			"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
			"source_ref": "last_decision_trace.agency_information.goal"})
	chain.append({"label": "当前行动：%s" % str(a.get("activity", "—")),
		"provenance": PROV_OBJECTIVE, "source_kind": "ACTOR_STATE",
		"source_ref": "activity"})
	return chain

# ————— helpers —————

static func _display_name_of(sim, actor_id: String) -> String:
	if sim.actors.has(actor_id):
		return str(sim.actors[actor_id]["display_name"])
	return actor_id

## R1 兼容字段：旧 HUD 键名（identity 字段位于顶层；这里补齐文本摘要键）
static func _compat_fields(out: Dictionary) -> void:
	var inv: Array = []
	for item in out["state"]["inventory_items"]:
		inv.append("%s×%d" % [str(item["id"]), int(item["count"])])
	out["activity_text"] = str(out.get("status_text", ""))
	var plan: Dictionary = out.get("plan", {})
	var goal_desc := str((plan.get("goal", {}) as Dictionary).get("desc", ""))
	out["goal_text"] = goal_desc if goal_desc != "" else "思考中..."
	out["location_text"] = str(out.get("location_text", ""))
	out["inventory_text"] = "、".join(inv) if not inv.is_empty() else "（空）"
	out["inventory_items"] = out["state"]["inventory_items"]
	var need_rows: Array = (out["needs"] as Dictionary)["rows"]
	var parts: Array = []
	for row in need_rows:
		parts.append("%s%d" % [str(row["label"]), int(row["value"])])
	out["needs_text"] = " ".join(parts)
	out["decision_text"] = str((out["decision"] as Dictionary)["reason"])
