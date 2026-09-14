extends Node
## HUD 预览夹具（UI-R1）：固定 ViewModel，无 NPC/模型/存档依赖。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --path game res://scenes/ui/ui_preview.tscn
## 可用 AIW_PREVIEW_FIXTURE 选夹具：
##   DEFAULT / NPC_SELECTED / NO_SELECTION / LONG_EVENT_LOG / PAUSED / WARNING
##   MEMORY_FILLED / DECISION_FILLED / RELATIONS_FILLED
## 正式观察界面使用同一 HUD 场景，不是第二套 UI 实现。

const HUD_SCENE := preload("res://scenes/observer/observer_hud.tscn")

const FIXTURES := ["DEFAULT", "NPC_SELECTED", "NO_SELECTION", "LONG_EVENT_LOG", "PAUSED",
	"WARNING", "MEMORY_FILLED", "DECISION_FILLED", "RELATIONS_FILLED"]

func _ready() -> void:
	get_tree().root.content_scale_size = Vector2i(480, 270) # 与正式观察同一像素画布
	var fixture := str(OS.get_environment("AIW_PREVIEW_FIXTURE"))
	if fixture == "" or not FIXTURES.has(fixture):
		fixture = "DEFAULT"
	var hud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.render(fixture_model(fixture))
	print("UI_PREVIEW fixture=%s" % fixture)
	hud.pause_requested.connect(func(): print("PREVIEW pause_requested"))
	hud.speed_requested.connect(func(m): print("PREVIEW speed_requested %d" % m))
	var inspector_tab := str(OS.get_environment("AIW_PREVIEW_TAB"))
	if inspector_tab != "":
		hud.set_inspector_tab(inspector_tab)

static func fixture_model(fixture_name := "DEFAULT") -> Dictionary:
	var model := _base_model()
	match fixture_name:
		"NPC_SELECTED":
			_fill_rich_selection(model)
		"NO_SELECTION":
			model["selected_actor"] = null
			model["recent_events"] = []
			model["time_label"] = "-"
		"LONG_EVENT_LOG":
			_fill_rich_selection(model)
			var events: Array = []
			for i in range(60):
				events.append({
					"seq": 100 + i,
					"text": "薇拉 在林地 %s 木头（第 %d 次挥斧）" % ["砍伐", i],
					"cause_seq": 99 if i % 7 == 0 else 0,
					"actor_ids": ["npc_weila"],
				})
			model["recent_events"] = events
			model["causal_chains"] = [
				{"title": "E107 事件链", "steps": ["E99 卡德加 提出 木材请求", "E100 薇拉 接受请求", "E107 薇拉 砍伐获得木头"]},
				{"title": "E114 事件链", "steps": ["E99 卡德加 提出 木材请求", "E114 薇拉 移交木头×1"]},
			]
		"PAUSED":
			model["paused"] = true
			_fill_rich_selection(model)
		"WARNING":
			model["warning_text"] = "E_DATA_MISSING: 世界配置文件不可读"
			model["lag_ticks"] = 7
		"MEMORY_FILLED":
			_fill_rich_selection(model)
			model["selected_actor"]["memory_items"] = _sample_memories()
		"DECISION_FILLED":
			_fill_rich_selection(model)
			model["selected_actor"]["decision"] = {
				"plan": "建造庇护所（需要木头×3、纤维×2）",
				"step": "前往林地砍伐木头",
				"reason": "夜里会下雨，露宿会消耗体力并提高生病风险",
				"blocker": "纤维×1（还差 1）",
				"next_step": "收集纤维×2 → 返回营地 → 建造",
			}
		"RELATIONS_FILLED":
			_fill_rich_selection(model)
			model["selected_actor"]["relationship_rows"] = [
				{"other_id": "npc_kadga", "other_name": "卡德加", "trust": 12, "benevolence": 0.1, "reliability": 0.2,
					"change": "D1 分鱼后 +3", "tom": {"has_food": 0.3, "generous": 0.1, "reliable": 0.2}},
				{"other_id": "npc_oun", "other_name": "缄默者欧恩", "trust": -5, "benevolence": -0.2, "reliability": 0.0,
					"change": "D2 拒绝供水后 -5", "tom": {"has_food": 0.6, "generous": -0.2, "reliable": 0.0}},
			]
	return model

static func _base_model() -> Dictionary:
	return {
		"view_schema_version": "0.2",
		"state_revision": 42,
		"world_name": "荒岛 · 观察模式",
		"time_label": "第 2 天 14:00",
		"paused": false,
		"speed_multiplier": 2,
		"lag_ticks": 0,
		"selected_actor": {
			"id": "npc_weila",
			"display_name": "薇拉",
			"status_text": "观察 旧灯塔",
			"activity_text": "观察 旧灯塔",
			"goal_text": "巡查潮汐规律",
			"decision_text": "沿海岸线向南巡查",
			"location_text": "(12, 8)",
			"inventory_text": "食物×1",
			"inventory_items": [{"id": "food", "count": 1}],
			"needs_text": "饿200/渴150/累200/孤独100",
		},
		"recent_events": [
			{"seq": 41, "text": "卡德加 到达 风铃驿站", "cause_seq": 0, "actor_ids": ["npc_kadga"]},
			{"seq": 42, "text": "薇拉 前往 旧灯塔", "cause_seq": 41, "actor_ids": ["npc_weila"]},
			{"seq": 43, "text": "缄默者欧恩 无法前往 风铃驿站，稍后改派", "cause_seq": 0, "actor_ids": ["npc_oun"]},
		],
		"dialogue_transcript": [
			{"day": 2, "speaker": "薇拉", "text": "灯塔的灯还能亮，说明有人维护过。", "act": "ASSERT", "seq": 44},
			{"day": 2, "speaker": "卡德加", "text": "也许是上周路过的船。别抱太大希望。", "act": "CAUTION", "seq": 45},
		],
		"story_threads": [],
		"causal_chains": [],
		"chronicle_text": "[color=#e8c170]第 2 天：薇拉醒来后没有立刻找水，而是走向了灯塔。[/color]",
		"warning_text": "",
	}

static func _fill_rich_selection(model: Dictionary) -> void:
	model["selected_actor"] = {
		"id": "npc_weila",
		"display_name": "薇拉",
		"status_text": "砍伐树木",
		"activity_text": "砍伐树木",
		"goal_text": "收集木头×3 建造庇护所",
		"decision_text": "林地就在北侧，步行两刻钟",
		"location_text": "(21, 34)",
		"inventory_text": "食物×1、木头×2",
		"inventory_items": [{"id": "food", "count": 1}, {"id": "wood", "count": 2}],
		"needs_text": "饿320/渴210/累350/孤独40",
		"memory_items": _sample_memories(),
		"personality": {
			"traits": [
				{"key": "resilience", "label": "韧性", "value": 0.85},
				{"key": "curiosity", "label": "好奇", "value": 0.75},
				{"key": "action_bias", "label": "行动", "value": 0.80},
				{"key": "caution", "label": "谨慎", "value": 0.30},
				{"key": "empathy", "label": "共情", "value": 0.65},
				{"key": "sociability", "label": "社交", "value": 0.60},
				{"key": "altruism", "label": "利他", "value": 0.55},
				{"key": "expressiveness", "label": "表达", "value": 0.85},
				{"key": "conflict_avoidance", "label": "避冲突", "value": 0.30},
				{"key": "pragmatism", "label": "务实", "value": 0.50},
			],
			"emotions": [
				{"key": "joy", "value": 0.22},
				{"key": "fear", "value": -0.08},
			],
			"beliefs": [
				{"text": "活着就有希望", "weight": 0.9},
				{"text": "知识就是生存的资本", "weight": 0.7},
			],
		},
		"decision": {
			"plan": "收集木头×3 建造庇护所",
			"step": "在林地砍伐第 3 根木头",
			"reason": "夜里会下雨，露宿会消耗体力",
			"blocker": "无",
			"next_step": "砍满 3 木头后返回营地",
		},
		"relationship_rows": [
			{"other_id": "npc_kadga", "other_name": "卡德加", "trust": 8, "benevolence": 0.2, "reliability": 0.1,
				"change": "D1 分鱼后 +3", "tom": {"has_food": 0.1, "generous": 0.2, "reliable": 0.1}},
			{"other_id": "npc_oun", "other_name": "缄默者欧恩", "trust": 0, "benevolence": 0.0, "reliability": 0.0,
				"change": "", "tom": {"has_food": 0.0, "generous": 0.0, "reliable": 0.0}},
		],
		"history_rows": [
			{"day": 2, "seq": 42, "text": "薇拉 前往 旧灯塔"},
			{"day": 2, "seq": 47, "text": "薇拉 开始砍伐树木"},
		],
		"history_dialogue_rows": [
			{"day": 2, "speaker": "薇拉", "text": "灯塔的灯还能亮，说明有人维护过。", "act": "ASSERT", "seq": 44},
		],
		"history_chain_rows": [
			"E41 卡德加 提出 木材请求 → E46 薇拉 接受请求",
		],
	}

static func _sample_memories() -> Array:
	return [
		{"day": 2, "tick": 30, "text": "卡德加 主动分给我一份烤鱼", "type": "shared_food_to_me", "counterpart": "npc_kadga", "importance": 0.8},
		{"day": 2, "tick": 28, "text": "我向 欧恩 要淡水被拒绝", "type": "i_refused_request", "counterpart": "npc_oun", "importance": -0.6},
		{"day": 1, "tick": 12, "text": "醒来时潮水刚退，海滩上有不少浮木", "type": "explored", "counterpart": "", "importance": 0.3},
		{"day": 1, "tick": 8, "text": "我们都活过了沉船之夜", "type": "reflected", "counterpart": "", "importance": 0.5},
	]
