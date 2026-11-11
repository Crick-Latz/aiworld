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

## P7.2C-R2 C2：统一的 blocker 解除价值——ask 与 seek 共用同一语义。
## parent blockedness、request urgency、goal age、trust/reliability 的函数；
## 不用两套魔法常量；causal flag 开启时取代旧的直接 utility 公式。
## P7.2C-R2-R1 K2：possession_support 是 candidate-local 参数（调用方按 peer
## 独立判断）——不写回 goal dict（旧写法会把 B 的 boost 泄漏给后续 C/D）。
static func holder_resolution_value(goal: Dictionary, actor: Dictionary,
		peer_id: String, base_pressure: float,
		possession_support: bool = false) -> float:
	var blockedness := clampf(float(goal.get("parent_blockedness", 0.5)), 0.0, 1.0)
	var urgency := clampf(float(goal.get("request_urgency", 0.5)), 0.0, 1.0)
	var goal_age := clampf(float(int(actor.get("now_tick", 0)) - int(goal.get("created_tick", 0))) / 120.0, 0.0, 1.0)
	var trust_norm := clampf((float(actor.get("trust_of", {}).get(peer_id, 0.0)) + 1000.0) / 2000.0, 0.0, 1.0)
	var tom: TheoryOfMind = actor.get("tom", null)
	var reliable := 0.5
	if tom != null:
		reliable = clampf((tom.belief_about(peer_id, "reliable") + 1.0) * 0.5, 0.0, 1.0)
	return clampf(
		0.16
		+ blockedness * 0.26
		+ maxf(urgency, base_pressure) * 0.24
		+ goal_age * 0.06
		+ trust_norm * 0.14
		+ reliable * 0.10
		+ (0.06 if possession_support else 0.0),
		0.06, 0.95)

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
	var eligible_peers: Array = []
	for peer in peers:
		var peer_id := str(peer.get("id", ""))
		if peer_id == "" or peer_id == str(actor.get("id", "")) or asked.has(peer_id) or excluded.has(peer_id):
			continue
		eligible_peers.append(peer)
		var trust_raw := float(actor.get("trust_of", {}).get(peer_id, 0.0))
		var trust_norm := clampf((trust_raw + 1000.0) / 2000.0, 0.0, 1.0)
		var reliable := clampf((tom.belief_about(peer_id, "reliable") + 1.0) * 0.5, 0.0, 1.0)
		var sociability := p.effective_trait("sociability", actor.get("needs", {}))
		var conflict := p.effective_trait("conflict_avoidance", actor.get("needs", {}))
		var peer_tile: Vector2i = peer.get("tile", actor.get("tile", Vector2i.ZERO))
		var actor_tile: Vector2i = actor.get("tile", Vector2i.ZERO)
		var distance := absi(peer_tile.x - actor_tile.x) + absi(peer_tile.y - actor_tile.y)
		# P7.2C-R2-R1 K2：candidate-local possession support——只对当前 peer
		# 判断（不再写回 goal dict，B 的 boost 不会泄漏给 C/D）。
		var utility: float
		if bool(goal.get("causal_arbitration_enabled", false)):
			var possession_support := tom.belief_about(peer_id,
				TheoryOfMind.possession_predicate(item_id)) > 0.05
			utility = holder_resolution_value(goal, actor, peer_id,
				maxf(pressure, urgency), possession_support)
		else:
			var blockedness := clampf(float(goal.get("parent_blockedness", 0.5)), 0.0, 1.0)
			utility = clampf(0.14 + maxf(pressure, urgency) * 0.26 + blockedness * 0.22
				+ trust_norm * 0.14 + reliable * 0.10 + sociability * 0.10 - conflict * 0.06, 0.06, 0.95)
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
	# P7.2C C1：身边没有可问的人时，基于自己的主观信息去找一个可能知道答案的人。
	# 合法信息源只有自己的 ToM last_seen / trust / reliability / 距离信念——
	# 不读真实库存、不读真实坐标、无神谕追踪；扑空是真实结果（seek 既有语义）。
	if not eligible_peers.is_empty() or not bool(goal.get("holder_reachability_enabled", false)):
		return out
	var seek := _build_seek_holder(actor, goal, pressure, urgency)
	if not seek.is_empty():
		out.append(seek)
		return out
	# P7.2C Round3 E2：request-time social fallback——无可问的人、也没有任何
	# last_seen 目标可找时，去自己【见过】的社会锚点（火堆营地）碰运气。
	# 只读主观 known_resources；远锚点不生成（26-27 tick 请求窗口内不现实）；
	# 到场不是 goal 终态——之后 others_visible 自然驱动 ask；营地没人则自然失败。
	if bool(goal.get("encounter_ecology_enabled", false)):
		var anchor_seek := _build_seek_social_anchor(actor, goal, maxf(pressure, urgency))
		if not anchor_seek.is_empty():
			out.append(anchor_seek)
	return out

## Round3 E2：找社会锚点候选——目标 = 请求者自己见过的最近火堆（主观
## known_resources["fires"]，key "x,y"）。utility 是 fallback 档（低于
## blocked ask 与 known-holder seek，与普通探索竞争）。
static func _build_seek_social_anchor(actor: Dictionary, goal: Dictionary,
		pressure_urgency: float) -> Dictionary:
	var kr: Dictionary = actor.get("known_resources", {})
	if not kr.has("fires"):
		return {}
	var fires: Dictionary = kr["fires"]
	if fires.is_empty():
		return {}
	var origin: Vector2i = actor.get("tile", Vector2i.ZERO)
	var anchor := Vector2i(-1, -1)
	var best_d := -1
	var keys: Array = fires.keys()
	keys.sort()
	for key in keys:
		var parts: Array = str(key).replace("(", "").replace(")", "").split(",")
		if parts.size() != 2:
			continue
		var ft := Vector2i(int(str(parts[0]).strip_edges()), int(str(parts[1]).strip_edges()))
		var d := absi(ft.x - origin.x) + absi(ft.y - origin.y)
		if best_d < 0 or d < best_d:
			best_d = d
			anchor = ft
	if anchor.x < 0 or best_d < 0:
		return {}
	if best_d > 30:
		return {}
	var p: PersonalityProfile = actor.get("personality", null)
	var sociability := 0.5
	if p != null:
		sociability = p.effective_trait("sociability", actor.get("needs", {}))
	var utility := clampf(0.10 + pressure_urgency * 0.22 + sociability * 0.10, 0.06, 0.75)
	return {
		"action": "seek_social_anchor",
		"target": anchor,
		"target_anchor": "fire",
		"utility": utility,
		"duration": maxi(1, best_d - 8),
		"desc": "回营地碰碰运气——也许有人知道谁有%s" % str(goal.get("item_id", "")),
		"information_goal_id": str(goal.get("goal_id", "")),
		"information_action": true,
		"information_kind": "SEEK_ANCHOR",
		"query_kind": "HOLDER",
		"parent_plan_id": str(goal.get("parent_plan_id", "")),
		"item_id": str(goal.get("item_id", "")),
		"holder_predicate": TheoryOfMind.possession_predicate(str(goal.get("item_id", ""))),
		"source_request_id": str(goal.get("source_request_id", "")),
	}

## P7.2C C1：找人候选——目标从请求者自己的 ToM last_seen 记忆里选（主观），
## 排序用 trust/reliability/sociability/last_seen 新鲜度/距离信念/请求紧迫度。
## 允许扑空：last_seen 陈旧时世界执行层会真实扑空（seek_person 既有语义）。
static func _build_seek_holder(actor: Dictionary, goal: Dictionary,
		pressure: float, urgency: float) -> Dictionary:
	var tom: TheoryOfMind = actor.get("tom", null)
	if tom == null:
		return {}
	var p: PersonalityProfile = actor.get("personality", null)
	if p == null:
		return {}
	var origin: Vector2i = actor.get("tile", Vector2i.ZERO)
	var asked: Array = goal.get("asked_actor_ids", [])
	var excluded: Array = goal.get("excluded_target_ids", [])
	# P7.2C-R1：本轮已找过的人不再重复找（stale last_seen 扑空后换目标）；
	# 找到的人只进 sought——不排除后续 ask（ask 只看 asked/excluded）。
	var sought: Array = goal.get("sought_actor_ids", [])
	var best_id := ""
	var best_score := 0.0
	var best_seen := {}
	var now := int(actor.get("now_tick", 0))
	for other_id in actor.get("trust_of", {}):
		var peer_id := str(other_id)
		if peer_id == "" or peer_id == str(actor.get("id", "")) \
				or asked.has(peer_id) or excluded.has(peer_id) or sought.has(peer_id):
			continue
		var seen := tom.last_seen_of(peer_id)
		if seen.is_empty():
			continue
		var trust_norm := clampf((float(actor.get("trust_of", {}).get(peer_id, 0.0)) + 1000.0) / 2000.0, 0.0, 1.0)
		var reliable := clampf((tom.belief_about(peer_id, "reliable") + 1.0) * 0.5, 0.0, 1.0)
		var sociability := p.effective_trait("sociability", actor.get("needs", {}))
		var seen_tick := int(seen.get("tick", -1))
		var freshness := clampf(1.0 / (1.0 + float(maxi(0, now - seen_tick)) / 120.0), 0.1, 1.0)
		var tile: Vector2i = seen.get("tile", origin)
		var distance := absi(tile.x - origin.x) + absi(tile.y - origin.y)
		var distance_belief := clampf(1.0 / (1.0 + float(distance) / 30.0), 0.1, 1.0)
		var score := trust_norm * 0.28 + reliable * 0.22 + sociability * 0.12 \
			+ freshness * 0.18 + distance_belief * 0.10 + clampf(maxf(pressure, urgency), 0.0, 1.0) * 0.10
		# P7.2C-R2 C3b-4：请求者对目标已有 positive has_item:X belief → 更高优先。
		if tom.belief_about(peer_id, TheoryOfMind.possession_predicate(str(goal.get("item_id", "")))) > 0.05:
			score += 0.20
		if score > best_score:
			best_score = score
			best_id = peer_id
			best_seen = seen
	if best_id == "":
		return {}
	var seek_tile: Vector2i = best_seen.get("tile", origin)
	var utility: float
	if bool(goal.get("causal_arbitration_enabled", false)):
		# P7.2C-R2-R1 K2：candidate-local——possession_support 只对 best_id 判断。
		var seek_possession := tom.belief_about(best_id,
			TheoryOfMind.possession_predicate(str(goal.get("item_id", "")))) > 0.05
		utility = holder_resolution_value(goal, actor, best_id,
			maxf(pressure, urgency), seek_possession)
		# C3b-4：known-holder 额外加分（主观 belief，非真实库存）。
		if seek_possession:
			utility = clampf(utility + 0.12, 0.06, 0.95)
	else:
		utility = clampf(0.14 + maxf(pressure, urgency) * 0.30 + best_score * 0.42, 0.06, 0.92)
	return {
		"action": "seek_holder_person",
		"target": seek_tile,
		"target_actor": best_id,
		"utility": utility,
		"duration": maxi(1, absi(seek_tile.x - origin.x) + absi(seek_tile.y - origin.y) - 8),
		"desc": "去找%s——也许他知道谁有%s" % [best_id, str(goal.get("item_id", ""))],
		"information_goal_id": str(goal.get("goal_id", "")),
		"information_action": true,
		"information_kind": "SEEK_HOLDER",
		"query_kind": "HOLDER",
		"parent_plan_id": str(goal.get("parent_plan_id", "")),
		"item_id": str(goal.get("item_id", "")),
		"holder_predicate": TheoryOfMind.possession_predicate(str(goal.get("item_id", ""))),
		"source_request_id": str(goal.get("source_request_id", "")),
	}
