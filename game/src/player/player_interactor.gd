class_name PlayerInteractor
extends Area3D
## 玩家交互器（WP-04）：挂在 Player.InteractionArea 上。
## 每 physics tick 从 overlaps 取候选（过滤无效/不可交互/超 1.75m 由选择器完成），
## 纯函数 InteractionTargetSelector 以 (distance_mm, view_angle_mdeg, target_id) 选择；
## 目标变化 emit target_changed；E/空格在有目标且未禁用时 emit interaction_requested 一次。

signal target_changed(target_id: String, display_name: String)
signal interaction_requested(target_id: String, display_name: String)

const INTERACT_RADIUS_MM := 1750

var current_target_id := ""
var current_display_name := ""
var player: CharacterBody3D = null
var camera: Camera3D = null
var input_enabled := true

func _physics_process(_delta: float) -> void:
	var next_id := ""
	var next_name := ""
	if player != null and is_instance_valid(player) and input_enabled:
		var candidates: Array = []
		for a in get_overlapping_areas():
			if not is_instance_valid(a):
				continue # 已释放节点防御
			if not bool(a.get_meta("interactable", false)):
				continue
			candidates.append({
				"target_id": str(a.get_meta("target_id", "")),
				"display_name": str(a.get_meta("display_name", "")),
				"position": a.global_position,
			})
		if candidates.size() > 0 and camera != null and is_instance_valid(camera):
			var basis := camera.global_transform.basis
			var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
			var sel: Dictionary = InteractionTargetSelector.select(candidates, player.global_position, forward)
			if not sel.is_empty():
				next_id = str(sel["target_id"])
				next_name = str(sel["display_name"])
	if next_id != current_target_id:
		current_target_id = next_id
		current_display_name = next_name
		target_changed.emit(current_target_id, current_display_name)

func try_interact() -> void:
	if input_enabled and not current_target_id.is_empty():
		interaction_requested.emit(current_target_id, current_display_name)

func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		current_target_id = ""
		current_display_name = ""
		target_changed.emit("", "")
