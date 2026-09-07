class_name WorldKnowledgeStore
extends RefCounted
## P6.0 §11/§14 WorldKnowledgeStore——"世界通常怎么运作"的规则库。
## ≠ BeliefStore（哪里有什么）≠ Possession（我手里有什么）。
## 视角：available_for(actor) 按 layer 过滤——COMMON_HUMAN 全员；
## CULTURAL 按世界包；EXPERTISE 按 actor 的 LifeHistory 派生专业标签。
## 只读数据容器：加载后不因模拟事件变化（学到的"本地事实"走 Belief，不进这里）。

var facts := {}          # id -> fact
var affordances := {}    # id -> rule
var pack_ids: Array = [] # 来源世界包（debug）

func load_pack(pack: Dictionary) -> void:
	pack_ids.append(str(pack.get("pack_id", "?")))
	for f in pack.get("facts", []):
		if KnowledgeFact.validate(f):
			facts[str(f["id"])] = f
	for r in pack.get("affordances", []):
		if AffordanceRule.validate(r):
			affordances[str(r["id"])] = r

## actor_expertise_tags：由调用方从 LifeHistory 派生（P1 数据，不改冻结层）
func available_for(actor_expertise_tags: Array) -> Dictionary:
	var out_facts := {}
	for id in facts:
		var f: Dictionary = facts[id]
		var layer := str(f.get("layer", ""))
		if layer == "COMMON_HUMAN" or layer == "CULTURAL":
			out_facts[id] = f
		elif layer == "EXPERTISE":
			for tag in f.get("subject_tags", []):
				if actor_expertise_tags.has(str(tag)):
					out_facts[id] = f
					break
	return {"facts": out_facts, "affordances": affordances.duplicate()}

## 检索：哪些规则能产出某资源标签（FOOD/WATER/SHELTER...）
func rules_producing(resource_tag: String, available: Dictionary = {}) -> Array:
	var out: Array = []
	var pool: Dictionary = available.get("affordances", affordances)
	for id in pool:
		var r: Dictionary = pool[id]
		if (r.get("produces", []) as Array).has(resource_tag):
			out.append(r)
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out

## 检索：哪些规则能提供某能力（CUT/HUNT_MEDIUM...）
func rules_providing_capability(capability: String, available: Dictionary = {}) -> Array:
	var out: Array = []
	var pool: Dictionary = available.get("affordances", affordances)
	for id in pool:
		var r: Dictionary = pool[id]
		if (r.get("provides_capabilities", []) as Array).has(capability):
			out.append(r)
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out

## 检索：某 tag 支持哪些 affordance（KE：一材多用）
func affordances_of_tag(tag: String) -> Array:
	var out: Array = []
	for id in affordances:
		var r: Dictionary = affordances[id]
		if (r.get("subject_tags", []) as Array).has(tag):
			out.append(r)
	out.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return out

func fact_by_id(id: String) -> Dictionary:
	return facts.get(id, {})

func counts() -> Dictionary:
	return {"facts": facts.size(), "affordances": affordances.size()}
