class_name MapNavigator
extends RefCounted
## 地图寻路工具（WP-04）。复用 WP-03 的 XZ 四邻接规则：
## AStarGrid2D DIAGONAL_MODE_NEVER；只有 walkable==1 且 obstacle==none 且 elevation==0 可进入。
## 输入越界、起终点不可走、无路或路径超过 max_nodes 时安静返回空数组。
## 相同地图/起点/终点得到相同路径。本模块不创建 NPC、不跑 semantic tick。

static func find_path(map: GeneratedMap, from_tile: Vector3i, to_tile: Vector3i, max_nodes: int = 256) -> Array:
	if map == null:
		return []
	var w := map.width
	var d := map.depth
	if not GridCoord.in_bounds(from_tile.x, from_tile.z, w, d) or not GridCoord.in_bounds(to_tile.x, to_tile.z, w, d):
		return []
	if from_tile.y != 0 or to_tile.y != 0:
		return []
	if not _enterable(map, from_tile.x, from_tile.z, w) or not _enterable(map, to_tile.x, to_tile.z, w):
		return []
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, d)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for z in d:
		for x in w:
			if not _enterable(map, x, z, w):
				astar.set_point_solid(Vector2i(x, z), true)
	var path: PackedVector2Array = astar.get_id_path(Vector2i(from_tile.x, from_tile.z), Vector2i(to_tile.x, to_tile.z))
	if path.is_empty():
		return []
	if path.size() > max_nodes:
		return []
	var out: Array = []
	for p in path:
		out.append(p)
	return out

static func _enterable(map: GeneratedMap, x: int, z: int, width: int) -> bool:
	var i := z * width + x
	return map.walkable[i] == 1 and map.obstacle[i] == "none" and map.elevation[i] == 0
