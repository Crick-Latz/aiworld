class_name NarrativeOutputValidator
extends RefCounted
## P3a-4 输出安全验证器：LLM/Mock 返回后不直接展示。
## 至少验证（总纲第 16.4 条）：
##   1. beat_ids 均存在于输入 IR
##   2. source_event_ids 均属于输入 IR 的 event_refs
##   3. source_trace_ids 均属于输入 IR 的 trace_refs
##   4. 无未知 actor（文本中不得出现 IR 之外的实体名——第一版校验 id 集）
##   5. 不允许新增 quoted dialogue（IR 无 speech content 时输出不得含直引号对话）
##   6. text 非空、结构完整
## 无法验证 → reject → fallback TemplateRenderer

static func validate(output, ir: Dictionary) -> Dictionary:
	if typeof(output) != TYPE_DICTIONARY:
		return {"ok": false, "code": "E_OUTPUT_NOT_DICT", "message": "输出必须是 Dictionary"}
	var o: Dictionary = output
	if not bool(o.get("ok", true)):
		return {"ok": false, "code": "E_OUTPUT_REJECTED", "message": str(o.get("code", ""))}
	var text := str(o.get("text", ""))
	if text.strip_edges() == "":
		return {"ok": false, "code": "E_TEXT_EMPTY", "message": "text 不得为空"}
	# 1. beat_ids ⊆ IR.beat_ids
	var ir_beats: Dictionary = {}
	for b in ir.get("selected_beats", []):
		ir_beats[str(b.get("beat_id", ""))] = true
	var out_beats: Array = o.get("beat_ids", [])
	for b in out_beats:
		if not ir_beats.has(str(b)):
			return {"ok": false, "code": "E_BEAT_UNKNOWN", "message": "beat_id 不在输入 IR: %s" % str(b)}
	# 2. event_ids ⊆ IR.event_refs
	var ir_events: Dictionary = {}
	for e in ir.get("source_refs", {}).get("event_ids", []):
		ir_events[int(e)] = true
	var out_events: Array = o.get("source_event_ids", [])
	var ir_event_list: Array = ir.get("source_refs", {}).get("event_ids", [])
	var ir_beat_list: Array = ir.get("selected_beats", [])
	if out_events.is_empty() and ir_event_list.size() > 0 and ir_beat_list.size() > 0:
		return {"ok": false, "code": "E_SOURCE_MISSING", "message": "有可引事件却未带任何 source_event_ids"}
	for e in out_events:
		if not ir_events.has(int(e)):
			return {"ok": false, "code": "E_EVENT_UNKNOWN", "message": "source_event_id 不在输入 IR: %s" % str(e)}
	# 3. trace_ids ⊆ IR.trace_refs
	var ir_traces: Dictionary = {}
	for t in ir.get("source_refs", {}).get("trace_ids", []):
		ir_traces[str(t)] = true
	for t in o.get("source_trace_ids", []):
		if not ir_traces.has(str(t)):
			return {"ok": false, "code": "E_TRACE_UNKNOWN", "message": "trace_id 不在输入 IR: %s" % str(t)}
	# 4. 无未知 actor id（IR 的 actors 并集 = beats.actors + focus）
	var known_actors: Dictionary = {}
	var focus := str(ir.get("focus_actor", ""))
	if focus != "":
		known_actors[focus] = true
	for b in ir.get("selected_beats", []):
		for a in b.get("actors", []):
			known_actors[str(a)] = true
	for a in o.get("mentioned_actors", []):  # renderer 若显式声明提到的 actor
		if not known_actors.has(str(a)):
			return {"ok": false, "code": "E_ACTOR_UNKNOWN", "message": "输出了 IR 之外的 actor: %s" % str(a)}
	# 5. 禁止编造对话：IR 无 speech 字段 → 输出文本不得含直引号对话（「」或 “” 包裹的引语）
	if not _ir_has_speech(ir) and _has_quoted_speech(text):
		return {"ok": false, "code": "E_DIALOGUE_FABRICATED", "message": "IR 无 speech content，输出不得包含引号对话"}
	return {"ok": true, "code": "OK", "message": ""}

static func _ir_has_speech(ir: Dictionary) -> bool:
	for f in ir.get("known_facts", []):
		if bool(f.get("is_speech", false)):
			return true
	for f in ir.get("subjective_facts", []):
		if bool(f.get("is_speech", false)):
			return true
	return false

static func _has_quoted_speech(text: String) -> bool:
	# 直引号对话模式：『…』「…」“…”（成对出现才算引语）
	return (text.count("『") > 0 and text.count("』") > 0) \
		or (text.count("「") > 0 and text.count("」") > 0) \
		or (text.count("“") > 0 and text.count("”") > 0)
