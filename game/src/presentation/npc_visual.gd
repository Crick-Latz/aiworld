extends Node3D
## NPC 视觉投影（OBS-01，M13）：无相互物理阻挡的视觉实体。
## 位置由装配层按逻辑 tick 插值驱动；名牌可区分；脚底有选择环。
## 不携带碰撞体——静态障碍由 walkable 网格阻止（原型限制已记录于任务书）。

var actor_id := ""

func setup(id: String, display_name: String, color: Color) -> void:
	actor_id = id
	set_meta("npc_id", id)
	var body: MeshInstance3D = $Body
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.7, 1.5, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mesh.material = mat
	body.mesh = mesh
	var label: Label3D = $NameLabel
	label.text = display_name
	label.font_size = 20
	label.outline_size = 4
	label.outline_modulate = Color(0.08, 0.08, 0.1, 0.85)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	var ring: MeshInstance3D = $Ring
	var torus := TorusMesh.new()
	torus.inner_radius = 0.4
	torus.outer_radius = 0.5
	ring.mesh = torus
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color8(80, 200, 230)
	rmat.emission_enabled = true
	rmat.emission = Color8(80, 200, 230)
	rmat.emission_energy_multiplier = 0.4
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rmat

# from/to 为 Vector2i 逻辑格；alpha ∈ [0,1) 为 tick 内插值进度
func update_position(from_tile: Vector2i, to_tile: Vector2i, alpha: float) -> void:
	var from3 := Vector3(from_tile.x + 0.5, 0.0, from_tile.y + 0.5)
	var to3 := Vector3(to_tile.x + 0.5, 0.0, to_tile.y + 0.5)
	global_position = from3.lerp(to3, clampf(alpha, 0.0, 1.0))

func set_selected(selected: bool) -> void:
	var ring: MeshInstance3D = $Ring
	visible = true
	ring.visible = true
	var mat: StandardMaterial3D = ring.material_override
	if mat != null:
		mat.emission_energy_multiplier = 1.2 if selected else 0.4
