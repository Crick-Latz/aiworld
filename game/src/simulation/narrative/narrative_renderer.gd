class_name NarrativeRenderer
extends RefCounted
## P3a-1 统一渲染契约（Grounded Narrative Renderer Contract）：
##   输入：NarrativeIR（不是 EventLog、不是 WorldState）
##   输出：NarrativeOutput{text, beat_ids, source_event_ids, source_trace_ids}
##   职责：把 IR 已确定的信息变成人类可读文本——省略而非补全。
##
## 永久规则（总纲第 2/17 条）：
##   1. Renderer 不得返回任何 simulation mutation（READ ONLY）
##   2. 所有 source ids 必须属于输入 IR（Validator 强制）
##   3. IR 不支持的解释必须省略
##   4. 任何实现（Template/Mock/LLM）故障时 fallback 到 Template，模拟继续

const OUTPUT_SCHEMA_VERSION := "narrative-output-1.0"

## 统一入口：任何 renderer 实现都必须经此签名调用。
## renderer_impl 必须是 {render: Callable(ir, style, language, length) -> Dictionary}
static func render(renderer_impl: Dictionary, ir: Dictionary, style: String = "chronicle", language: String = "zh", length: int = 3) -> Dictionary:
	if renderer_impl.is_empty() or not renderer_impl.has("render"):
		return _fallback(ir, style, language, length, "E_RENDERER_MISSING")
	if not bool(ir.get("ok", false)):
		return _fallback(ir, style, language, length, "E_IR_INVALID")
	var raw = await (renderer_impl["render"] as Callable).call(ir, style, language, length)
	# Validator：LLM/Mock 输出一律验证；不合法 → fallback
	var verdict: Dictionary = NarrativeOutputValidator.validate(raw, ir)
	if bool(verdict.get("ok", false)):
		return raw
	return _fallback(ir, style, language, length, str(verdict.get("code", "E_VALIDATION")))

## 确定性 fallback：Template 渲染器永远可用（无外部依赖、无随机）
static func _fallback(ir: Dictionary, style: String, language: String, length: int, reason: String) -> Dictionary:
	var out: Dictionary = TemplateNarrativeRenderer.render(ir, style, language, length)
	out["fallback_reason"] = reason
	return out
