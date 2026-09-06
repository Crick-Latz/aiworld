class_name StoryThread
extends RefCounted
## P4 长时程故事线（Long-Horizon Story Threads）：
## 回答"这件事其实已经持续多久了？"（StoryBeat 回答"刚才发生了什么？"）。
##
## 永久原则（GPT 第 2/3 条）：
##   READS history / NEVER WRITES future
##   不增加 Utility / 不创建 Goal / 不改变 Emotion / 不触发 Event / 不要求闭合
##   真实世界完全不知道 StoryThread 存在。
##
## 线程关联三级优先（第 24 条）：
##   Tier 1 — Explicit Identity Link（promise_id/institution_id/question_id）最强
##   Tier 2 — Approved Causal Edge（CausalGraph 结构边）
##   Tier 3 — Semantic + Participant Continuity（严格 fallback：同参与者+兼容语义+关系/claim 链接）
## 禁止纯时间邻近关联（第 25 条）。
## Precision > Recall（第 60 条）：宁可 orphan beat，不要 false story。

const STATUSES := ["OPEN", "ACTIVE", "DORMANT", "RESOLVED", "SUPERSEDED"]
const TYPES := ["PROMISE_THREAD", "EPISTEMIC_THREAD", "RELATIONSHIP_CONFLICT",
	"RECIPROCITY_THREAD", "INSTITUTION_CONFLICT", "AUTHORITY_THREAD", "RELOCATION_THREAD"]

const DORMANT_AFTER_TICKS := 120  # 5 游戏日无相关事件 → DORMANT（不是 RESOLVED！第 6 条）

var threads: Array = []
var _next_id := 0

## ── Thread 创建（只从结构化 ThreadSeed，GPT 第 62-63 条）──
func open_thread(thread_type: String, participants: Array, seed_event_seq: int, seed_tick: int, identity: Dictionary, episode_key: String = "") -> String:
	var tid := "TH_%03d" % _next_id
	_next_id += 1
	threads.append({
		"thread_id": tid,
		"thread_type": thread_type,
		"participants": participants,
		"identity": identity,
		"episode_key": episode_key,  # P4.1: 唯一 episode ID（不是 dyad！同 dyad 可有多个独立 episode）
		"opened_tick": seed_tick,
		"last_activity_tick": seed_tick,
		"resolved_tick": -1,
		"status": "OPEN",
		"activity_score": 1.0,
		"opening_nodes": [seed_event_seq],
		"causal_nodes": [],
		"latest_nodes": [],
		"unresolved_items": [],
		"significance": 0.5,
		"source_event_ids": [seed_event_seq],
		"resolution": "",
		"resolution_reason": "",
		"parent_thread_id": "",
		"related_thread_ids": [],
	})
	return tid

## ── 事件入线程（三级关联，GPT 第 24-26 条）──
func ingest_event(e: Dictionary, causal_edges: Array) -> void:
	var t := str(e.get("type", ""))
	var seq := int(e.get("seq", 0))
	var tick := int(e.get("tick", 0))
	var actor := str(e.get("actor_id", ""))
	var to_id := str(e.get("to_id", str(e.get("proposer_id", ""))))

	# P4.1 Tier 1：episode_key 匹配（每个承诺/疑问/冲突是独立 episode——不是 dyad！）
	for th in threads:
		if _is_resolved_or_superseded(th):
			continue
		var th_ep := str(th.get("episode_key", ""))
		if th_ep != "" and _episode_match(th_ep, e):
			_add_node(th, seq, tick)
			_check_resolution(th, e)
			_record_attachment(th, seq, "TIER_1_EXPLICIT_ID")
			return
	# P4.1 legacy Tier 1：dyad fallback（仅对无 episode_key 的线程）
	for th in threads:
		if _is_resolved_or_superseded(th):
			continue
		if str(th.get("episode_key", "")) != "":
			continue  # 有 episode_key 的线程不用 dyad 匹配
		if _tier1_match(th, e):
			_add_node(th, seq, tick)
			_check_resolution(th, e)
			_record_attachment(th, seq, "TIER_1_DYAD_FALLBACK")
			return

	# Tier 2：因果边匹配
	for edge in causal_edges:
		var to_node := str(edge.get("to", ""))
		if to_node.begins_with("event:") and to_node.substr(6).to_int() == seq:
			var from_node := str(edge.get("from", ""))
			if from_node.begins_with("event:"):
				var from_seq := from_node.substr(6).to_int()
				for th in threads:
					if _is_resolved_or_superseded(th):
						continue
					if (th["source_event_ids"] as Array).has(from_seq):
						_add_node(th, seq, tick)
						_check_resolution(th, e)
						return

	# Tier 3：严格的语义+参与者 fallback（第 26 条：同参与者 + 兼容语义 + 关系链接）
	var tier3_thread = _tier3_strict_match(e, actor, to_id, t)
	if tier3_thread != null:
		_add_node(tier3_thread, seq, tick)
		_check_resolution(tier3_thread, e)

func _tier1_match(th: Dictionary, e: Dictionary) -> bool:
	var t := str(e.get("type", ""))
	var identity: Dictionary = th.get("identity", {})

	# PROMISE_THREAD：promise 事件通过 to_id + actor dyad 匹配
	if str(th.get("thread_type", "")) == "PROMISE_THREAD":
		var promisor := str(identity.get("promisor", ""))
		var promisee := str(identity.get("promisee", ""))
		var actor := str(e.get("actor_id", ""))
		var to_id := str(e.get("to_id", ""))
		# promise_made 的 actor=promisor, to=promisee
		if t == "promise_made" and actor == promisor and to_id == promisee:
			return true
		# promise_kept/broken 的 actor=promisor, to=promisee
		if t in ["promise_kept", "promise_broken"] and actor == promisor and to_id == promisee:
			return true
		# 求助/分享与承诺相关（reciprocity 链）
		if t in ["food_request_accepted", "shared_food"] and actor == promisor and to_id == promisee:
			return true
		return false

	# EPISTEMIC_THREAD：question_id 匹配或同 dyad 的认识行动
	if str(th.get("thread_type", "")) == "EPISTEMIC_THREAD":
		var asker := str(identity.get("asker", ""))
		var subject := str(identity.get("subject", ""))
		var actor2 := str(e.get("actor_id", ""))
		var to2 := str(e.get("to_id", ""))
		# 认识行动（ask/observe/claim）在匹配 dyad 上
		if t in ["reason_asked", "reason_claimed", "reason_deflected", "observing_person", "asked_about", "third_party_claimed"]:
			if actor2 == asker and to2 == subject:
				return true
		# 拒绝事件在匹配 dyad 上（thread 的 opening）
		if t in ["food_request_refused", "water_request_refused", "tool_request_refused"]:
			var prop := str(e.get("proposer_id", ""))
			if prop == asker and actor2 == subject:
				return true
		# 反思（belief revision）由 asker 产生
		if t == "reflected" and actor2 == asker:
			var txt := str(e.get("text", ""))
			if txt.find("错怪") != -1:
				return true  # belief revision 关闭 epistemic thread
		# 空 hand 而归（evidence against hypothesis）
		if t in ["foraged_empty", "fished_empty", "ruins_empty"]:
			if asker != "" and _is_observer_of(sim_actors_ref, asker, actor2):
				return true
		return false

	# RECIPROCITY_THREAD：同 dyad 的帮助/回报
	if str(th.get("thread_type", "")) == "RECIPROCITY_THREAD":
		var helper := str(identity.get("helper", ""))
		var receiver := str(identity.get("receiver", ""))
		var actor3 := str(e.get("actor_id", ""))
		var to3 := str(e.get("to_id", str(e.get("proposer_id", ""))))
		if t in ["food_request_accepted", "shared_food"] and actor3 == helper and to3 == receiver:
			return true
		# 反向（receiver 回报 helper）
		if t in ["food_request_accepted", "shared_food"] and actor3 == receiver and to3 == helper:
			return true
		return false

	return false

# sim_actors_ref 用于 Tier 3 的距离检查（由 ThreadEngine 设置）
var sim_actors_ref: Dictionary = {}

func _is_observer_of(actors: Dictionary, observer_id: String, actor_id: String) -> bool:
	if not actors.has(actor_id) or not actors.has(observer_id):
		return false
	var obs_tile: Vector2i = actors[observer_id].get("tile", Vector2i(999, 999))
	var act_tile: Vector2i = actors[actor_id].get("tile", Vector2i(-999, -999))
	return absi(obs_tile.x - act_tile.x) + absi(obs_tile.y - act_tile.y) <= 8

func _tier3_strict_match(e: Dictionary, actor: String, to_id: String, event_type: String):
	# 第 26 条：same participants + compatible thread semantic + relevant link
	# 极其保守——只匹配同 dyad 的同类型后续事件
	if actor == "" or to_id == "":
		return null
	for th in threads:
		if _is_resolved_or_superseded(th):
			continue
		var parts: Array = th.get("participants", [])
		if parts.size() == 2:
			var pair_a := [str(parts[0]), str(parts[1])]
			var dyad_match: bool = (actor == pair_a[0] and to_id == pair_a[1]) or (actor == pair_a[1] and to_id == pair_a[0])
			if dyad_match and _compatible_semantic(str(th.get("thread_type", "")), event_type):
				return th
	return null

func _compatible_semantic(thread_type: String, event_type: String) -> bool:
	match thread_type:
		"PROMISE_THREAD":
			return event_type in ["promise_made", "promise_kept", "promise_broken", "remind_promise"]
		"EPISTEMIC_THREAD":
			return event_type in ["reason_asked", "reason_claimed", "reason_deflected", "reflected",
				"food_request_refused", "foraged_empty", "fished_empty"]
		"RELATIONSHIP_CONFLICT":
			return event_type in ["confronted_violation", "kept_distance", "relocated",
				"food_request_refused", "rule_opposed"]
		"RECIPROCITY_THREAD":
			return event_type in ["food_request_accepted", "shared_food", "promise_kept"]
		"INSTITUTION_CONFLICT":
			return event_type in ["storage_withheld", "storage_partial_comply", "storage_contributed",
				"confronted_violation", "rule_revised", "rule_proposed", "rule_opposed", "rule_supported"]
		"AUTHORITY_THREAD":
			return event_type in ["rule_supported", "rule_proposed", "institution_established", "rule_revised"]
		"RELOCATION_THREAD":
			return event_type in ["relocated", "found_person", "request_missed"]
	return false

func _check_resolution(th: Dictionary, e: Dictionary) -> void:
	var t := str(e.get("type", ""))
	var tt := str(th.get("thread_type", ""))
	if tt == "PROMISE_THREAD":
		if t == "promise_kept":
			th["status"] = "RESOLVED"
			th["resolved_tick"] = int(e.get("tick", 0))
			th["resolution"] = "FULFILLED"
			th["resolution_reason"] = str(e.get("text", ""))
		elif t == "promise_broken":
			th["status"] = "RESOLVED"
			th["resolved_tick"] = int(e.get("tick", 0))
			th["resolution"] = "VIOLATED"
			th["resolution_reason"] = str(e.get("text", ""))
	elif tt == "EPISTEMIC_THREAD":
		if t == "reflected":
			var txt := str(e.get("text", ""))
			if txt.find("错怪") != -1:
				th["status"] = "RESOLVED"
				th["resolved_tick"] = int(e.get("tick", 0))
				th["resolution"] = "BELIEF_REVISED"
				th["resolution_reason"] = txt.substr(0, 40)
		elif t in ["reason_claimed"]:
			# 收到声明但不一定可信——降级为 ACTIVE（仍不确定）
			th["status"] = "ACTIVE"

func _add_node(th: Dictionary, seq: int, tick: int) -> void:
	th["causal_nodes"].append(seq)
	th["source_event_ids"].append(seq)
	th["latest_nodes"] = [seq]
	th["last_activity_tick"] = tick
	th["activity_score"] = 1.0
	if th["status"] == "OPEN":
		th["status"] = "ACTIVE"
	elif th["status"] == "DORMANT":
		th["status"] = "ACTIVE"  # Reactivation（第 32 条）

func _is_resolved_or_superseded(th: Dictionary) -> bool:
	return str(th.get("status", "")) in ["RESOLVED", "SUPERSEDED"]

## ── 状态更新（每 N tick 调用）──
func update_threads(current_tick: int) -> void:
	for th in threads:
		if _is_resolved_or_superseded(th):
			continue
		var idle := current_tick - int(th.get("last_activity_tick", 0))
		if idle > DORMANT_AFTER_TICKS and str(th.get("status", "")) == "ACTIVE":
			th["status"] = "DORMANT"  # 第 6 条：时间过去 ≠ 问题解决
			th["activity_score"] = 0.0

func threads_for_actor(actor_id: String) -> Array:
	var out: Array = []
	for th in threads:
		if (th.get("participants", []) as Array).has(actor_id):
			out.append(th)
	return out

func thread_by_id(tid: String):
	for th in threads:
		if str(th.get("thread_id", "")) == tid:
			return th
	return {}

func stats() -> Dictionary:
	var s := {"opened": threads.size(), "active": 0, "dormant": 0, "resolved": 0, "reactivated": 0}
	for th in threads:
		match str(th.get("status", "")):
			"ACTIVE": s["active"] += 1
			"DORMANT": s["dormant"] += 1
			"RESOLVED": s["resolved"] += 1
	return s

## P4.1: episode_key 匹配（事件 → 线程的唯一标识——不是 dyad）
func _episode_match(episode_key: String, e: Dictionary) -> bool:
	var parts := episode_key.split("|")
	if parts.size() < 2:
		return false
	var kind := parts[0]
	var actor := str(e.get("actor_id", ""))
	var to_id := str(e.get("to_id", str(e.get("proposer_id", ""))))
	match kind:
		"promise":
			if parts.size() >= 3:
				return actor == parts[1] and to_id == parts[2] and str(e.get("type", "")) in ["promise_kept", "promise_broken", "remind_promise"]
		"question":
			if parts.size() >= 3:
				return actor == parts[1] and to_id == parts[2] and str(e.get("type", "")) in ["reason_asked", "reason_claimed", "reason_deflected", "observing_person", "reflected", "foraged_empty", "fished_empty"]
		"institution":
			return str(e.get("rule_id", "")) == parts[1]
		"reciprocity":
			if parts.size() >= 3:
				return (actor == parts[1] and to_id == parts[2]) or (actor == parts[2] and to_id == parts[1])
		"conflict":
			if parts.size() >= 3:
				return (actor == parts[1] or to_id == parts[1]) and str(e.get("type", "")) in ["confronted_violation", "kept_distance", "relocated"]
	return false

## P4.1: 记录 attachment provenance（每个节点为什么被加入这个线程）
func _record_attachment(th: Dictionary, node_seq: int, tier: String) -> void:
	var att: Array = th.get("attachments", [])
	att.append({"node": node_seq, "tier": tier, "tick": int(th.get("last_activity_tick", 0))})
	th["attachments"] = att

## P4.1: Thread Purity——同一线程不得包含多个独立 episode
func check_purity() -> int:
	var contaminated := 0
	for th in threads:
		var tt := str(th.get("thread_type", ""))
		if tt in ["PROMISE_THREAD", "EPISTEMIC_THREAD", "RECIPROCITY_THREAD"]:
			var key := str(th.get("episode_key", ""))
			var seeds := 0
			for n in th.get("opening_nodes", []):
				seeds += 1
			if seeds > 1:
				contaminated += 1
	return contaminated

## P4.1: 统计 attachment tier 分布
func attachment_stats() -> Dictionary:
	var out := {"tier1": 0, "tier2": 0, "tier3": 0, "total": 0}
	for th in threads:
		for att in th.get("attachments", []):
			out["total"] += 1
			match str(att.get("tier", "")):
				"TIER_1_EXPLICIT_ID", "TIER_1_DYAD_FALLBACK":
					out["tier1"] += 1
				"TIER_2_CAUSAL_EDGE":
					out["tier2"] += 1
				"TIER_3_SEMANTIC":
					out["tier3"] += 1
	return out
