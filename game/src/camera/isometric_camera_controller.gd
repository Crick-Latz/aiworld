class_name IsometricCameraController
extends Node3D
## 正交等距相机控制器（WP-04）。挂载在 CameraRig 上，Rig 即跟随点；
## MainCamera 保持 local offset(12,12,12) 并 look_at 跟随点（固定俯角）。
## 跟随：指数平滑（时间常数 follow_smoothing_seconds，帧率无关）；
## Q/R：绕世界 Y 轴精确 90°、0.25 秒 Tween，未完成时忽略新旋转；
## 滚轮：每档 size±zoom_step，严格 clamp 12..30；重建时 kill_tween 并解绑目标。

var camera: Camera3D = null
var offset := Vector3(12, 12, 12)
var orthogonal_size := 20.0
var near := 0.1
var far := 200.0
var follow_smoothing := 0.18
var zoom_min := 12.0
var zoom_max := 30.0
var zoom_step := 2.0
var rotation_step_deg := 90.0
var rotation_tween_seconds := 0.25
var yaw_deg := 0.0
var enabled := true

var _target: Node3D = null
var _tween: Tween = null

func _ready() -> void:
	camera = get_node_or_null("YawPivot/MainCamera")
	if camera == null:
		return # 允许独立实例化（配置防御单元测试）
	camera.position = offset
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = near
	camera.far = far
	camera.size = orthogonal_size
	camera.current = true
	camera.look_at(global_position)

func configure(cfg: Dictionary) -> void:
	if typeof(cfg) != TYPE_DICTIONARY:
		return
	# 配置防御（R1）：非法值安静回退任务单默认值，不产生 ERROR
	var off = cfg.get("offset", offset)
	if typeof(off) == TYPE_DICTIONARY:
		var ox := float(off.get("x", 12.0))
		var oy := float(off.get("y", 12.0))
		var oz := float(off.get("z", 12.0))
		offset = Vector3(
			ox if is_finite(ox) else 12.0,
			oy if is_finite(oy) else 12.0,
			oz if is_finite(oz) else 12.0)
	elif typeof(off) == TYPE_VECTOR3 and is_finite(off.x) and is_finite(off.y) and is_finite(off.z):
		offset = off
	else:
		offset = Vector3(12, 12, 12)
	orthogonal_size = clampf(float(cfg.get("orthogonal_size", 20.0)), 4.0, 100.0)
	var near_v := float(cfg.get("near", 0.1))
	near = near_v if near_v > 0.0 and is_finite(near_v) else 0.1
	var far_v := float(cfg.get("far", 200.0))
	far = far_v if (is_finite(far_v) and far_v > near) else (200.0 if 200.0 > near else near + 100.0)
	var fs := float(cfg.get("follow_smoothing_seconds", 0.18))
	follow_smoothing = clampf(fs if fs > 0.0 and is_finite(fs) else 0.18, 0.0, 5.0)
	var zmin := float(cfg.get("zoom_min", 12.0))
	zoom_min = zmin if zmin > 0.0 and is_finite(zmin) else 12.0
	var zmax := float(cfg.get("zoom_max", 30.0))
	zoom_max = zmax if is_finite(zmax) else 30.0
	if zoom_max < zoom_min:
		zoom_max = 30.0 if 30.0 >= zoom_min else zoom_min
	var zstep := float(cfg.get("zoom_step", 2.0))
	zoom_step = zstep if zstep > 0.0 and is_finite(zstep) else 2.0
	rotation_step_deg = float(cfg.get("rotation_step_degrees", 90.0)) if float(cfg.get("rotation_step_degrees", 90.0)) > 0.0 else 90.0
	var rts := float(cfg.get("rotation_tween_seconds", 0.25))
	rotation_tween_seconds = clampf(rts if rts > 0.0 and is_finite(rts) else 0.25, 0.0, 5.0)
	if camera != null:
		camera.position = offset
		camera.near = near
		camera.far = far
		camera.size = clampf(orthogonal_size, zoom_min, zoom_max)
		camera.look_at(global_position)

func bind_target(node: Node3D, snap: bool) -> void:
	_target = node
	if snap and _target != null:
		global_position = _target.global_position
		camera.look_at(global_position)

func clear_target() -> void:
	_target = null

func kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null

func _process(delta: float) -> void:
	if not enabled or _target == null or not is_instance_valid(_target):
		return
	# 帧率无关的指数平滑（时间常数 follow_smoothing 秒）
	var alpha := 1.0 - exp(-delta / maxf(follow_smoothing, 0.0001))
	global_position = global_position.lerp(_target.global_position, alpha)

func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("camera_rotate_left"):
		rotate_yaw(1)
	elif event.is_action_pressed("camera_rotate_right"):
		rotate_yaw(-1)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			apply_zoom(-zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			apply_zoom(zoom_step)

func rotate_yaw(direction: int) -> void:
	if _tween != null and _tween.is_valid() and _tween.is_running():
		return # Tween 未完成时忽略重复旋转，不累计失控
	# R2：插值目标建立在 YawPivot 当前实际角度之上（连续角度，跨 0/360 不绕远路）。
	# 显示口径 yaw_deg 单独归一化到 0..360，只作诊断，不参与插值。
	var pivot := $YawPivot
	var target_y: float = pivot.rotation.y + direction * deg_to_rad(rotation_step_deg)
	kill_tween()
	_tween = create_tween()
	_tween.tween_property(pivot, "rotation:y", target_y, rotation_tween_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	yaw_deg = fmod(rad_to_deg(target_y) + 360.0, 360.0)

func apply_zoom(step: float) -> void:
	if camera != null:
		camera.size = clampf(camera.size + step, zoom_min, zoom_max)

func get_debug_state() -> Dictionary:
	return {
		"yaw": int(round(fmod(yaw_deg + 360.0, 360.0))) % 360,
		"size": camera.size if camera != null else 0.0,
	}