class_name World2DProjector
extends RefCounted
## UI-R1 v3：2D 像素世界投影器（presentation only）。
## 只读 MapController 窄接口（get_obstacle / is_walkable_tile / get_poi_tiles /
## get_spawn_tile / map_size），把逻辑地图投影成暖色像素地形 + 占位物件 + 六分区布景
## 布景纪律（v3）：具有阻挡语义的物件只允许出现在模拟已判不可行走的格子；
## 可行走格只放花/杂草/贝壳/漂木/幼苗/小作物等"踩过也合理"的轻装饰。
## POI 用轻量木牌标记（可穿过），不再用帐篷/木屋等阻挡感物件。
## 沙滩/林地边缘等视觉分类是纯表现层派生，不携带任何模拟真值语义；
## 装饰与布景用稳定哈希（无 RNG 流，不参与确定性回放诊断）。

const TILE_SIZE := 16

const PROP_TEXTURES := {
	"tree_oak": preload("res://assets/pixel/props/tree_oak.png"),
	"tree_pine": preload("res://assets/pixel/props/tree_pine.png"),
	"lighthouse": preload("res://assets/pixel/props/lighthouse.png"),
	"stump": preload("res://assets/pixel/props/stump.png"),
	"rock": preload("res://assets/pixel/props/rock.png"),
	"rock_large": preload("res://assets/pixel/props/rock_large.png"),
	"bush": preload("res://assets/pixel/props/bush.png"),
	"berry_bush": preload("res://assets/pixel/props/berry_bush.png"),
	"sapling": preload("res://assets/pixel/props/sapling.png"),
	"flower": preload("res://assets/pixel/props/flower.png"),
	"weed": preload("res://assets/pixel/props/weed.png"),
	"campfire": preload("res://assets/pixel/props/campfire.png"),
	"cabin": preload("res://assets/pixel/props/cabin.png"),
	"tent": preload("res://assets/pixel/props/tent.png"),
	"market_stall": preload("res://assets/pixel/props/market_stall.png"),
	"crate": preload("res://assets/pixel/props/crate.png"),
	"barrel": preload("res://assets/pixel/props/barrel.png"),
	"chest": preload("res://assets/pixel/props/chest.png"),
	"fence_h": preload("res://assets/pixel/props/fence_h.png"),
	"fence_v": preload("res://assets/pixel/props/fence_v.png"),
	"well": preload("res://assets/pixel/props/well.png"),
	"workbench": preload("res://assets/pixel/props/workbench.png"),
	"machine": preload("res://assets/pixel/props/machine.png"),
	"log_pile": preload("res://assets/pixel/props/log_pile.png"),
	"stone_pile": preload("res://assets/pixel/props/stone_pile.png"),
	"crop_a": preload("res://assets/pixel/props/crop_a.png"),
	"crop_b": preload("res://assets/pixel/props/crop_b.png"),
	"shell": preload("res://assets/pixel/props/shell.png"),
	"driftwood": preload("res://assets/pixel/props/driftwood.png"),
}

## POI id → 占位物件名（正式美术到位后换资源即可）
const POI_PROP := {
	"post_house": "poi_flag",
	"tide_market": "poi_flag",
	"old_lighthouse": "poi_flag",
}

## 一次性把整张地图投影进 ground_layer（TileMapLayer）与 props_root（Node2D）。
## 返回统计字典（诊断用，不参与模拟）。
static func project(map_controller, ground_layer: TileMapLayer, props_root: Node2D) -> Dictionary:
	var tile_set := PixelTileset.build()
	ground_layer.tile_set = tile_set
	ground_layer.clear()
	for c in props_root.get_children():
		props_root.remove_child(c)
		c.free()
	var size: Vector2i = map_controller.map_size()
	var occupied := {}
	var stats := {"tiles": 0, "water": 0, "sand": 0, "grass": 0, "forest": 0, "rock": 0, "props": 0, "zones": {}}
	for z in size.y:
		for x in size.x:
			var logic := _classify(map_controller, x, z, size)
			ground_layer.set_cell(Vector2i(x, z), 0, PixelTileset.atlas_coords(logic["tile"]))
			stats["tiles"] += 1
			match logic["tile"].split("_")[0]:
				"grass", "dirt", "path", "farmland": stats["grass"] += 1
				"sand", "foam": stats["sand"] += 1
				"shallow", "deep": stats["water"] += 1
				"forest": stats["forest"] += 1
				"rock", "cliff", "gravel": stats["rock"] += 1
			if logic.has("prop"):
				_spawn_prop(props_root, str(logic["prop"]), Vector2i(x, z))
				occupied[Vector2i(x, z)] = true
				stats["props"] += 1
	# POI 物件（覆盖散布装饰不重复占格）
	for poi_id in map_controller.get_poi_tiles():
		var prop_name: String = POI_PROP.get(poi_id, "campfire")
		var t: Vector3i = map_controller.get_poi_tiles()[poi_id]
		if not occupied.has(Vector2i(t.x, t.z)):
			_spawn_prop(props_root, prop_name, Vector2i(t.x, t.z))
			occupied[Vector2i(t.x, t.z)] = true
			stats["props"] += 1
	# 六分区布景：营地（出生点邻域）+ 农地 + 工坊
	stats["zones"] = _dress_zones(map_controller, ground_layer, props_root, occupied)
	stats["props"] += int((stats["zones"] as Dictionary).get("props", 0))
	return stats

## 单格视觉分类：返回 {"tile": 逻辑名, "prop"?: 物件名}
static func _classify(map_controller, x: int, z: int, size: Vector2i) -> Dictionary:
	var obstacle := str(map_controller.get_obstacle(x, z))
	var walkable: bool = map_controller.is_walkable_tile(Vector3i(x, 0, z))
	var alt := _stable_hash(x, z, "alt") % 2 == 0
	if obstacle == "water":
		var near_land := _any_neighbor(map_controller, x, z, size,
				func(ox: int, oz: int) -> bool: return str(map_controller.get_obstacle(ox, oz)) != "water")
		if near_land:
			return {"tile": "foam_edge" if alt else "shallow_a"}
		return {"tile": "shallow_b" if alt else "deep_a"}
	if obstacle == "tree":
		var tree_kind := "tree_pine" if _stable_hash(x, z, "pine") % 3 == 0 else "tree_oak"
		return {"tile": "forest_a" if alt else "forest_b", "prop": tree_kind}
	if obstacle == "rock":
		return {"tile": "rock_ground_a" if alt else "rock_ground_b",
			"prop": "rock_large" if _stable_hash(x, z, "bigrock") % 5 == 0 else "rock"}
	if walkable:
		var near_water := _any_neighbor(map_controller, x, z, size,
				func(ox: int, oz: int) -> bool: return str(map_controller.get_obstacle(ox, oz)) == "water")
		if near_water:
			var out := {"tile": "sand_a" if alt else "sand_b"}
			if _stable_hash(x, z, "shell") % 31 == 0:
				out["prop"] = "shell"
			elif _stable_hash(x, z, "drift") % 37 == 0:
				out["prop"] = "driftwood"
			return out
		var near_forest := _any_neighbor(map_controller, x, z, size,
				func(ox: int, oz: int) -> bool: return str(map_controller.get_obstacle(ox, oz)) == "tree")
		if near_forest:
			var forest_out := {"tile": "forest_b" if alt else "forest_a"}
			if _stable_hash(x, z, "sap") % 41 == 0:
				forest_out["prop"] = "sapling"
			return forest_out
		if _stable_hash(x, z, "dirt") % 23 == 0:
			return {"tile": "dirt"}
		# v3.1：walkable 草地只放可穿过的轻装饰；bush/berry_bush 是视觉阻挡性灌木，
		# 资产保留但不再投影到可行走格（待 non-walkable footprint 机制）
		var grass_out := {"tile": "grass_a" if alt else "grass_b"}
		var pick := _stable_hash(x, z, "deco")
		if pick % 43 == 0:
			grass_out["prop"] = "flower"
		elif pick % 47 == 0:
			grass_out["prop"] = "weed"
		return grass_out
	# 不可行走且无障碍物：生成器语义里是抬升地形，画成悬崖沿
	return {"tile": "cliff_edge"}

## 出生点邻域确定性布景（v3 阻挡纪律版）：
## - 阻挡语义物件（木屋/井/工作台/机器/围栏/箱柜/木石堆/营火/帐篷/市集/灯塔）
##   一律不落在可行走格；当前地图生成器没有合法 non-walkable footprint 可分配，
##   因此全部取消（宁缺毋假——不为画面丰富制造"可穿过的木屋"）。
## - 农地：耕地 tile + 小作物（轻装饰，踩过合理）。
## - 营地点缀：少量花/幼苗。
static func _dress_zones(map_controller, ground_layer: TileMapLayer, props_root: Node2D, occupied: Dictionary) -> Dictionary:
	var spawn: Vector3i = map_controller.get_spawn_tile()
	var free := _free_ring(map_controller, Vector2i(spawn.x, spawn.z), occupied, 7)
	var stats := {"camp": 0, "farm": 0, "workshop": 0, "props": 0}
	var cursor := 0
	var farm_count := 0
	while cursor < free.size() and farm_count < 6:
		var t: Vector2i = free[cursor]
		ground_layer.set_cell(t, 0, PixelTileset.atlas_coords("farmland"))
		_spawn_prop(props_root, "crop_b" if farm_count % 2 == 0 else "crop_a", t)
		occupied[t] = true
		cursor += 1
		farm_count += 1
		stats["farm"] += 1
		stats["props"] += 1
	var deco := ["flower", "sapling", "flower", "weed", "flower"]
	for prop_name in deco:
		if cursor >= free.size():
			break
		var t: Vector2i = free[cursor]
		_spawn_prop(props_root, prop_name, t)
		occupied[t] = true
		cursor += 1
		stats["camp"] += 1
		stats["props"] += 1
	stats["workshop"] = 0 # 阻挡性工坊物件待合法 non-walkable footprint（见头注释）
	return stats

## 出生点邻域的可行走空闲格，按（切比雪夫距离, x, y）稳定排序。
static func _free_ring(map_controller, center: Vector2i, occupied: Dictionary, radius: int) -> Array:
	var size: Vector2i = map_controller.map_size()
	var found: Array = []
	for z in range(maxi(0, center.y - radius), mini(size.y, center.y + radius + 1)):
		for x in range(maxi(0, center.x - radius), mini(size.x, center.x + radius + 1)):
			var t := Vector2i(x, z)
			if t == center or occupied.has(t):
				continue
			if not map_controller.is_walkable_tile(Vector3i(x, 0, z)):
				continue
			found.append([maxi(absi(x - center.x), absi(z - center.y)), x, z])
	found.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and (a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))))
	var out: Array = []
	for row in found:
		out.append(Vector2i(row[1], row[2]))
	return out

static func _any_neighbor(map_controller, x: int, z: int, size: Vector2i, pred: Callable) -> bool:
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for d in dirs:
		var nx: int = x + d.x
		var nz: int = z + d.y
		if nx < 0 or nz < 0 or nx >= size.x or nz >= size.y:
			continue
		if bool(pred.call(nx, nz)):
			return true
	return false

## 稳定装饰哈希：与运行平台无关的 FNV-1a 派生（纯表现层，非 RNG 流）。
static func _stable_hash(x: int, z: int, salt: String) -> int:
	var h := 2166136261
	var s := "%s|%d|%d" % [salt, x, z]
	for i in s.length():
		h = (h ^ s.unicode_at(i)) * 16777619
		h &= 0x7FFFFFFF
	return h

## 物件脚底对齐格底边；高于 16px 的物件（树/木屋/灯塔）向上延伸覆盖上一行。
static func _spawn_prop(props_root: Node2D, prop_name: String, tile: Vector2i) -> void:
	var tex: Texture2D = PROP_TEXTURES.get(prop_name, null)
	if tex == null:
		return
	var s := Sprite2D.new()
	s.name = StringName("%s_%d_%d" % [prop_name, tile.x, tile.y])
	s.texture = tex
	s.centered = false
	s.position = Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE + TILE_SIZE - tex.get_height())
	s.z_index = 1
	props_root.add_child(s)
