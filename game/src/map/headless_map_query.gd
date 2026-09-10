class_name HeadlessMapQuery
extends RefCounted
## The same terrain/query contract as MapController, without meshes, camera or UI.
var _map: GeneratedMap

func _init(generated: GeneratedMap) -> void:
	_map = generated

func map_size() -> Vector2i:
	return Vector2i(_map.width, _map.depth)

func get_map_rect() -> Rect2i:
	return Rect2i(0, 0, _map.width, _map.depth)

func get_spawn_tile() -> Vector3i:
	return _map.spawn_tile

func get_poi_tiles() -> Dictionary:
	return _map.poi_tiles.duplicate(true)

func get_poi_tile(poi_id: String) -> Vector2i:
	if not _map.poi_tiles.has(poi_id):
		return Vector2i(-1, -1)
	var tile: Vector3i = _map.poi_tiles[poi_id]
	return Vector2i(tile.x, tile.z)

func is_walkable_tile(tile: Vector3i) -> bool:
	return tile.y == 0 and GridCoord.in_bounds(tile.x, tile.z, _map.width, _map.depth) \
		and _map.walkable[tile.z * _map.width + tile.x] == 1

func get_obstacle(x: int, z: int) -> String:
	if not GridCoord.in_bounds(x, z, _map.width, _map.depth):
		return "none"
	return _map.obstacle[z * _map.width + x]

func find_walk_path(from_tile: Vector3i, to_tile: Vector3i, max_nodes: int = 256) -> Array:
	return MapNavigator.find_path(_map, from_tile, to_tile, max_nodes)
