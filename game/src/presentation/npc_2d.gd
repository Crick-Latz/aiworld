class_name Npc2D
extends Node2D
## UI-R1：2D 像素 NPC 表现（presentation）。
## 接口与 3D npc_visual 对齐：setup / update_position / set_selected + meta npc_id。
## 位置由装配层按逻辑 tick 插值驱动；4 向 idle/walk/run 由占位 spritesheet 切片。
## 衬衫为近白色，可被 modulate 染成每个角色的识别色。

const SHEET := preload("res://assets/pixel/npc/npc_sheet_16.png")
const SHADOW_TEX := preload("res://assets/pixel/markers/shadow.png")
const TILE := 16

## spritesheet 行布局：每方向一行（down/up/left/right），idle 0-3 / walk 4-7 / run 8-11
const DIRECTIONS := ["down", "up", "left", "right"]
const KIND_FRAMES := {"idle": 2, "walk": 4, "run": 4}
const KIND_FPS := {"idle": 2, "walk": 6, "run": 10}
const KIND_ROW_BASE := {"idle": 0, "walk": 4, "run": 8}

var actor_id := ""

var _facing := "down"
var _kind := "idle"
var _name_color := Color.WHITE

@onready var shadow: Sprite2D = $Shadow
@onready var body: AnimatedSprite2D = $Body
@onready var name_label: Label = $NameLabel

func setup(id: String, display_name: String, color: Color) -> void:
	actor_id = id
	set_meta("npc_id", id)
	_name_color = color
	if body.sprite_frames == null:
		body.sprite_frames = _build_frames()
	body.modulate = color
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", color.lightened(0.35))
	_apply_anim(true)

func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for kind in KIND_FRAMES:
		for dir_i in DIRECTIONS.size():
			var anim_name := "%s_%s" % [kind, DIRECTIONS[dir_i]]
			frames.add_animation(anim_name)
			frames.set_animation_speed(anim_name, KIND_FPS[kind])
			frames.set_animation_loop(anim_name, true)
			var row: int = KIND_ROW_BASE[kind] + dir_i
			for col in KIND_FRAMES[kind]:
				var tex := AtlasTexture.new()
				tex.atlas = SHEET
				tex.region = Rect2(col * TILE, row * TILE, TILE, TILE)
				frames.add_frame(anim_name, tex)
	return frames

## from/to 为 Vector2i 逻辑格；alpha ∈ [0,1] 为 tick 内插值进度；running 提示跑动动画。
func update_position(from_tile: Vector2i, to_tile: Vector2i, alpha: float, running := false) -> void:
	var delta := Vector2i(to_tile - from_tile)
	if delta != Vector2i.ZERO:
		_facing = _facing_from(delta)
		_kind = "run" if running else "walk"
	else:
		_kind = "idle"
	_apply_anim()
	var from_px := (Vector2(from_tile) + Vector2(0.5, 0.78)) * TILE
	var to_px := (Vector2(to_tile) + Vector2(0.5, 0.78)) * TILE
	global_position = from_px.lerp(to_px, clampf(alpha, 0.0, 1.0))

func set_selected(selected: bool) -> void:
	name_label.add_theme_color_override("font_color",
		Color.WHITE if selected else _name_color.lightened(0.35))
	name_label.add_theme_constant_override("outline_size", 3 if selected else 2)

func _apply_anim(force_restart := false) -> void:
	var anim_name := "%s_%s" % [_kind, _facing]
	if body.sprite_frames != null and body.sprite_frames.has_animation(anim_name):
		if body.animation != anim_name or not body.is_playing():
			body.play(anim_name)
		elif force_restart:
			body.stop()
			body.play(anim_name)

static func _facing_from(delta: Vector2i) -> String:
	if absi(delta.x) >= absi(delta.y):
		return "right" if delta.x > 0 else "left"
	return "down" if delta.y > 0 else "up"
