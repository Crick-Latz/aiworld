class_name MapBoundaryBuilder
extends RefCounted
## 地图四面边界（WP-04）：在地图片区四周创建 4 个不可见 StaticBody3D。
## layer = world_solid(bit1)；厚度 t=0.3、高 h=3.0；
## West/East 中心 x = -t/2 / width+t/2，size = (t, h, depth+2t)；
## North/South 中心 z = -t/2 / depth+t/2，size = (width+2t, h, t)；中心 y = h/2。
## 内边缘严格位于 x=0/x=width/z=0/z=depth。重建前先清旧节点；禁止用每帧 clamp 冒充。

const WALL_NAMES := ["West", "East", "North", "South"]

static func build(root: Node3D, width: int, depth: int) -> void:
	clear(root)
	var t := 0.3
	var h := 3.0
	_add_wall(root, "West", Vector3(-t * 0.5, h * 0.5, depth * 0.5), Vector3(t, h, depth + 2.0 * t))
	_add_wall(root, "East", Vector3(width + t * 0.5, h * 0.5, depth * 0.5), Vector3(t, h, depth + 2.0 * t))
	_add_wall(root, "North", Vector3(width * 0.5, h * 0.5, -t * 0.5), Vector3(width + 2.0 * t, h, t))
	_add_wall(root, "South", Vector3(width * 0.5, h * 0.5, depth + t * 0.5), Vector3(width + 2.0 * t, h, t))

static func clear(root: Node3D) -> void:
	for c in root.get_children():
		root.remove_child(c)
		c.free()

static func _add_wall(root: Node3D, wall_name: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D" # 离树节点会被自动改成 @Name@N，显式命名保证可寻址
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	body.position = center # BoundaryRoot 位于原点，局部即全局；离树亦可安全构建
