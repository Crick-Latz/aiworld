class_name NarrativeClaim
extends RefCounted
## P3a-2 原子叙事主张（Atomic Narrative Claims）：
## 解决"带着正确引用胡说八道"——不仅知道句子引用了什么，还知道句子声称了什么。
##
## 每个主张 = 一条可验证的原子断言：
##   {claim_id, type, subject, predicate, object, qualifiers,
##    epistemic_status, source_event_ids, source_trace_ids, beat_id}
##
## epistemic_status（truth level，绝不混用）：
##   OBJECTIVE   世界真值（发生的事件）
##   PERCEIVED   某人感知到（看见但未解释）
##   BELIEVED    某人当时的主观信念（可能是错的）
##   INFERRED    某人的解释推断（解释竞争的产物）
##   RETROSPECTIVE 事后修正（反思推翻了旧信念）
##
## 产生规则：只做确定性转换（事件字段→主张），LLM 永远不能创建 Claim。
## CAUSAL_LINK 类主张只有存在结构化因果边时才允许（时间相邻≠因果）。

const TYPES := ["WORLD_EVENT", "BELIEF", "EMOTION", "INTENTION",
	"RELATIONSHIP_CHANGE", "INSTITUTION_STATE", "CAUSAL_LINK", "UNCERTAINTY",
	"SPEECH_ACT",  # P3a-2.1：说了 X ≠ 相信 X（sincerity 永远 UNKNOWN）
	"INTERPRETATION", "DECISION_REASON"]

var _claims: Array = []
var _next_id := 0

func _add(type: String, subject: String, predicate: String, object, status: String,
		event_ids: Array, trace_ids: Array = [], confidence: float = 1.0) -> String:
	var cid := "C%d" % _next_id
	_next_id += 1
	_claims.append({
		"claim_id": cid,
		"type": type,
		"subject": subject,
		"predicate": predicate,
		"object": object,
		"epistemic_status": status,
		"source_event_ids": event_ids,
		"source_trace_ids": trace_ids,
		"confidence": confidence,  # P3a-2.1：低于 0.6 只能写"怀疑"，高于 0.8 才能写"几乎认定"
		"beat_id": "",
	})
	return cid

func attach_to_beat(claim_id: String, beat_id: String) -> void:
	for c in _claims:
		if str(c["claim_id"]) == claim_id:
			c["beat_id"] = beat_id
			return

func all() -> Array:
	return _claims

## ── 确定性提取：从可见事件生成主张 ──
## perspective 决定 truth level：OBJECTIVE 视角全是 OBJECTIVE；
## CHARACTER 视角对他人行为是 PERCEIVED，对自己记忆里的信念是 BELIEVED。
static func extract(events: Array, perspective: String, focus_actor: String = "", actors: Dictionary = {}, edges: Array = []) -> Array:
	var nc := NarrativeClaim.new()
	for e in events:
		var seq: Array = [int(e.get("seq", 0))]
		var t := str(e.get("type", ""))
		var actor := str(e.get("actor_id", ""))
		var to_id := str(e.get("to_id", ""))
		var status := "OBJECTIVE"
		if perspective == "CHARACTER" and actor != focus_actor and actor != "":
			status = "PERCEIVED"  # 我看见他做了（不解释为什么）
		match t:
			"food_request_refused", "water_request_refused", "tool_request_refused":
				nc._add("WORLD_EVENT", actor, "REFUSED_REQUEST", {"from": str(e.get("proposer_id", "")),
					"object": str(e.get("object", "food"))}, status, seq)
			"food_request_accepted", "water_request_accepted", "tool_request_accepted":
				nc._add("WORLD_EVENT", actor, "GRANTED_REQUEST", {"to": str(e.get("proposer_id", "")),
					"object": str(e.get("object", "food"))}, status, seq)
			"shared_food":
				nc._add("WORLD_EVENT", actor, "GAVE_RESOURCE", {"to": to_id, "object": "food"}, status, seq)
			"promise_made":
				nc._add("INTENTION", actor, "PROMISED", {"to": to_id}, status, seq)
			"promise_kept":
				nc._add("WORLD_EVENT", actor, "KEPT_PROMISE", {"to": to_id}, status, seq)
			"promise_broken":
				nc._add("WORLD_EVENT", actor, "BROKE_PROMISE", {"to": to_id}, status, seq)
			"rule_proposed":
				nc._add("INSTITUTION_STATE", actor, "PROPOSED_RULE",
					{"object": str(e.get("object", ""))}, status, seq)
			"institution_established":
				nc._add("INSTITUTION_STATE", actor, "RULE_ADOPTED",
					{"object": str(e.get("object", ""))}, status, seq)
			"storage_withheld":
				nc._add("WORLD_EVENT", actor, "VIOLATED",
					{"rule_id": str(e.get("rule_id", ""))}, status, seq,
					[str(e.get("trace_id", ""))] if str(e.get("trace_id", "")) != "" else [])
			"storage_contributed":
				nc._add("WORLD_EVENT", actor, "COMPLIED", {"rule_id": str(e.get("rule_id", "")),
					"required": int(e.get("required", 0)), "actual": int(e.get("amount", 0)), "ratio": 1.0},
					status, seq, [str(e.get("trace_id", ""))] if str(e.get("trace_id", "")) != "" else [])
			"storage_partial_comply":
				# P3a-2.1 修 2：部分遵守是一等语义——绝不压回"CONTRIBUTED"让 LLM 写成"履行了规则"
				var req2: int = maxi(1, int(e.get("required", 1)))
				nc._add("WORLD_EVENT", actor, "PARTIALLY_COMPLIED", {"rule_id": str(e.get("rule_id", "")),
					"required": int(e.get("required", 0)), "actual": int(e.get("amount", 0)),
					"ratio": clampf(float(e.get("amount", 0)) / float(req2), 0.0, 1.0)},
					status, seq, [str(e.get("trace_id", ""))] if str(e.get("trace_id", "")) != "" else [])
			"confronted_violation":
				nc._add("WORLD_EVENT", actor, "CONFRONTED", {"target": to_id}, status, seq)
			"relocated":
				nc._add("WORLD_EVENT", actor, "RELOCATED", {}, status, seq)
			"reason_asked":
				nc._add("INTENTION", actor, "SOUGHT_REASON", {"from": to_id}, status, seq)
			"reason_claimed":
				# P3a-2.1 修 1（truth-level bug）：说了 X ≠ 相信 X（Claim ≠ Speaker Belief）。
				# 世界事实只是"欧恩表达了这个结构化声明"； sincerity 永远 UNKNOWN。
				# OBJECTIVE 视角 → OBJECTIVE（之前误标 PERCEIVED）。
				# 只有说话者确有 belief 证据时，才由 trace 提取层另行生成 BELIEF_STATE。
				nc._add("SPEECH_ACT", actor, "STATED",
					{"proposition": str(e.get("claim", "")), "sincerity": "UNKNOWN"},
					"OBJECTIVE" if perspective == "OBJECTIVE" else "PERCEIVED", seq)
			"reflected":
				var txt := str(e.get("text", ""))
				if txt.find("错怪") != -1:
					nc._add("BELIEF", actor, "REVISED_BELIEF", {"about": txt.substr(0, 20)},
						"RETROSPECTIVE", seq)
				else:
					nc._add("BELIEF", actor, "REFLECTED", {}, "RETROSPECTIVE" if perspective != "OBJECTIVE" else status, seq)
			"explored_hurt":
				nc._add("WORLD_EVENT", actor, "INJURED", {}, status, seq)
			"weather_storm":
				nc._add("WORLD_EVENT", "", "STORM", {}, "OBJECTIVE", seq)
	# P3a-2.1：Trace 心理 Claims（确定性；LLM 永不能创建）
	# 内部状态只在 CHARACTER/RETROSPECTIVE 视角使用（OBJECTIVE 默认不用，第 9 条）
	if perspective != "OBJECTIVE" and actors.has(focus_actor) and focus_actor != "":
		nc._extract_psych(actors[focus_actor])
	# P3a-2.1：DECISION_FACTOR 从 institution trace（所有视角——决策因素是行为原因，非隐秘内心）
	for aid in actors:
		nc._extract_decision_factors(actors[aid])
	# P3a-2.1：CAUSAL_LINK 只从已批准结构边（绝不自己建边；CONTRIBUTED_TO 而非 CAUSED）
	for edge in edges:
		var esrc := str(edge.get("source", ""))
		if ["promise_linkage", "institution_linkage", "trace_linkage", "epistemic_linkage", "spatial_linkage"].has(esrc):
			var rel: String = {"FULFILLS": "FULFILLED", "VIOLATES": "VIOLATED", "ESTABLISHES": "ESTABLISHED",
				"CAUSE": "CONTRIBUTED_TO", "RESPONDS_TO": "TRIGGERED", "CHANGES_RELATIONSHIP": "CONTRIBUTED_TO"}.get(str(edge.get("relation", "")), "CONTRIBUTED_TO")
			nc._add("CAUSAL_LINK", "", rel, {"from": edge.get("from", ""), "to": edge.get("to", "")},
				"INFERRED", [], [], 0.9)  # 结构边 → 高置信但仍是 INFERRED（非直接观察）
	return nc.all()

## 心理状态提取：记忆里的解释分布 → INTERPRETATION（带 confidence）；反思 → BELIEF_REVISION
func _extract_psych(actor: Dictionary) -> void:
	for m in actor.get("memories", []):
		var interp: Dictionary = m.get("interpretation", {})
		if interp.is_empty():
			continue
		var dom := str(interp.get("dominant", ""))
		if dom == "":
			continue
		# 主导解释的权重 = confidence（解释竞争的真实分布，不是拍脑袋）
		var conf := 0.5
		for c in interp.get("candidates", []):
			if str(c.get("id", "")) == dom:
				conf = float(c.get("weight", 0.5))
		var subj := str(actor.get("id", ""))
		var cp := str(m.get("counterpart_id", ""))
		_add("INTERPRETATION", subj, "INTERPRETED_MOTIVE", {"actor": cp, "motive": dom},
			"INFERRED", [int(m.get("seq", -1))] if int(m.get("seq", -1)) >= 0 else [], [], conf)
	# 情绪：最近一次认知转移的情绪变化（只有最近的可提取——诚实局限）
	var lt: Dictionary = actor.get("last_transition", {})
	for em_key in lt.get("emotion_changes", {}):
		var em_val: float = float(lt["emotion_changes"][em_key])
		if absf(em_val) > 0.05:
			_add("EMOTION", str(actor.get("id", "")), "FELT_" + str(em_key).to_upper(),
				{"intensity": em_val}, "BELIEVED", [])

## 从 claim_ids 派生 source ids（LLM 未来只能给 claim_ids；底层 ids 由系统推导）
static func derive_sources(claims: Array, claim_ids: Array) -> Dictionary:
	var event_ids: Array = []
	var trace_ids: Array = []
	for c in claims:
		if claim_ids.has(str(c.get("claim_id", ""))):
			for e in c.get("source_event_ids", []):
				if not event_ids.has(int(e)):
					event_ids.append(int(e))
			for t in c.get("source_trace_ids", []):
				if str(t) != "" and not trace_ids.has(str(t)):
					trace_ids.append(str(t))
	return {"event_ids": event_ids, "trace_ids": trace_ids}

## 决策因素：从 institution trace 生成（只提取实际参与评分的变量；CONTRIBUTED_TO 而非 CAUSED）
func _extract_decision_factors(actor: Dictionary) -> void:
	var tr: Dictionary = actor.get("last_institution_trace", {})
	if tr.is_empty():
		return
	var subj := str(actor.get("id", ""))
	var mode := str(tr.get("mode", ""))
	var tid: Array = [str(tr.get("trace_id", ""))] if str(tr.get("trace_id", "")) != "" else []
	# 只提取 trace 里明确记录的决策变量（不猜测未记录的因素）
	var leg: float = float(tr.get("legitimacy", -1))
	if leg >= 0 and leg < 0.35 and (mode == "VIOLATE" or mode == "PARTIAL"):
		_add("DECISION_REASON", subj, "LOW_LEGITIMACY_FACTOR", {"action": mode, "legitimacy": leg},
			"INFERRED", [], tid, 0.8)
	var det: float = float(tr.get("detection", -1))
	if det >= 0 and det < 0.3 and mode == "VIOLATE":
		_add("DECISION_REASON", subj, "LOW_DETECTION_FACTOR", {"action": mode, "detection": det},
			"INFERRED", [], tid, 0.8)
	var rec: float = float(tr.get("recognition", -1))
	if rec >= 0.5:
		_add("DECISION_REASON", subj, "RECOGNIZED_RULE", {"action": mode, "recognition": rec},
			"INFERRED", [], tid, 0.9)
