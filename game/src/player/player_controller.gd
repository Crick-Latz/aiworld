class_name PlayerController
extends CharacterBody3D
## 玩家控制器（WP-04）。
## 物理：相机相对 WASD/方向键输入 -> 世界方向（y 强制 0、长度>1 归一化）；
## velocity 为 m/s，move_and_slide() 前严禁再乘 delta；空中只对 y 施加 -gravity*delta；
## 落地清残留负 y 速度；输入为零水平速度归零（无惯性）。
## 逻辑格用 GridCoord 换算，仅 tile 变化时 emit tile_changed 一次；
## y<-1 或坐标非有限 -> 恢复到 last_safe_tile（正常应为 0 次）。
## set_test_world_direction/clear_test_input 仅供测试与截图自动驾驶，默认关闭。

signal tile_changed(actor_id: String, tile: Vector3i)
signal fell_and_recovered(from_position: Vector3, to_tile: Vector3i)

const ACTOR_ID := "player"

var move_speed := 4.5
var gravity := 20.0
var map_size := Vector2i.ZERO
var spawn_tile := Vector3i.ZERO
var current_tile := Vector3i.ZERO
var last_reported_tile := Vector3i.ZERO
var last_safe_tile := Vector3i.ZERO
var input_enabled := true
var fall_recoveries := 0

var _camera: Camera3D = null
var _test_world_dir := Vector3.ZERO
var _test_input_active := false

func _ready() -> void:
	var sprite: AnimatedSprite3D = $VisualRoot/AnimatedSprite3D
	if sprite.sprite_frames == null:
		var frames := SpriteFrames.new()
		frames.add_animation("idle")
		frames.add_frame("idle", preload("res://assets/prototype/player_placeholder.svg"))
		sprite.sprite_frames = frames
		sprite.animation = "idle"
		sprite.frame = 0
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var ring: MeshInstance3D = $VisualRoot/SelectionRing
	if ring.mesh == null:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.36
		torus.outer_radius = 0.44
		ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color8(80, 200, 230)
		mat.emission_enabled = true
		mat.emission = Color8(80, 200, 230)
		mat.emission_energy_multiplier = 0.5
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = mat

func configure(camera: Camera3D, spawn: Vector3i, size: Vector2i, actor_config: Dictionary) -> Dictionary:
	_camera = camera
	spawn_tile = spawn
	map_size = size
	# 配置防御（R1）：非有限或非正数回退任务单默认值 4.5 / 20.0
	var spd := float(actor_config.get("player_speed_m_per_second", 4.5))
	var grav := float(actor_config.get("gravity_m_per_second_squared", 20.0))
	move_speed = spd if (spd > 0.0 and is_finite(spd)) else 4.5
	gravity = grav if (grav > 0.0 and is_finite(grav)) else 20.0
	global_position = GridCoord.tile_to_world(spawn) + Vector3(0, 0.05, 0)
	current_tile = spawn
	last_reported_tile = spawn
	last_safe_tile = spawn
	velocity = Vector3.ZERO
	fall_recoveries = 0
	return {"ok": true}

func get_current_tile() -> Vector3i:
	return current_tile

func get_debug_state() -> Dictionary:
	return {
		"actor_id": ACTOR_ID,
		"tile": current_tile,
		"world": global_position,
		"on_floor": is_on_floor(),
		"speed": Vector2(velocity.x, velocity.z).length(),
		"fall_recoveries": fall_recoveries,
	}

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled

# —— 测试/自动驾驶专用：直接注入世界方向，默认关闭；正式输入仍来自 InputMap ——
func set_test_world_direction(dir: Vector3) -> void:
	_test_world_dir = Vector3(dir.x, 0.0, dir.z)
	_test_input_active = true

func clear_test_input() -> void:
	_test_input_active = false
	_test_world_dir = Vector3.ZERO

func _physics_process(delta: float) -> void:
	var dir := _compute_world_direction()
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0 # 落地不持续积累负速度
	else:
		velocity.y -= gravity * delta
	velocity.x = dir.x * move_speed
	velocity.z = dir.z * move_speed
	move_and_slide()
	_update_tile_tracking()
	_check_safety()

func _compute_world_direction() -> Vector3:
	if _test_input_active:
		var d := Vector3(_test_world_dir.x, 0.0, _test_world_dir.z)
		return d.normalized() if d.length() > 1.0 else d
	if not input_enabled:
		return Vector3.ZERO
	if _camera == null or not is_instance_valid(_camera):
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var basis := _camera.global_transform.basis
	var right := Vector3(basis.x.x, 0.0, basis.x.z)
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	if right.length_squared() > 0.000001:
		right = right.normalized()
	if forward.length_squared() > 0.000001:
		forward = forward.normalized()
	# get_vector 的上方向 y 为负值：屏幕前 = forward * (-input.y)
	var world_dir := right * input.x + forward * (-input.y)
	world_dir.y = 0.0
	if world_dir.length() > 1.0:
		world_dir = world_dir.normalized()
	return world_dir

func _update_tile_tracking() -> void:
	var tile := GridCoord.world_to_tile(global_position)
	current_tile = tile
	if tile != last_reported_tile:
		# 安全格只能在地图范围内更新（R1）：越界/负坐标不得成为恢复点
		if is_on_floor() and tile.y == 0 \
				and tile.x >= 0 and tile.z >= 0 \
				and tile.x < map_size.x and tile.z < map_size.y:
			last_safe_tile = tile
		last_reported_tile = tile
		tile_changed.emit(ACTOR_ID, tile)

func _check_safety() -> void:
	var p := global_position
	var bad := p.y < -1.0 or is_nan(p.x) or is_inf(p.x) or is_nan(p.y) or is_inf(p.y) or is_nan(p.z) or is_inf(p.z)
	if bad:
		fall_recoveries += 1
		fell_and_recovered.emit(p, last_safe_tile)
		global_position = GridCoord.tile_to_world(last_safe_tile) + Vector3(0, 0.05, 0)
		velocity = Vector3.ZERO
		current_tile = last_safe_tile
		last_reported_tile = last_safe_tile
