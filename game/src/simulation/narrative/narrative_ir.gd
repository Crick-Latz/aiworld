class_name NarrativeIR
extends RefCounted
## P3a Narrative IR（确定性叙事中间层）：LLM 完全处在最后。
##   EventLog + DecisionTrace + Belief/Evidence + Institution Lifecycle
##     → CausalGraph（禁止时间邻近=因果）
##     → StoryBeat 确定性提取（对已发生因果结构分类，非剧情模板）
##     → NarrativeIR（perspective + known_facts + forbidden_inferences + source_refs）
##     → LLM Renderer（READ ONLY，输出必须带 source ids）
##
## 三视角（第 25-26 条）：OBJECTIVE 只用世界真值；CHARACTER 只用该角色当时
## 感知到的（玩家知道欧恩有粮 ≠ 薇拉的编年史知道）；RETROSPECTIVE 允许写
## 后来的修正但必须标时间。

const BEAT_TYPES := ["MISUNDERSTANDING", "BELIEF_REVISION", "REQUEST_CONFLICT",
	"RECIPROCITY", "PROMISE_ARC", "INSTITUTION_FORMATION", "INSTITUTION_CONFLICT",
	"AUTHORITY_CHANGE", "RELOCATION"]

const SCHEMA_VERSION := "narrative-ir-1.0"
const PERSPECTIVES := ["OBJECTIVE", "CHARACTER", "RETROSPECTIVE"]

static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message, "schema_version": SCHEMA_VERSION}

static func _event_node_id(seq: int) -> String:
	return "event:%d" % seq

static func _trace_node_id(trace_id: String) -> String:
	return "trace:%s" % trace_id

static func _validate_events(events) -> Dictionary:
	if typeof(events) != TYPE_ARRAY:
		return _error("E_NARRATIVE_EVENTS_INVALID", "events 必须是 Array")
	var seen := {}
	for raw in events:
		if typeof(raw) != TYPE_DICTIONARY:
			return _error("E_NARRATIVE_EVENT_INVALID", "event 必须是 Dictionary")
		var seq = raw.get("seq", null)
		if typeof(seq) != TYPE_INT or int(seq) < 0:
			return _error("E_NARRATIVE_EVENT_ID_INVALID", "event.seq 必须是非负整数")
		if seen.has(int(seq)):
			return _error("E_NARRATIVE_EVENT_ID_DUPLICATE", "event.seq 不得重复")
		seen[int(seq)] = true
	return {"ok": true, "code": "OK", "message": "", "seen": seen}

## ── CausalGraph：因果边必须有结构来源，禁止时间推测 ──
static func build_causal_graph(events) -> Dictionary:
	var valid := _validate_events(events)
	if not bool(valid.get("ok", false)):
		return valid
	var nodes: Array = []
	var edges: Array = []
	var node_ids := {}
	var event_by_seq := {}
	var rule_proposals := {}
	for raw in events:
		var e: Dictionary = raw
		var seq := int(e["seq"])
		var event_id := _event_node_id(seq)
		nodes.append({"id": event_id, "kind": "EVENT", "seq": seq, "event_type": str(e.get("type", ""))})
		node_ids[event_id] = true
		event_by_seq[seq] = e
		var trace_id := str(e.get("trace_id", ""))
		if trace_id != "":
			var trace_node := _trace_node_id(trace_id)
			if not node_ids.has(trace_node):
				nodes.append({"id": trace_node, "kind": "TRACE", "trace_id": trace_id})
				node_ids[trace_node] = true
		if str(e.get("type", "")) == "rule_proposed" and typeof(e.get("rule", null)) == TYPE_DICTIONARY:
			var rid := str((e["rule"] as Dictionary).get("rule_id", ""))
			if rid != "":
				rule_proposals[rid] = seq
	for raw in events:
		var e: Dictionary = raw
		var seq := int(e["seq"])
		var to_id := _event_node_id(seq)
		var event_type := str(e.get("type", ""))
		var sources = e.get("source_event_ids", [])
		if typeof(sources) == TYPE_ARRAY:
			for raw_source in sources:
				if typeof(raw_source) != TYPE_INT:
					continue
				var source_seq := int(raw_source)
				var from_id := _event_node_id(source_seq)
				if source_seq == seq or not event_by_seq.has(source_seq):
					continue
				var relation := "CAUSES"
				var source_kind := "explicit_event_linkage"
				if event_type == "promise_kept" or event_type == "promise_broken":
					relation = "FULFILLS" if event_type == "promise_kept" else "VIOLATES"
					source_kind = "promise_linkage"
				elif event_type == "institution_established" or event_type == "rule_revised":
					relation = "ESTABLISHES" if event_type == "institution_established" else "REVISES"
					source_kind = "institution_linkage"
				elif ["reason_asked", "asked_about", "reason_claimed", "reason_deflected", "third_party_claimed", "third_party_unknown"].has(event_type):
					relation = "RESPONDS_TO"
					source_kind = "epistemic_linkage"
				edges.append({"from": from_id, "to": to_id, "relation": relation, "source": source_kind})
		var trace_id := str(e.get("trace_id", ""))
		if trace_id != "":
			edges.append({"from": _trace_node_id(trace_id), "to": to_id, "relation": "CAUSES", "source": "trace_linkage"})
		var rule_id := str(e.get("rule_id", ""))
		if rule_id == "" and typeof(e.get("rule", null)) == TYPE_DICTIONARY:
			rule_id = str((e["rule"] as Dictionary).get("rule_id", ""))
		if rule_id != "" and rule_proposals.has(rule_id):
			var proposal_seq := int(rule_proposals[rule_id])
			if proposal_seq != seq and not _has_edge(edges, _event_node_id(proposal_seq), to_id):
				edges.append({"from": _event_node_id(proposal_seq), "to": to_id, "relation": "GOVERNS", "source": "institution_linkage"})
	edges.sort_custom(func(a, b):
		var ka := "%s|%s|%s" % [str(a["from"]), str(a["to"]), str(a["relation"])]
		var kb := "%s|%s|%s" % [str(b["from"]), str(b["to"]), str(b["relation"])]
		return ka < kb)
	return {"ok": true, "code": "OK", "message": "", "nodes": nodes, "edges": edges}

static func _has_edge(edges: Array, from_id: String, to_id: String) -> bool:
	for edge in edges:
		if str(edge.get("from", "")) == from_id and str(edge.get("to", "")) == to_id:
			return true
	return false

static func build_causal_edges(events) -> Array:
	var graph := build_causal_graph(events)
	return graph.get("edges", []) if bool(graph.get("ok", false)) else []

## ── StoryBeat：只按结构字段分类，自然语言文本不参与事实或因果判断 ──
static func _source_ids(e: Dictionary, include_self: bool = true) -> Array:
	var out: Array = []
	var sources = e.get("source_event_ids", [])
	if typeof(sources) == TYPE_ARRAY:
		for raw in sources:
			if typeof(raw) == TYPE_INT and int(raw) >= 0 and not out.has(int(raw)):
				out.append(int(raw))
	var own := int(e.get("seq", 0))
	if include_self and e.has("seq") and own >= 0 and not out.has(own):
		out.append(own)
	out.sort()
	return out

static func _actors_of(e: Dictionary) -> Array:
	var out: Array = []
	for key in ["actor_id", "proposer_id", "to_id", "target_id", "about_id"]:
		var id := str(e.get(key, ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out

static func _make_beat(type: String, stage: String, e: Dictionary, significance: float) -> Dictionary:
	var source_ids := _source_ids(e, true)
	var id_parts: Array = []
	for source_id in source_ids:
		id_parts.append(str(source_id))
	var trace_ids: Array = []
	var trace_id := str(e.get("trace_id", ""))
	if trace_id != "":
		trace_ids.append(trace_id)
	return {"beat_id": "beat:%s:%s:%s" % [type, stage, ",".join(id_parts)],
		"type": type, "stage": stage, "actors": _actors_of(e),
		"start_tick": int(e.get("tick", 0)), "source_event_ids": source_ids,
		"source_trace_ids": trace_ids, "significance": significance}

static func extract_beats(events, actors = {}) -> Array:
	if not bool(_validate_events(events).get("ok", false)):
		return []
	var beats: Array = []
	for raw in events:
		var e: Dictionary = raw
		match str(e.get("type", "")):
			"food_request_refused", "water_request_refused", "tool_request_refused":
				beats.append(_make_beat("REQUEST_CONFLICT", "refused", e, 0.65))
			"shared_food", "food_request_accepted", "water_request_accepted", "tool_request_accepted":
				beats.append(_make_beat("RECIPROCITY", "helped", e, 0.55))
			"promise_made":
				beats.append(_make_beat("PROMISE_ARC", "made", e, 0.4))
			"promise_kept":
				beats.append(_make_beat("PROMISE_ARC", "fulfilled", e, 0.7))
			"promise_broken":
				beats.append(_make_beat("PROMISE_ARC", "violated", e, 0.8))
			"reflected":
				if str(e.get("reflection_kind", "")) == "belief_revision" and not _source_ids(e, false).is_empty():
					beats.append(_make_beat("MISUNDERSTANDING", "resolved", e, 0.9))
					beats.append(_make_beat("BELIEF_REVISION", "revised", e, 0.85))
			"institution_established":
				beats.append(_make_beat("INSTITUTION_FORMATION", "established", e, 0.8))
			"rule_revised":
				beats.append(_make_beat("INSTITUTION_CONFLICT", "reformed", e, 0.75))
			"storage_withheld":
				beats.append(_make_beat("INSTITUTION_CONFLICT", "hidden_violation", e, 0.6))
			"confronted_violation":
				beats.append(_make_beat("INSTITUTION_CONFLICT", "enforced", e, 0.7))
			"relocated":
				beats.append(_make_beat("RELOCATION", "moved", e, 0.5))
			"rule_supported":
				beats.append(_make_beat("AUTHORITY_CHANGE", "endorsed", e, 0.3))
	return beats

## ── NarrativeSelector：显著性 = 状态变化幅度，非戏剧性（第 22-23 条）──
static func select_beats(beats: Array, limit: int) -> Array:
	var sorted := beats.duplicate(true)
	sorted.sort_custom(func(a, b):
		var sa := float(a.get("significance", 0.0))
		var sb := float(b.get("significance", 0.0))
		if not is_equal_approx(sa, sb):
			return sa > sb
		var ta := int(a.get("start_tick", 0))
		var tb := int(b.get("start_tick", 0))
		if ta != tb:
			return ta < tb
		return str(a.get("beat_id", "")) < str(b.get("beat_id", "")))
	return sorted.slice(0, maxi(0, limit))

## ── NarrativeIR 组装（perspective 隔离在第 25 条）──
static func build_ir(sim, perspective: String, focus_actor: String, limit: int) -> Dictionary:
	if sim == null:
		return _error("E_NARRATIVE_SIM_INVALID", "simulation 不可为空")
	if not PERSPECTIVES.has(perspective):
		return _error("E_NARRATIVE_PERSPECTIVE_INVALID", "未知 perspective")
	var events = sim.events
	var actors = sim.actors
	var valid := _validate_events(events)
	if not bool(valid.get("ok", false)):
		return valid
	if perspective != "OBJECTIVE" and (focus_actor == "" or not actors.has(focus_actor)):
		return _error("E_NARRATIVE_ACTOR_NOT_FOUND", "focus_actor 不存在")
	var visible_events: Array = []
	var known_facts: Array = []
	var subjective_facts: Array = []
	var forbidden: Array = []
	if perspective == "OBJECTIVE":
		visible_events = events.duplicate(true)
		for e in visible_events:
			known_facts.append({"tick": int(e.get("tick", 0)), "text": str(e.get("text", "")), "seq": int(e.get("seq", 0))})
		known_facts = known_facts.slice(maxi(0, known_facts.size() - maxi(0, limit) * 3), known_facts.size())
	else:
		var actor: Dictionary = actors[focus_actor]
		var known_ids := {}
		for m in actor.get("memories", []):
			var mem_seq := int(m.get("seq", 0))
			if m.has("seq") and mem_seq >= 0:
				known_ids[mem_seq] = true
			subjective_facts.append({"tick": int(m.get("tick", 0)), "text": str(m.get("text", "")),
				"type": str(m.get("type", "")), "source_event_ids": [mem_seq] if m.has("seq") and mem_seq >= 0 else []})
		for e in events:
			var seq := int(e.get("seq", 0))
			if known_ids.has(seq):
				visible_events.append(e.duplicate(true))
			elif perspective == "RETROSPECTIVE" and str(e.get("type", "")) == "reflected" and str(e.get("actor_id", "")) == focus_actor:
				visible_events.append(e.duplicate(true))
				known_facts.append({"tick": int(e.get("tick", 0)), "text": str(e.get("text", "")),
					"seq": seq, "retrospective": true})
		for oid in actors:
			if oid != focus_actor:
				forbidden.append({"kind": "HIDDEN_STATE", "subject_id": str(oid), "field": "inventory",
					"reason": "未被该角色感知的真实库存不可叙述"})
				forbidden.append({"kind": "UNSUPPORTED_MENTAL_STATE", "subject_id": str(oid),
					"field": "truthfulness", "reason": "没有证据时不得判断是否说谎"})
	var graph := build_causal_graph(visible_events)
	if not bool(graph.get("ok", false)):
		return graph
	var beats := select_beats(extract_beats(visible_events, actors), limit)
	var event_refs: Array = []
	var trace_refs: Array = []
	for e in visible_events:
		event_refs.append(int(e.get("seq", 0)))
		var trace_id := str(e.get("trace_id", ""))
		if trace_id != "" and not trace_refs.has(trace_id):
			trace_refs.append(trace_id)
	var beat_refs: Array = []
	for beat in beats:
		beat_refs.append(str(beat.get("beat_id", "")))
	var result := {"ok": true, "code": "OK", "message": "", "schema_version": SCHEMA_VERSION,
		"perspective": perspective, "focus_actor": focus_actor,
		"window": {"start": 0, "end": int(sim.tick)}, "causal_graph": graph,
		"selected_beats": beats, "known_facts": known_facts,
		"subjective_facts": subjective_facts, "forbidden_inferences": forbidden,
		"source_refs": {"event_ids": event_refs, "trace_ids": trace_refs, "beat_ids": beat_refs}}
	result["ir_hash"] = _sha256(JSON.stringify(_canonicalize(result)))
	return result

static func _canonicalize(value):
	if typeof(value) == TYPE_DICTIONARY:
		var out := {}
		var keys: Array = value.keys()
		keys.sort_custom(func(a, b): return str(a) < str(b))
		for key in keys:
			out[key] = _canonicalize(value[key])
		return out
	if typeof(value) == TYPE_ARRAY:
		var out_array: Array = []
		for item in value:
			out_array.append(_canonicalize(item))
		return out_array
	return value

static func _sha256(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var bytes := text.to_utf8_buffer()
	if not bytes.is_empty():
		ctx.update(bytes)
	return ctx.finish().hex_encode()
