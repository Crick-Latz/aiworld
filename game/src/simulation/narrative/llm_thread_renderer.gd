class_name LlmThreadRenderer
extends RefCounted
## P4.3 Grounded LLM Thread Renderer（GPT 指令 2026-09-07）
## 管线：ThreadEngine → ThreadIR → 确定性 ThreadClaims → allowed package → LLM →
##        {sentences:[{text,claim_ids}]} → 校验 → ThreadSummaryRenderer fallback。
## 永久原则：LLM 负责讲故事，不负责决定故事是什么——
##   不能建/并/拆 Thread、不能改 status/episode、不能加 causal edge、
##   不能加动机、不能把 belief 写成 truth、不能编对话、不能引用 allowed 之外的 claim。
## 文本只读：渲染全程不碰 World/Cognition/Thread 结构（Text Invariance）。
## 第一版只做 neutral_story_summary 一种文风（§13）。

const DEPTHS := {"TITLE": 1, "SUMMARY": 4, "TIMELINE": 8}
const TURNING_EVENT_TYPES := ["promise_kept", "promise_broken", "confronted_violation", "institution_established"]
const MOTIVE_WORDS := ["背叛", "故意", "暗中", "企图", "心怀", "蓄意", "报复"]
const TRUTH_WORDS := ["真相", "原来真的", "终于知道", "事实证明"]
const RELATION_WORDS := ["友谊", "信任", "感情加深", "关系改善", "越来越亲"]
const CAUSAL_WORDS := ["因为", "所以", "于是", "导致", "因此"]

const PROMPT_SYSTEM := "你是一个故事线渲染器（Grounded Thread Renderer），不是故事生成器。\n" \
	+ "你会收到一条真实发生的故事线（thread）的原子主张（claims），每条有 claim_id、主体、谓词、认识层级与叙事角色。\n" \
	+ "你的唯一任务：把这些主张组织成自然的中文叙述，让机器日志读起来像故事。\n" \
	+ "深度要求：TITLE=1 句且极短；SUMMARY=2-4 句讲清开始/发展/结果或悬置；TIMELINE=按时间顺序逐段讲主要变化。\n" \
	+ "硬性禁止：\n" \
	+ "- 不得引入主张之外的事实、动机、情绪或对话（不得使用引号）\n" \
	+ "- BELIEVED/PERCEIVED 的主张只能写成『他认为/他以为/看起来』，绝不能写成客观事实\n" \
	+ "- 没有相应主张时不得写动机（背叛/故意/报复）、不得写关系升温（友谊/信任加深）、不得写因果连接（因为/所以）\n" \
	+ "- 主张不足以支撑的内容必须省略，不得补全\n" \
	+ "输出格式（严格 JSON，不要任何其他文字）：\n" \
	+ '{"sentences": [{"text": "句子", "claim_ids": ["C0"]}]}'

## ── ThreadIR（§3）：确定性构建。thread_role 由代码按节点位置/事件类型产生，非 LLM ──
static func build_render_ir(sim, thread: Dictionary) -> Dictionary:
	var nodes: Array = (thread.get("source_event_ids", []) as Array).duplicate()
	var names: Array = []
	for p in thread.get("participants", []):
		if sim.actors.has(str(p)):
			names.append(str(sim.actors[str(p)]["display_name"]))
		else:
			names.append(str(p))
	var name_map := {}
	for p in thread.get("participants", []):
		if sim.actors.has(str(p)):
			name_map[str(p)] = str(sim.actors[str(p)]["display_name"])
	var claims_all: Array = NarrativeClaim.extract(sim.events, "OBJECTIVE", "")
	var seed_seq := int(nodes[0]) if not nodes.is_empty() else -1
	var resolved_tick := int(thread.get("resolved_tick", -1))
	var thread_claims: Array = []
	for c in claims_all:
		var hit := -1
		for se in c.get("source_event_ids", []):
			if nodes.has(int(se)):
				hit = int(se)
				break
		if hit < 0:
			continue
		var role := "DEVELOPMENT"
		if hit == seed_seq:
			role = "OPENING"
		elif resolved_tick >= 0 and _tick_of_seq(sim, hit) >= resolved_tick:
			role = "RESOLUTION"
		elif TURNING_EVENT_TYPES.has(_type_of_seq(sim, hit)) or str(c.get("type", "")) == "CAUSAL_LINK":
			role = "TURNING_POINT"
		var subj := str(c.get("subject", ""))
		var subj_name := str(name_map.get(subj, subj))
		var obj: Variant = c.get("object", {})
		var obj_name: Variant = obj
		if typeof(obj) == TYPE_STRING and name_map.has(str(obj)):
			obj_name = name_map[str(obj)]
		thread_claims.append({
			"claim_id": str(c.get("claim_id", "")),
			"type": str(c.get("type", "")),
			"subject": subj_name,
			"predicate": str(c.get("predicate", "")),
			"object": obj_name,
			"epistemic_status": str(c.get("epistemic_status", "OBJECTIVE")),
			"thread_role": role,
			"tick_hint": _tick_of_seq(sim, hit),
			"source_event_ids": (c.get("source_event_ids", []) as Array).duplicate(),
			"source_trace_ids": (c.get("source_trace_ids", []) as Array).duplicate(),
		})
	thread_claims.sort_custom(func(a, b): return int(a["tick_hint"]) < int(b["tick_hint"]))
	var start_tick := int(thread.get("opened_tick", 0))
	var last_tick := int(thread.get("last_activity_tick", start_tick))
	var ordered: Array = []
	var resolution_ids: Array = []
	var unresolved_ids: Array = []
	for tc in thread_claims:
		ordered.append(str(tc["claim_id"]))
		if str(tc["thread_role"]) == "RESOLUTION":
			resolution_ids.append(str(tc["claim_id"]))
		else:
			unresolved_ids.append(str(tc["claim_id"]))
	return {
		"ok": not thread_claims.is_empty(),
		"thread_id": str(thread.get("thread_id", "")),
		"thread_type": str(thread.get("thread_type", "")),
		"status": str(thread.get("status", "")),
		"resolution": str(thread.get("resolution", "")),
		"actors": names,
		"start_tick": start_tick,
		"last_tick": last_tick,
		"duration": maxi(1, last_tick - start_tick),
		"perspective": "OBJECTIVE",
		"ordered_claim_ids": ordered,
		"resolution_claim_ids": resolution_ids,
		"unresolved_claim_ids": unresolved_ids,
		"allowed_claims": thread_claims,
		"source_refs": nodes,  # validator/debug 用——绝不发给 LLM（§3）
	}

static func _tick_of_seq(sim, seq: int) -> int:
	for e in sim.events:
		if int(e.get("seq", -1)) == seq:
			return int(e.get("tick", 0))
	return 0

static func _type_of_seq(sim, seq: int) -> String:
	for e in sim.events:
		if int(e.get("seq", -1)) == seq:
			return str(e.get("type", ""))
	return ""

## ── 主入口：render(config, render_ir, depth, ev_lookup) → 统一输出（含 fallback）──
static func render(config: Dictionary, render_ir: Dictionary, depth: String, ev_lookup: Dictionary = {}) -> Dictionary:
	if not DEPTHS.has(depth):
		return _fallback(render_ir, depth, ev_lookup, "bad_depth")
	if not bool(render_ir.get("ok", false)):
		return _fallback(render_ir, depth, ev_lookup, "empty_thread")  # LA
	var package := _build_package(render_ir, depth)
	if package.is_empty():
		return _fallback(render_ir, depth, ev_lookup, "no_claims")
	var raw := ""
	if config.has("mock_raw"):
		raw = str(config["mock_raw"])  # 测试通道：注入 LLM 原始输出（同一解析/校验路径）
	elif not config.is_empty() and config.has("api_key"):
		raw = await _call_api(config, package)
	if raw == "":
		return _fallback(render_ir, depth, ev_lookup, "network_fail")
	var parsed := _parse_and_guard(raw, render_ir)
	if parsed.is_empty():
		return _fallback(render_ir, depth, ev_lookup, _last_reject)
	parsed["depth"] = depth
	return parsed

static var _last_reject := ""

## ── 最小权限 package（§10）：只有主张摘要，绝无 EventLog/WorldState/隐藏信念 ──
static func _build_package(render_ir: Dictionary, depth: String) -> Array:
	var out_claims: Array = []
	for c in render_ir.get("allowed_claims", []):
		out_claims.append({
			"claim_id": str(c["claim_id"]),
			"subject": str(c["subject"]),
			"predicate": str(c["predicate"]),
			"object": c["object"],
			"epistemic_status": str(c["epistemic_status"]),
			"thread_role": str(c["thread_role"]),
			"tick_hint": int(c["tick_hint"]),
		})
	if out_claims.is_empty():
		return []
	return [{
		"thread_type": str(render_ir.get("thread_type", "")),
		"status": str(render_ir.get("status", "")),
		"resolution": str(render_ir.get("resolution", "")),
		"duration_ticks": int(render_ir.get("duration", 0)),
		"participants": render_ir.get("actors", []),
		"depth": depth,
		"max_sentences": int(DEPTHS[depth]),
		"style": "neutral_story_summary",
		"claims": out_claims,
	}]

## ── 解析 + 守卫（LF/LG/LH/LI/§5-9 全部在这层确定性执行）──
static func _parse_and_guard(raw: String, render_ir: Dictionary) -> Dictionary:
	_last_reject = ""
	var json_text := raw.strip_edges()
	if json_text.begins_with("```"):
		json_text = json_text.substr(json_text.find("\n") + 1)
		json_text = json_text.replace("```", "")
	var parsed: Variant = JSON.parse_string(json_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_reject = "invalid_json"
		return {}
	var sentences_raw: Array = parsed.get("sentences", [])
	if sentences_raw.is_empty():
		_last_reject = "no_sentences"
		return {}
	var by_id := {}
	for c in render_ir.get("allowed_claims", []):
		by_id[str(c["claim_id"])] = c
	var sentences: Array = []
	var sid := 0
	for sn in sentences_raw:
		if typeof(sn) != TYPE_DICTIONARY:
			continue
		var text := str(sn.get("text", "")).strip_edges()
		var cids: Array = sn.get("claim_ids", [])
		if text == "" or cids.is_empty():
			continue  # LE：无 claim 的句子剔除
		var cited: Array = []
		var all_valid := true
		for cid in cids:
			if not by_id.has(str(cid)):
				all_valid = false  # LD：幻觉 id 剔除整句
				break
			cited.append(by_id[str(cid)])
		if not all_valid:
			continue
		# LH：禁止编造对话
		if text.find("「") != -1 or text.find("」") != -1 or text.find("『") != -1 or text.find("』") != -1 or text.find("“") != -1 or text.find("”") != -1 or text.find(String.chr(34)) != -1:
			continue
		# LF：动机词需要 INTERPRETATION/DECISION_REASON 主张支撑
		if _has_any(text, MOTIVE_WORDS) and not _cited_has_type(cited, ["INTERPRETATION", "DECISION_REASON"]):
			continue
		# LG：believed→truth 升级禁止——真相词需要 OBJECTIVE 主张支撑
		if _has_any(text, TRUTH_WORDS) and not _cited_has_status(cited, ["OBJECTIVE"]):
			continue
		# §7：关系升温词需要 RELATIONSHIP_CHANGE 支撑
		if _has_any(text, RELATION_WORDS) and not _cited_has_type(cited, ["RELATIONSHIP_CHANGE"]):
			continue
		# LI：因果连接词需要 CAUSAL_LINK 支撑
		if _has_any(text, CAUSAL_WORDS) and not _cited_has_type(cited, ["CAUSAL_LINK"]):
			continue
		var derived: Dictionary = NarrativeClaim.derive_sources(render_ir.get("allowed_claims", []), cids)
		sentences.append({
			"sentence_id": "S%d" % sid,
			"text": text,
			"claim_ids": cids,
			"thread_roles": _roles_of(render_ir, cids),
			"source_event_ids": derived["event_ids"],
			"source_trace_ids": derived["trace_ids"],
		})
		sid += 1
	if sentences.is_empty():
		_last_reject = "all_sentences_rejected"
		return {}
	return {
		"ok": true, "renderer": "llm",
		"text": "\n".join(sentences.map(func(s): return str(s["text"]))),
		"sentences": sentences,
		"source_event_ids": _collect(sentences, "source_event_ids"),
		"source_trace_ids": _collect(sentences, "source_trace_ids"),
		"schema_version": "thread-render-1.0",
	}

## ── Fallback：ThreadSummaryRenderer（确定性模板，§15）──
static func _fallback(render_ir: Dictionary, depth: String, ev_lookup: Dictionary, reason: String) -> Dictionary:
	var text := ""
	match depth:
		"TITLE":
			text = ThreadSummaryRenderer.render_title(_to_legacy_ir(render_ir))
		"SUMMARY":
			text = ThreadSummaryRenderer.render_summary(_to_legacy_ir(render_ir), ev_lookup)
		"TIMELINE":
			var lines: Array = ThreadSummaryRenderer.render_timeline(_to_legacy_ir(render_ir), ev_lookup)
			text = "\n".join(lines)
	return {"ok": true, "renderer": "template", "depth": depth, "text": text,
		"sentences": [], "fallback_reason": reason, "schema_version": "thread-render-1.0"}

## build_render_ir → ThreadSummaryRenderer 期望的 legacy 字段
static func _to_legacy_ir(render_ir: Dictionary) -> Dictionary:
	return {
		"thread_type": render_ir.get("thread_type", ""),
		"status": render_ir.get("status", ""),
		"resolution": render_ir.get("resolution", ""),
		"participants": ",".join(render_ir.get("actors", [])),
		"opened_day": int(render_ir.get("start_tick", 0)) / 24 + 1,
		"last_activity_day": int(render_ir.get("last_tick", 0)) / 24 + 1,
		"title_seed": _title_seed(str(render_ir.get("thread_type", "")), render_ir.get("actors", [])),
		"source_event_ids": render_ir.get("source_refs", []),
	}

static func _title_seed(thread_type: String, names: Array) -> String:
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
			return "营地规则的争议"
		"AUTHORITY_THREAD":
			return "%s的影响力" % n
		"RELOCATION_THREAD":
			return "%s的迁移" % n
	return n + "的故事线"

static func _has_any(text: String, words: Array) -> bool:
	for w in words:
		if text.find(str(w)) != -1:
			return true
	return false

static func _cited_has_type(cited: Array, types: Array) -> bool:
	for c in cited:
		if types.has(str(c.get("type", ""))):
			return true
	return false

static func _cited_has_status(cited: Array, statuses: Array) -> bool:
	for c in cited:
		if statuses.has(str(c.get("epistemic_status", ""))):
			return true
	return false

static func _roles_of(render_ir: Dictionary, cids: Array) -> Array:
	var out: Array = []
	for c in render_ir.get("allowed_claims", []):
		if cids.has(str(c["claim_id"])):
			out.append(str(c["thread_role"]))
	return out

static func _collect(sentences: Array, field: String) -> Array:
	var out: Array = []
	for sn in sentences:
		for v in sn.get(field, []):
			if not out.has(v):
				out.append(v)
	return out

## ── API（沿用 P3 已验证的 OpenAI 兼容调用；同步阻塞可接受——渲染离主循环）──
static func _call_api(config: Dictionary, package: Array) -> String:
	var http := HTTPRequest.new()
	http.timeout = float(config.get("timeout_seconds", 8))
	var tree := Engine.get_main_loop()
	if tree is SceneTree:
		(tree as SceneTree).root.add_child(http)
	var body := JSON.stringify({
		"model": str(config.get("model", "glm-4-flash")),
		"temperature": 0.2,
		"messages": [
			{"role": "system", "content": PROMPT_SYSTEM},
			{"role": "user", "content": JSON.stringify(package)},
		],
	})
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer " + str(config["api_key"]),
	])
	var url := str(config.get("base_url", "")).rstrip("/") + "/chat/completions"
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		if http.get_parent():
			http.queue_free()
		return ""
	var result: Array = await http.request_completed
	if http.get_parent():
		http.queue_free()
	if result.size() < 4 or int(result[1]) != 200:
		return ""
	var json: Variant = JSON.parse_string(str(result[3].get_string_from_utf8()))
	if typeof(json) != TYPE_DICTIONARY:
		return ""
	var choices: Array = json.get("choices", [])
	if choices.is_empty():
		return ""
	return str(choices[0].get("message", {}).get("content", ""))
