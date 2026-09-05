class_name InteractionTargetSelector
extends RefCounted
## 交互目标纯函数选择器（WP-04）。
## 排序键精确为 (distance_mm 升序, view_angle_mdeg 升序, target_id 字典序升序)：
## 距离/夹角先量化为整数，避免浮点抖动；距离只用脚点 XZ；角度用相机前向与
## 玩家->目标向量的点积（clamp、acos、deg、*1000 四舍五入）；同点角度记 0。

const INTERACT_RADIUS_MM := 1750

static func select(candidates: Array, player_pos: Vector3, camera_forward_xz: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var best_key: Array = []
	for c in candidates:
		var p: Vector3 = c.get("position", Vector3.ZERO)
		var dx := p.x - player_pos.x
		var dz := p.z - player_pos.z
		var dist_mm := int(round(sqrt(dx * dx + dz * dz) * 1000.0))
		if dist_mm > INTERACT_RADIUS_MM:
			continue
		var angle_mdeg := 0
		if dist_mm > 0:
			var to_t := Vector3(dx, 0.0, dz)
			var f := Vector3(camera_forward_xz.x, 0.0, camera_forward_xz.z)
			if f.length_squared() > 0.000001:
				to_t = to_t.normalized()
				f = f.normalized()
				var dotv := clampf(to_t.dot(f), -1.0, 1.0)
				angle_mdeg = int(round(rad_to_deg(acos(dotv)) * 1000.0))
		var key: Array = [dist_mm, angle_mdeg, str(c.get("target_id", ""))]
		if best.is_empty() or _key_less(key, best_key):
			best = {
				"target_id": c.get("target_id", ""),
				"display_name": c.get("display_name", ""),
				"position": p,
			}
			best_key = key
	return best

static func _key_less(a: Array, b: Array) -> bool:
	for i in 3:
		if a[i] < b[i]:
			return true
		if a[i] > b[i]:
			return false
	return false
