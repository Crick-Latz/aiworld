class_name PixelTileset
extends RefCounted
## UI-R1：地形 TileSet 运行时构建（presentation）。
## 从 assets/pixel/tiles/terrain_16.png 图集切片，避免手写 .tres；
## 逻辑名 → 图集坐标的唯一映射表在这里维护。

const ATLAS := preload("res://assets/pixel/tiles/terrain_16.png")
const TILE_SIZE := 16

## 图集布局（8 列 × 3 行，每格 16px）：
## (0,0)grass_a (1,0)grass_b (2,0)sand_a (3,0)sand_b (4,0)dirt (5,0)path
## (6,0)forest_a (7,0)forest_b
## (0,1)shallow_a (1,1)shallow_b (2,1)deep_a (3,1)deep_b (4,1)rock_ground_a
## (5,1)rock_ground_b (6,1)cliff_edge (7,1)gravel
## (0,2)foam_edge (1,2)sand_grass_edge
const TILES := {
	"grass_a": Vector2i(0, 0), "grass_b": Vector2i(1, 0),
	"sand_a": Vector2i(2, 0), "sand_b": Vector2i(3, 0),
	"dirt": Vector2i(4, 0), "path": Vector2i(5, 0),
	"forest_a": Vector2i(6, 0), "forest_b": Vector2i(7, 0),
	"shallow_a": Vector2i(0, 1), "shallow_b": Vector2i(1, 1),
	"deep_a": Vector2i(2, 1), "deep_b": Vector2i(3, 1),
	"rock_ground_a": Vector2i(4, 1), "rock_ground_b": Vector2i(5, 1),
	"cliff_edge": Vector2i(6, 1), "gravel": Vector2i(7, 1),
	"foam_edge": Vector2i(0, 2), "sand_grass_edge": Vector2i(1, 2), "farmland": Vector2i(2, 2),
}

static func build() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	ts.add_source(_build_atlas_source(), 0)
	return ts

static func atlas_coords(logical_name: String) -> Vector2i:
	return TILES.get(logical_name, TILES["grass_a"])

static func _build_atlas_source() -> TileSetAtlasSource:
	var src := TileSetAtlasSource.new()
	src.texture = ATLAS
	src.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for name_key in TILES:
		src.create_tile(TILES[name_key])
	return src
