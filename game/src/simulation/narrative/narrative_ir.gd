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

## ── CausalGraph：因果边必须有结构来源，禁止时间推测 ──
static func build_causal_edges(events: Array) -> Array:
	var edges: Array = []
	var promises := {}    # promise 键 → made 事件（FULFILLS/VIOLATES 边）
	var traces := {}      # trace_id → trace（CAUSE 边：决策→行为）
	var rules := {}       # rule_id → proposal 事件（ESTABLISHES 边）
	var refusals_by_pair := {}  # 提出者→拒绝事件（MISUNDERSTANDING 种子）
	for e in events:
		var t := str(e.get("type", ""))
		var eid := int(e.get("seq", 0))
		match t:
			"promise_made":
				promises["%s->%s" % [str(e.get("actor_id", "")), str(e.get("to_id", ""))]] = eid
			"promise_kept":
				var k1 := "%s->%s" % [str(e.get("actor_id", "")), str(e.get("to_id", ""))]
				if promises.has(k1):
					edges.append({"from": promises[k1], "to": eid, "relation": "FULFILLS", "source": "promise_linkage"})
			"promise_broken":
				var k2 := "%s->%s" % [str(e.get("actor_id", "")), str(e.get("to_id", ""))]
				if promises.has(k2):
					edges.append({"from": promises[k2], "to": eid, "relation": "VIOLATES", "source": "promise_linkage"})
			"rule_proposed":
				if e.has("rule"):
					rules[str(e["rule"].get("rule_id", ""))] = eid
			"institution_established":
				if e.has("rule"):
					var rid := str(e["rule"].get("rule_id", ""))
					if rules.has(rid):
						edges.append({"from": rules[rid], "to": eid, "relation": "ESTABLISHES", "source": "institution_linkage"})
			"storage_contributed", "storage_withheld", "storage_partial_comply":
				var tid := str(e.get("trace_id", ""))
				if tid != "":
					edges.append({"from": tid, "to": eid, "relation": "CAUSE", "source": "trace_linkage"})
					if t == "storage_withheld":
						edges.append({"from": eid, "to": str(e.get("rule_id", "")), "relation": "VIOLATES", "source": "institution_linkage"})
			"food_request_refused", "water_request_refused", "tool_request_refused":
				refusals_by_pair["%s->%s" % [str(e.get("proposer_id", "")), str(e.get("actor_id", ""))]] = eid
			"reason_asked":
				var pair := "%s->%s" % [str(e.get("actor_id", "")), str(e.get("to_id", ""))]
				if refusals_by_pair.has(pair):
					edges.append({"from": refusals_by_pair[pair], "to": eid, "relation": "RESPONDS_TO", "source": "epistemic_linkage"})
			"relocated":
				edges.append({"from": eid, "to": eid, "relation": "CHANGES_RELATIONSHIP", "source": "spatial_linkage"})
	return edges

## ── StoryBeat 提取（8+1 类，结构分类非模板）──
static func extract_beats(events: Array, actors: Dictionary) -> Array:
	var beats: Array = []
	var refusals := {}   # pair_key -> {event, tick}
	var belief_revisions := []
	for e in events:
		var t := str(e.get("type", ""))
		var tick := int(e.get("tick", 0))
		match t:
			"promise_made":
				beats.append({"type": "PROMISE_ARC", "stage": "made", "actors": [str(e.get("actor_id", "")), str(e.get("to_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.4})
			"promise_kept":
				beats.append({"type": "PROMISE_ARC", "stage": "fulfilled", "actors": [str(e.get("actor_id", "")), str(e.get("to_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.7})
			"promise_broken":
				beats.append({"type": "PROMISE_ARC", "stage": "violated", "actors": [str(e.get("actor_id", "")), str(e.get("to_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.8})
			"food_request_refused", "water_request_refused", "tool_request_refused":
				refusals["%s->%s" % [str(e.get("proposer_id", "")), str(e.get("actor_id", ""))]] = {"seq": int(e.get("seq", 0)), "tick": tick}
			"reflected":
				var txt := str(e.get("text", ""))
				if txt.find("错怪") != -1:
					# BELIEF_REVISION：需要有更早的拒绝（MISUNDERSTANDING 配对）
					for pair in refusals:
						if str(pair).begins_with(str(e.get("actor_id", ""))):
							beats.append({"type": "MISUNDERSTANDING", "actors": [str(e.get("actor_id", "")), str(pair).split("->")[1]],
								"start_tick": int(refusals[pair]["tick"]), "end_tick": tick,
								"source_event_ids": [int(refusals[pair]["seq"]), int(e.get("seq", 0))], "significance": 0.9})
							beats.append({"type": "BELIEF_REVISION", "actors": [str(e.get("actor_id", ""))],
								"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.85})
							break
			"institution_established":
				beats.append({"type": "INSTITUTION_FORMATION", "actors": [str(e.get("actor_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.8})
			"rule_revised":
				beats.append({"type": "INSTITUTION_CONFLICT", "stage": "reformed", "actors": [str(e.get("actor_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.75})
			"storage_withheld":
				beats.append({"type": "INSTITUTION_CONFLICT", "stage": "hidden_violation", "actors": [str(e.get("actor_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.6})
			"confronted_violation":
				beats.append({"type": "INSTITUTION_CONFLICT", "stage": "enforced", "actors": [str(e.get("actor_id", "")), str(e.get("to_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.7})
			"relocated":
				beats.append({"type": "RELOCATION", "actors": [str(e.get("actor_id", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.5})
			"rule_supported":
				beats.append({"type": "AUTHORITY_CHANGE", "actors": [str(e.get("actor_id", "")), str(e.get("rule", {}).get("proposer", ""))],
					"start_tick": tick, "source_event_ids": [int(e.get("seq", 0))], "significance": 0.3})
	# ND：无源 beat 已被构造保证（每类都带 source_event_ids）
	return beats

## ── NarrativeSelector：显著性 = 状态变化幅度，非戏剧性（第 22-23 条）──
static func select_beats(beats: Array, limit: int) -> Array:
	var sorted := beats.duplicate()
	sorted.sort_custom(func(a, b): return float(a.get("significance", 0.0)) > float(b.get("significance", 0.0)))
	return sorted.slice(0, limit)

## ── NarrativeIR 组装（perspective 隔离在第 25 条）──
static func build_ir(sim, perspective: String, focus_actor: String, limit: int) -> Dictionary:
	var beats := select_beats(extract_beats(sim.events, sim.actors), limit)
	var known_facts: Array = []
	var subjective_facts: Array = []
	var forbidden: Array = []
	if perspective == "OBJECTIVE":
		for e in sim.events:
			known_facts.append({"tick": int(e.get("tick", 0)), "text": str(e.get("text", "")), "seq": int(e.get("seq", 0))})
		known_facts = known_facts.slice(maxi(0, known_facts.size() - limit * 3), known_facts.size())
	elif perspective == "CHARACTER":
		# 只用 focus_actor 当时感知到的（他的记忆 + 他的 ToM——不含世界真值）
		var a: Dictionary = sim.actors.get(focus_actor, {})
		for m in a.get("memories", []):
			subjective_facts.append({"tick": int(m.get("tick", 0)), "text": str(m.get("text", "")), "type": str(m.get("type", ""))})
		# 禁止推断：我不知道他人库存/他人是否说谎/未确立的情感
		for oid in sim.actors:
			if oid != focus_actor:
				forbidden.append("%s 的真实库存对 %s 不可见（除非目击声明或证据）" % [oid, focus_actor])
				forbidden.append("没有证据表明 %s 知道 %s 是否说谎" % [focus_actor, oid])
	elif perspective == "RETROSPECTIVE":
		# 允许后来修正：主观事实 + 反思洞察（带时间标记）
		var a2: Dictionary = sim.actors.get(focus_actor, {})
		for m2 in a2.get("memories", []):
			subjective_facts.append({"tick": int(m2.get("tick", 0)), "text": str(m2.get("text", "")), "type": str(m2.get("type", ""))})
		for e2 in sim.events:
			if str(e2.get("type", "")) == "reflected" and str(e2.get("actor_id", "")) == focus_actor:
				known_facts.append({"tick": int(e2.get("tick", 0)), "text": str(e2.get("text", "")), "seq": int(e2.get("seq", 0)), "retrospective": true})
	return {
		"perspective": perspective,
		"focus_actor": focus_actor,
		"window": {"start": 0, "end": sim.tick},
		"selected_beats": beats,
		"known_facts": known_facts,
		"subjective_facts": subjective_facts,
		"forbidden_inferences": forbidden,
		"source_refs": {"events": "sim.events[seq]", "traces": "actor.last_institution_trace"},
	}
