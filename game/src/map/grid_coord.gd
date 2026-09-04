class_name GridCoord
extends RefCounted
## 逻辑格坐标工具（WP-03）。XZ 为逻辑平面，Y/Vector3i 第二分量表示 level。

static func to_index(x: int, z: int, width: int) -> int:
	return z * width + x

static func in_bounds(x: int, z: int, width: int, depth: int) -> bool:
	return x >= 0 and z >= 0 and x < width and z < depth

static func tile_to_world(tile: Vector3i, cell_size_m := 1.0, level_height_m := 0.5) -> Vector3:
	return Vector3(
		(tile.x + 0.5) * cell_size_m,
		tile.y * level_height_m,
		(tile.z + 0.5) * cell_size_m)

static func world_to_tile(pos: Vector3, cell_size_m := 1.0, level_height_m := 0.5) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / cell_size_m)),
		int(floor(pos.y / level_height_m)),
		int(floor(pos.z / cell_size_m)))
