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

## 社会页事件类型前缀（按真实 type 命名，见 INVENTORY §11）：
## material/commitment 系为全大写（MATERIAL_REQUEST_* / MATERIAL_COUNTER_* / COMMITMENT_*）；
## P7.0/P7.2B 信息事件为全小写（holder_information_* / source_information_*）。
const HOLDER_EVENT_PREFIXES := ["holder_information_", "source_information_"]
const SOCIAL_EVENT_PREFIXES := ["MATERIAL_REQUEST", "MATERIAL_COUNTER", "MATERIAL_TRANSFER", "COMMITMENT",
	"holder_information_", "source_information_", "shared_food", "food_request", "promise", "PROMISE",
	"transfer", "TRANSFER"]

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
	out["plan"] = _plan(sim, a, actor_id)
	out["mind"] = _mind(sim, a, actor_id)
	out["relationships"] = _relationships(sim, actor_id)
	out["memories"] = _memories(a)
	out["social"] = _social(sim, actor_id)
	out["why"] = _why(sim, a, out)
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

## 原始情绪值为角色主观状态[主观]；“主导情绪”是 presentation 做 max(|value|)
## 聚合后的选择——聚合本身 [推导]。
static func _emotions(a: Dictionary) -> Dictionary:
	var p: PersonalityProfile = a.get("personality", null)
	var rows: Array = []
	var dominant := {"label": "平静", "value": 0.0, "provenance": PROV_DERIVED,
		"derived_note": "max(|value|) 聚合选择"}
	if p != null:
		for key in ["joy", "fear", "anger", "sadness", "guilt"]:
			var v: float = p.emotions.get(key, 0.0)
			rows.append({"key": key, "label": EMOTION_LABELS[key], "value": v,
				"provenance": PROV_SUBJECTIVE})
			if absf(v) > absf(float(dominant["value"])):
				dominant = {"label": EMOTION_LABELS[key], "value": v, "provenance": PROV_DERIVED,
					"derived_note": "max(|value|) 聚合选择"}
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

# ————— plan：LIVE（公开 accessor）与 DECISION-TIME SNAPSHOT（trace）分离 —————
# LIVE：sim.agency_plan_run(actor_id) / sim.agency_information_goal(actor_id)——只读公开 API。
# SNAPSHOT：actor.last_decision_trace（他上一次做决定时怎么看）。
# run.steps 不保存每步独立终态：非 current 步骤一律 UNKNOWN，不虚构 COMPLETED。

static func _plan(sim, a: Dictionary, actor_id: String) -> Dictionary:
	var trace: Dictionary = a.get("last_decision_trace", {})
	var intention: Dictionary = _current_intention(a)
	var live_run: Dictionary = {}
	if sim != null and sim.has_method("agency_plan_run"):
		live_run = sim.agency_plan_run(actor_id)
	var live_goal: Dictionary = {}
	if sim != null and sim.has_method("agency_information_goal"):
		live_goal = sim.agency_information_goal(actor_id)
	var nodes: Array = []
	# ROOT GOAL（决策时快照）
	if trace.has("active_goal"):
		nodes.append({"kind": "ROOT_GOAL", "label": str(trace.get("goal_desc", trace["active_goal"])),
			"value": "优先级 %.2f" % float(trace.get("goal_priority", 0.0)),
			"status": "ACTIVE", "provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE"})
	var live_summary: Dictionary = {}
	if not live_run.is_empty():
		# LIVE RUN：当前真实 run（run_id/plan_id/state/reason_code/current_step_id 全只读）
		var run_state := str(live_run.get("state", ""))
		nodes.append({"kind": "RUN", "label": "执行 %s" % str(live_run.get("run_id", "")),
			"value": "计划 %s · %s" % [str(live_run.get("plan_id", "")), run_state],
			"status": run_state if run_state != "" else "PENDING",
			"provenance": PROV_SUBJECTIVE, "source_kind": "LIVE_RUN",
			"source_ref": "agency_plan_run"})
		var cur := str(live_run.get("current_step_id", ""))
		var step_rows: Array = []
		var steps: Array = live_run.get("steps", [])
		for i in range(steps.size()):
			var s: Dictionary = steps[i]
			var sid := str(s.get("step_id", ""))
			step_rows.append({"step_id": sid, "order": i, "is_current": sid == cur,
				"status": "CURRENT" if sid == cur else "UNKNOWN",
				"provenance": PROV_SUBJECTIVE})
		for srow in step_rows:
			nodes.append({"kind": "STEP", "label": "步骤 %s" % str(srow["step_id"]),
				"value": "当前" if bool(srow["is_current"]) else "",
				"status": str(srow["status"]),
				"provenance": PROV_SUBJECTIVE, "source_kind": "LIVE_RUN",
				"source_ref": "agency_plan_run.steps"})
		live_summary = {
			"run_id": str(live_run.get("run_id", "")),
			"plan_id": str(live_run.get("plan_id", "")),
			"root_goal": str(live_run.get("root_goal", "")),
			"state": run_state,
			"reason_code": str(live_run.get("reason_code", "")),
			"current_step_id": cur,
			"steps": step_rows,
			"provenance": PROV_SUBJECTIVE, "source_kind": "LIVE_RUN",
			"source_ref": "agency_plan_run"}
	elif trace.has("agency_execution"):
		# 决策时快照兜底（live run 不存在时才使用）
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
		if str(trace["agency_execution"].get("blocker_reason", "")) != "":
			nodes.append({"kind": "BLOCKER", "label": str(trace["agency_execution"]["blocker_reason"]),
				"value": "", "status": "BLOCKED",
				"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE"})
	# 信息目标：LIVE 优先（真实字段 state；fixture 兼容 status 回退），否则决策快照
	var goal_dict: Dictionary = live_goal
	var goal_source := "LIVE_ACCESSOR"
	if goal_dict.is_empty():
		goal_dict = (trace.get("agency_information", {}) as Dictionary).get("goal", {})
		goal_source = "DECISION_TRACE"
	if not goal_dict.is_empty():
		var g_state := str(goal_dict.get("state", goal_dict.get("status", "")))
		nodes.append({"kind": "SUBGOAL",
			"label": "信息目标 %s" % str(goal_dict.get("query_kind", goal_dict.get("kind", ""))),
			"value": "状态 %s" % g_state,
			"status": g_state if g_state != "" else "PENDING",
			"provenance": PROV_SUBJECTIVE, "source_kind": goal_source,
			"source_ref": "agency_information_goal" if goal_source == "LIVE_ACCESSOR" else "last_decision_trace.agency_information.goal"})
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
		"live_run": live_summary,
		"live_information_goal": live_goal,
		"decision_snapshot": {
			"agency_execution": trace.get("agency_execution", {}),
			"agency_information_goal": (trace.get("agency_information", {}) as Dictionary).get("goal", {})},
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
	# primary question：按 stakes 降序再 tick 降序选“当前最重要问题”（并列按 about/kind 稳定）。
	# 选择本身是 presentation 聚合 → [推导]；问题内容仍是角色主观。
	var primary := {}
	for q in open_questions:
		if primary.is_empty() or _question_outranks(q, primary):
			primary = q.duplicate()
	if not primary.is_empty():
		primary["provenance"] = PROV_DERIVED
	return {
		"open_questions": open_questions,
		"primary_question": primary,
		"tom_subjects": subjects,
		"prediction_error": tom.mean_prediction_error() if tom != null else 0.0,
		"provenance": PROV_SUBJECTIVE,
	}

## 排序键：stakes 降序 → tick 降序 → about/kind 字典序（保证确定性）
static func _question_outranks(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a.get("stakes", 0.0)), float(b.get("stakes", 0.0))):
		return float(a.get("stakes", 0.0)) > float(b.get("stakes", 0.0))
	if int(a.get("tick", 0)) != int(b.get("tick", 0)):
		return int(a.get("tick", 0)) > int(b.get("tick", 0))
	var ak := str(a.get("about", "")) + "|" + str(a.get("kind", ""))
	var bk := str(b.get("about", "")) + "|" + str(b.get("kind", ""))
	return ak < bk

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

# ————— social（承诺台账只读过滤 + 事件尾部派生，仅选中 NPC 直接参与的事件） —————

## 相关性判定：事件参与方字段命中选中 NPC 才算他的社会经历。
## reported_holder_id / observed 等提及字段不算直接参与（C 谈论 B ≠ B 参与）。
static func _event_relevant_to_actor(e: Dictionary, actor_id: String) -> bool:
	for key in ["actor_id", "requester_id", "target_id", "to_id", "debtor_id", "creditor_id",
			"reporter_id", "proposer_id", "from_actor_id", "to_actor_id"]:
		if str(e.get(key, "")) == actor_id:
			return true
	for id in e.get("actor_ids", []):
		if str(id) == actor_id:
			return true
	return false

static func _event_in_family(etype: String, prefixes: Array) -> bool:
	for prefix in prefixes:
		if etype.begins_with(prefix):
			return true
	return false

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
	# 事件尾部派生（≤EVENT_SCAN_LIMIT，从尾部直到够数即停）；
	# 只收选中 NPC 直接参与的事件——无关两人之间的请求/情报不进他的社会页。
	var requests: Array = []
	var holder_events: Array = []
	var social_events: Array = []
	var events: Array = sim.events
	for i in range(events.size() - 1, maxi(-1, events.size() - 1 - EVENT_SCAN_LIMIT), -1):
		var e: Dictionary = events[i]
		if not _event_relevant_to_actor(e, actor_id):
			continue
		var etype := str(e.get("type", ""))
		var row := {"day": int(e.get("day", 1)), "seq": int(e.get("seq", 0)),
			"text": str(e.get("text", "")), "type": etype}
		if etype.begins_with("MATERIAL_REQUEST") and requests.size() < MAX_SOCIAL_EVENTS:
			requests.append(row)
		elif _event_in_family(etype, HOLDER_EVENT_PREFIXES) and holder_events.size() < MAX_SOCIAL_EVENTS:
			holder_events.append(row)
		if _event_in_family(etype, SOCIAL_EVENT_PREFIXES) and social_events.size() < MAX_SOCIAL_EVENTS:
			social_events.append(row)
		if requests.size() >= MAX_SOCIAL_EVENTS and social_events.size() >= MAX_SOCIAL_EVENTS \
				and holder_events.size() >= MAX_SOCIAL_EVENTS:
			break
	return {
		"commitments": commitments,
		"recent_requests": requests,
		"holder_events": holder_events,
		"recent_social_events": social_events,
		"display_name": display_name,
		"provenance": PROV_OBJECTIVE}

# ————— why（fail-closed 因果；整体是 presentation 串联 → [推导]） —————
# 规则（UI-R2 R1 Semantic Hardening）：
#   1. 因果箭头只允许出现在 decision trace / live accessor 支持的节点之间；
#   2. 只有当前数值的需求/情绪进入“当前上下文”区（无箭头，不冒充原因）；
#   3. 无 delta/trend 数据时禁止“升高/下降”措辞；
#   4. simulation 已记录的 trace.reason 以“决策理由”优先展示，不用 UI 自选的最高需求取代。

static func _why(sim, a: Dictionary, built: Dictionary) -> Dictionary:
	var trace: Dictionary = a.get("last_decision_trace", {})
	# —— 当前上下文（presentation 整理；不参与因果链）——
	var context: Array = []
	var top_need: Dictionary = {}
	for row in (built["needs"] as Dictionary)["rows"]:
		if top_need.is_empty() or float(row["frac"]) > float(top_need["frac"]):
			top_need = row
	if not top_need.is_empty() and float(top_need["frac"]) > 0.05:
		context.append({"label": "当前需求：%s %d" % [str(top_need["label"]), int(top_need["value"])],
			"provenance": str(top_need["provenance"]), "source_kind": "ACTOR_NEED",
			"source_ref": "needs." + str(top_need["key"])})
	# —— 决策理由（simulation 记录的选择理由）——
	var decision_reason := {}
	if str(trace.get("reason", "")) != "":
		decision_reason = {"text": str(trace["reason"]),
			"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
			"source_ref": "last_decision_trace.reason"}
	# —— 因果链节点（全部来自 trace / live accessor / actor 公开状态）——
	var nodes: Array = []
	var links: Array = []
	if trace.has("goal_desc"):
		nodes.append({"label": "当前目标：%s" % str(trace["goal_desc"]),
			"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
			"source_ref": "last_decision_trace.goal_desc"})
	var intention: Dictionary = (built["plan"] as Dictionary)["intention"]
	if not intention.is_empty():
		nodes.append({"label": "意图：%s（承诺度 %.0f%%）" % [
			str(intention.get("desc", intention.get("action", ""))),
			float(intention.get("commitment", 0.0)) * 100.0],
			"provenance": PROV_SUBJECTIVE, "source_kind": "INTENTION",
			"source_ref": "intentions.current_intention"})
	var trace_has_execution := trace.has("agency_execution") \
		and str(trace["agency_execution"].get("step_id", "")) != ""
	if trace_has_execution:
		var ex: Dictionary = trace["agency_execution"]
		nodes.append({"label": "步骤：%s" % str(ex["step_id"]),
			"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
			"source_ref": "last_decision_trace.agency_execution.step_id"})
		if str(ex.get("blocker_reason", "")) != "":
			nodes.append({"label": "阻塞：%s" % str(ex["blocker_reason"]),
				"provenance": PROV_SUBJECTIVE, "source_kind": "DECISION_TRACE",
				"source_ref": "last_decision_trace.agency_execution.blocker_reason"})
	# 信息目标：live accessor 优先；trace 内 agency_information.goal 存在才允许挂进因果链
	var live_goal: Dictionary = {}
	if sim != null and sim.has_method("agency_information_goal"):
		live_goal = sim.agency_information_goal(actor_id_of(built))
	var goal_for_chain: Dictionary = live_goal if not live_goal.is_empty() \
		else (trace.get("agency_information", {}) as Dictionary).get("goal", {})
	if not goal_for_chain.is_empty():
		var g_state := str(goal_for_chain.get("state", goal_for_chain.get("status", "")))
		nodes.append({"label": "信息目标：%s（%s）" % [
			str(goal_for_chain.get("query_kind", goal_for_chain.get("kind", ""))), g_state],
			"provenance": PROV_SUBJECTIVE,
			"source_kind": "LIVE_ACCESSOR" if not live_goal.is_empty() else "DECISION_TRACE",
			"source_ref": "agency_information_goal" if not live_goal.is_empty() \
				else "last_decision_trace.agency_information.goal"})
	if str(a.get("activity", "")) != "":
		nodes.append({"label": "当前行动：%s" % str(a["activity"]),
			"provenance": PROV_OBJECTIVE, "source_kind": "ACTOR_STATE",
			"source_ref": "activity"})
	# 链接：相邻节点均为 trace/live 支持时为记录级链接[主观]；
	# 末端“→当前行动”无直接 trace 字段佐证，显式标 [推导]（PRESENTATION_LINK）。
	for i in range(nodes.size() - 1):
		var link := {"from": i, "to": i + 1}
		if str(nodes[i + 1].get("source_kind", "")) == "ACTOR_STATE":
			link["provenance"] = PROV_DERIVED
			link["source_kind"] = "PRESENTATION_LINK"
			link["source_ref"] = "activity（执行系统维护，Presentation 无直接 trace 字段）"
		else:
			link["provenance"] = PROV_SUBJECTIVE
			link["source_kind"] = "DECISION_TRACE"
			link["source_ref"] = str(nodes[i + 1].get("source_ref", ""))
		links.append(link)
	return {
		"provenance": PROV_DERIVED,
		"derived_note": "因果链由 presentation 从决策留痕/公开状态确定性串联",
		"decision_reason": decision_reason,
		"nodes": nodes,
		"links": links,
		"context": context,
	}

static func actor_id_of(built: Dictionary) -> String:
	return str(built.get("id", ""))

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
