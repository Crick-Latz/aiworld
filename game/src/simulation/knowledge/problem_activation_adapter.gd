class_name ProblemActivationAdapter
extends RefCounted
## P6.1 §12-13 问题激活适配器——Needs → Problem 查询语义。
## Need ≠ Goal ≠ Problem ≠ Intention：Problem 只是"向知识库查询什么手段"，
## 不改 GoalManager、不改 Intention、不进 DecisionEngine。
## 第一版只接当前世界真正支持的：HUNGER / THIRST / ISOLATION。

const HUNGER_GATE := 400.0
const THIRST_GATE := 400.0
const ISOLATION_GATE := 650.0

static func activate(actor: Dictionary) -> Array:
	var needs: Dictionary = actor.get("needs", {})
	var out: Array = []
	if float(needs.get("hunger", 0)) >= HUNGER_GATE:
		out.append("HUNGER")
	if float(needs.get("thirst", 0)) >= THIRST_GATE:
		out.append("THIRST")
	if float(needs.get("social", 0)) >= ISOLATION_GATE:
		out.append("ISOLATION")
	return out
