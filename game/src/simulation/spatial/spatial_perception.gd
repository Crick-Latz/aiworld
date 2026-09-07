class_name SpatialPerception
extends RefCounted
## P5：唯一允许读取世界地理真值的"传感器"（SN 审计 第十节分层）。
## 输出只写入 SpatialBeliefMap / ToM.last_seen——不直接改决策状态、不写模拟世界。
## 视野 = base × 昼夜 × 天气（SN-F：真实数据门，不是 UI 效果）；
## LOS：rock/tree 遮挡，water 不遮挡（第一版不含 elevation——SN 指令第十三节）。

const BASE_VISION := 12
const SIGHT_BLOCKERS := ["rock", "tree"]

static func daylight_factor(hour: int) -> float:
	if hour >= 20 or hour < 6:
		return 0.35  # 夜
	if hour >= 18 or hour < 8:
		return 0.7   # 黄昏/黎明
	return 1.0      # 白昼

static func weather_factor(weather: String) -> float:
	match weather:
		"storm":
			return 0.5
		"rain":
			return 0.8
		_:
			return 1.0

static func effective_vision(hour: int, weather: String) -> int:
	return maxi(3, int(float(BASE_VISION) * daylight_factor(hour) * weather_factor(weather)))

## Bresenham 直线视线：中间格遇 rock/tree 即遮挡（端点本身不算）
static func has_los(map_query, from: Vector2i, to: Vector2i) -> bool:
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var sx := 1 if to.x > from.x else -1
	var sy := 1 if to.y > from.y else -1
	var err := dx - dy
	var x := from.x
	var y := from.y
	while not (x == to.x and y == to.y):
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		if x == to.x and y == to.y:
			break
		if SIGHT_BLOCKERS.has(map_query.get_obstacle(x, y)):
			return false
	return true

static func can_see(map_query, hour: int, weather: String, from: Vector2i, to: Vector2i) -> bool:
	var d := absi(to.x - from.x) + absi(to.y - from.y)
	if d > effective_vision(hour, weather):
		return false
	return has_los(map_query, from, to)

## 每 tick 感知：① 视野内未知格（增量——静态地图看过的不再看）
## ② 视野内资源信念快照（含枯竭/已搜的即时修正——看见就是修正）
## ③ 视野内人物 → ToM.last_seen 实时刷新（P1 修复：不再只有事件目击才刷新）
static func perceive(sim, a: Dictionary) -> void:
	var belief: SpatialBeliefMap = a.get("spatial", null)
	if belief == null:
		return
	var hour: int = int(sim.world_time.get("hour", 12))
	var weather := str(sim.world.get("weather", "clear"))
	var vision := effective_vision(hour, weather)
	var pos: Vector2i = a["tile"]
	# 地图静态：站位不变时视野内未知格集合不变——地形扫描只在移动后做（性能）
	var last_pos = a.get("_p5_perceive_pos", null)
	if typeof(last_pos) != TYPE_VECTOR2I or (last_pos as Vector2i) != pos:
		for dy in range(-vision, vision + 1):
			for dx in range(-vision, vision + 1):
				if absi(dx) + absi(dy) > vision:
					continue
				var tx := pos.x + dx
				var ty := pos.y + dy
				if not belief.map_rect.has_point(Vector2i(tx, ty)):
					continue
				if belief.is_known(tx, ty):
					continue
				if not has_los(sim.map_query, pos, Vector2i(tx, ty)):
					continue
				var walkable: bool = sim.map_query.is_walkable_tile(Vector3i(tx, 0, ty))
				var obst: String = sim.map_query.get_obstacle(tx, ty)
				belief.observe_cell(tx, ty,
						SpatialBeliefMap.CELL_FREE if walkable else SpatialBeliefMap.CELL_BLOCKED,
						obst, sim.tick)
		a["_p5_perceive_pos"] = pos
	_perceive_resources(sim, belief, pos, hour, weather)
	var tom = a.get("tom", null)
	if tom != null:
		for other_id in sim.actors:
			if str(other_id) == str(a.get("id", "")):
				continue
			var otile: Vector2i = sim.actors[other_id]["tile"]
			if can_see(sim.map_query, hour, weather, pos, otile):
				tom.see_at(str(other_id), otile, sim.tick)

static func _perceive_resources(sim, belief: SpatialBeliefMap, pos: Vector2i, hour: int, weather: String) -> void:
	var w: Dictionary = sim.world
	var t: int = sim.tick
	for bush in w.get("berry_bushes", []):
		var bp = bush.get("pos", null)
		if typeof(bp) == TYPE_VECTOR2I and _in_sight(sim, pos, bp, hour, weather):
			belief.observe_resource("berry", bp, int(bush.get("food", 0)) > 0, false, t)
	for spring in w.get("water_springs", []):
		if typeof(spring) == TYPE_VECTOR2I and _in_sight(sim, pos, spring, hour, weather):
			belief.observe_resource("water", spring, true, false, t)
	for spot in w.get("fish_spots", []):
		if typeof(spot) == TYPE_VECTOR2I and _in_sight(sim, pos, spot, hour, weather):
			belief.observe_resource("fish", spot, true, false, t)
	for beach in w.get("shell_beaches", []):
		if typeof(beach) == TYPE_VECTOR2I and _in_sight(sim, pos, beach, hour, weather):
			belief.observe_resource("shell", beach, true, false, t)
	for ruin in w.get("ruins", []):
		var rp = ruin.get("pos", null)
		if typeof(rp) == TYPE_VECTOR2I and _in_sight(sim, pos, rp, hour, weather):
			belief.observe_resource("ruin", rp, true, bool(ruin.get("searched", false)), t)
	for tree in w.get("trees", []):
		if typeof(tree) == TYPE_VECTOR2I and _in_sight(sim, pos, tree, hour, weather):
			belief.observe_resource("tree", tree, true, false, t)
	var fires: Dictionary = w.get("fires", {})
	for pk in fires:
		var ft := _pos_from_key(str(pk))
		if ft.x >= 0 and bool(fires[pk]) and _in_sight(sim, pos, ft, hour, weather):
			belief.observe_resource("fire", ft, true, false, t)

static func _in_sight(sim, pos: Vector2i, target: Vector2i, hour: int, weather: String) -> bool:
	var d := absi(target.x - pos.x) + absi(target.y - pos.y)
	if d > effective_vision(hour, weather):
		return false
	return has_los(sim.map_query, pos, target)

## MapController 的火堆键格式 "str(Vector2i)" = "(x, y)"
static func _pos_from_key(pk: String) -> Vector2i:
	var clean := pk.replace("(", "").replace(")", "").replace(" ", "")
	var parts := clean.split(",")
	if parts.size() == 2:
		return Vector2i(int(parts[0]), int(parts[1]))
	return Vector2i(-1, -1)
