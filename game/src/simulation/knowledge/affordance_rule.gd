class_name AffordanceRule
extends RefCounted
## P6.0 §10 AffordanceRule——同一物体可有多个用途（wood_as_fuel / wood_as_structure）。
## 纯数据规则；由 MeansEndsPlanner 检索组合，绝不在代码里写 if target == deer。

## rule 结构：
## {id, subject_tags[], affordance, produces[], provides_capabilities[],
##  requirements[], risks[], knowledge_required[], estimated_effort}
static func validate(rule: Dictionary) -> bool:
	if not rule.has("id") or not rule.has("affordance"):
		return false
	var tags = rule.get("subject_tags", [])
	if typeof(tags) != TYPE_ARRAY or (tags as Array).is_empty():
		return false
	return true

## 该规则是否在 subject 上可用（ctx 的标签集包含任一 subject_tag）
static func matches(rule: Dictionary, available_tags: Array) -> bool:
	for t in rule.get("subject_tags", []):
		if available_tags.has(str(t)):
			return true
	return false
