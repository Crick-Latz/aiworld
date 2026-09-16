extends Node
## HUD 预览夹具（UI-R2）：固定大脑 ViewModel（schema 0.3），无 NPC/模型/存档依赖。
## 运行：tools/Godot_v4.7.2-stable_win64_console.exe --path game res://scenes/ui/ui_preview.tscn
## AIW_PREVIEW_FIXTURE 选夹具；AIW_PREVIEW_TAB 预选 Inspector 页。
## mock 数据与 NpcBrainViewModel.build() 输出同构（OPTIONAL MOCK 项在文档标明）。

const HUD_SCENE := preload("res://scenes/observer/observer_hud.tscn")

const FIXTURES := ["DEFAULT", "NPC_SELECTED", "NO_SELECTION", "LONG_EVENT_LOG", "PAUSED",
	"WARNING", "MEMORY_FILLED", "DECISION_FILLED", "RELATIONS_FILLED",
	"BRAIN_OVERVIEW_FULL", "BRAIN_DECISION_FULL", "BRAIN_DECISION_NO_TRACE",
	"BRAIN_PLAN_BLOCKED", "BRAIN_TOM_HOLDER_EVIDENCE", "BRAIN_RELATION_ASYMMETRIC",
	"BRAIN_MEMORY_LONG", "BRAIN_SOCIAL_COMMITMENT", "BRAIN_NO_SOCIAL_DATA",
	"BRAIN_OPEN_QUESTIONS", "BRAIN_TRUTH_VS_SUBJECTIVE", "BRAIN_SOCIAL_UNRELATED_FILTER"]

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
		"NO_SELECTION":
			model["selected_actor"] = null
			model["recent_events"] = []
			model["time_label"] = "-"
		"LONG_EVENT_LOG":
			model["selected_actor"] = _brain_full()
			var events: Array = []
			for i in range(60):
				events.append({"seq": 100 + i, "text": "薇拉 在林地砍伐木头（第 %d 次挥斧）" % i,
					"cause_seq": 99 if i % 7 == 0 else 0, "actor_ids": ["npc_weila"]})
			model["recent_events"] = events
			model["causal_chains"] = [
				{"title": "E107 事件链", "steps": ["E99 卡德加 提出 木材请求", "E100 薇拉 接受请求", "E107 薇拉 砍伐获得木头"]}]
		"PAUSED":
			model["paused"] = true
			model["selected_actor"] = _brain_full()
		"WARNING":
			model["warning_text"] = "E_DATA_MISSING: 世界配置文件不可读"
			model["lag_ticks"] = 7
		"MEMORY_FILLED":
			var sel := _brain_full()
			sel["memories"] = {"rows": _memories(20)}
			model["selected_actor"] = sel
		"DECISION_FILLED":
			var sel2 := _brain_full()
			sel2["decision"] = {
				"chosen": "chop_wood", "reason": "夜里会下雨，露宿会消耗体力并提高生病风险",
				"current_action": "在林地砍伐第 3 根木头", "blocker": "纤维×1（还差 1）",
				"next_step": "收集纤维×2 → 返回营地 → 建造",
				"candidates": [
					{"action": "chop_wood", "utility": 0.72, "chosen": true},
					{"action": "find_water", "utility": 0.43},
					{"action": "talk_oun", "utility": 0.21},
					{"action": "rest", "utility": 0.18}],
				"considered_count": 4, "dominant_interpretation": "他是善意的",
				"decision_tick": 312, "provenance": "subjective"}
			model["selected_actor"] = sel2
		"RELATIONS_FILLED":
			var sel3 := _brain_full()
			sel3["relationships"] = {"rows": [
				{"other_id": "npc_kadga", "other_name": "卡德加", "trust": 12, "benevolence": 220,
					"reliability": 60, "obligation": 0, "fear": 0, "change": "D1 分鱼后 +3",
					"provenance": "objective", "tom": {"has_food": 0.3, "generous": 0.1, "reliable": 0.2}},
				{"other_id": "npc_oun", "other_name": "缄默者欧恩", "trust": -5, "benevolence": -180,
					"reliability": 0, "obligation": 40, "fear": 0, "change": "D2 拒绝供水后 -5",
					"provenance": "objective", "tom": {"has_food": 0.6, "generous": -0.2, "reliable": 0.0}}]}
			model["selected_actor"] = sel3
		"BRAIN_DECISION_NO_TRACE":
			var sel4 := _brain_full()
			sel4["decision"] = {"chosen": "", "reason": "", "current_action": "刚醒来",
				"blocker": "", "next_step": "", "candidates": [], "considered_count": 0,
				"dominant_interpretation": "", "decision_tick": 0, "provenance": "subjective"}
			model["selected_actor"] = sel4
		"BRAIN_PLAN_BLOCKED":
			var sel5 := _brain_full()
			# R1.1：LIVE 与决策快照真分区演示——live root=SHELTER，快照 root=觅食（不同目标），
			# live 信息目标 parent_run_id/blocker_step_id 与 run 身份匹配（附着在 run 流内）
			sel5["plan"] = {
				"goal": {"desc": "觅食", "priority": 0.55, "provenance": "subjective"},
				"intention": {"action": "chop_wood", "commitment": 0.82, "started_tick": 300,
					"target": Vector2i(21, 34), "desc": "在林地砍伐木头"},
				"execution": {"run_id": "run_31", "plan_id": "plan_4", "step_id": "step_1",
					"blocker_reason": "缺少 food ×1", "selected": false, "decision_tick": 300},
				"live": {
					"root_goal": "SHELTER",
					"run": {"run_id": "run_42", "plan_id": "plan_9", "state": "ACTIVE",
						"reason_code": "", "current_step_id": "s2"},
					"steps": [
						{"step_id": "s1", "order": 0, "is_current": false, "status": "UNKNOWN", "provenance": "subjective"},
						{"step_id": "s2", "order": 1, "is_current": true, "status": "CURRENT", "provenance": "subjective"},
						{"step_id": "s3", "order": 2, "is_current": false, "status": "UNKNOWN", "provenance": "subjective"}],
					"attached_information_goal": {"query_kind": "HOLDER", "state": "ACTIVE",
						"item_id": "wood", "parent_run_id": "run_42", "blocker_step_id": "s2"},
					"provenance": "subjective", "source_kind": "LIVE_RUN", "source_ref": "agency_plan_run"},
				"live_run": {"run_id": "run_42", "plan_id": "plan_9", "state": "ACTIVE",
					"reason_code": "", "current_step_id": "s2"},
				"live_information_goal": {"query_kind": "HOLDER", "state": "ACTIVE",
					"item_id": "wood", "parent_run_id": "run_42", "blocker_step_id": "s2"},
				"decision_snapshot": {
					"goal": {"desc": "觅食", "priority": 0.55},
					"execution": {"run_id": "run_31", "plan_id": "plan_4", "step_id": "step_1",
						"blocker_reason": "缺少 food ×1", "selected": false, "decision_tick": 300},
					"information_goal": {}},
				"nodes": [
					{"kind": "ROOT_GOAL", "section": "live", "label": "SHELTER", "value": "run run_42", "status": "ACTIVE",
						"provenance": "subjective", "source_kind": "LIVE_RUN", "source_ref": "agency_plan_run.root_goal"},
					{"kind": "RUN", "section": "live", "label": "执行 run_42", "value": "计划 plan_9 · ACTIVE", "status": "ACTIVE",
						"provenance": "subjective", "source_kind": "LIVE_RUN", "source_ref": "agency_plan_run"},
					{"kind": "STEP", "section": "live", "label": "步骤 s1", "value": "", "status": "UNKNOWN",
						"provenance": "subjective", "source_kind": "LIVE_RUN", "source_ref": "agency_plan_run.steps"},
					{"kind": "STEP", "section": "live", "label": "步骤 s2", "value": "当前", "status": "CURRENT",
						"provenance": "subjective", "source_kind": "LIVE_RUN", "source_ref": "agency_plan_run.steps"},
					{"kind": "STEP", "section": "live", "label": "步骤 s3", "value": "", "status": "UNKNOWN",
						"provenance": "subjective", "source_kind": "LIVE_RUN", "source_ref": "agency_plan_run.steps"},
					{"kind": "SUBGOAL", "section": "live", "no_arrow_in": false, "label": "信息目标 HOLDER",
						"value": "状态 ACTIVE", "status": "ACTIVE",
						"provenance": "subjective", "source_kind": "LIVE_ACCESSOR", "source_ref": "agency_information_goal"},
					{"kind": "ROOT_GOAL", "section": "snapshot", "label": "觅食", "value": "优先级 0.55", "status": "ACTIVE",
						"provenance": "subjective", "source_kind": "DECISION_TRACE"},
					{"kind": "STEP", "section": "snapshot", "label": "步骤 step_1", "value": "缺少 food ×1", "status": "BLOCKED",
						"provenance": "subjective", "source_kind": "DECISION_TRACE"},
					{"kind": "BLOCKER", "section": "snapshot", "label": "缺少 food ×1", "value": "", "status": "BLOCKED",
						"provenance": "subjective", "source_kind": "DECISION_TRACE"}],
				"provenance": "subjective"}
			model["selected_actor"] = sel5
		"BRAIN_TOM_HOLDER_EVIDENCE":
			var sel6 := _brain_full()
			sel6["mind"]["tom_subjects"] = [
				{"other_id": "npc_kadga", "other_name": "卡德加", "provenance": "subjective",
					"last_seen": {"tile": Vector2i(15, 22), "tick": 310},
					"rows": [
						{"predicate": "has_item:shells", "label": "持有 shells", "value": 0.42,
							"confidence": 0.40, "last_evidence_tick": 275, "provenance": "subjective"},
						{"predicate": "reliable", "label": "可靠", "value": 0.31,
							"confidence": 0.60, "last_evidence_tick": 240, "provenance": "subjective"},
						{"predicate": "generous", "label": "慷慨", "value": -0.12,
							"confidence": 0.20, "last_evidence_tick": 180, "provenance": "subjective"}]},
				{"other_id": "npc_oun", "other_name": "缄默者欧恩", "provenance": "subjective",
					"last_seen": {"tile": Vector2i(30, 12), "tick": 290},
					"rows": [
						{"predicate": "has_item:wood", "label": "持有 wood", "value": 0.55,
							"confidence": 0.40, "last_evidence_tick": 288, "provenance": "subjective"}]}]
			model["selected_actor"] = sel6
		"BRAIN_RELATION_ASYMMETRIC":
			var sel7 := _brain_full()
			sel7["relationships"] = {"rows": [
				{"other_id": "npc_kadga", "other_name": "卡德加", "trust": 120, "benevolence": 300,
					"reliability": 120, "obligation": 0, "fear": 0, "change": "D2 分鱼后 +3",
					"provenance": "objective", "tom": {"has_food": 0.1, "generous": 0.3, "reliable": 0.2}}]}
			model["selected_actor"] = sel7
			model["recent_events"] = [
				{"seq": 51, "text": "卡德加 → 薇拉 信任 -20（拒绝分享后）", "cause_seq": 0},
				{"seq": 50, "text": "薇拉 → 卡德加 信任 +120（分鱼之后）", "cause_seq": 0}]
		"BRAIN_MEMORY_LONG":
			var sel8 := _brain_full()
			sel8["memories"] = {"rows": _memories(20)}
			model["selected_actor"] = sel8
		"BRAIN_SOCIAL_COMMITMENT":
			var sel9 := _brain_full()
			sel9["social"] = {
				"commitments": [
					{"commitment_id": "c_01", "direction": "我欠", "counterpart_name": "卡德加",
						"object": "shell", "quantity": 2, "status": "ACTIVE", "due_tick": 420,
						"source_request_id": "material:npc_weila:7:shell", "provenance": "objective"},
					{"commitment_id": "c_02", "direction": "欠我", "counterpart_name": "缄默者欧恩",
						"object": "wood", "quantity": 1, "status": "FULFILLED", "due_tick": 380,
						"source_request_id": "material:npc_oun:3:wood", "provenance": "objective"}],
				"recent_requests": [
					{"day": 2, "seq": 44, "type": "MATERIAL_REQUEST_OFFERED", "text": "薇拉 向 卡德加 请求 shell×2 已提出"},
					{"day": 2, "seq": 41, "type": "MATERIAL_REQUEST_ACCEPTED", "text": "卡德加 接受 薇拉 的请求"}],
				"holder_events": [
					{"day": 2, "seq": 46, "type": "holder_information_shared", "text": "卡德加 回答 薇拉 的持有询问"}],
				"recent_social_events": [
					{"day": 2, "seq": 47, "type": "COMMITMENT_CREATED", "text": "薇拉 承诺：交付 卡德加 shell×2"},
					{"day": 1, "seq": 30, "type": "shared_food", "text": "卡德加 主动分给 薇拉 一份烤鱼"}],
				"display_name": "薇拉", "provenance": "objective"}
			model["selected_actor"] = sel9
		"BRAIN_NO_SOCIAL_DATA":
			var sel10 := _brain_full()
			sel10["social"] = {"commitments": [], "recent_requests": [], "holder_events": [],
				"source_information_events": [],
				"recent_social_events": [], "display_name": "薇拉", "provenance": "objective"}
			model["selected_actor"] = sel10
		"BRAIN_OPEN_QUESTIONS":
			var sel11 := _brain_full()
			sel11["mind"]["open_questions"] = [
				{"about": "npc_kadga", "about_name": "卡德加", "kind": "why_refused", "entropy": 0.8,
					"stakes": 0.6, "tick": 260, "source_event_ids": [38], "provenance": "subjective"},
				{"about": "wood", "about_name": "wood", "kind": "where_to_find", "entropy": 0.5,
					"stakes": 0.9, "tick": 240, "source_event_ids": [22], "provenance": "subjective"}]
			# primary_question：stakes 0.9 的 wood 疑问胜出（排序是 presentation 聚合 → derived）
			sel11["mind"]["primary_question"] = {
				"about": "wood", "about_name": "wood", "kind": "where_to_find", "entropy": 0.5,
				"stakes": 0.9, "tick": 240, "source_event_ids": [22], "provenance": "derived"}
			model["selected_actor"] = sel11
		"BRAIN_TRUTH_VS_SUBJECTIVE":
			# §51 关键语义测试：世界事实（自己库存 wood×2，无 shells）vs 主观信念（认为卡德加可能有 shells）
			var sel12 := _brain_full()
			sel12["state"]["inventory_items"] = [{"id": "wood", "count": 2, "provenance": "objective"}]
			sel12["inventory_items"] = sel12["state"]["inventory_items"]
			sel12["inventory_text"] = "wood×2"
			sel12["mind"]["tom_subjects"] = [
				{"other_id": "npc_kadga", "other_name": "卡德加", "provenance": "subjective",
					"last_seen": {"tile": Vector2i(15, 22), "tick": 310},
					"rows": [{"predicate": "has_item:shells", "label": "持有 shells", "value": 0.5,
						"confidence": 0.40, "last_evidence_tick": 275, "provenance": "subjective"}]}]
			sel12["mind"]["open_questions"] = [
				{"about": "shells", "about_name": "shells", "kind": "who_has", "entropy": 0.7,
					"stakes": 0.8, "tick": 250, "source_event_ids": [40], "provenance": "subjective"}]
			sel12["mind"]["primary_question"] = {
				"about": "shells", "about_name": "shells", "kind": "who_has", "entropy": 0.7,
				"stakes": 0.8, "tick": 250, "source_event_ids": [40], "provenance": "derived"}
			model["selected_actor"] = sel12
		"BRAIN_SOCIAL_UNRELATED_FILTER":
			# §K15/K5 语义演示：世界事件流里有“欧恩→卡德加”的无关请求，
			# 但薇拉的社会页只显示她直接参与的事件（过滤发生在 ViewModel _event_relevant_to_actor）。
			var sel13 := _brain_full()
			sel13["social"] = {
				"commitments": [],
				"recent_requests": [
					{"day": 2, "seq": 45, "type": "MATERIAL_REQUEST_CREATED", "text": "薇拉 向 卡德加 请求 wood×1 已提出"}],
				"holder_events": [
					{"day": 2, "seq": 46, "type": "holder_information_shared", "text": "卡德加 回答 薇拉 的持有询问"}],
				"source_information_events": [],
				"recent_social_events": [
					{"day": 2, "seq": 46, "type": "holder_information_shared", "text": "卡德加 回答 薇拉 的持有询问"},
					{"day": 2, "seq": 45, "type": "MATERIAL_REQUEST_CREATED", "text": "薇拉 向 卡德加 请求 wood×1 已提出"}],
				"display_name": "薇拉", "provenance": "objective"}
			model["selected_actor"] = sel13
			model["recent_events"] = [
				{"seq": 49, "text": "欧恩 向 卡德加 请求 shell×1（与薇拉无关——不进她的社会页）", "cause_seq": 0, "actor_ids": ["npc_oun", "npc_kadga"]},
				{"seq": 46, "text": "卡德加 回答 薇拉 的持有询问", "cause_seq": 0, "actor_ids": ["npc_kadga", "npc_weila"]}]
		_:
			pass
	return model

static func _base_model() -> Dictionary:
	return {
		"view_schema_version": "0.3",
		"state_revision": 42,
		"world_name": "荒岛 · 观察模式",
		"time_label": "第 2 天 14:00",
		"paused": false,
		"speed_multiplier": 2,
		"lag_ticks": 0,
		"selected_actor": _brain_full(),
		"recent_events": [
			{"seq": 41, "text": "卡德加 到达 风铃驿站", "cause_seq": 0, "actor_ids": ["npc_kadga"]},
			{"seq": 42, "text": "薇拉 前往 旧灯塔", "cause_seq": 41, "actor_ids": ["npc_weila"]},
			{"seq": 43, "text": "缄默者欧恩 无法前往 风铃驿站，稍后改派", "cause_seq": 0, "actor_ids": ["npc_oun"]}],
		"dialogue_transcript": [
			{"day": 2, "speaker": "薇拉", "text": "灯塔的灯还能亮，说明有人维护过。", "act": "ASSERT", "seq": 44},
			{"day": 2, "speaker": "卡德加", "text": "也许是上周路过的船。别抱太大希望。", "act": "CAUTION", "seq": 45}],
		"story_threads": [],
		"causal_chains": [],
		"chronicle_text": "[color=#e8c170]第 2 天：薇拉醒来后没有立刻找水，而是走向了灯塔。[/color]",
		"warning_text": "",
	}

static func _brain_full() -> Dictionary:
	return {
		"id": "npc_weila", "display_name": "薇拉", "status_text": "砍伐树木",
		"location_text": "(21, 34)", "provenance": "objective",
		"state": {"activity": "砍伐树木", "inventory_items": [
			{"id": "food", "count": 1, "provenance": "objective"},
			{"id": "wood", "count": 2, "provenance": "objective"}], "provenance": "objective"},
		"needs": {"rows": [
			{"key": "hunger", "label": "饥饿", "value": 720, "frac": 0.72, "provenance": "objective"},
			{"key": "social", "label": "孤独", "value": 510, "frac": 0.51, "provenance": "objective"},
			{"key": "thirst", "label": "口渴", "value": 390, "frac": 0.39, "provenance": "objective"},
			{"key": "fatigue", "label": "疲劳", "value": 180, "frac": 0.18, "provenance": "derived",
				"derived_note": "fatigue = 1000 - energy"}],
			"provenance": "objective"},
		"emotions": {"rows": [
			{"key": "joy", "label": "喜悦", "value": 0.10, "provenance": "subjective"},
			{"key": "fear", "label": "担忧", "value": 0.62, "provenance": "subjective"},
			{"key": "anger", "label": "愤怒", "value": 0.05, "provenance": "subjective"},
			{"key": "sadness", "label": "悲伤", "value": 0.21, "provenance": "subjective"},
			{"key": "guilt", "label": "内疚", "value": 0.0, "provenance": "subjective"}],
			"dominant": {"label": "担忧", "value": 0.62, "provenance": "derived",
				"derived_note": "max(|value|) 聚合选择"}, "provenance": "subjective"},
		"personality": {"traits": [
			{"key": "resilience", "label": "韧性", "value": 0.85, "provenance": "objective"},
			{"key": "expressiveness", "label": "表达", "value": 0.85, "provenance": "objective"},
			{"key": "action_bias", "label": "行动", "value": 0.80, "provenance": "objective"},
			{"key": "curiosity", "label": "好奇", "value": 0.75, "provenance": "objective"},
			{"key": "empathy", "label": "共情", "value": 0.65, "provenance": "objective"},
			{"key": "sociability", "label": "社交", "value": 0.60, "provenance": "objective"},
			{"key": "altruism", "label": "利他", "value": 0.55, "provenance": "objective"},
			{"key": "pragmatism", "label": "务实", "value": 0.50, "provenance": "objective"},
			{"key": "caution", "label": "谨慎", "value": 0.30, "provenance": "objective"},
			{"key": "conflict_avoidance", "label": "避冲突", "value": 0.30, "provenance": "objective"}],
			"beliefs": [
				{"text": "活着就有希望", "weight": 0.9, "provenance": "subjective"},
				{"text": "知识就是生存的资本", "weight": 0.7, "provenance": "subjective"}],
			"provenance": "subjective"},
		"decision": {
			"chosen": "chop_wood", "reason": "夜里会下雨，露宿会消耗体力并提高生病风险",
			"current_action": "在林地砍伐第 3 根木头", "blocker": "", "next_step": "砍满 3 木头后返回营地",
			"candidates": [
				{"action": "chop_wood", "utility": 0.72, "chosen": true},
				{"action": "find_water", "utility": 0.43},
				{"action": "talk_oun", "utility": 0.21},
				{"action": "rest", "utility": 0.18}],
			"considered_count": 4, "dominant_interpretation": "", "decision_tick": 312,
			"provenance": "subjective"},
		"plan": {
			"goal": {"desc": "建造庇护所", "priority": 0.78, "provenance": "subjective"},
			"intention": {"action": "chop_wood", "commitment": 0.82, "started_tick": 300,
				"target": Vector2i(21, 34), "desc": "在林地砍伐木头"},
			"execution": {"run_id": "run_17", "plan_id": "plan_9", "step_id": "step_2",
				"blocker_reason": "", "selected": true, "decision_tick": 312},
			"live": {},
			"live_run": {},
			"live_information_goal": {},
			"decision_snapshot": {
				"goal": {"desc": "建造庇护所", "priority": 0.78},
				"execution": {"run_id": "run_17", "plan_id": "plan_9", "step_id": "step_2",
					"blocker_reason": "", "selected": true, "decision_tick": 312},
				"information_goal": {}},
			"nodes": [
				{"kind": "ROOT_GOAL", "section": "snapshot", "label": "建造庇护所", "value": "优先级 0.78", "status": "ACTIVE",
					"provenance": "subjective", "source_kind": "DECISION_TRACE"},
				{"kind": "PLAN", "section": "snapshot", "label": "计划 plan_9", "value": "运行 run_17", "status": "ACTIVE",
					"provenance": "subjective", "source_kind": "DECISION_TRACE"},
				{"kind": "STEP", "section": "snapshot", "label": "步骤 step_2：获得木头", "value": "", "status": "ACTIVE",
					"provenance": "subjective", "source_kind": "DECISION_TRACE"}],
			"provenance": "subjective"},
		"mind": {"open_questions": [], "primary_question": {}, "tom_subjects": [
			{"other_id": "npc_kadga", "other_name": "卡德加", "provenance": "subjective",
				"last_seen": {"tile": Vector2i(15, 22), "tick": 310},
				"rows": [
					{"predicate": "has_food", "label": "有食物", "value": 0.3,
						"confidence": 0.4, "last_evidence_tick": 260, "provenance": "subjective"}]},
			{"other_id": "npc_oun", "other_name": "缄默者欧恩", "provenance": "subjective",
				"last_seen": {"tile": Vector2i(30, 12), "tick": 290},
				"rows": [
					{"predicate": "reliable", "label": "可靠", "value": 0.0,
						"confidence": 0.0, "last_evidence_tick": -1, "provenance": "subjective"}]}],
			"prediction_error": 0.12, "provenance": "subjective"},
		"relationships": {"rows": [
			{"other_id": "npc_kadga", "other_name": "卡德加", "trust": 8, "benevolence": 220,
				"reliability": 60, "obligation": 0, "fear": 0, "change": "",
				"provenance": "objective", "tom": {"has_food": 0.3, "generous": 0.1, "reliable": 0.2}},
			{"other_id": "npc_oun", "other_name": "缄默者欧恩", "trust": 0, "benevolence": 0,
				"reliability": 0, "obligation": 0, "fear": 0, "change": "",
				"provenance": "objective", "tom": {"has_food": 0.0, "generous": 0.0, "reliable": 0.0}}]},
		"memories": {"rows": _memories(4), "provenance": "subjective"},
		"social": {
			"commitments": [
				{"commitment_id": "c_01", "direction": "我欠", "counterpart_name": "卡德加",
					"object": "shell", "quantity": 2, "status": "ACTIVE", "due_tick": 420,
					"source_request_id": "material:npc_weila:7:shell", "provenance": "objective"}],
			"recent_requests": [
				{"day": 2, "seq": 44, "type": "MATERIAL_REQUEST_OFFERED", "text": "薇拉 向 卡德加 请求 shell×2 已提出"}],
			"holder_events": [
				{"day": 2, "seq": 46, "type": "holder_information_shared", "text": "卡德加 回答 薇拉 的持有询问"}],
			"source_information_events": [
				{"day": 2, "seq": 48, "type": "source_information_shared", "text": "欧恩 告诉 薇拉：北滩有浮木来源"}],
			"recent_social_events": [
				{"day": 1, "seq": 30, "type": "shared_food", "text": "卡德加 主动分给 薇拉 一份烤鱼"}],
			"display_name": "薇拉", "provenance": "objective"},
		"why": {
			"provenance": "derived",
			"derived_note": "因果链由 presentation 从决策留痕/公开状态确定性串联",
			"decision_reason": {"text": "夜里会下雨，露宿会消耗体力并提高生病风险",
				"provenance": "subjective", "source_kind": "DECISION_TRACE",
				"source_ref": "last_decision_trace.reason"},
			"nodes": [
				{"label": "当前目标：建造庇护所", "provenance": "subjective", "source_kind": "DECISION_TRACE", "source_ref": "last_decision_trace.goal_desc"},
				{"label": "意图：在林地砍伐木头（承诺度 82%）", "provenance": "subjective", "source_kind": "INTENTION", "source_ref": "intentions.current_intention"},
				{"label": "步骤：step_2", "provenance": "subjective", "source_kind": "DECISION_TRACE", "source_ref": "last_decision_trace.agency_execution.step_id"},
				{"label": "当前行动：砍伐树木", "provenance": "objective", "source_kind": "ACTOR_STATE", "source_ref": "activity"}],
			"links": [
				{"from": 0, "to": 1, "provenance": "subjective", "source_kind": "DECISION_TRACE", "source_ref": "last_decision_trace.selected"},
				{"from": 1, "to": 2, "provenance": "subjective", "source_kind": "DECISION_TRACE", "source_ref": "last_decision_trace.agency_execution"},
				{"from": 2, "to": 3, "provenance": "derived", "source_kind": "PRESENTATION_LINK",
					"source_ref": "activity（执行系统维护，Presentation 无直接 trace 字段）"}],
			"context": [
				{"label": "当前需求：饥饿 720", "provenance": "objective", "source_kind": "ACTOR_NEED", "source_ref": "needs.hunger"}]},
		"activity_text": "砍伐树木", "goal_text": "建造庇护所",
		"inventory_text": "food×1、wood×2",
		"inventory_items": [{"id": "food", "count": 1, "provenance": "objective"},
			{"id": "wood", "count": 2, "provenance": "objective"}],
		"needs_text": "饥饿720 孤独510 口渴390 疲劳180",
		"decision_text": "夜里会下雨，露宿会消耗体力并提高生病风险",
	}

static func _memories(n: int) -> Array:
	var out: Array = []
	var texts := [
		["卡德加 主动分给我一份烤鱼", "shared_food_to_me", "npc_kadga", 0.8],
		["我向 欧恩 要淡水被拒绝", "i_refused_request", "npc_oun", -0.6],
		["醒来时潮水刚退，海滩上有不少浮木", "explored_found", "", 0.3],
		["我们都活过了沉船之夜", "reflected", "", 0.5],
		["卡德加 兑现了送水的承诺", "promise_kept", "npc_kadga", 0.7],
		["暴雨中淋了一夜", "weather_storm", "", -0.8]]
	for i in range(n):
		var t: Array = texts[i % texts.size()]
		out.append({"seq": 30 + i, "tick": 300 + i * 6, "day": (300 + i * 6) / 24 + 1,
			"text": t[0], "type": t[1], "counterpart": t[2],
			"derived_importance": t[3], "interpretation": {}, "provenance": "subjective"})
	return out
