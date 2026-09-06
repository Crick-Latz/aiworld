class_name TemplateNarrativeRenderer
extends RefCounted
## P3a-2 确定性模板渲染器：
##   - 验证 IR 足够表达内容（IR 表达力的试金石）
##   - LLM 不可用时的 fallback
##   - LLM 幻觉对照组（同一 IR，模板输出永远可追溯）
## 零随机、零外部依赖——同 IR 必须产生 byte-identical 输出。

const BEAT_LABELS := {
	"MISUNDERSTANDING": "一场误会",
	"BELIEF_REVISION": "认识的转变",
	"PROMISE_ARC": "承诺",
	"INSTITUTION_FORMATION": "新规矩的诞生",
	"INSTITUTION_CONFLICT": "规矩受到挑战",
	"AUTHORITY_CHANGE": "威信的变化",
	"RELOCATION": "迁居",
	"RECIPROCITY": "互助",
	"REQUEST_CONFLICT": "求助风波",
}

static func render(ir: Dictionary, _style: String = "chronicle", language: String = "zh", length: int = 3) -> Dictionary:
	if not bool(ir.get("ok", false)):
		return _reject("E_IR_INVALID", "IR 无效")
	var lines: Array = []
	var beat_ids: Array = []
	var event_ids: Array = []
	var trace_ids: Array = []
	# 头行：视角标记（CHARACTER/RETROSPECTIVE 明确时间层级）
	var perspective := str(ir.get("perspective", "OBJECTIVE"))
	var focus := str(ir.get("focus_actor", ""))
	if perspective == "OBJECTIVE":
		lines.append("【营地记事】")
	elif perspective == "CHARACTER":
		lines.append("【%s 的所见所感】" % _actor_name(ir, focus))
	else:
		lines.append("【%s 的回望】" % _actor_name(ir, focus))
	# 主体：每个 beat 一句话，全部从 source_event_ids 回溯原文
	var beats: Array = ir.get("selected_beats", [])
	var used := 0
	for beat in beats:
		if used >= maxi(1, length):
			break
		var bid := str(beat.get("beat_id", ""))
		var btype := str(beat.get("type", ""))
		var src_events: Array = beat.get("source_event_ids", [])
		if bid == "":
			continue
			if src_events.is_empty():
				# 无源事件但 beat 有效：计入 ids，文本省略（省略而非补全）
				beat_ids.append(bid)
				continue
		var label := str(BEAT_LABELS.get(btype, btype))
		var quote := _first_event_text(ir, int(src_events[0]))
		if quote == "":
			beat_ids.append(bid)
			continue
		if perspective == "RETROSPECTIVE" and int(beat.get("start_tick", 0)) > 0:
			lines.append("第 %d 天·%s——%s" % [_day_of(int(beat.get("start_tick", 0))), label, quote])
		else:
			lines.append("%s——%s" % [label, quote])
		beat_ids.append(bid)
		for s in src_events:
			event_ids.append(int(s))
		var t: Array = beat.get("source_trace_ids", [])
		for tid in t:
			trace_ids.append(str(tid))
		used += 1
	# IR 不足以支持任何叙述 → 明确说"没有值得记的事"，而不是编造
	if used == 0:
		lines.append("这一天没有什么值得记下的事。" if language == "zh" else "Nothing noteworthy.")
	return {"ok": true, "text": "\n".join(lines), "beat_ids": beat_ids,
		"source_event_ids": event_ids, "source_trace_ids": trace_ids,
		"renderer": "template", "schema_version": "narrative-output-1.0"}

static func _actor_name(ir: Dictionary, actor_id: String) -> String:
	# IR 不携带 names 表时退回 id（不读取 sim——renderer 只见 IR）
	return actor_id

static func _first_event_text(ir: Dictionary, seq: int) -> String:
	# 从 IR 的已知事实里找原文（OBJECTIVE 在 known_facts；CHARACTER 在 subjective_facts）
	for f in ir.get("known_facts", []):
		if int(f.get("seq", -1)) == seq:
			return str(f.get("text", ""))
	for f in ir.get("subjective_facts", []):
		if (f.get("source_event_ids", []) as Array).has(seq):
			return str(f.get("text", ""))
	return ""

static func _day_of(tick: int) -> int:
	return tick / 24 + 1

static func _reject(code: String, msg: String) -> Dictionary:
	return {"ok": false, "code": code, "message": msg, "text": "", "beat_ids": [],
		"source_event_ids": [], "source_trace_ids": [], "renderer": "template"}
