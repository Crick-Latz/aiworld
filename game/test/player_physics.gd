extends SceneTree
## WP-04 物理集成测试（真实实例化 Main 并等待 physics frame，不做源码字符串检查）。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://test/player_physics.gd
## 退出码：全部通过=0。失败打印位置/碰撞细节，不无限等待（每段有步数预算）。

var passed := 0
var failed := 0
var _started := false
var _finished := false
var _inst: Node = null

func _initialize() -> void:
	print("WP04 physics harness: tests deferred to first frame")

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run() # 异步：挂起后引擎继续跑帧，直到 quit()
	return _finished

func _run() -> void:
	await _run_all_tests()
	print("SUMMARY pass=%d fail=%d" % [passed, failed])
	_finished = true
	quit(0 if failed == 0 else 1)

func _check(name: String, cond: bool, detail: String = "") -> void:
	if cond:
		passed += 1
		print("PASS %s" % name)
	else:
		failed += 1
		print("FAIL %s  %s" % [name, detail])

func _steps(n: int) -> void:
	for i in n:
		await physics_frame

func _run_all_tests() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		_check("main_loadable", false, "场景不可加载")
		return
	_inst = ps.instantiate()
	root.add_child(_inst)
	await _steps(30) # 落地稳定
	var player: PlayerController = _inst.get_node_or_null("World/ActorRoot/Player")
	if player == null:
		_check("player_spawned_on_floor", false, "无玩家")
		return
	var ctl = _inst.get_node("World/MapController")

	_check("player_spawned_on_floor", player.is_on_floor(), "pos=%s" % player.global_position)
	var expect := GridCoord.tile_to_world(ctl.get_spawn_tile())
	_check("spawn_position_matches_tile",
		absf(player.global_position.x - expect.x) < 0.25
		and absf(player.global_position.z - expect.z) < 0.25
		and absf(player.global_position.y - 0.05) < 0.25,
		"pos=%s expect=%s" % [player.global_position, expect])

	var p0 := player.global_position
	await _steps(60)
	_check("no_drift_without_input", player.global_position.distance_to(p0) < 0.02,
		"drift=%.3f" % player.global_position.distance_to(p0))

	var dir := _clear_direction(ctl, player)
	player.set_test_world_direction(dir)
	var start := player.global_position
	await _steps(60)
	player.clear_test_input()
	var moved := (player.global_position - start).dot(dir)
	_check("move_speed_1s", moved > 3.8 and moved < 5.2, "moved=%.2f dir=%s" % [moved, dir])

	var diag_dir := (dir + Vector3(dir.z, 0, -dir.x)).normalized()
	player.set_test_world_direction(diag_dir)
	start = player.global_position
	await _steps(60)
	var diag := player.global_position.distance_to(start)
	player.clear_test_input()
	_check("diagonal_speed_capped", diag > 3.5 and diag < 4.95, "diag=%.2f" % diag)

	await _test_blocked_by_obstacle(ctl, player)

	await _drive_to_boundary(ctl, player, "x-", "west")
	await _drive_to_boundary(ctl, player, "x+", "east")
	await _drive_to_boundary(ctl, player, "z-", "north")
	await _drive_to_boundary(ctl, player, "z+", "south")

	await _visit_pois(ctl, player)

	var pc = _inst.get_node("Ui/PauseController")
	var before_pause := player.global_position
	player.set_test_world_direction(Vector3(1, 0, 0))
	pc.pause()
	await _steps(120)
	var frozen: bool = player.global_position == before_pause
	pc.resume()
	player.clear_test_input()
	_check("pause_freezes_player", frozen, "delta=%s" % (player.global_position - before_pause))

	var cam_ctl = _inst.get_node("World/CameraRig")
	Input.action_press("move_up")
	var s1 := player.global_position
	await _steps(30)
	Input.action_release("move_up")
	var d1 := player.global_position - s1
	d1.y = 0
	cam_ctl.rotate_yaw(1)
	await _steps(20) # 等 90° Tween 完成
	Input.action_press("move_up")
	var s2 := player.global_position
	await _steps(30)
	Input.action_release("move_up")
	var d2 := player.global_position - s2
	d2.y = 0
	var dotv := 1.0
	if d1.length() > 0.5 and d2.length() > 0.5:
		dotv = d1.normalized().dot(d2.normalized())
	_check("camera_rotation_rotates_input_dir", absf(dotv) < 0.35, "dot=%.2f d1=%s d2=%s" % [dotv, d1, d2])

	var cam: Camera3D = _inst.get_node("World/CameraRig/YawPivot/MainCamera")
	cam_ctl.apply_zoom(-1000.0)
	var z1: float = cam.size
	cam_ctl.apply_zoom(1000.0)
	var z2: float = cam.size
	_check("zoom_clamp", absf(z1 - 12.0) < 0.001 and absf(z2 - 30.0) < 0.001)

	_check("camera_follows_player",
		_inst.get_node("World/CameraRig").global_position.distance_to(player.global_position) < 1.5,
		"dist=%f" % _inst.get_node("World/CameraRig").global_position.distance_to(player.global_position))

	# 配置防御（R1）：非法速度/重力回退默认后仍按 4.5 m/s 移动
	var cam3: Camera3D = _inst.get_node("World/CameraRig/YawPivot/MainCamera")
	player.configure(cam3, ctl.get_spawn_tile(), ctl.map_size(),
		{"player_speed_m_per_second": INF, "gravity_m_per_second_squared": NAN})
	player.set_test_world_direction(Vector3(1, 0, 0))
	var s3 := player.global_position
	await _steps(60)
	player.clear_test_input()
	var moved_cfg := player.global_position.distance_to(s3)
	_check("player_config_fallback_speed", moved_cfg > 3.5 and moved_cfg < 5.2, "moved=%.2f" % moved_cfg)

	await _test_boundary_fixture()

	var counter: Array = [0]
	player.tile_changed.connect(func(_a, _t): counter[0] += 1)
	player.global_position += Vector3(0.05, 0, 0.05) # 同格内微移
	await _steps(5)
	var c0: int = counter[0]
	var cross_dir := _clear_direction(ctl, player) # 出生点东侧可能是障碍，选清障方向
	player.set_test_world_direction(cross_dir)
	await _steps(45)
	player.clear_test_input()
	var c1: int = counter[0] - c0
	_check("tile_changed_no_repeat_in_tile", c0 == 0, "count=%d" % c0)
	_check("tile_changed_on_cross", c1 >= 1 and c1 <= 6, "count=%d" % c1)

	_check("no_fall_recoveries", player.fall_recoveries == 0, str(player.fall_recoveries))

	var spec_result: Dictionary = WorldSpecLoader.load_from_path("res://data/demo_world/world_spec.json")
	_inst.apply_world(spec_result.data)
	await _steps(30)
	_check("rebuild_single_player",
		_inst.get_node("World/ActorRoot").get_child_count() == 1
		and _inst.get_node("World/BoundaryRoot").get_child_count() == 4)

	root.remove_child(_inst)
	_inst.free()

func _clear_direction(ctl, player: PlayerController) -> Vector3:
	var tile := player.get_current_tile()
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var clear := true
		for k in range(1, 6):
			if not ctl.is_walkable_tile(Vector3i(tile.x + int(dir.x) * k, 0, tile.z + int(dir.z) * k)):
				clear = false
				break
		if clear:
			return dir
	return Vector3(1, 0, 0)

func _test_blocked_by_obstacle(ctl, player: PlayerController) -> void:
	var found := _find_blocked_spot(ctl, player.get_current_tile())
	if found.is_empty():
		_check("blocked_by_obstacle", false, "BFS 范围内找不到阻挡格")
		return
	var stand: Vector3i = found["stand"]
	var blocked: Vector3 = found["blocked_center"]
	player.global_position = GridCoord.tile_to_world(stand) + Vector3(0, 0.05, 0)
	await _steps(5)
	var dirb := (blocked - Vector3(player.global_position.x, 0, player.global_position.z)).normalized()
	var slides := 0
	player.set_test_world_direction(dirb)
	for i in 30:
		await physics_frame
		slides = maxi(slides, player.get_slide_collision_count())
	player.clear_test_input()
	var dist2 := Vector2(player.global_position.x - blocked.x, player.global_position.z - blocked.z).length()
	_check("blocked_by_obstacle", slides > 0 and dist2 > 0.45,
		"slides=%d dist=%.2f blocked=%s" % [slides, dist2, blocked])

# BFS 沿可行走格找第一个带不可行走四邻的格子（stand 站位 + blocked 阻挡格中心）
func _find_blocked_spot(ctl, from_tile: Vector3i) -> Dictionary:
	var visited := {}
	var queue: Array = [Vector2i(from_tile.x, from_tile.z)]
	visited[from_tile.x * 1000 + from_tile.z] = true
	while queue.size() > 0:
		var c: Vector2i = queue.pop_front()
		for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n := Vector2i(c.x + dir.x, c.y + dir.y)
			if not GridCoord.in_bounds(n.x, n.y, 64, 64):
				continue
			if ctl.is_walkable_tile(Vector3i(n.x, 0, n.y)):
				var key := n.x * 1000 + n.y
				if not visited.has(key):
					visited[key] = true
					queue.append(n)
			else:
				return {"stand": Vector3i(c.x, 0, c.y), "blocked_center": Vector3(n.x + 0.5, 0, n.y + 0.5)}
	return {}

func _drive_to_boundary(ctl, player: PlayerController, axis: String, wall_name: String) -> void:
	# 先沿可行走格找到该轴最边缘的格子，用导航走过去，再垂直推向边界墙
	var best := Vector2i(-1, -1)
	for z in 64:
		for x in 64:
			if not ctl.is_walkable_tile(Vector3i(x, 0, z)):
				continue
			if best.x < 0:
				best = Vector2i(x, z)
				continue
			if axis == "x+" and x > best.x:
				best = Vector2i(x, z)
			elif axis == "x-" and x < best.x:
				best = Vector2i(x, z)
			elif axis == "z+" and z > best.y:
				best = Vector2i(x, z)
			elif axis == "z-" and z < best.y:
				best = Vector2i(x, z)
	var path: Array = ctl.find_walk_path(player.get_current_tile(), Vector3i(best.x, 0, best.y))
	if not path.is_empty():
		await _walk_path(player, path)
	var dirs := {"x+": Vector3(1, 0, 0), "x-": Vector3(-1, 0, 0), "z+": Vector3(0, 0, 1), "z-": Vector3(0, 0, -1)}
	player.set_test_world_direction(dirs[axis])
	for i in 60:
		await physics_frame
	player.clear_test_input()
	var p := player.global_position
	_check("boundary_" + wall_name,
		p.x >= -0.05 and p.x <= 64.05 and p.z >= -0.05 and p.z <= 64.05 and player.is_on_floor(),
		"pos=%s floor=%s" % [p, player.is_on_floor()])

func _visit_pois(ctl, player: PlayerController) -> void:
	var pois: Dictionary = ctl.get_poi_tiles()
	var interactor: PlayerInteractor = player.get_node("InteractionArea")
	var expected: Array = []
	for pid in pois:
		expected.append(str(pid))
	expected.sort()
	var selected: Array = []
	var interacted: Array = []
	interactor.interaction_requested.connect(func(id, _n): interacted.append(str(id)))
	var visit_ok := true
	for pid in pois:
		var path: Array = ctl.find_walk_path(player.get_current_tile(), pois[pid])
		if path.is_empty():
			visit_ok = false
			continue
		var reached := await _walk_path(player, path)
		if not reached:
			visit_ok = false
			continue
		await _steps(10)
		if interactor.current_target_id == str(pid):
			selected.append(str(pid))
		interactor.try_interact() # 每个 POI 分别交互一次（R1）
	selected.sort()
	interacted.sort()
	_check("poi_arrival_via_path", visit_ok, "")
	_check("poi_selected_exact_set", selected == expected,
		"expected=%s got=%s" % [str(expected), str(selected)])
	_check("poi_interacted_exact_set", interacted == expected,
		"expected=%s got=%s" % [str(expected), str(interacted)])

# —— WP-04-R1：隔离边界夹具（平地+四面墙+真实滑撞+移墙对照）与安全格防御 ——
func _test_boundary_fixture() -> void:
	var fixture := Node3D.new()
	fixture.position = Vector3(100, 0, 100) # 远离主场景 64x64 地图（共享同一物理世界）
	root.add_child(fixture)
	var wall_root := Node3D.new()
	wall_root.name = "Walls"
	fixture.add_child(wall_root)
	var floor_body := StaticBody3D.new()
	floor_body.name = "FixtureFloor"
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(200, 1, 200)
	fcs.shape = fbox
	floor_body.add_child(fcs)
	floor_body.position = Vector3(10, -0.5, 10) # 顶面 y=0，覆盖 0..20 区域
	fixture.add_child(floor_body)
	MapBoundaryBuilder.build(wall_root, 20, 20)
	var player_scene: PackedScene = load("res://scenes/actors/player.tscn")
	var player: PlayerController = player_scene.instantiate()
	fixture.add_child(player)
	player.configure(null, Vector3i(10, 0, 10), Vector2i(20, 20), {})
	await _steps(10)
	var cases := [
		{"wall": "West", "start": Vector3(1.5, 0.05, 10.0), "dir": Vector3(-1, 0, 0)},
		{"wall": "East", "start": Vector3(18.5, 0.05, 10.0), "dir": Vector3(1, 0, 0)},
		{"wall": "North", "start": Vector3(10.0, 0.05, 1.5), "dir": Vector3(0, 0, -1)},
		{"wall": "South", "start": Vector3(10.0, 0.05, 18.5), "dir": Vector3(0, 0, 1)},
	]
	for c in cases:
		player.position = c["start"]
		player.velocity = Vector3.ZERO
		await _steps(2)
		var hits := {}
		player.set_test_world_direction(c["dir"])
		for i in 90:
			await physics_frame
			for k in player.get_slide_collision_count():
				var col := player.get_slide_collision(k)
				if col.get_collider() != null:
					hits[str(col.get_collider().name)] = true
		player.clear_test_input()
		var contained := false
		if c["dir"].x < 0:
			contained = player.position.x >= 0.30
		elif c["dir"].x > 0:
			contained = player.position.x <= 19.70
		elif c["dir"].z < 0:
			contained = player.position.z >= 0.30
		else:
			contained = player.position.z <= 19.70
		_check("boundary_wall_%s_slide" % str(c["wall"]).to_lower(),
			hits.has(str(c["wall"])) and contained,
			"hits=%s pos=%s" % [str(hits.keys()), player.position])
	# 对照：移除边界后同样推力会越界（证明输入生效且墙真的挡了）
	await process_frame # 离开物理回调再 free 碰撞体
	MapBoundaryBuilder.clear(wall_root)
	await physics_frame
	player.position = Vector3(0.8, 0.05, 10.0)
	player.velocity = Vector3.ZERO
	await _steps(2)
	player.set_test_world_direction(Vector3(-1, 0, 0))
	for i in 90:
		await physics_frame
	player.clear_test_input()
	_check("boundary_control_crosses_without_walls", player.position.x < -0.5,
		"x=%f" % player.position.x)
	# 安全格防御：地图外的落地位置不得成为恢复点
	var safe_before: Vector3i = player.last_safe_tile
	player.position = Vector3(-3.0, 0.05, 5.0)
	await _steps(10)
	_check("safe_tile_stays_in_map",
		player.last_safe_tile.x >= 0 and player.last_safe_tile.x < 20
		and player.last_safe_tile.z >= 0 and player.last_safe_tile.z < 20,
		"before=%s after=%s" % [str(safe_before), str(player.last_safe_tile)])
	root.remove_child(fixture)
	fixture.free()

func _walk_path(player: PlayerController, path: Array) -> bool:
	var guard := 0
	for cell in path:
		var target := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
		var local := 0
		while local < 120:
			var to := target - player.global_position
			to.y = 0.0
			if to.length() < 0.18:
				break
			player.set_test_world_direction(to.normalized())
			await physics_frame
			local += 1
			guard += 1
			if guard > 20000:
				player.clear_test_input()
				return false
	player.clear_test_input()
	return true
