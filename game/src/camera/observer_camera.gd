class_name ObserverCamera
extends Node3D
## 观察相机（OBS-01，M16）：右键拖动平移（y=0 地面平面求交）、滚轮缩放、
## Q/R 90° 旋转（连续角度，跨零点不绕远路——同 WP-04-R2 修复模式）。
## 不跟随角色；不消耗模拟 RNG；模拟暂停时仍可操作（不依赖整树暂停）。

var camera: Camera3D = null
var offset := Vector3(28, 28, 28)
var zoom_min := 16.0
var zoom_max := 90.0
var zoom_step := 6.0
var rotation_tween_seconds := 0.25
var yaw_deg := 0.0

var _tween: Tween = null
var _panning := false
var _grab_point := Vector3.ZERO

func _ready() -> void:
	camera = get_node_or_null("YawPivot/MainCamera")
	if camera == null:
		return
	camera.position = offset
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 40.0
	camera.near = 0.1
	camera.far = 400.0
	camera.current = true
	camera.look_at(global_position)

func center_on(world_pos: Vector3) -> void:
	global_position = Vector3(world_pos.x, 0.0, world_pos.z)
	camera.look_at(global_position)

func _input(event: InputEvent) -> void:
	if camera == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed
			if _panning:
				_grab_point = _ground_point(mb.position)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = clampf(camera.size - zoom_step, zoom_min, zoom_max)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = clampf(camera.size + zoom_step, zoom_min, zoom_max)
	elif event is InputEventMouseMotion and _panning:
		var cur := _ground_point((event as InputEventMouseMotion).position)
		global_position += _grab_point - cur
		camera.look_at(global_position)
	elif event.is_action_pressed("camera_rotate_left"):
		rotate_yaw(1)
	elif event.is_action_pressed("camera_rotate_right"):
		rotate_yaw(-1)

# 屏幕坐标 -> y=0 地面交点（装配层用于人物拾取）；无交点返回 rig 自身位置
func ground_point(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return global_position
	var t := -origin.y / dir.y
	if t < 0.0:
		return global_position
	return origin + dir * t

func _ground_point(screen: Vector2) -> Vector3:
	return ground_point(screen)

func rotate_yaw(direction: int) -> void:
	if _tween != null and _tween.is_valid() and _tween.is_running():
		return
	var pivot := $YawPivot
	var target_y: float = pivot.rotation.y + direction * PI * 0.5
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(pivot, "rotation:y", target_y, rotation_tween_seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	yaw_deg = fmod(rad_to_deg(target_y) + 360.0, 360.0)
