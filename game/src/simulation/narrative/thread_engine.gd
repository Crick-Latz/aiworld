class_name ThreadEngine
extends RefCounted
## P4 ThreadEngine：从真实事件流中识别和更新 StoryThread。
## READ-ONLY——不修改任何模拟状态（TH 测试验证）。
##
## ThreadSeed 来源（GPT 第 63 条，全确定性）：
##   promise_made → PROMISE_THREAD
##   food/water/tool_request_refused + 高熵解释 → EPISTEMIC_THREAD
##   food_request_accepted / shared_food → RECIPROCITY_THREAD
##   confronted_violation → RELATIONSHIP_CONFLICT
##   storage_withheld → INSTITUTION_CONFLICT
##   rule_supported → AUTHORITY_THREAD
##   relocated → RELOCATION_THREAD

var engine := StoryThread.new()
var _last_processed_seq := -1

## 主入口：传入模拟事件 + 因果边 + actor 状态
func process(sim) -> void:
	var edges: Array = NarrativeIR.build_causal_edges(sim.events)
	engine.sim_actors_ref = sim.actors
	for e in sim.events:
		var seq := int(e.get("seq", 0))
		if seq <= _last_processed_seq:
			continue
		_last_processed_seq = seq
		var t := str(e.get("type", ""))
		# ThreadSeed 检测
		_try_seed(t, e, sim)
		# 事件入现有线程
		engine.ingest_event(e, edges)
	# 状态更新
	engine.update_threads(sim.tick)

func _try_seed(event_type: String, e: Dictionary, sim) -> void:
	var actor := str(e.get("actor_id", ""))
	var to_id := str(e.get("to_id", str(e.get("proposer_id", ""))))
	var tick := int(e.get("tick", 0))
	var seq := int(e.get("seq", 0))

	match event_type:
		"promise_made":
			if actor != "" and to_id != "":
				engine.open_thread("PROMISE_THREAD", [actor, to_id], seq, tick,
					{"promisor": actor, "promisee": to_id},
					"promise|%s|%s|%d" % [actor, to_id, seq])
		"food_request_refused", "water_request_refused", "tool_request_refused":
			# EPISTEMIC_THREAD：被拒者有 open_question 时
			var proposer := str(e.get("proposer_id", ""))
			if proposer != "" and actor != "" and sim.actors.has(proposer):
				var has_question := false
				for q in sim.actors[proposer].get("open_questions", []):
					if str(q.get("about", "")) == actor:
						has_question = true
						break
				if has_question:
					engine.open_thread("EPISTEMIC_THREAD", [proposer, actor], seq, tick,
						{"asker": proposer, "subject": actor})
		"food_request_accepted", "water_request_accepted", "tool_request_accepted":
			var proposer := str(e.get("proposer_id", ""))
			if actor != "" and proposer != "":
				engine.open_thread("RECIPROCITY_THREAD", [actor, proposer], seq, tick,
					{"helper": actor, "receiver": proposer},
					"reciprocity|%s|%s|%d" % [actor, proposer, seq])
		"shared_food":
			if actor != "" and to_id != "":
				engine.open_thread("RECIPROCITY_THREAD", [actor, to_id], seq, tick,
					{"helper": actor, "receiver": to_id},
					"reciprocity|%s|%s|%d" % [actor, to_id, seq])
		"confronted_violation":
			if actor != "" and to_id != "":
				engine.open_thread("RELATIONSHIP_CONFLICT", [actor, to_id], seq, tick,
					{"confronter": actor, "confronted": to_id},
					"conflict|%s|%s|%d" % [actor, to_id, seq])
		"storage_withheld":
			if actor != "":
				engine.open_thread("INSTITUTION_CONFLICT", [actor], seq, tick,
					{"violator": actor, "rule_id": str(e.get("rule_id", ""))},
					"institution|%s" % str(e.get("rule_id", "")))
		"rule_supported":
			if actor != "":
				engine.open_thread("AUTHORITY_THREAD", [actor], seq, tick,
					{"supporter": actor})
		"relocated":
			if actor != "":
				engine.open_thread("RELOCATION_THREAD", [actor], seq, tick,
					{"mover": actor})

## ThreadIR（第 39 条）：给 Renderer/Observer 的结构化摘要
func build_thread_ir(sim, thread: Dictionary) -> Dictionary:
	var participants: Array = thread.get("participants", [])
	var names: Array = []
	for p in participants:
		if sim.actors.has(str(p)):
			names.append(str(sim.actors[str(p)]["display_name"]))
		else:
			names.append(str(p))
	var title_seed := _title_seed(str(thread.get("thread_type", "")), names)
	var opening_claims: Array = []
	var latest_claims: Array = []
	var resolution_claims: Array = []
	# 从 NarrativeClaim 提取相关 claims
	var all_claims: Array = NarrativeClaim.extract(sim.events, "OBJECTIVE", "")
	for c in all_claims:
		var src_events: Array = c.get("source_event_ids", [])
		for se in src_events:
			if (thread.get("source_event_ids", []) as Array).has(int(se)):
				if opening_claims.size() < 3:
					opening_claims.append(str(c.get("claim_id", "")))
				latest_claims = [str(c.get("claim_id", ""))]
				if str(thread.get("status", "")) == "RESOLVED":
					resolution_claims = [str(c.get("claim_id", ""))]
	return {
		"thread_id": str(thread.get("thread_id", "")),
		"thread_type": str(thread.get("thread_type", "")),
		"title_seed": title_seed,
		"status": str(thread.get("status", "")),
		"resolution": str(thread.get("resolution", "")),
		"participants": names,
		"opened_day": int(thread.get("opened_tick", 0)) / 24 + 1,
		"last_activity_day": int(thread.get("last_activity_tick", 0)) / 24 + 1,
		"node_count": (thread.get("source_event_ids", []) as Array).size(),
		"opening_claims": opening_claims,
		"latest_claims": latest_claims,
		"resolution_claims": resolution_claims,
		"source_event_ids": thread.get("source_event_ids", []),
	}

func _title_seed(thread_type: String, names: Array) -> String:
	var n := "、".join(names)
	match thread_type:
		"PROMISE_THREAD":
			return "%s的承诺" % n
		"EPISTEMIC_THREAD":
			return "%s的疑问" % n
		"RELATIONSHIP_CONFLICT":
			return "%s的冲突" % n
		"RECIPROCITY_THREAD":
			return "%s的互助" % n
		"INSTITUTION_CONFLICT":
			return "制度争议（%s）" % n
		"AUTHORITY_THREAD":
			return "%s的影响力变化" % n
		"RELOCATION_THREAD":
			return "%s的迁居" % n
	return n
