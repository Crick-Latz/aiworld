class_name World2DProjector
extends RefCounted
## UI-R1：2D 像素世界投影器（presentation only）。
## 只读 MapController 窄接口（get_obstacle / is_walkable_tile / get_poi_tiles /
## get_spawn_tile / map_size），把 64x64 逻辑地图投影成暖色像素地形 + 占位物件。
## 沙滩/林地边缘等视觉分类是纯表现层派生，不携带任何模拟真值语义；
## 装饰散布用稳定哈希（无 RNG 流，不参与确定性回放诊断）。

const TILE_SIZE := 16

const PROP_TEXTURES := {
	"tree": preload("res://assets/pixel/props/tree.png"),
	"stump": preload("res://assets/pixel/props/stump.png"),
	"rock": preload("res://assets/pixel/props/rock.png"),
	"bush": preload("res://assets/pixel/props/bush.png"),
	"berry_bush": preload("res://assets/pixel/props/berry_bush.png"),
	"campfire": preload("res://assets/pixel/props/campfire.png"),
	"tent": preload("res://assets/pixel/props/tent.png"),
	"market_stall": preload("res://assets/pixel/props/market_stall.png"),
	"lighthouse": preload("res://assets/pixel/props/lighthouse.png"),
	"shell": preload("res://assets/pixel/props/shell.png"),
	"driftwood": preload("res://assets/pixel/props/driftwood.png"),
}

## POI id → 占位物件名（正式美术到位后换资源即可）
const POI_PROP := {
	"post_house": "tent",
	"tide_market": "market_stall",
	"old_lighthouse": "lighthouse",
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
	var placed_props := {}
	var stats := {"tiles": 0, "water": 0, "sand": 0, "grass": 0, "forest": 0, "rock": 0, "props": 0}
	for z in size.y:
		for x in size.x:
			var logic := _classify(map_controller, x, z, size)
			ground_layer.set_cell(Vector2i(x, z), 0, PixelTileset.atlas_coords(logic["tile"]))
			stats["tiles"] += 1
			match logic["tile"].split("_")[0]:
				"grass", "dirt", "path": stats["grass"] += 1
				"sand", "foam": stats["sand"] += 1
				"shallow", "deep": stats["water"] += 1
				"forest": stats["forest"] += 1
				"rock", "cliff", "gravel": stats["rock"] += 1
			if logic.has("prop"):
				_spawn_prop(props_root, str(logic["prop"]), Vector2i(x, z))
				placed_props[Vector2i(x, z)] = true
				stats["props"] += 1
	# POI 物件（覆盖散布装饰不重复占格）
	for poi_id in map_controller.get_poi_tiles():
		var prop_name: String = POI_PROP.get(poi_id, "campfire")
		var t: Vector3i = map_controller.get_poi_tiles()[poi_id]
		if not placed_props.has(Vector2i(t.x, t.z)):
			_spawn_prop(props_root, prop_name, Vector2i(t.x, t.z))
			stats["props"] += 1
	# 营地篝火：出生格
	var spawn: Vector3i = map_controller.get_spawn_tile()
	if not placed_props.has(Vector2i(spawn.x, spawn.z)):
		_spawn_prop(props_root, "campfire", Vector2i(spawn.x, spawn.z))
		stats["props"] += 1
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
		return {"tile": "forest_a" if alt else "forest_b", "prop": "tree"}
	if obstacle == "rock":
		return {"tile": "rock_ground_a" if alt else "rock_ground_b", "prop": "rock"}
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
			return {"tile": "forest_b" if alt else "forest_a"}
		if _stable_hash(x, z, "dirt") % 23 == 0:
			return {"tile": "dirt"}
		var grass_out := {"tile": "grass_a" if alt else "grass_b"}
		if _stable_hash(x, z, "bush") % 29 == 0:
			grass_out["prop"] = "berry_bush" if _stable_hash(x, z, "berry") % 2 == 0 else "bush"
		return grass_out
	# 不可行走且无障碍物：生成器语义里是抬升地形，画成悬崖沿
	return {"tile": "cliff_edge"}

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

## 物件脚底对齐格底边；高于 16px 的物件（树/灯塔）向上延伸覆盖上一行。
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
