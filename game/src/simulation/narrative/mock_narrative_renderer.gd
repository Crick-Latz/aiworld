class_name MockNarrativeRenderer
extends RefCounted
## P3a-3 Mock 渲染器：模拟真实 LLM provider 的全部故障模式，用于验证
## 契约/Validator/fallback 在真实 API 接入前就锁死。
## 与既有 MockProvider（ai_mock.gd 体系）同哲学：零网络、确定性故障注入。

# mode: "ok" | "timeout" | "malformed" | "missing_sources" | "fabricated_dialogue" | "hallucinated_ids" | "crash"
static func make(mode: String = "ok") -> Dictionary:
	return {"render": func(ir: Dictionary, style: String, language: String, length: int): return MockNarrativeRenderer._dispatch(mode, ir, style, language, length)}

static func _dispatch(mode: String, ir: Dictionary, style: String, language: String, length: int):
	match mode:
		"ok":
			return _mode_ok(ir, style, language, length)
		"timeout":
			return null  # 模拟 provider 无响应（render 返回 null）
		"malformed":
			return {"text": "残缺输出没有 ids", "random_field": true}  # 缺 beat_ids/source_ids
		"missing_sources":
			return {"ok": true, "text": "看起来正确但没带任何来源。", "beat_ids": [], "source_event_ids": [], "source_trace_ids": []}
		"fabricated_dialogue":
			return {"ok": true, "text": "薇拉说：“你为什么不给我食物？”", "beat_ids": _first_beat(ir), "source_event_ids": _first_events(ir), "source_trace_ids": []}
		"hallucinated_ids":
			return {"ok": true, "text": "编造的叙述。", "beat_ids": ["beat_999"], "source_event_ids": [99999], "source_trace_ids": ["trace_ghost"]}
		"crash":
			return {}  # 模拟 provider 崩溃（空 dict）
		_:
			return null

static func _mode_ok(ir: Dictionary, _style: String, _language: String, length: int) -> Dictionary:
	# 合规输出：模板内容 + 正确 ids（模拟"完美 LLM"对照组）
	var t: Dictionary = TemplateNarrativeRenderer.render(ir, _style, _language, length)
	t["renderer"] = "mock-llm"
	return t

static func _first_beat(ir: Dictionary) -> Array:
	var beats: Array = ir.get("selected_beats", [])
	if beats.is_empty():
		return []
	return [str(beats[0].get("beat_id", ""))]

static func _first_events(ir: Dictionary) -> Array:
	var evts: Array = ir.get("source_refs", {}).get("event_ids", [])
	if evts.is_empty():
		return []
	return [int(evts[0])]
