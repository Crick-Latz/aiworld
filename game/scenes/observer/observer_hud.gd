extends CanvasLayer
## UI-R1 观察 HUD（2D 像素版）：只暴露 render(ViewModel) 与意图信号。
## 布局（v3 游戏式 HUD）：顶部紧凑状态栏（左世界名/日期时间，右 倍速/暂停/菜单）；
## 右侧 NPC Inspector（6 页，未选中时收起）；底部时间线（事件·故事·对话·因果链，
## 默认收起为 tab 条，点击展开、再点当前 tab 收回）。世界画面是视觉主体。
## 内部节点路径不外泄；不读写 Simulation 内部状态；缺字段一律显示占位文案。
## 契约（observer_sim.gd 依赖）：render(model)、tick_label 含 "N×"、sel_name 含角色名、
## events_label 解析文本含事件文本；信号 pause/speed/save/scenario 不变。

signal pause_requested
signal speed_requested(multiplier: int)
signal save_requested
signal scenario_requested(scenario_name: String)

const INSPECTOR_TABS := ["overview", "memory", "personality", "decision", "relations", "history"]
const TIMELINE_TABS := ["events", "stories", "dialogue", "causal"]
const EMOTION_LABELS := {"joy": "开心", "fear": "恐惧", "anger": "愤怒", "sadness": "悲伤", "guilt": "内疚"}
const MAX_EVENT_LINES := 14
const MAX_MEMORIES := 8

var _inspector_tab := "overview"
var _timeline_tab := "events"
var _timeline_autopicked := false
var _timeline_expanded := false
const TIMELINE_COLLAPSED_HEIGHT := 16
const TIMELINE_EXPANDED_HEIGHT := 74

@onready var world_label: Label = $Root/TopBar/TopMargin/TopHBox/WorldLabel
@onready var tick_label: Label = $Root/TopBar/TopMargin/TopHBox/TickLabel
@onready var warn_label: Label = $Root/TopBar/TopMargin/TopHBox/WarnLabel
@onready var lag_label: Label = $Root/TopBar/TopMargin/TopHBox/LagLabel
@onready var pause_btn: Button = $Root/TopBar/TopMargin/TopHBox/PauseBtn
@onready var x1_btn: Button = $Root/TopBar/TopMargin/TopHBox/X1Btn
@onready var x2_btn: Button = $Root/TopBar/TopMargin/TopHBox/X2Btn
@onready var x4_btn: Button = $Root/TopBar/TopMargin/TopHBox/X4Btn
@onready var menu_btn: Button = $Root/TopBar/TopMargin/TopHBox/MenuBtn
@onready var inspector_panel: PanelContainer = $Root/InspectorPanel
@onready var bottom_pages: Control = $Root/BottomPanel/BotMargin/BotVBox/PagesH
@onready var bottom_panel: PanelContainer = $Root/BottomPanel
@onready var sel_name: Label = $Root/InspectorPanel/InsMargin/InsVBox/HeaderH/SelName
@onready var sel_status: Label = $Root/InspectorPanel/InsMargin/InsVBox/HeaderH/StatusLabel
@onready var goal_label: Label = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/OverviewPage/GoalLabel
@onready var decision_line_label: Label = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/OverviewPage/DecisionLineLabel
@onready var location_label: Label = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/OverviewPage/LocationLabel
@onready var needs_label: Label = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/OverviewPage/NeedsLabel
@onready var inventory_label: Label = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/OverviewPage/InventoryLabel
@onready var events_label: RichTextLabel = $Root/BottomPanel/BotMargin/BotVBox/PagesH/EventsLabel
@onready var hint_label: Label = $Root/HintLabel
var tab_buttons := {}
var timeline_buttons := {}
var pages := {}
var timeline_pages := {}

func _ready() -> void:
	pause_btn.pressed.connect(func(): pause_requested.emit())
	x1_btn.pressed.connect(func(): speed_requested.emit(1))
	x2_btn.pressed.connect(func(): speed_requested.emit(2))
	x4_btn.pressed.connect(func(): speed_requested.emit(4))
	_menu = PopupMenu.new()
	add_child(_menu) # 必须入树，否则成为孤儿节点在退出时泄漏 RID
	_menu.add_item("存档", 0)
	_menu.add_item("基准场景", 1)
	_menu.add_item("对照场景", 2)
	_menu.id_pressed.connect(_on_menu_id)
	menu_btn.pressed.connect(func(): _menu.popup(Rect2i(Vector2i(menu_btn.global_position), Vector2i(120, 72))))
	var grid: GridContainer = $Root/InspectorPanel/InsMargin/InsVBox/TabGrid
	for tab_name in INSPECTOR_TABS:
		var btn: Button = grid.get_node(NodePath(String(tab_name).capitalize()))
		btn.pressed.connect(func(): _set_inspector_tab(tab_name))
		tab_buttons[tab_name] = btn
	var tab_row: HBoxContainer = $Root/BottomPanel/BotMargin/BotVBox/TabRow
	for tab_name in TIMELINE_TABS:
		var btn: Button = tab_row.get_node(NodePath(String(tab_name).capitalize()))
		btn.pressed.connect(func(): _on_timeline_tab_pressed(tab_name))
		timeline_buttons[tab_name] = btn
	for tab_name in INSPECTOR_TABS:
		pages[tab_name] = $Root/InspectorPanel/InsMargin/InsVBox/PagesV.get_node(NodePath(String(tab_name).capitalize() + "Page")) as Control
	for tab_name in TIMELINE_TABS:
		timeline_pages[tab_name] = $Root/BottomPanel/BotMargin/BotVBox/PagesH.get_node(NodePath(String(tab_name).capitalize() + "Label")) as Control
	inspector_panel.visible = false # 未选中即收起（v3）
	_apply_timeline_collapse(false) # 默认收起：面板真的只有 tab 条高度
	_set_inspector_tab(_inspector_tab)
	_set_timeline_tab(_timeline_tab)

var _menu: PopupMenu

func _on_menu_id(id: int) -> void:
	if id == 0:
		save_requested.emit()
	elif id == 1:
		scenario_requested.emit("baseline")
	elif id == 2:
		scenario_requested.emit("control")

## 点击 tab：未展开或切换页 → 展开；再次点击当前页 → 收回
func _on_timeline_tab_pressed(tab_name: String) -> void:
	if _timeline_expanded and _timeline_tab == tab_name:
		_apply_timeline_collapse(false)
	else:
		_apply_timeline_collapse(true)
		_set_timeline_tab(tab_name)

## 收起时 BottomPanel 的 offset_top 收到 -16（只剩 tab 条），否则面板仍占 74px 挡世界
func _apply_timeline_collapse(expanded: bool) -> void:
	_timeline_expanded = expanded
	bottom_pages.visible = expanded
	bottom_panel.offset_top = -TIMELINE_EXPANDED_HEIGHT if expanded else -TIMELINE_COLLAPSED_HEIGHT

## 预览/截图工具入口
func set_inspector_tab(tab_name: String) -> void:
	_set_inspector_tab(tab_name)

func set_timeline_tab(tab_name: String) -> void:
	_apply_timeline_collapse(true)
	_set_timeline_tab(tab_name)

func _set_inspector_tab(tab_name: String) -> void:
	if not INSPECTOR_TABS.has(tab_name):
		return
	_inspector_tab = tab_name
	for name_key in pages:
		(pages[name_key] as Control).visible = str(name_key) == tab_name
		if tab_buttons.has(name_key):
			(tab_buttons[name_key] as Button).set_pressed_no_signal(str(name_key) == tab_name)

func _set_timeline_tab(tab_name: String) -> void:
	if not TIMELINE_TABS.has(tab_name):
		return
	_timeline_tab = tab_name
	for name_key in timeline_pages:
		(timeline_pages[name_key] as Control).visible = str(name_key) == tab_name
		if timeline_buttons.has(name_key):
			(timeline_buttons[name_key] as Button).set_pressed_no_signal(str(name_key) == tab_name)

## model 见 docs/ui/OBSERVER_VIEW_MODEL.md（view_schema_version 0.2）
func render(model: Dictionary) -> void:
	world_label.text = str(model.get("world_name", "灰雾港 · 观察模式"))
	var warning := str(model.get("warning_text", ""))
	warn_label.visible = warning != ""
	if warning != "":
		warn_label.text = "⚠ " + warning.substr(0, 44)
	var lag: int = int(model.get("lag_ticks", 0))
	lag_label.visible = lag > 0
	if lag > 0:
		lag_label.text = "滞后 %d" % lag
	tick_label.text = "%s · %s · %d×" % [
		str(model.get("time_label", "-")),
		"已暂停" if bool(model.get("paused", false)) else "运行中",
		int(model.get("speed_multiplier", 1))]
	var sel = model.get("selected_actor", null)
	_render_selection(sel)
	_render_timeline(model)
	var hint := str(model.get("hint_text", ""))
	if hint != "":
		hint_label.text = hint

func _render_selection(sel) -> void:
	inspector_panel.visible = sel != null and typeof(sel) == TYPE_DICTIONARY
	if sel != null and typeof(sel) == TYPE_DICTIONARY:
		sel_name.text = str(sel.get("display_name", "-"))
		sel_status.text = str(sel.get("status_text", sel.get("activity_text", "-")))
		goal_label.text = "目标：%s" % _placeholder(sel, "goal_text")
		var decision_text := str(sel.get("decision_text", ""))
		decision_line_label.text = "决策：%s" % (decision_text if decision_text != "" else "—")
		location_label.text = "位置：%s" % _placeholder(sel, "location_text")
		needs_label.text = "需求：%s" % str(sel.get("needs_text", "—"))
		inventory_label.text = "物资：%s" % _inventory_text(sel)
		_set_rtl_bbcode(pages["memory"], _memory_bbcode(sel))
		_set_rtl_bbcode(pages["personality"], _personality_bbcode(sel))
		_set_rtl_bbcode(pages["decision"], _decision_bbcode(sel))
		_set_rtl_bbcode(pages["relations"], _relations_bbcode(sel))
		_set_rtl_bbcode(pages["history"], _history_bbcode(sel))
	else:
		sel_name.text = "未选中"
		sel_status.text = "点击世界中的角色"
		goal_label.text = "目标：—"
		decision_line_label.text = "决策：—"
		location_label.text = "位置：—"
		needs_label.text = "需求：—"
		inventory_label.text = "物资：—"
		for key in ["memory", "personality", "decision", "relations", "history"]:
			_set_rtl_bbcode(pages[key], "[color=#8899aa]暂无数据（未选中角色）[/color]")

func _render_timeline(model: Dictionary) -> void:
	# 事件页：编年史头 + 最近事件
	var lines: Array = []
	var chronicle: String = str(model.get("chronicle_text", ""))
	if chronicle != "":
		lines.append(chronicle)
	var events: Array = model.get("recent_events", [])
	for e in events.slice(maxi(0, events.size() - MAX_EVENT_LINES), events.size()):
		lines.append("[color=#aabbcc]%d[/color] %s" % [int(e.get("seq", 0)), str(e.get("text", ""))])
	events_label.clear()
	events_label.append_text("\n".join(lines) if not lines.is_empty() else "[color=#8899aa]暂无事件[/color]")
	# 故事页：ThreadEngine 线程优先，其次句子级编年史
	var threads: Array = model.get("story_threads", [])
	var s_lines: Array = []
	if not threads.is_empty():
		for tir in threads.slice(0, 6):
			s_lines.append("[color=#e8c170]%s[/color]" % str(tir.get("_llm_title", tir.get("_title", ""))))
			s_lines.append("  [color=#8899aa]%s[/color]" % str(tir.get("_llm_summary", tir.get("_summary", ""))).substr(0, 60))
	else:
		var sentences: Array = model.get("narrative_sentences", [])
		if not sentences.is_empty():
			for sn in sentences:
				s_lines.append(str(sn.get("text", "")))
		else:
			s_lines.append("[color=#8899aa]暂无故事线[/color]")
	_fill_rtl(timeline_pages["stories"], s_lines)
	# 对话页
	var dialogue: Array = model.get("dialogue_transcript", [])
	var d_lines: Array = []
	if dialogue.is_empty():
		d_lines.append("[color=#8899aa]暂无对话[/color]")
	else:
		for dl in dialogue.slice(maxi(0, dialogue.size() - 8), dialogue.size()):
			d_lines.append("[color=#c0d8e8]%s：[/color]%s [color=#667788](%s)[/color]" % [
				str(dl.get("speaker", "")), str(dl.get("text", "")), str(dl.get("act", ""))])
	_fill_rtl(timeline_pages["dialogue"], d_lines)
	# 因果链页
	var chains: Array = model.get("causal_chains", [])
	var c_lines: Array = []
	if chains.is_empty():
		c_lines.append("[color=#8899aa]暂无因果链数据[/color]")
	else:
		for chain in chains:
			c_lines.append("[color=#e8c170]%s[/color]" % str(chain.get("title", "链")))
			for step in chain.get("steps", []):
				c_lines.append("  %s" % str(step))
	_fill_rtl(timeline_pages["causal"], c_lines)
	# 首次渲染自动挑一个有内容的页；之后尊重用户选择
	if not _timeline_autopicked:
		_timeline_autopicked = true
		if not events.is_empty():
			_set_timeline_tab("events")
		elif not threads.is_empty() or not (model.get("narrative_sentences", []) as Array).is_empty():
			_set_timeline_tab("stories")

func _placeholder(sel: Dictionary, key: String) -> String:
	var v := str(sel.get(key, ""))
	return v if v != "" else "—"

func _inventory_text(sel: Dictionary) -> String:
	if sel.has("inventory_items"):
		var parts: Array = []
		for item in sel.get("inventory_items", []):
			var n: int = int(item.get("count", 0))
			if n > 0:
				parts.append("%s×%d" % [str(item.get("id", "?")), n])
		return "、".join(parts) if not parts.is_empty() else "（空）"
	var legacy := str(sel.get("inventory_text", ""))
	return legacy if legacy != "" else "（空）"

func _memory_bbcode(sel: Dictionary) -> String:
	var mems: Array = sel.get("memory_items", [])
	if mems.is_empty():
		return "[color=#8899aa]暂无记忆[/color]"
	var recent: Array = []
	var important: Array = []
	var social: Array = []
	for i in range(mems.size() - 1, maxi(-1, mems.size() - 1 - MAX_MEMORIES), -1):
		var m: Dictionary = mems[i]
		var line := "[color=#e8c170]D%d[/color] %s" % [int(m.get("day", 0)), str(m.get("text", ""))]
		recent.append(line)
		if absf(float(m.get("importance", 0.0))) >= 0.5:
			important.append(line)
		if str(m.get("counterpart", "")) != "":
			social.append("[color=#c0d8e8]%s[/color] %s" % [_short(str(m.get("counterpart", ""))), str(m.get("text", ""))])
	var out := "[color=#e8c170]── 最近记忆 ──[/color]\n" + "\n".join(recent)
	out += "\n[color=#e8c170]── 重要记忆 ──[/color]\n"
	out += "\n".join(important) if not important.is_empty() else "[color=#8899aa]无[/color]"
	out += "\n[color=#e8c170]── 社会记忆 ──[/color]\n"
	out += "\n".join(social) if not social.is_empty() else "[color=#8899aa]无[/color]"
	return out

func _decision_bbcode(sel: Dictionary) -> String:
	var decision: Dictionary = sel.get("decision", {})
	if decision.is_empty():
		return "[color=#8899aa]暂无决策数据[/color]"
	var out := ""
	out += "[color=#e8c170]当前计划[/color]：%s\n" % str(decision.get("plan", "—"))
	out += "[color=#e8c170]当前步骤[/color]：%s\n" % str(decision.get("step", "—"))
	out += "[color=#e8c170]理由[/color]：%s\n" % str(decision.get("reason", "—"))
	out += "[color=#e8c170]阻塞[/color]：%s\n" % str(decision.get("blocker", "无"))
	out += "[color=#e8c170]下一步意图[/color]：%s" % str(decision.get("next_step", "—"))
	return out

func _relations_bbcode(sel: Dictionary) -> String:
	var rows: Array = sel.get("relationship_rows", [])
	if rows.is_empty():
		return "[color=#8899aa]暂无关系数据[/color]"
	# 紧凑排版（v3.1 evidence）：视口仅容 ~9 逻辑行，名字并入维度行、
	# 变化轨迹仅在非空时显示，保证【关系】与【ToM】两区可同屏取证
	var out := "[color=#e8c170]── 关系（真实有向边）──[/color]
"
	for r in rows:
		out += "[color=#c0d8e8]%s[/color] 信任%s 善意%s 可靠性%s
" % [
			str(r.get("other_name", "?")),
			_sign(int(r.get("trust", 0))),
			_sign(int(r.get("benevolence", 0))),
			_sign(int(r.get("reliability", 0)))]
		out += "  亏欠%s 畏惧%s" % [
			_sign(int(r.get("obligation", 0))),
			_sign(int(r.get("fear", 0)))]
		var change := str(r.get("change", ""))
		if change != "":
			out += "  [color=#8899aa]变化：%s[/color]" % change
		out += "
"
	out += "[color=#e8c170]── 我对他的判断（Theory of Mind）──[/color]
"
	for r in rows:
		var tom: Dictionary = r.get("tom", {})
		if tom.is_empty():
			continue
		out += "[color=#c0d8e8]%s[/color] [color=#8899aa]有食%+.1f 慷慨%+.1f 可靠%+.1f[/color]
" % [
			str(r.get("other_name", "?")),
			float(tom.get("has_food", 0.0)), float(tom.get("generous", 0.0)), float(tom.get("reliable", 0.0))]
	return out

## 关系维度展示格式化（正数带 +，负数自带 -）
func _sign(v: int) -> String:
	return ("+" if v > 0 else "") + str(v)

func _history_bbcode(sel: Dictionary) -> String:
	var rows: Array = sel.get("history_rows", [])
	var dialogue: Array = sel.get("history_dialogue_rows", [])
	var chains: Array = sel.get("history_chain_rows", [])
	if rows.is_empty() and dialogue.is_empty() and chains.is_empty():
		return "[color=#8899aa]暂无历史数据[/color]"
	var out := "[color=#e8c170]── 最近事件 ──[/color]\n"
	if rows.is_empty():
		out += "[color=#8899aa]无[/color]\n"
	for r in rows:
		out += "[color=#aabbcc]D%d E%d[/color] %s\n" % [int(r.get("day", 0)), int(r.get("seq", 0)), str(r.get("text", ""))]
	out += "\n[color=#e8c170]── 最近对话 ──[/color]\n"
	if dialogue.is_empty():
		out += "[color=#8899aa]无[/color]\n"
	for dl in dialogue:
		out += "[color=#c0d8e8]D%d %s：[/color]%s\n" % [int(dl.get("day", 0)), str(dl.get("speaker", "")), str(dl.get("text", ""))]
	out += "\n[color=#e8c170]── 承诺 / 请求 / 行动链 ──[/color]\n"
	if chains.is_empty():
		out += "[color=#8899aa]无（等待 cause_seq 链数据）[/color]"
	for step in chains:
		out += "%s\n" % str(step)
	return out

func _personality_bbcode(sel: Dictionary) -> String:
	var personality: Dictionary = sel.get("personality", {})
	var traits: Array = personality.get("traits", [])
	var by_key := {}
	for t in traits:
		by_key[str(t.get("key", ""))] = t
	var out := ""
	if traits.is_empty():
		out += "[color=#8899aa]暂无特质数据\n[/color]"
	var groups := [
		["基础特质", ["resilience", "curiosity", "pragmatism"]],
		["气质与风险偏好", ["action_bias", "caution", "expressiveness", "conflict_avoidance"]],
		["社交倾向", ["empathy", "sociability", "altruism"]],
	]
	for group in groups:
		out += "[color=#e8c170]── %s ──[/color]\n" % str(group[0])
		for key in group[1]:
			if by_key.has(key):
				var t: Dictionary = by_key[key]
				out += "%s %s %.2f\n" % [str(t.get("label", key)), _bar(float(t.get("value", 0.0))), float(t.get("value", 0.0))]
		out += "\n"
	out = out.substr(0, out.length() - 1)
	var emotions: Array = personality.get("emotions", [])
	out += "\n[color=#e8c170]── 情绪 ──[/color]\n"
	if emotions.is_empty():
		out += "[color=#8899aa]平稳[/color]"
	else:
		var parts: Array = []
		for e in emotions:
			var label := str(EMOTION_LABELS.get(str(e.get("key", "")), str(e.get("key", "?"))))
			parts.append("%s%+.0f%%" % [label, float(e.get("value", 0.0)) * 100.0])
		out += " ".join(parts)
	var beliefs: Array = personality.get("beliefs", [])
	out += "\n[color=#e8c170]── 信念 ──[/color]\n"
	if beliefs.is_empty():
		out += "[color=#8899aa]暂无数据[/color]"
	else:
		for b in beliefs:
			out += "%s（%.1f）\n" % [str(b.get("text", "")), float(b.get("weight", 0.0))]
	return out

func _bar(value: float) -> String:
	var filled := int(round(clampf(value, 0.0, 1.0) * 5.0))
	var s := ""
	for i in 5:
		s += "▓" if i < filled else "·"
	return s

func _short(s: String) -> String:
	return s.substr(0, 4) if s.length() > 4 else s

## RichTextLabel 写 bbcode 必须走 append_text（.text 不解析标签）。
func _set_rtl_bbcode(page, bbcode: String) -> void:
	var rtl := page as RichTextLabel
	if rtl == null:
		return
	rtl.clear()
	rtl.append_text(bbcode)

func _fill_rtl(page, lines: Array) -> void:
	var rtl := page as RichTextLabel
	if rtl == null:
		return
	rtl.clear()
	if lines.is_empty():
		rtl.append_text("[color=#8899aa]暂无数据[/color]")
	else:
		rtl.append_text("\n".join(lines))
