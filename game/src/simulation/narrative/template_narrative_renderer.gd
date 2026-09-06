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

## P3a-2 claim-first 渲染：每句 = 一组已验证的原子主张（sentence contract）
static func render(ir: Dictionary, style: String = "neutral_chronicle", language: String = "zh", length: int = 3) -> Dictionary:
	if not bool(ir.get("ok", false)):
		return _reject("E_IR_INVALID", "IR 无效")
	var sentences: Array = []
	var beats: Array = ir.get("selected_beats", [])
	var claims: Array = ir.get("claims", [])
	var claim_by_id := {}
	for c in claims:
		claim_by_id[str(c.get("claim_id", ""))] = c
	# 头行（HEADER：允许零 claim）
	var perspective := str(ir.get("perspective", "OBJECTIVE"))
	var focus := str(ir.get("focus_actor", ""))
	var header := _style_header(style, perspective, focus)
	sentences.append({"sentence_id": "S0", "kind": "HEADER", "text": header, "claim_ids": [], "beat_ids": [], "source_event_ids": [], "source_trace_ids": []})
	var used := 0
	var sid_n := 1
	for beat in beats:
		if used >= maxi(1, length):
			break
		var bid := str(beat.get("beat_id", ""))
		var cids: Array = beat.get("claim_ids", [])
		if bid == "" or cids.is_empty():
			continue
		var label := str(BEAT_LABELS.get(str(beat.get("type", "")), str(beat.get("type", ""))))
		# 句子文本由 claims 确定性合成（不是自由发挥）
		var c0: Dictionary = claim_by_id.get(str(cids[0]), {})
		if c0.is_empty():
			continue
		var subj := str(c0.get("subject", ""))
		var pred := str(c0.get("predicate", ""))
		var body := "%s %s" % [subj, PREDICATE_LABELS.get(pred, pred)]
		var text := _style_sentence(style, label, body, int(beat.get("start_tick", 0)), perspective)
		# 来源：从 claim_ids 系统派生（NL：LLM 未来只给 claim_ids，ids 由系统推导）
		var derived: Dictionary = NarrativeClaim.derive_sources(claims, cids)
		sentences.append({"sentence_id": "S%d" % sid_n, "kind": "CONTENT", "text": text,
			"claim_ids": cids.duplicate(), "beat_ids": [bid],
			"source_event_ids": derived["event_ids"], "source_trace_ids": derived["trace_ids"]})
		sid_n += 1
		used += 1
	if used == 0:
		sentences.append({"sentence_id": "S%d" % sid_n, "kind": "EMPTY_DAY", "text": "这一天没有什么值得记下的事。" if language == "zh" else "Nothing noteworthy.", "claim_ids": [], "beat_ids": [], "source_event_ids": [], "source_trace_ids": []})
	var full_text: Array = []
	for sn in sentences:
		full_text.append(str(sn.get("text", "")))
	return {"ok": true, "text": "
".join(full_text), "sentences": sentences,
		"beat_ids": _collect(sentences, "beat_ids"), "source_event_ids": _collect(sentences, "source_event_ids"),
		"source_trace_ids": _collect(sentences, "source_trace_ids"),
		"renderer": "template", "schema_version": "narrative-output-1.1"}

static func _collect(sentences: Array, field: String) -> Array:
	var out: Array = []
	for sn in sentences:
		for v in sn.get(field, []):
			if not out.has(v):
				out.append(v)
	return out

const PREDICATE_LABELS := {
	"REFUSED_REQUEST": "拒绝了求助",
	"GRANTED_REQUEST": "答应了求助",
	"GAVE_RESOURCE": "分出了食物",
	"PROMISED": "许下了承诺",
	"KEPT_PROMISE": "兑现了承诺",
	"BROKE_PROMISE": "违背了承诺",
	"PROPOSED_RULE": "提议了新规矩",
	"RULE_ADOPTED": "让规矩立了起来",
	"WITHHELD_CONTRIBUTION": "没有按约交公",
	"CONTRIBUTED": "交了公粮",
	"CONFRONTED": "当面对质",
	"RELOCATED": "搬了家",
	"SOUGHT_REASON": "去问了缘由",
	"STATED": "说了什么",
	"REVISED_BELIEF": "重新审视了自己的判断",
	"REFLECTED": "想了很久",
	"INJURED": "受了伤",
	"STORM": "暴风雨来了",
}
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

## ── P3a-4 风格系统：不同 style 的 claims/beat_ids 完全相同（NX 断言），只变表面语言 ──
const STYLES := ["neutral_chronicle", "concise_historical", "character_diary"]

static func _style_header(style: String, perspective: String, focus: String) -> String:
	match style:
		"concise_historical":
			return "· 摘要 ·" if perspective == "OBJECTIVE" else "· %s ·" % focus
		"character_diary":
			return "——%s——" % focus if focus != "" else "· 日记 ·"
		_:  # neutral_chronicle（默认）
			if perspective == "CHARACTER":
				return "【%s 的所见所感】" % focus
			elif perspective == "RETROSPECTIVE":
				return "【%s 的回望】" % focus
			return "【营地记事】"

static func _style_sentence(style: String, label: String, body: String, tick: int, _perspective: String) -> String:
	var day := tick / 24 + 1
	match style:
		"concise_historical":
			return body  # 极简：无标签无天数——只有谓语事实
		"character_diary":
			return "第%d天，%s。（%s）" % [day, body, label]
		_:  # neutral_chronicle
			return "%s——%s" % [label, body]

## 置信度措辞（第 16 条）：<0.6 怀疑 / 0.6-0.8 认为 / >0.8 几乎认定
static func confidence_hedge(confidence: float) -> String:
	if confidence < 0.6:
		return "似乎"
	elif confidence <= 0.8:
		return ""
	return "显然"