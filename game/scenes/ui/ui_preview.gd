extends Node
## HUD 预览夹具（OBS-01，23-B）：固定 ViewModel，无 NPC/模型/存档依赖。
## 可直接运行调布局：tools/Godot_v4.7.2-stable_win64_console.exe --path game res://scenes/ui/ui_preview.tscn
## 正式观察界面使用同一 HUD 场景，不是第二套 UI 实现。

const HUD_SCENE := preload("res://scenes/observer/observer_hud.tscn")

static func fixture_model() -> Dictionary:
	return {
		"view_schema_version": "0.1",
		"state_revision": 42,
		"time_label": "第 2 天 14:37",
		"paused": false,
		"speed_multiplier": 2,
		"lag_ticks": 0,
		"selected_actor": {
			"id": "npc_weila",
			"display_name": "薇拉",
			"activity_text": "观察 旧灯塔",
			"goal_text": "巡查潮汐规律",
			"location_text": "旧灯塔",
		},
		"recent_events": [
			{"seq": 41, "text": "卡德加 到达 风铃驿站", "cause_seq": 0, "actor_ids": ["npc_kadga"]},
			{"seq": 42, "text": "薇拉 前往 旧灯塔", "cause_seq": 0, "actor_ids": ["npc_weila"]},
			{"seq": 43, "text": "缄默者欧恩 无法前往 风铃驿站，稍后改派", "cause_seq": 0, "actor_ids": ["npc_oun"]},
		],
		"warning_text": "",
	}

func _ready() -> void:
	var hud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.render(fixture_model())
	hud.pause_requested.connect(func(): print("PREVIEW pause_requested"))
	hud.speed_requested.connect(func(m): print("PREVIEW speed_requested %d" % m))
