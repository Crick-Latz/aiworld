class_name ObserverCamera2D
extends Camera2D
## UI-R1：2D 像素观察相机（presentation）。
## WASD/方向键平移、滚轮缩放（步进、夹紧）、右键/中键拖拽平移；无旋转。
## 只动相机，不读任何模拟状态。

const PAN_SPEED := 220.0
const MIN_ZOOM := 0.75
const MAX_ZOOM := 4.0
const ZOOM_STEP := 1.25

var _dragging := false

func _ready() -> void:
	enabled = false # 由 observer_main 在 2D 模式显式启用

func _process(delta: float) -> void:
	if not enabled:
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		dir.x += 1.0
	if Input.is_action_pressed("move_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("move_down"):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		global_position += dir.normalized() * PAN_SPEED * delta / zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_apply_zoom(ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_apply_zoom(1.0 / ZOOM_STEP)
		elif (mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE):
			_dragging = mb.pressed
			if _dragging:
				mb.button_mask |= mb.button_index # 保持按住状态用于拖拽
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		global_position -= mm.relative / zoom.x

func _apply_zoom(factor: float) -> void:
	zoom = (zoom * factor).clamp(Vector2.ONE * MIN_ZOOM, Vector2.ONE * MAX_ZOOM)

func center_on(world_pos: Vector2) -> void:
	global_position = world_pos
