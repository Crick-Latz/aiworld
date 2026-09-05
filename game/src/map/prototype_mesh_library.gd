class_name PrototypeMeshLibrary
extends RefCounted
## 代码构建的 MeshLibrary 原型块（WP-03 / R1）。
## R1：颜色一律用 Color8 按 sRGB 定义（避免把 sRGB 数值当线性 Color 出现荧光色）；
## shapes 显式传 [Shape3D, Transform3D] 配对，不依赖引擎自动补 Identity；
## ground 顶面对齐逻辑 y=0（格中心在 L*0.5+0.25，箱高 0.1 => dy=-0.30）；
## rock/tree 上移半高使底部落在地面（dy=+0.15 / +0.45）；water 顶面略低于地面。
## item 名称稳定，MapProjector 一律按名称解析 item id。

const ITEM_NAMES := [
	"ground_grass", "ground_stone", "ground_road", "ground_sand",
	"water_blocked", "rock_small", "tree_lowpoly",
]
# GridMap cell_size=(1,0.5,1)，cell 中心位于 (L+0.5)*0.5 = L*0.5+0.25
const GROUND_DY := -0.30 # 顶面 = L*0.5+0.25-0.30+0.05 = L*0.5
const WATER_DY := -0.30 # 顶面 = L*0.5-0.02（低于地面顶面 2cm）
const ROCK_DY := 0.15 # 底面 = L*0.5+0.25+0.15-0.40 = L*0.5
const TREE_DY := 0.45 # 底面 = L*0.5+0.25+0.45-0.70 = L*0.5

static func build() -> MeshLibrary:
	var lib := MeshLibrary.new()
	_add_ground(lib, 0, "ground_grass", Color8(96, 148, 76))
	_add_ground(lib, 1, "ground_stone", Color8(140, 140, 148))
	_add_ground(lib, 2, "ground_road", Color8(72, 72, 80))
	_add_ground(lib, 3, "ground_sand", Color8(199, 179, 128))
	_add_water(lib, 4)
	_add_rock_svg(lib, 5)
	_add_tree_svg(lib, 6)
	return lib

# 阶段 A：SVG 贴图的 rock/tree（QuadMesh + SVG 纹理 + billboard 效果）
static func _add_rock_svg(lib: MeshLibrary, id: int) -> void:
	lib.create_item(id)
	lib.set_item_name(id, "rock_small")
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.9, 0.9)
	var tex := load("res://assets/prototype/rock.svg")
	if tex != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
	lib.set_item_mesh(id, mesh)
	lib.set_item_mesh_transform(id, _offset(ROCK_DY))
	var shape := CylinderShape3D.new()
	shape.radius = 0.35
	shape.height = 0.6
	lib.set_item_shapes(id, [shape, _offset(ROCK_DY)])

static func _add_tree_svg(lib: MeshLibrary, id: int) -> void:
	lib.create_item(id)
	lib.set_item_name(id, "tree_lowpoly")
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.4, 1.4)
	var tex := load("res://assets/prototype/tree.svg")
	if tex != null:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
	lib.set_item_mesh(id, mesh)
	lib.set_item_mesh_transform(id, _offset(TREE_DY + 0.2))
	var shape := CylinderShape3D.new()
	shape.radius = 0.25
	shape.height = 1.2
	lib.set_item_shapes(id, [shape, _offset(TREE_DY)])

static func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	return m

static func _offset(dy: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(0, dy, 0))

static func _add_ground(lib: MeshLibrary, id: int, item_name: String, color: Color) -> void:
	lib.create_item(id)
	lib.set_item_name(id, item_name)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.1, 1.0)
	mesh.material = _mat(color)
	lib.set_item_mesh(id, mesh)
	lib.set_item_mesh_transform(id, _offset(GROUND_DY))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.1, 1.0)
	lib.set_item_shapes(id, [shape, _offset(GROUND_DY)])

static func _add_water(lib: MeshLibrary, id: int) -> void:
	lib.create_item(id)
	lib.set_item_name(id, "water_blocked")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.06, 1.0)
	var mat := _mat(Color8(51, 97, 158, 217))
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	lib.set_item_mesh(id, mesh)
	lib.set_item_mesh_transform(id, _offset(WATER_DY))
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 0.4, 1.0)
	lib.set_item_shapes(id, [shape, _offset(WATER_DY)])

static func _add_rock(lib: MeshLibrary, id: int) -> void:
	lib.create_item(id)
	lib.set_item_name(id, "rock_small")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 0.8, 0.7)
	mesh.material = _mat(Color8(115, 112, 120))
	lib.set_item_mesh(id, mesh)
	lib.set_item_mesh_transform(id, _offset(ROCK_DY))
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.8, 0.7)
	lib.set_item_shapes(id, [shape, _offset(ROCK_DY)])

static func _add_tree(lib: MeshLibrary, id: int) -> void:
	lib.create_item(id)
	lib.set_item_name(id, "tree_lowpoly")
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.32
	mesh.bottom_radius = 0.42
	mesh.height = 1.4
	mesh.material = _mat(Color8(41, 97, 51))
	lib.set_item_mesh(id, mesh)
	lib.set_item_mesh_transform(id, _offset(TREE_DY))
	var shape := CylinderShape3D.new()
	shape.radius = 0.4
	shape.height = 1.4
	lib.set_item_shapes(id, [shape, _offset(TREE_DY)])
