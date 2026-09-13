class_name InformationActionPolicy
extends RefCounted
## P7.0 主观行动候选。搜索方向只来自自己的已知/未知边界；询问对象只来自
## 当前可见人物和自己的 TheoryOfMind 证据。此类不接收 world/map truth。

const DIRECTIONS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const MIN_PEER_KNOWLEDGE := 0.08

static func build(actor: Dictionary, goal: Dictionary, at_tick: int) -> Array:
	var out: Array = []
	if goal.is_empty() or str(goal.get("state", "")) != InformationSubgoalTracker.STATE_ACTIVE:
		return out
	if str(goal.get("query_kind", "SOURCE")) == "HOLDER":
		return _build_holder_asks(actor, goal)
	var source_kinds: Array = goal.get("source_kinds", [])
	if source_kinds.is_empty():
		return out
	var source_kind := str(source_kinds[0])
	var p: PersonalityProfile = actor.get("personality", null)
	var belief: SpatialBeliefMap = actor.get("spatial", null)
	if p == null or belief == null:
		return out
	var pressure := _pressure(actor.get("needs", {}), str(goal.get("root_goal", "")))
	var target := choose_search_target(actor.get("tile", Vector2i.ZERO), belief,
		goal.get("tried_tiles", []), int(goal.get("attempts", 0)))
	if target.x >= 0:
		var curiosity := p.effective_trait("curiosity", actor.get("needs", {}))
		var caution := p.effective_trait("caution", actor.get("needs", {}))
		var attempt_fatigue := clampf(float(goal.get("search_failures", 0)) * 0.04, 0.0, 0.24)
		var utility := clampf(0.24 + pressure * 0.48 + curiosity * 0.18 - caution * 0.08 - attempt_fatigue, 0.06, 0.92)
		out.append({
			"action": "search_resource_source",
			"target": target,
			"utility": utility,
			"duration": 1,
			"desc": "寻找%s来源" % str(goal.get("item_id", "物资")),
			"information_goal_id": str(goal.get("goal_id", "")),
			"information_action": true,
			"information_kind": "SEARCH",
			"parent_plan_id": str(goal.get("parent_plan_id", "")),
			"item_id": str(goal.get("item_id", "")),
			"source_kind": source_kind,
		})

	var visible: Array = actor.get("others_visible", [])
	var asked: Array = goal.get("asked_actor_ids", [])
	var tom: TheoryOfMind = actor.get("tom", null)
	if tom == null:
		return out
	var peers: Array = visible.duplicate(true)
	peers.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	for peer in peers:
		var peer_id := str(peer.get("id", ""))
		if peer_id == "" or asked.has(peer_id):
			continue
		var predicate := InformationExchangePolicy.knowledge_predicate(source_kind)
		var peer_belief := tom.belief_about(peer_id, predicate)
		var peer_confidence := tom.confidence_of(peer_id, predicate)
		if peer_belief <= MIN_PEER_KNOWLEDGE or peer_confidence <= 0.0:
			continue
		var trust_raw := float(actor.get("trust_of", {}).get(peer_id, 0.0))
		var trust_norm := clampf((trust_raw + 1000.0) / 2000.0, 0.0, 1.0)
		var sociability := p.effective_trait("sociability", actor.get("needs", {}))
		var conflict := p.effective_trait("conflict_avoidance", actor.get("needs", {}))
		var utility := clampf(0.16 + pressure * 0.38 + maxf(peer_belief, 0.0) * 0.22
			+ peer_confidence * 0.12 + trust_norm * 0.12 + sociability * 0.08 - conflict * 0.05,
			0.05, 0.95)
		var peer_tile: Vector2i = peer.get("tile", actor.get("tile", Vector2i.ZERO))
		var actor_tile: Vector2i = actor.get("tile", Vector2i.ZERO)
		var peer_distance := absi(peer_tile.x - actor_tile.x) + absi(peer_tile.y - actor_tile.y)
		# 询问动作会逐 tick 追踪目标。持续时间覆盖进入 8 格交谈半径所需的距离，
		# 目标继续移动时仍可能扑空，结果由世界执行层裁决。
		out.append({
			"action": "ask_resource_source",
			"target": peer_tile,
			"target_actor": peer_id,
			"utility": utility,
			"duration": maxi(1, peer_distance - 8),
			"desc": "向%s打听%s来源" % [peer_id, str(goal.get("item_id", "物资"))],
			"information_goal_id": str(goal.get("goal_id", "")),
			"information_action": true,
			"information_kind": "ASK",
			"parent_plan_id": str(goal.get("parent_plan_id", "")),
			"item_id": str(goal.get("item_id", "")),
			"source_kind": source_kind,
			"peer_knowledge_belief": peer_belief,
			"peer_knowledge_confidence": peer_confidence,
		})
	return out

static func choose_search_target(origin: Vector2i, belief: SpatialBeliefMap,
		tried_tiles: Array, attempt_index: int = 0) -> Vector2i:
	if belief == null:
		return Vector2i(-1, -1)
	var tried := {}
	for k in tried_tiles:
		tried[str(k)] = true
	var candidates := {}
	for cell_key in belief.cells:
		var cell: Dictionary = belief.cells[cell_key]
		if int(cell.get("state", SpatialBeliefMap.CELL_UNKNOWN)) != SpatialBeliefMap.CELL_FREE:
			continue
		var base := _tile_from_key(str(cell_key))
		for direction in DIRECTIONS:
			var tile: Vector2i = base + direction
			if belief.map_rect.size != Vector2i.ZERO and not belief.map_rect.has_point(tile):
				continue
			if belief.cell_state(tile.x, tile.y) != SpatialBeliefMap.CELL_UNKNOWN:
				continue
			var key := SpatialBeliefMap.key(tile.x, tile.y)
			if tried.has(key):
				continue
			candidates[key] = tile
	var ordered: Array = candidates.values()
	ordered.sort_custom(func(a, b):
		var ad := absi(a.x - origin.x) + absi(a.y - origin.y)
		var bd := absi(b.x - origin.x) + absi(b.y - origin.y)
		if ad != bd:
			return ad < bd
		var aq := _direction_quadrant(origin, a, attempt_index)
		var bq := _direction_quadrant(origin, b, attempt_index)
		if aq != bq:
			return aq < bq
		return a.x < b.x or (a.x == b.x and a.y < b.y))
	if not ordered.is_empty():
		return ordered[0]
	# 极端夹具中还没有已知 FREE 格时，从地图范围内选择一个确定性未知方向。
	for distance in [4, 7, 10]:
		for offset in range(DIRECTIONS.size()):
			var d: Vector2i = DIRECTIONS[(attempt_index + offset) % DIRECTIONS.size()]
			var fallback: Vector2i = origin + d * distance
			if belief.map_rect.size != Vector2i.ZERO and not belief.map_rect.has_point(fallback):
				continue
			if belief.cell_state(fallback.x, fallback.y) == SpatialBeliefMap.CELL_UNKNOWN \
					and not tried.has(SpatialBeliefMap.key(fallback.x, fallback.y)):
				return fallback
	return Vector2i(-1, -1)

static func _pressure(needs: Dictionary, root_goal: String) -> float:
	var key := str(InformationSubgoalTracker.ROOT_NEED.get(root_goal, ""))
	return clampf(float(needs.get(key, 0.0)) / 1000.0, 0.0, 1.0) if key != "" else 0.0

static func _tile_from_key(value: String) -> Vector2i:
	var parts := value.split(",")
	if parts.size() != 2:
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))

static func _direction_quadrant(origin: Vector2i, tile: Vector2i, rotation: int) -> int:
	var delta := tile - origin
	var base := 0
	if absi(delta.x) >= absi(delta.y):
		base = 0 if delta.x >= 0 else 1
	else:
		base = 2 if delta.y >= 0 else 3
	return (base - rotation) % 4

## P7.2B：开放式持有询问。"我不知道谁有 X"本身就是向身边人打听的理由——
## 不要求预先相信对方"知道答案"；候选=当前可见、非自己、本轮未问过、未被本次
## material request 拒绝过。排序只用 A 自己的信任/ToM/人格/距离，不读任何真值。
static func _build_holder_asks(actor: Dictionary, goal: Dictionary) -> Array:
	var out: Array = []
	var p: PersonalityProfile = actor.get("personality", null)
	var tom: TheoryOfMind = actor.get("tom", null)
	if p == null or tom == null:
		return out
	var item_id := str(goal.get("item_id", ""))
	if item_id == "":
		return out
	var asked: Array = goal.get("asked_actor_ids", [])
	var excluded: Array = goal.get("excluded_target_ids", [])
	var pressure := _pressure(actor.get("needs", {}), str(goal.get("root_goal", "")))
	var urgency := clampf(float(goal.get("request_urgency", 0.5)), 0.0, 1.0)
	var peers: Array = (actor.get("others_visible", []) as Array).duplicate(true)
	peers.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	for peer in peers:
		var peer_id := str(peer.get("id", ""))
		if peer_id == "" or peer_id == str(actor.get("id", "")) or asked.has(peer_id) or excluded.has(peer_id):
			continue
		var trust_raw := float(actor.get("trust_of", {}).get(peer_id, 0.0))
		var trust_norm := clampf((trust_raw + 1000.0) / 2000.0, 0.0, 1.0)
		var reliable := clampf((tom.belief_about(peer_id, "reliable") + 1.0) * 0.5, 0.0, 1.0)
		var sociability := p.effective_trait("sociability", actor.get("needs", {}))
		var conflict := p.effective_trait("conflict_avoidance", actor.get("needs", {}))
		var peer_tile: Vector2i = peer.get("tile", actor.get("tile", Vector2i.ZERO))
		var actor_tile: Vector2i = actor.get("tile", Vector2i.ZERO)
		var distance := absi(peer_tile.x - actor_tile.x) + absi(peer_tile.y - actor_tile.y)
		var utility := clampf(0.18 + maxf(pressure, urgency) * 0.32 + trust_norm * 0.14
			+ reliable * 0.10 + sociability * 0.10 - conflict * 0.06, 0.06, 0.92)
		out.append({
			"action": "ask_item_holder",
			"target": peer_tile,
			"target_actor": peer_id,
			"utility": utility,
			"duration": maxi(1, distance - 8),
			"desc": "向%s打听谁有%s" % [peer_id, item_id],
			"information_goal_id": str(goal.get("goal_id", "")),
			"information_action": true,
			"information_kind": "ASK_HOLDER",
			"query_kind": "HOLDER",
			"parent_plan_id": str(goal.get("parent_plan_id", "")),
			"item_id": item_id,
			"holder_predicate": TheoryOfMind.possession_predicate(item_id),
			"source_request_id": str(goal.get("source_request_id", "")),
			"peer_reliability_belief": reliable,
		})
	return out
