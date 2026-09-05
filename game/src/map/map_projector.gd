class_name MapProjector
extends RefCounted
## GeneratedMap -> GridMap / POI 节点投影（WP-03 / R1 / WP-04）。
## 纪律：item id 一律通过 MeshLibrary 名称解析；投影前清空，避免重复构建残留。
## R1：POI Label3D 显示 poi_rules 的显示名（metadata 仍存稳定 poi_id）。
## WP-04：每个 POI 根节点是 Area3D（Poi_<安全ID>，layer=interaction bit4、mask=player bit2），
## 子碰撞球不阻挡玩家；metadata 含 interactable/target_type/target_id/display_name/poi_id。

static func project(map: GeneratedMap, ground_grid: GridMap, obstacle_grid: GridMap,
		poi_root: Node3D, mesh_lib: MeshLibrary, poi_names: Dictionary = {}) -> Dictionary:
	var ids := {}
	for name in PrototypeMeshLibrary.ITEM_NAMES:
		var id := mesh_lib.find_item_by_name(name)
		if id < 0:
			return {"ok": false, "code": "E_SCHEMA_INVALID", "message": "MeshLibrary 缺少 item：" + name,
				"ground_cells": 0, "obstacle_cells": 0, "poi_count": 0}
		ids[name] = id

	ground_grid.clear()
	obstacle_grid.clear()
	for c in poi_root.get_children():
		poi_root.remove_child(c)
		c.free()

	var ground_cells := 0
	var obstacle_cells := 0
	for z in map.depth:
		for x in map.width:
			var i := z * map.width + x
			var level := map.elevation[i]
			ground_grid.set_cell_item(Vector3i(x, level, z), int(ids["ground_" + map.ground[i]]), 0)
			ground_cells += 1
			var ob := map.obstacle[i]
			if ob == "water":
				obstacle_grid.set_cell_item(Vector3i(x, 0, z), int(ids["water_blocked"]), 0)
				obstacle_cells += 1
			elif ob == "rock":
				obstacle_grid.set_cell_item(Vector3i(x, level, z), int(ids["rock_small"]), 0)
				obstacle_cells += 1
			elif ob == "tree":
				obstacle_grid.set_cell_item(Vector3i(x, level, z), int(ids["tree_lowpoly"]), 0)
				obstacle_cells += 1

	var poi_count := 0
	for pid in map.poi_tiles:
		var tile: Vector3i = map.poi_tiles[pid]
		var safe_id := _safe_id(str(pid))
		var display := str(poi_names.get(str(pid), str(pid)))

		var area := Area3D.new()
		area.name = "Poi_" + safe_id
		area.collision_layer = 8 # interaction bit 4
		area.collision_mask = 2 # player bit 2（检测玩家，不产生实体推挤）
		area.monitoring = true
		area.position = GridCoord.tile_to_world(tile)
		area.set_meta("interactable", true)
		area.set_meta("target_type", "poi")
		area.set_meta("target_id", str(pid))
		area.set_meta("display_name", display)
		area.set_meta("poi_id", str(pid)) # 兼容既有语义：稳定 ID

		var marker := MeshInstance3D.new()
		marker.name = "MarkerMesh"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.8, 1.6, 0.8)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color8(242, 140, 26)
		mat.emission_enabled = true
		mat.emission = Color8(242, 140, 26)
		mat.emission_energy_multiplier = 0.6
		mesh.material = mat
		marker.mesh = mesh
		marker.position = Vector3(0, 0.8, 0)

		var label := Label3D.new()
		label.name = "Label3D"
		label.text = display
		label.font_size = 20
		label.fixed_size = true
		label.no_depth_test = true
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color8(255, 248, 220)
		label.outline_size = 4
		label.outline_modulate = Color8(24, 24, 32, 220)
		label.position = Vector3(0, 1.9, 0) # marker 顶面之上，不与柱体重叠

		var cs := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.8
		cs.shape = sphere
		cs.position = Vector3(0, 0.8, 0)

		area.add_child(marker)
		area.add_child(label)
		area.add_child(cs)
		poi_root.add_child(area)
		poi_count += 1

	return {"ok": true, "code": "OK", "message": "",
		"ground_cells": ground_cells, "obstacle_cells": obstacle_cells, "poi_count": poi_count}

static func _safe_id(pid: String) -> String:
	var out := ""
	for ch in pid.to_lower():
		if ("a" <= ch and ch <= "z") or ("0" <= ch and ch <= "9") or ch == "_":
			out += ch
	return out if not out.is_empty() else "poi"
