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
	"RELATIONSHIP_CHANGE", "INSTITUTION_STATE", "CAUSAL_LINK", "UNCERTAINTY"]

var _claims: Array = []
var _next_id := 0

func _add(type: String, subject: String, predicate: String, object, status: String,
		event_ids: Array, trace_ids: Array = []) -> String:
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
static func extract(events: Array, perspective: String, focus_actor: String = "") -> Array:
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
				nc._add("WORLD_EVENT", actor, "WITHHELD_CONTRIBUTION",
					{"rule_id": str(e.get("rule_id", ""))}, status, seq,
					[str(e.get("trace_id", ""))] if str(e.get("trace_id", "")) != "" else [])
			"storage_contributed", "storage_partial_comply":
				nc._add("WORLD_EVENT", actor, "CONTRIBUTED",
					{"amount": int(e.get("amount", 0)), "required": int(e.get("required", 0))},
					status, seq, [str(e.get("trace_id", ""))] if str(e.get("trace_id", "")) != "" else [])
			"confronted_violation":
				nc._add("WORLD_EVENT", actor, "CONFRONTED", {"target": to_id}, status, seq)
			"relocated":
				nc._add("WORLD_EVENT", actor, "RELOCATED", {}, status, seq)
			"reason_asked":
				nc._add("INTENTION", actor, "SOUGHT_REASON", {"from": to_id}, status, seq)
			"reason_claimed":
				nc._add("BELIEF", actor, "STATED", {"claim": str(e.get("claim", ""))},
					"PERCEIVED" if actor != focus_actor else "BELIEVED", seq)
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
	# CAUSAL_LINK 主张：只从已验证的结构化因果边生成（NJ 的实现基础——
	# 调用方传入 edges，这里只转成 Claim，绝不自己推断因果）
	return nc.all()

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
