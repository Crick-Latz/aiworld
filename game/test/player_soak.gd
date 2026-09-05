extends SceneTree
## WP-04 30 分钟模拟稳定性（只在收尾门禁执行一次，不在单元测试中重复）。
## 固定 demo world/seed；真实 PlayerController + CharacterBody3D 沿 MapNavigator 路径
## 循环访问三个 POI；累计 >=108000 个 <=1/60s 物理步（>=1800 秒模拟），POI 总到达 >=10
## 且每个至少 1 次；每 60 步做有限数/范围/唯一玩家/边界完整性检查。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 600 --path game --script res://test/player_soak.gd

const TARGET_STEPS := 108000
const MIN_VISITS := 10
const VISIT_COOLDOWN_STEPS := 300

var _started := false
var _finished := false

func _initialize() -> void:
	print("SOAK harness: deferred to first frame")

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run() # 异步：挂起后引擎继续跑帧，直到 quit()
	return _finished

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	# 任务书允许的 headless 离线加速：以 --fixed-fps 600 启动（本文件头注释的命令）。
	# 每个引擎帧推进固定 1/600s 模拟时间，物理仍按 60Hz 固定 1/60s 完整步进，
	# 不用大 delta 跳过碰撞；实测约 98000 步/秒。
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		print("PLAYER_SOAK FAILED no_scene")
		quit(1)
		return
	var inst = ps.instantiate()
	root.add_child(inst)
	for i in 30:
		await physics_frame
	var player: PlayerController = inst.get_node_or_null("World/ActorRoot/Player")
	if player == null:
		print("PLAYER_SOAK FAILED no_player")
		quit(1)
		return
	var ctl = inst.get_node("World/MapController")
	var pois: Dictionary = ctl.get_poi_tiles()
	var pid_list: Array = pois.keys()
	var visits := 0
	var per_poi := {}
	for p in pid_list:
		per_poi[p] = 0
	var last_visit_step := {}
	var steps := 0
	var failures := 0
	var idx := 0
	var budget := 400000
	var min_poi_visits := 0

	while steps < TARGET_STEPS or visits < MIN_VISITS or min_poi_visits < 1:
		if steps >= budget:
			failures += 1
			break
		var pid = pid_list[idx % pid_list.size()]
		idx += 1
		var target_tile: Vector3i = pois[pid]
		var path: Array = ctl.find_walk_path(player.get_current_tile(), target_tile)
		if path.is_empty():
			failures += 1
			await physics_frame
			steps += 1
			continue
		var guard := 0
		for cell in path:
			var target := Vector3(float(cell.x) + 0.5, 0.0, float(cell.y) + 0.5)
			var local := 0
			while local < 150:
				var to := target - player.global_position
				to.y = 0.0
				if to.length() < 0.18:
					break
				player.set_test_world_direction(to.normalized())
				await physics_frame
				steps += 1
				local += 1
				guard += 1
				if steps % 60 == 0:
					var err := _sanity(inst, player)
					if err != "":
						failures += 1
						print("SOAK SANITY: %s" % err)
				if steps >= budget:
					break
			if steps >= budget:
				break
		player.clear_test_input()
		var pw: Vector3 = GridCoord.tile_to_world(target_tile)
		var dist := Vector2(player.global_position.x - pw.x, player.global_position.z - pw.z).length()
		if dist < 1.7 and steps - int(last_visit_step.get(pid, -VISIT_COOLDOWN_STEPS)) > VISIT_COOLDOWN_STEPS:
			visits += 1
			per_poi[pid] = int(per_poi[pid]) + 1
			last_visit_step[pid] = steps
		min_poi_visits = per_poi.values().min() if per_poi.size() > 0 else 0

	var wall := Time.get_ticks_msec() - t0
	var sim_seconds := steps / 60
	print("PLAYER_SOAK simulated_seconds=%d physics_steps=%d poi_visits=%d falls=%d failures=%d wall_ms=%d" % [
		sim_seconds, steps, visits, player.fall_recoveries, failures, wall])
	var ok := failures == 0 and player.fall_recoveries == 0 and visits >= MIN_VISITS \
		and min_poi_visits >= 1 and steps >= TARGET_STEPS
	root.remove_child(inst)
	inst.free()
	_finished = true
	quit(0 if ok else 1)

func _sanity(inst, player: PlayerController) -> String:
	var p := player.global_position
	if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
		return "NaN position %s" % p
	if p.x < -1.0 or p.x > 65.0 or p.z < -1.0 or p.z > 65.0:
		return "out of map %s" % p
	if p.y < -1.0:
		return "fell %s" % p
	if inst.get_node("World/ActorRoot").get_child_count() != 1:
		return "player count != 1"
	if inst.get_node("World/BoundaryRoot").get_child_count() != 4:
		return "boundary count != 4"
	return ""
