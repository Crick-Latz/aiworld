class_name KnowledgeFact
extends RefCounted
## P6.0 §12 知识四层：COMMON_HUMAN / CULTURAL / EXPERTISE / LEARNED_LOCAL。
## 知识陈述"世界通常怎么运作"（水可以解渴），不含"哪里有水"（那是 Belief/Spatial 的职责）。
## LEARNED_LOCAL 不进本库——由既有 Belief/SpatialBeliefMap 支撑，不复制。

const LAYERS := ["COMMON_HUMAN", "CULTURAL", "EXPERTISE"]

## fact 结构（纯数据，由 JSON 加载）：
## {id, layer, subject_tags[], relation, object, statement}
## relation ∈ PROVIDES（X 可提供 Y）/ ENABLES（X 可实现能力 Y）/
##            REQUIRES（做 X 需要 Y）/ DANGEROUS（X 危险）
static func validate(fact: Dictionary) -> bool:
	if not fact.has("id") or not fact.has("layer"):
		return false
	if not LAYERS.has(str(fact["layer"])):
		return false
	var tags = fact.get("subject_tags", [])
	if typeof(tags) != TYPE_ARRAY or (tags as Array).is_empty():
		return false
	if str(fact.get("relation", "")) == "" or str(fact.get("object", "")) == "":
		return false
	return true
