class_name MapGenerator
extends RefCounted
## 确定性 2.5D 地图生成器（WP-03 / R1）。
## 流程：噪声（含 biome profile 偏置）-> 稳定排序分配地貌 -> 小连通块清理 ->
##       POI 独立 RNG 放置 -> AStarGrid2D 两格宽道路 -> 比率复核 -> spawn 与洪泛 ->
##       MapSnapshot+hash。
## R1：region.biome 必须验证白名单并经 BIOME_PROFILES 真正改变
## ground 选择、tree/rock 比例、water 评分与视觉 elevation 倾向；
## 数量级仍由 terrain_weights 决定，biome 不绕过任何最终检查。
## 纪律：一切随机源显式派生；禁止全局随机；最多 8 次确定性尝试；不改传入 WorldSpec。

const GENERATOR_VERSION := "mapgen-0.1.0"
const GROUND_WHITELIST := ["grass", "stone", "road", "sand"]
const OBSTACLE_WHITELIST := ["none", "water", "rock", "tree"]
const DECORATION_WHITELIST := ["none", "flower", "shrub"]
const WATER_RATIO_MIN := 0.05
const WATER_RATIO_MAX := 0.18
const SOLID_RATIO_MIN := 0.10
const SOLID_RATIO_MAX := 0.25
const MIN_CLUSTER_CELLS := 5
const MAX_ELEVATION_LEVEL := 3
const WALK_COST_GROUND := 1.0
const WALK_COST_SOLID := 8.0
const WALK_COST_WATER := 40.0
const EDGE_EXTRA_COST := 3.0

# biome 纯常量 profile（R1）：
#   grass_t/stone_t：普通地面湿度阈值（m>grass_t→grass；m<stone_t→stone；否则 sand）
#   tree_t：固体障碍判 tree 的湿度阈值（低于此为 rock）
#   water_moist：water 评分的湿度权重（swamp/coast 更受 moisture 影响）
#   elev_gain：非零视觉 elevation 的放大系数（mountain/ruins 更高耸）
const BIOME_PROFILES := {
	"plains": {"grass_t": -0.10, "stone_t": -0.50, "tree_t": -0.10, "water_moist": 0.10, "elev_gain": 1.0},
	"forest": {"grass_t": -0.20, "stone_t": -0.60, "tree_t": -0.30, "water_moist": 0.10, "elev_gain": 1.0},
	"mountain": {"grass_t": 0.35, "stone_t": 0.05, "tree_t": 0.55, "water_moist": 0.10, "elev_gain": 1.6},
	"desert": {"grass_t": 0.80, "stone_t": -0.95, "tree_t": 0.60, "water_moist": 0.20, "elev_gain": 1.1},
	"snow": {"grass_t": 0.25, "stone_t": -0.30, "tree_t": 0.30, "water_moist": 0.30, "elev_gain": 1.3},
	"swamp": {"grass_t": 0.30, "stone_t": -0.80, "tree_t": -0.10, "water_moist": 1.00, "elev_gain": 1.0},
	"coast": {"grass_t": 0.10, "stone_t": -0.60, "tree_t": 0.10, "water_moist": 0.70, "elev_gain": 1.0},
	"urban": {"grass_t": 0.20, "stone_t": -0.20, "tree_t": 0.40, "water_moist": 0.10, "elev_gain": 1.2},
	"ruins": {"grass_t": 0.25, "stone_t": -0.25, "tree_t": 0.35, "water_moist": 0.10, "elev_gain": 1.4},
}

static func generate(world_spec: Dictionary, config: Dictionary) -> Dictionary:
	if typeof(world_spec) != TYPE_DICTIONARY or world_spec.is_empty():
		return _fail_schema("world_spec 为空")
	if typeof(config) != TYPE_DICTIONARY:
		config = {}

	var world_seed := int(world_spec.get("seed", -1))
	if world_seed < 0:
		return _fail_schema("seed 非法")
	var world_id := str(world_spec.get("world_id", ""))

	var region: Dictionary = {}
	for r in world_spec.get("regions", []):
		if typeof(r) == TYPE_DICTIONARY and str(r.get("id")) == str(world_spec.get("starting_region_id")):
			region = r
			break
	if region.is_empty():
		return _fail_schema("starting_region_id 找不到对应 region")

	var biome := str(region.get("biome", ""))
	if not BIOME_PROFILES.has(biome):
		return _fail_schema("未知 biome：" + biome)

	var size = region.get("size")
	if typeof(size) != TYPE_DICTIONARY:
		return _fail_schema("region.size 必须是对象")
	var width := int(size.get("width", 0))
	var depth := int(size.get("depth", 0))
	if width < 32 or width > 256 or depth < 32 or depth > 256:
		return _fail_schema("region.size 超出 32..256")

	var weights = region.get("terrain_weights")
	if typeof(weights) != TYPE_DICTIONARY:
		return _fail_schema("terrain_weights 必须是对象")
	var w_ground := float(weights.get("ground", 0.0))
	var w_water := float(weights.get("water", 0.0))
	var w_obstacle := float(weights.get("obstacle", 0.0))
	if absf(w_ground + w_water + w_obstacle - 1.0) > 1e-6:
		return _fail_schema("terrain_weights 之和必须为 1")

	var poi_rules = region.get("poi_rules")
	if typeof(poi_rules) != TYPE_ARRAY or poi_rules.size() < 3:
		return _fail_schema("poi_rules 至少 3 个")
	var sorted_pois: Array = []
	for p in poi_rules:
		if typeof(p) != TYPE_DICTIONARY:
			return _fail_schema("poi_rules 条目必须是对象")
		sorted_pois.append(p)
	sorted_pois.sort_custom(func(a, b): return str(a.get("id")) < str(b.get("id")))

	var noise_cfg = config.get("noise", {})
	if typeof(noise_cfg) != TYPE_DICTIONARY:
		noise_cfg = {}
	var ctx: Dictionary = {
		"world_id": world_id,
		"world_seed": world_seed,
		"region_id": str(region.get("id")),
		"biome": biome,
		"profile": BIOME_PROFILES[biome],
		"width": width,
		"depth": depth,
		"water_target": w_water,
		"solid_target": w_obstacle,
		"poi_rules": sorted_pois,
		"elev_freq": float(noise_cfg.get("elevation_frequency", 0.035)),
		"elev_oct": int(noise_cfg.get("elevation_octaves", 4)),
		"moist_freq": float(noise_cfg.get("moisture_frequency", 0.045)),
		"moist_oct": int(noise_cfg.get("moisture_octaves", 3)),
		"padding": clampi(int(config.get("edge_padding_tiles", 4)), 1, 32),
		"poi_min_dist": clampi(int(config.get("poi_min_manhattan_distance", 10)), 4, 64),
		"walk_min": float(config.get("walkable_ratio_min", 0.65)),
		"walk_max": float(config.get("walkable_ratio_max", 0.82)),
		"max_attempts": clampi(int(config.get("max_generation_attempts", 8)), 1, 8),
	}

	for attempt in range(ctx.max_attempts):
		var map := _attempt(ctx, attempt)
		if map != null:
			return {"ok": true, "code": "OK", "message": "", "data": map, "attempts": attempt + 1}
	return {
		"ok": false, "code": "E_MAP_UNREACHABLE",
		"message": "%d 次确定性尝试均未生成合法地图" % ctx.max_attempts,
		"data": null, "attempts": ctx.max_attempts,
	}

# —— 单次确定性尝试；任何约束不满足返回 null 进入下次 retry ——

static func _attempt(ctx: Dictionary, attempt: int) -> GeneratedMap:
	var w: int = ctx.width
	var d: int = ctx.depth
	var total := w * d
	var profile: Dictionary = ctx.profile
	var map := GeneratedMap.new()
	map.setup(w, d)
	map.retry_index = attempt
	map.effective_seed = SeedDeriver.derive(ctx.world_seed, "map:%s:attempt" % ctx.region_id, attempt)

	var elev_noise := _make_noise(SeedDeriver.derive32(ctx.world_seed, "map:%s:elevation" % ctx.region_id, attempt), ctx.elev_freq, ctx.elev_oct)
	var moist_noise := _make_noise(SeedDeriver.derive32(ctx.world_seed, "map:%s:moisture" % ctx.region_id, attempt), ctx.moist_freq, ctx.moist_oct)
	var deco_noise := _make_noise(SeedDeriver.derive32(ctx.world_seed, "map:%s:decoration" % ctx.region_id, attempt), ctx.moist_freq, 2)

	var elev := PackedFloat32Array()
	var moist := PackedFloat32Array()
	elev.resize(total)
	moist.resize(total)
	for z in d:
		for x in w:
			var i := z * w + x
			elev[i] = elev_noise.get_noise_2d(x, z)
			moist[i] = moist_noise.get_noise_2d(x, z)

	# 稳定排序分配：water 评分含 biome 湿度权重（swamp/coast 低洼湿地更易成水）；
	# 固体障碍按"高海拔-湿度"得分。数量级由 terrain_weights 决定。
	var by_water: Array = []
	var by_solid: Array = []
	for i in total:
		by_water.append({"i": i, "s": elev[i] + float(profile["water_moist"]) * moist[i]})
		by_solid.append({"i": i, "s": elev[i] - moist[i] * 0.5})
	by_water.sort_custom(_cmp_score)
	by_solid.sort_custom(_cmp_score)
	var water_target := int(round(float(ctx.water_target) * total))
	var solid_target := int(round(float(ctx.solid_target) * total))
	var water_set := {}
	for k in mini(water_target, by_water.size()):
		water_set[by_water[k]["i"]] = true
	var solid_set := {}
	var placed := 0
	for entry in by_solid:
		if placed >= solid_target:
			break
		if water_set.has(entry["i"]):
			continue
		solid_set[entry["i"]] = true
		placed += 1

	for z in d:
		for x in w:
			var i := z * w + x
			var e := elev[i]
			var m := moist[i]
			if water_set.has(i):
				map.obstacle[i] = "water"
				map.ground[i] = "sand"
				map.elevation[i] = 0
			elif solid_set.has(i):
				# tree/rock 比例由 biome 的 tree_t 决定（forest 多树、mountain/desert 多岩）
				map.obstacle[i] = "tree" if m > float(profile["tree_t"]) else "rock"
				map.ground[i] = "grass" if map.obstacle[i] == "tree" else "stone"
				# 视觉 elevation 倾向由 biome 的 elev_gain 放大（mountain/ruins 更高耸）
				var t := clampf((e + 1.0) * 0.5 * float(profile["elev_gain"]), 0.0, 1.0)
				map.elevation[i] = clampi(1 + int(t * MAX_ELEVATION_LEVEL), 1, MAX_ELEVATION_LEVEL)
			else:
				map.obstacle[i] = "none"
				# 普通地面按 biome 阈值选择 grass/stone/sand
				if m > float(profile["grass_t"]):
					map.ground[i] = "grass"
				elif m < float(profile["stone_t"]):
					map.ground[i] = "stone"
				else:
					map.ground[i] = "sand"
				map.elevation[i] = 0
			if map.obstacle[i] == "none" and deco_noise.get_noise_2d(x, z) > 0.45:
				map.decoration[i] = "flower" if m > 0.0 else "shrub"

	_recompute_walkable(map)
	_remove_small_clusters(map, "water")
	_remove_small_clusters(map, "solid")
	_recompute_walkable(map)

	# —— POI：按 id 排序放置，各自独立显式 RNG ——
	var pois: Array = []
	for rule in ctx.poi_rules:
		var pid := str(rule.get("id"))
		var rng := RandomNumberGenerator.new()
		rng.seed = SeedDeriver.derive(ctx.world_seed, "map:%s:poi:%s" % [ctx.region_id, pid], attempt)
		var candidates := _poi_candidates(map, ctx.padding)
		_shuffle(candidates, rng)
		var found := Vector2i(-1, -1)
		for c in candidates:
			var ok := true
			for p in pois:
				var pt: Vector2i = p["tile"]
				if absi(int(c.x) - int(pt.x)) + absi(int(c.y) - int(pt.y)) < ctx.poi_min_dist:
					ok = false
					break
			if ok:
				found = c
				break
		if found.x < 0:
			return null
		pois.append({"id": pid, "tile": found})

	if pois.size() < 3:
		return null

	# —— 道路：首 POI 为根连接其余，路径+垂直相邻格 => 2 格宽 ——
	_carve_roads(map, pois, ctx.padding)
	_recompute_walkable(map)

	# —— 比率复核（道路开挖后重算）——
	var ratios := _ratios(map)
	if ratios["walk"] < ctx.walk_min or ratios["walk"] > ctx.walk_max:
		return null
	if ratios["water"] < WATER_RATIO_MIN or ratios["water"] > WATER_RATIO_MAX:
		return null
	if ratios["solid"] < SOLID_RATIO_MIN or ratios["solid"] > SOLID_RATIO_MAX:
		return null

	# —— 出生点与可达性 ——
	var spawn = _find_spawn(map, pois)
	if spawn == null:
		return null
	var reach := _flood(map, Vector2i(spawn.x, spawn.z))
	for p in pois:
		var pt: Vector2i = p["tile"]
		if not reach.has(pt.y * w + pt.x):
			return null

	for p in pois:
		map.poi_tiles[p["id"]] = Vector3i(int(p["tile"].x), 0, int(p["tile"].y))
	map.spawn_tile = spawn
	map.snapshot = MapSnapshotCodec.build_snapshot(
		str(ctx.world_id), str(ctx.region_id), w, d,
		map.ground, map.obstacle, map.decoration, map.elevation, map.poi_tiles, map.spawn_tile)
	map.map_hash = str(map.snapshot["hash"])
	return map

# —— 工具 ——

static func _make_noise(seed32: int, frequency: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = frequency
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = maxi(1, octaves)
	n.seed = seed32
	return n

static func _cmp_score(a, b) -> bool:
	if a["s"] != b["s"]:
		return a["s"] < b["s"]
	return a["i"] < b["i"]

# spawn 环内稳定次序：先 z 后 x
static func _cmp_zx(a, b) -> bool:
	if int(a.y) != int(b.y):
		return int(a.y) < int(b.y)
	return int(a.x) < int(b.x)

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

static func _recompute_walkable(map: GeneratedMap) -> void:
	for i in range(map.width * map.depth):
		map.walkable[i] = 1 if (map.obstacle[i] == "none" and map.elevation[i] == 0) else 0

static func _is_kind(obstacle: String, kind: String) -> bool:
	if kind == "water":
		return obstacle == "water"
	return obstacle == "rock" or obstacle == "tree"

static func _remove_small_clusters(map: GeneratedMap, kind: String) -> void:
	var w := map.width
	var d := map.depth
	var visited := PackedByteArray()
	visited.resize(w * d)
	for z in d:
		for x in w:
			var start := z * w + x
			if visited[start] == 1 or not _is_kind(map.obstacle[start], kind):
				continue
			var stack: Array = [Vector2i(x, z)]
			var cells: Array = []
			visited[start] = 1
			while stack.size() > 0:
				var c: Vector2i = stack.pop_back()
				cells.append(c)
				for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx := int(c.x) + int(dir.x)
					var nz := int(c.y) + int(dir.y)
					if not GridCoord.in_bounds(nx, nz, w, d):
						continue
					var ni := nz * w + nx
					if visited[ni] == 1 or not _is_kind(map.obstacle[ni], kind):
						continue
					visited[ni] = 1
					stack.append(Vector2i(nx, nz))
			if cells.size() < MIN_CLUSTER_CELLS:
				for c in cells:
					var i := int(c.y) * w + int(c.x)
					map.obstacle[i] = "none"
					map.ground[i] = "sand"
					map.elevation[i] = 0
					map.decoration[i] = "none"

static func _poi_candidates(map: GeneratedMap, padding: int) -> Array:
	var out: Array = []
	for z in range(padding, map.depth - padding):
		for x in range(padding, map.width - padding):
			if map.walkable[z * map.width + x] == 1:
				out.append(Vector2i(x, z))
	return out

static func _carve_roads(map: GeneratedMap, pois: Array, padding: int) -> void:
	var w := map.width
	var d := map.depth
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, d)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for z in d:
		for x in w:
			var i := z * w + x
			var cost := WALK_COST_GROUND
			if map.obstacle[i] == "water":
				cost = WALK_COST_WATER
			elif map.obstacle[i] != "none":
				cost = WALK_COST_SOLID
			var edge := mini(mini(x, w - 1 - x), mini(z, d - 1 - z))
			if edge < padding:
				cost += EDGE_EXTRA_COST
			astar.set_point_weight_scale(Vector2i(x, z), cost)
	var root := Vector2i(int(pois[0]["tile"].x), int(pois[0]["tile"].y))
	for k in range(1, pois.size()):
		var target := Vector2i(int(pois[k]["tile"].x), int(pois[k]["tile"].y))
		var path: PackedVector2Array = astar.get_id_path(root, target)
		for idx in range(path.size()):
			_set_road(map, int(path[idx].x), int(path[idx].y))
			if idx > 0:
				var dx := int(path[idx].x) - int(path[idx - 1].x)
				var dz := int(path[idx].y) - int(path[idx - 1].y)
				var sx := dz
				var sz := dx # 垂直于行进方向的相邻格
				if not GridCoord.in_bounds(int(path[idx].x) + sx, int(path[idx].y) + sz, w, d):
					sx = -sx
					sz = -sz
				_set_road(map, int(path[idx].x) + sx, int(path[idx].y) + sz)

static func _set_road(map: GeneratedMap, x: int, z: int) -> void:
	var i := z * map.width + x
	map.ground[i] = "road"
	map.obstacle[i] = "none"
	map.elevation[i] = 0
	map.decoration[i] = "none"
	map.walkable[i] = 1

static func _ratios(map: GeneratedMap) -> Dictionary:
	var total := map.width * map.depth
	var walk := 0
	var water := 0
	var solid := 0
	for i in total:
		if map.walkable[i] == 1:
			walk += 1
		elif map.obstacle[i] == "water":
			water += 1
		else:
			solid += 1
	return {
		"walk": float(walk) / float(total),
		"water": float(water) / float(total),
		"solid": float(solid) / float(total),
	}

static func _find_spawn(map: GeneratedMap, pois: Array):
	var w := map.width
	var d := map.depth
	var px := int(pois[0]["tile"].x)
	var pz := int(pois[0]["tile"].y)
	for r in range(1, w + d):
		var ring: Array = []
		for z in range(pz - r, pz + r + 1):
			for x in range(px - r, px + r + 1):
				if absi(x - px) + absi(z - pz) == r and GridCoord.in_bounds(x, z, w, d):
					ring.append(Vector2i(x, z))
		ring.sort_custom(_cmp_zx)
		for c in ring:
			var i := int(c.y) * w + int(c.x)
			if map.walkable[i] != 1:
				continue
			var is_poi := false
			for p in pois:
				if int(p["tile"].x) == int(c.x) and int(p["tile"].y) == int(c.y):
					is_poi = true
					break
			if not is_poi:
				return Vector3i(int(c.x), 0, int(c.y))
	return null

static func _flood(map: GeneratedMap, from_tile: Vector2i) -> Dictionary:
	var w := map.width
	var d := map.depth
	var visited := {}
	var stack: Array = [from_tile]
	visited[int(from_tile.y) * w + int(from_tile.x)] = true
	while stack.size() > 0:
		var c: Vector2i = stack.pop_back()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := int(c.x) + int(dir.x)
			var nz := int(c.y) + int(dir.y)
			if not GridCoord.in_bounds(nx, nz, w, d):
				continue
			var ni := nz * w + nx
			if map.walkable[ni] == 1 and not visited.has(ni):
				visited[ni] = true
				stack.append(Vector2i(nx, nz))
	return visited

static func _fail_schema(message: String) -> Dictionary:
	return {"ok": false, "code": "E_SCHEMA_INVALID", "message": message, "data": null, "attempts": 0}
