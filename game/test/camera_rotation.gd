extends SceneTree
## WP-04-R2 相机跨零点旋转回归（真实节点 + 真实 Tween，非源码字符串检查）。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --headless --fixed-fps 60 --path game --script res://test/camera_rotation.gd
## 每帧累加 wrapf(cur-prev, -PI, PI)：把等价角归一化造成的数值跳变排除；
## 断言：每段有符号累计 = ±90°（容差 1°）、每帧显著增量方向一致、终点等价朝向正确。

var passed := 0
var failed := 0
var _started := false
var _finished := false
var _inst: Node = null
var _pivot: Node3D = null
var _ctl: Node = null

const TOL_RAD := 0.017453 # 1°
const SEGMENT_FRAMES := 30 # 60fps 下 0.5s > 0.25s Tween

func _initialize() -> void:
	print("WP04-R2 camera rotation harness: deferred to first frame")

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
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

func _run_all_tests() -> void:
	var ps: PackedScene = load("res://scenes/main/main.tscn")
	if ps == null:
		_check("main_loadable", false, "场景不可加载")
		return
	_inst = ps.instantiate()
	root.add_child(_inst)
	for i in 10:
		await process_frame
	_ctl = _inst.get_node("World/CameraRig")
	_pivot = _inst.get_node("World/CameraRig/YawPivot")
	if absf(_pivot.rotation.y) > 0.001: # 期望初始 0°
		_pivot.rotation.y = 0.0

	# —— 矩阵 1：起点 0°，一次右转（真实注册输入 camera_rotate_right）——
	await _reset_to_zero()
	var seg := await _segment_via_input("camera_rotate_right")
	_check("cross_zero_right_signed_minus_90",
		seg.ok and seg.total < 0.0 and absf(absf(seg.total) - deg_to_rad(90.0)) <= TOL_RAD,
		"total_deg=%.2f consistent=%s" % [rad_to_deg(seg.total), seg.consistent])
	_check("cross_zero_right_end_equiv_270",
		_equiv_yaw(_pivot.rotation.y, 270.0), "yaw=%.2f" % rad_to_deg(_pivot.rotation.y))

	# —— 矩阵 2：三左至 270°，再一次左转跨零点 ——
	await _reset_to_zero()
	for i in 3:
		seg = await _segment_via_call(1)
	_check("preset_three_lefts", seg.ok and absf(seg.total - deg_to_rad(90.0)) <= TOL_RAD,
		"total_deg=%.2f consistent=%s" % [rad_to_deg(seg.total), seg.consistent])
	seg = await _segment_via_input("camera_rotate_left")
	_check("cross_zero_left_signed_plus_90",
		seg.ok and seg.total > 0.0 and absf(absf(seg.total) - deg_to_rad(90.0)) <= TOL_RAD,
		"total_deg=%.2f consistent=%s" % [rad_to_deg(seg.total), seg.consistent])
	_check("cross_zero_left_end_equiv_0",
		_equiv_yaw(_pivot.rotation.y, 0.0), "yaw=%.2f" % rad_to_deg(_pivot.rotation.y))

	# —— 矩阵 3：从 0° 连续四次左转 / 四次右转 ——
	await _reset_to_zero()
	var all_ok := true
	for i in 4:
		seg = await _segment_via_call(1)
		if not (seg.ok and absf(seg.total - deg_to_rad(90.0)) <= TOL_RAD):
			all_ok = false
	_check("four_lefts_each_plus_90_return", all_ok and _equiv_yaw(_pivot.rotation.y, 0.0),
		"end_yaw=%.2f" % rad_to_deg(_pivot.rotation.y))
	await _reset_to_zero()
	all_ok = true
	for i in 4:
		seg = await _segment_via_call(-1)
		if not (seg.ok and absf(seg.total + deg_to_rad(90.0)) <= TOL_RAD):
			all_ok = false
	_check("four_rights_each_minus_90_return", all_ok and _equiv_yaw(_pivot.rotation.y, 0.0),
		"end_yaw=%.2f" % rad_to_deg(_pivot.rotation.y))

	# —— 矩阵 4：左右交替 ——
	await _reset_to_zero()
	all_ok = true
	var dirs := [1, -1, 1, -1]
	for d in dirs:
		seg = await _segment_via_call(d)
		var want: float = deg_to_rad(90.0) * int(d)
		if not (seg.ok and absf(seg.total - want) <= TOL_RAD):
			all_ok = false
	_check("alternating_no_drift", all_ok and _equiv_yaw(_pivot.rotation.y, 0.0),
		"end_yaw=%.2f" % rad_to_deg(_pivot.rotation.y))

	# —— 矩阵 5：Tween 期间再按一次，只完成一次 90° ——
	await _reset_to_zero()
	var early := await _segment_with_mid_press("camera_rotate_left", 5)
	_check("mid_tween_press_ignored",
		early.ok and absf(early.total - deg_to_rad(90.0)) <= TOL_RAD,
		"total_deg=%.2f" % rad_to_deg(early.total))

	# —— 矩阵 6：旋转途中暂停并恢复 ——
	await _reset_to_zero()
	var paused_seg := await _segment_with_pause(1)
	_check("pause_freezes_and_resume_completes", paused_seg,
		"详见上方 PAUSE_SEGMENT 输出")

	root.remove_child(_inst)
	_inst.free()

func _reset_to_zero() -> void:
	# 直接重置朝向；等待足够帧确保无 Tween 残留
	_ctl.kill_tween()
	_pivot.rotation.y = 0.0
	for i in 3:
		await process_frame

# 采集一段旋转：每帧累加 wrap 后增量，检查显著增量方向一致
func _segment_via_call(direction: int) -> Dictionary:
	_ctl.rotate_yaw(direction)
	return await _sample_segment(direction)

func _segment_via_input(action: String) -> Dictionary:
	var direction := 1 if action == "camera_rotate_left" else -1
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	return await _sample_segment(direction)

func _segment_with_mid_press(action: String, press_at_frame: int) -> Dictionary:
	var direction := 1 if action == "camera_rotate_left" else -1
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	return await _sample_segment(direction, press_at_frame, ev)

func _sample_segment(direction: int, mid_press_frame: int = -1, mid_ev: InputEventAction = null) -> Dictionary:
	var prev: float = _pivot.rotation.y
	var total := 0.0
	var consistent := true
	var first_sig := 0.0
	for i in SEGMENT_FRAMES:
		if mid_press_frame == i and mid_ev != null:
			Input.parse_input_event(mid_ev) # Tween 运行中再按一次
		await process_frame
		var cur: float = _pivot.rotation.y
		var d := wrapf(cur - prev, -PI, PI)
		if absf(d) > 0.0005:
			if first_sig == 0.0:
				first_sig = signf(d)
			elif signf(d) != first_sig:
				consistent = false
		total += d
		prev = cur
	var ok_seg := consistent and absf(absf(total) - deg_to_rad(90.0)) <= TOL_RAD
	print("SEGMENT dir=%d total_deg=%.2f consistent=%s end_yaw=%.2f" % [
		direction, rad_to_deg(total), consistent, rad_to_deg(_pivot.rotation.y)])
	return {"ok": ok_seg, "total": total, "consistent": consistent}

# 暂停恢复段：前 4 帧正常转，随后暂停 12 帧采样角度不变，恢复后 30 帧完成
func _segment_with_pause(direction: int) -> bool:
	_ctl.rotate_yaw(direction)
	var prev: float = _pivot.rotation.y
	var before_pause := 0.0
	for i in 4:
		await process_frame
		var cur: float = _pivot.rotation.y
		before_pause += wrapf(cur - prev, -PI, PI)
		prev = cur
	paused = true
	var frozen := true
	for i in 12:
		await process_frame
		var cur: float = _pivot.rotation.y
		if absf(wrapf(cur - prev, -PI, PI)) > 0.0005:
			frozen = false
		prev = cur
	paused = false
	var after := 0.0
	var consistent := true
	var first_sig := 0.0
	for i in 30:
		await process_frame
		var cur: float = _pivot.rotation.y
		var d := wrapf(cur - prev, -PI, PI)
		if absf(d) > 0.0005:
			if first_sig == 0.0:
				first_sig = signf(d)
			elif signf(d) != first_sig:
				consistent = false
		after += d
		prev = cur
	var total := before_pause + after
	var ok_seg := frozen and consistent and absf(total - deg_to_rad(90.0) * direction) <= TOL_RAD
	print("PAUSE_SEGMENT before_deg=%.2f frozen=%s after_deg=%.2f total_deg=%.2f" % [
		rad_to_deg(before_pause), frozen, rad_to_deg(after), rad_to_deg(total)])
	return ok_seg

func _equiv_yaw(actual_rad: float, want_deg: float) -> bool:
	var a := fmod(rad_to_deg(actual_rad) - want_deg, 360.0)
	if a > 180.0:
		a -= 360.0
	if a < -180.0:
		a += 360.0
	return absf(a) <= 1.0
