class_name AgencyContextBuilder
extends RefCounted
## P6.1 §3-11 SubjectiveAgencyContext 构造器——只从 actor 自己的主观系统派生。
## 铁律（fail-closed）：
##   possessed 只来自自己的 inventory（合法 self-state）；
##   known_sources 只来自 SpatialBeliefMap/PlaceBelief（绝不信 GeneratedMap/world.resources）；
##   信念缺位 → known_sources=[] + CONTEXT_SOURCE_MISSING（不回退真值，RB 门）；
##   peer 能力只经 PerceivedCapabilityAdapter（自己的证据，非真值，RC 门）；
##   expertise 从自己的 LifeHistory 文本关键词派生（数据驱动，无角色名分支）。

## P6.3A：物品标签/能力一律由 ItemCatalog 派生（旧硬编码表已删；fish_spear 的
## SPEAR 标签与 PIERCE/FISH/HUNT_MEDIUM 能力现来自 data/items/items.json）
static var _catalog: ItemCatalog = null
static var _recipes: RecipeCatalog = null

static func _ensure_catalogs() -> void:
	if _catalog == null:
		_catalog = ItemCatalog.load_default()
		_recipes = RecipeCatalog.load_default(_catalog)

const SOURCE_KIND_TAGS := {
	"berry": "BERRY", "water": "SPRING", "fish": "FISH", "tree": "WOOD",
	"shell": "SHELL", "ruin": "RUIN", "fire": "FIRE",
}
const EXPERTISE_KEYWORDS := [
	["房", "WOODWORKING"], ["修", "WOODWORKING"], ["工", "WOODWORKING"],
	["船", "NAVIGATION"], ["海难", "NAVIGATION"], ["航海", "NAVIGATION"],
	["粮", "FOODHANDLING"], ["饥", "FOODHANDLING"], ["厨", "FOODHANDLING"],
]

static func build(sim, actor: Dictionary) -> Dictionary:
	var ctx := {
		"actor_id": str(actor.get("id", "")),
		"possessed_tags": [],
		"possessed_capabilities": [],
		"known_sources": [],
		"known_source_tags": [],
		"expertise_tags": [],
		"known_recipe_refs": [],
		"possessed_items": {},
		"known_peers": [],
		"activated_problems": [],
		"context_refs": [],
		"flags": [],
	}
	# 1) 持有：只来自自己的 inventory——经 ItemCatalog/InventoryOps 派生（P6.3A）
	_ensure_catalogs()
	var inv: Dictionary = actor.get("inventory", {})
	for tag in InventoryOps.tags_of_inventory(inv, _catalog):
		_add_unique(ctx["possessed_tags"], tag)
	for cap in InventoryOps.capabilities_of_inventory(inv, _catalog):
		_add_unique(ctx["possessed_capabilities"], cap)
	# P6.3B-0-R1 §二：possessed_items = 自己库存的规范化快照（item_id -> int quantity）
	ctx["possessed_items"] = InventoryOps.normalize(inv)
	# 2) 已知来源：只来自 SpatialBeliefMap（P5 的主观空间记忆）
	var belief = actor.get("spatial", null)
	if belief == null or not (belief is SpatialBeliefMap):
		ctx["flags"].append("CONTEXT_SOURCE_MISSING")  # RB：fail-closed，绝不回退世界
	else:
		for k in belief.known_resources:
			var r: Dictionary = belief.known_resources[k]
			var tag := str(SOURCE_KIND_TAGS.get(str(r["kind"]), ""))
			if tag == "" or not bool(r.get("believed_present", false)):
				continue
			var source_id := str(k)
			ctx["known_sources"].append({
				"tag": tag, "source_id": source_id,
				"belief_ref": "known_source:" + source_id,
				"last_seen_tick": int(r.get("last_seen_tick", 0)),
				"confidence": 1.0,
			})
			_add_unique(ctx["known_source_tags"], tag)
			_add_unique(ctx["context_refs"], "known_source:" + source_id)
	# 3) 专长：自己的 LifeHistory 文本关键词（不是别人的）
	var life = actor.get("life_history", null)
	if life != null:
		for ev in life.events:
			var desc := str(ev.get("desc", ""))
			for pair in EXPERTISE_KEYWORDS:
				if desc.find(str(pair[0])) != -1:
					_add_unique(ctx["expertise_tags"], str(pair[1]))
	# P6.3A：主观已知配方 refs（世界包知识 ∩ 配方 knowledge_refs——经 WorldKnowledgeStore 唯一权威）
	# P6.3A-R1 §5：知识侧 adapter（items 不再依赖 WorldKnowledgeStore）；sim 为 null 时走
	# 兼容路径（单元测试用——known_recipe_refs 经参数注入）
	if sim is IslandSimulation:
		for rr in RecipeKnowledgeAdapter.known_recipe_refs(ctx.get("expertise_tags", []), (sim as IslandSimulation).agency_knowledge_store(), _recipes):
			_add_unique(ctx["known_recipe_refs"], rr)

	# 4) 伙伴能力：只经感知适配器（自己的证据）
	for other_id in sim.actors:
		if str(other_id) == str(ctx["actor_id"]):
			continue
		var caps: Array = PerceivedCapabilityAdapter.perceived_capabilities(actor, str(other_id))
		if not caps.is_empty():
			ctx["known_peers"].append({"id": str(other_id), "expertise_tags": caps, "trust": 0.5})
			_add_unique(ctx["context_refs"], "peer_cap:" + str(other_id))
	# 5) 问题激活：Needs → Problem 查询语义（不改 Goal/Intention）
	ctx["activated_problems"] = ProblemActivationAdapter.activate(actor)
	return ctx

## 确定性 context hash（§15）：排序后哈希，禁止字典迭代序/时钟/UUID
static func context_hash(ctx: Dictionary) -> String:
	var parts: Array = [
		str(ctx.get("actor_id", "")),
		_join_sorted(ctx.get("possessed_tags", [])),
		_join_sorted(ctx.get("possessed_capabilities", [])),
		_join_sorted(ctx.get("known_source_tags", [])),
		_join_sorted(ctx.get("expertise_tags", [])),
		_join_sorted(ctx.get("known_recipe_refs", [])),
		_items_hash(ctx.get("possessed_items", {})),
	]
	for p in ctx.get("known_peers", []):
		parts.append(str(p.get("id", "")) + ":" + _join_sorted(p.get("expertise_tags", [])))
	for s in ctx.get("known_sources", []):
		parts.append(str(s.get("source_id", "")))
	return str(hash("|".join(parts)))

static func _add_unique(arr: Array, value: String) -> void:
	if not arr.has(value):
		arr.append(value)

static func _items_hash(d: Dictionary) -> String:
	var keys: Array = d.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append(str(k) + ":" + str(int(d[k])))
	return ",".join(parts)

static func _join_sorted(arr: Array) -> String:
	var d := (arr as Array).duplicate()
	d.sort()
	return ",".join(d)
