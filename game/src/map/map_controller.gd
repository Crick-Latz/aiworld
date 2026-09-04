extends Node
## MapController：Main 场景的一次构建入口（WP-03 / R1）。
## 职责：拿 WorldSpec + AppConfig 的 map 配置生成地图并投影到场景节点；
## 保存诊断数据供 F3 调试层读取。构建失败返回稳定错误码，不抛异常。
## R1 状态恢复：每次 build 从零开始——清空旧地图/计数/比率/错误；
## 失败时清空 GridMap 与 PoiRoot，has_map() 必须 false，不残留上一张地图数据。

var _map: GeneratedMap = null
var _mesh_lib: MeshLibrary = null
var _ground_cells := 0
var _obstacle_cells := 0
var _poi_count := 0
var _ratios: Dictionary = {}
var _last_error_code := ""
var _last_error_message := ""

func build(world_spec: Dictionary, map_config: Dictionary) -> Dictionary:
	# 状态复位（R1）：一次新 build 不携带上一张地图的任何数据
	_map = null
	_ground_cells = 0
	_obstacle_cells = 0
	_poi_count = 0
	_ratios = {}
	_last_error_code = ""
	_last_error_message = ""

	var ground_grid := get_node_or_null("../GroundGrid") as GridMap
	var obstacle_grid := get_node_or_null("../ObstacleGrid") as GridMap
	var poi_root := get_node_or_null("../PoiRoot")
	if ground_grid == null or obstacle_grid == null or poi_root == null:
		_last_error_code = "E_SCHEMA_INVALID"
		_last_error_message = "场景缺少 GroundGrid/ObstacleGrid/PoiRoot 节点"
		return {"ok": false, "code": _last_error_code, "message": _last_error_message, "data": null, "attempts": 0}

	if _mesh_lib == null:
		_mesh_lib = PrototypeMeshLibrary.build()
	ground_grid.mesh_library = _mesh_lib
	obstacle_grid.mesh_library = _mesh_lib
	ground_grid.collision_layer = 1
	obstacle_grid.collision_layer = 1

	var result := MapGenerator.generate(world_spec, map_config)
	if not result.ok:
		_last_error_code = str(result.code)
		_last_error_message = str(result.message)
		_clear_projection(ground_grid, obstacle_grid, poi_root)
		return result

	var poi_names := _extract_poi_names(world_spec)
	var map_data: GeneratedMap = result.data
	var proj := MapProjector.project(map_data, ground_grid, obstacle_grid, poi_root, _mesh_lib, poi_names)
	if not proj.ok:
		_last_error_code = str(proj.code)
		_last_error_message = str(proj.message)
		_clear_projection(ground_grid, obstacle_grid, poi_root)
		return {"ok": false, "code": _last_error_code, "message": _last_error_message, "data": null, "attempts": result.attempts}

	_map = map_data
	_ground_cells = int(proj.ground_cells)
	_obstacle_cells = int(proj.obstacle_cells)
	_poi_count = int(proj.poi_count)
	_ratios = MapGenerator._ratios(_map)
	return result

func has_map() -> bool:
	return _map != null

func map_size() -> Vector2i:
	return Vector2i(_map.width, _map.depth) if _map != null else Vector2i.ZERO

func get_map_debug() -> Dictionary:
	var err := "%s: %s" % [_last_error_code, _last_error_message] if not _last_error_code.is_empty() else "-"
	if _map == null:
		return {
			"map_generator_version": "-", "map_hash": "-", "map_retry_index": "-",
			"map_size": "-", "map_ratios": "-",
			"map_cells": "-", "poi_count": "-", "spawn_tile": "-",
			"map_error": err,
		}
	return {
		"map_generator_version": str(_map.snapshot.get("generator_version", "-")),
		"map_hash": _map.map_hash,
		"map_retry_index": str(_map.retry_index),
		"map_size": "%d x %d" % [_map.width, _map.depth],
		"map_ratios": "walk=%.3f water=%.3f solid=%.3f" % [_ratios.get("walk", 0.0), _ratios.get("water", 0.0), _ratios.get("solid", 0.0)],
		"map_cells": "ground=%d obstacle=%d" % [_ground_cells, _obstacle_cells],
		"poi_count": str(_poi_count),
		"spawn_tile": "(%d, %d)" % [_map.spawn_tile.x, _map.spawn_tile.z],
		"map_error": err,
	}

func _clear_projection(ground_grid: GridMap, obstacle_grid: GridMap, poi_root: Node3D) -> void:
	ground_grid.clear()
	obstacle_grid.clear()
	for c in poi_root.get_children():
		poi_root.remove_child(c)
		c.free()

static func _extract_poi_names(world_spec: Dictionary) -> Dictionary:
	var names := {}
	var regions = world_spec.get("regions", [])
	if typeof(regions) != TYPE_ARRAY:
		return names
	for r in regions:
		if typeof(r) != TYPE_DICTIONARY or str(r.get("id")) != str(world_spec.get("starting_region_id")):
			continue
		var rules = r.get("poi_rules", [])
		if typeof(rules) == TYPE_ARRAY:
			for pr in rules:
				if typeof(pr) == TYPE_DICTIONARY:
					names[str(pr.get("id"))] = str(pr.get("name", pr.get("id")))
		break
	return names
