extends CanvasLayer
## UI-R2 观察 HUD：七页大脑观察器（概览/决策/计划/认知/关系/记忆/社会）+ 底部时间线。
## 只消费 ViewModel 字典（大脑 ViewModel 由 NpcBrainViewModel 组装，schema 0.3）；
## 每个数据块带 provenance 徽章：[事实] objective / [主观] subjective / [推导] derived。
## 契约（observer_sim.gd 依赖）：render(model)、tick_label 含 "N×"、sel_name 含角色名、
## events_label 解析文本含事件文本；信号 pause/speed/save/scenario 不变。
## 节点复用：静态结构全部在 tscn，4Hz 刷新只更新文本/bbcode，不重建 Inspector 树。

signal pause_requested
signal speed_requested(multiplier: int)
signal save_requested
signal scenario_requested(scenario_name: String)

const INSPECTOR_TABS := ["overview", "decision", "plan", "mind", "relations", "memory", "social"]
const TIMELINE_TABS := ["events", "stories", "dialogue", "causal"]
const EMOTION_LABELS := {"joy": "喜悦", "fear": "担忧", "anger": "愤怒", "sadness": "悲伤", "guilt": "内疚"}
const MAX_EVENT_LINES := 14
const RAW_SNIPPET_LEN := 240

## 语义色（集中定义——§47 不散写；控件色走 Theme）
const C_GOLD := "#e8c170"
const C_BLUE := "#7ab8d4"
const C_GRAY := "#9a9a8a"
const C_BODY := "#c0d8e8"
const C_DIM := "#8899aa"
const C_POS := "#8ac964"
const C_NEG := "#e07a5f"
const C_ACTIVE := "#e8c170"
const C_BLOCK := "#e07a5f"
const PLAN_STATUS := {
	"DONE": {"icon": "✓", "color": C_POS}, "ACTIVE": {"icon": "▶", "color": C_ACTIVE},
	"BLOCKED": {"icon": "!", "color": C_BLOCK}, "PENDING": {"icon": "…", "color": C_DIM},
	"FAILED": {"icon": "×", "color": C_NEG}, "CANCELLED": {"icon": "–", "color": C_DIM},
	"SUSPENDED": {"icon": "!", "color": C_BLOCK}, "CURRENT": {"icon": "▶", "color": C_ACTIVE},
	"UNKNOWN": {"icon": "?", "color": C_DIM},
}

var _inspector_tab := "overview"
var _timeline_tab := "events"
var _timeline_autopicked := false
var _timeline_expanded := false
var _memory_filter := "all"
var _last_brain: Dictionary = {}

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
@onready var sel_name: Label = $Root/InspectorPanel/InsMargin/InsVBox/HeaderH/SelName
@onready var sel_status: Label = $Root/InspectorPanel/InsMargin/InsVBox/HeaderH/StatusLabel
@onready var needs_label: RichTextLabel = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/OverviewPage
@onready var events_label: RichTextLabel = $Root/BottomPanel/BotMargin/BotVBox/PagesH/EventsLabel
@onready var hint_label: Label = $Root/HintLabel
@onready var inspector_panel: PanelContainer = $Root/InspectorPanel
@onready var bottom_pages: Control = $Root/BottomPanel/BotMargin/BotVBox/PagesH
@onready var bottom_panel: PanelContainer = $Root/BottomPanel
@onready var memory_list: RichTextLabel = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/MemoryPage/MemoryList
var tab_buttons := {}
var timeline_buttons := {}
var pages := {}
var timeline_pages := {}
var memory_filter_buttons := {}

var _menu: PopupMenu

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
	var filter_row: HBoxContainer = $Root/InspectorPanel/InsMargin/InsVBox/PagesV/MemoryPage/MemoryFilterRow
	for filter_name in ["all", "social", "important", "recent"]:
		var node_name: String = {"all": "FilterAll", "social": "FilterSocial", "important": "FilterImportant", "recent": "FilterRecent"}[filter_name]
		var fbtn: Button = filter_row.get_node(NodePath(node_name))
		fbtn.pressed.connect(func(): _set_memory_filter(filter_name))
		memory_filter_buttons[filter_name] = fbtn
	inspector_panel.visible = false # 未选中即收起
	_apply_timeline_collapse(false) # 默认收起：面板真的只有 tab 条高度
	_set_inspector_tab(_inspector_tab)
	_set_timeline_tab(_timeline_tab)

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

## 记忆筛选（纯 presentation filter，不改模拟状态）
func _set_memory_filter(filter_name: String) -> void:
	_memory_filter = filter_name
	for name_key in memory_filter_buttons:
		(memory_filter_buttons[name_key] as Button).set_pressed_no_signal(str(name_key) == filter_name)
	if not _last_brain.is_empty():
		_render_memory(_last_brain)

## model 见 docs/ui/OBSERVER_VIEW_MODEL.md（view_schema_version 0.3）
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

# ————— provenance 徽章与工具 —————

func _prov(p: String) -> String:
	match p:
		"objective": return "[color=%s][事实][/color]" % C_GOLD
		"derived": return "[color=%s][推导][/color]" % C_GRAY
		_: return "[color=%s][主观][/color]" % C_BLUE

func _bar(frac: float, cells: int = 8) -> String:
	var filled := int(round(clampf(frac, 0.0, 1.0) * float(cells)))
	var s := ""
	for i in cells:
		s += "▓" if i < filled else "·"
	return s

func _fmt_signed(v: int) -> String:
	return ("+" if v > 0 else "") + str(v)

func _fmt_float(v: float) -> String:
	return "%+.2f" % v

func _set_rtl(page, bbcode: String) -> void:
	var rtl := page as RichTextLabel
	if rtl == null:
		return
	rtl.clear()
	rtl.append_text(bbcode)

func _raw_snippet(data) -> String:
	var s := JSON.stringify(data, "  ")
	if s.length() > RAW_SNIPPET_LEN:
		s = s.substr(0, RAW_SNIPPET_LEN) + "…"
	return s

# ————— 选中渲染 —————

func _render_selection(sel) -> void:
	inspector_panel.visible = sel != null and typeof(sel) == TYPE_DICTIONARY
	if not (sel != null and typeof(sel) == TYPE_DICTIONARY):
		sel_name.text = "未选中"
		sel_status.text = "点击世界中的角色"
		_last_brain = {}
		return
	_last_brain = sel
	sel_name.text = str(sel.get("display_name", "-"))
	sel_status.text = str(sel.get("status_text", sel.get("activity_text", "-")))
	_render_needs(sel)
	_render_decision(sel)
	_render_plan(sel)
	_render_mind(sel)
	_render_relations(sel)
	_render_memory(sel)
	_render_social(sel)

## 概览：needs bars（fatigue 为 1000-energy 的推导换算，显式标注）+ 情绪 + 最重要问题
func _render_needs(sel: Dictionary) -> void:
	var needs: Dictionary = sel.get("needs", {})
	var rows: Array = needs.get("rows", [])
	var lines: Array = []
	lines.append("目标：%s" % (str(sel.get("goal_text", "")) if str(sel.get("goal_text", "")) != "" else "—"))
	lines.append("位置：%s" % str(sel.get("location_text", "—")))
	var inv: Array = sel.get("inventory_items", [])
	if inv.is_empty():
		lines.append("物资：—")
	else:
		var parts: Array = []
		for item in inv:
			parts.append("%s×%d" % [str(item.get("id", "?")), int(item.get("count", 0))])
		lines.append("物资：%s %s" % ["、".join(parts), _prov("objective")])
	lines.append("")
	lines.append("[color=%s]── 需求 ──[/color]" % C_GOLD)
	for row in rows:
		var note := ""
		if str(row.get("key", "")) == "fatigue":
			note = " %s(=1000-energy)" % _prov("derived")
		lines.append("%s %s %4d%s" % [str(row.get("label", "?")), _bar(float(row.get("frac", 0.0))), int(row.get("value", 0)), note])
	var emotions: Dictionary = sel.get("emotions", {})
	var dominant: Dictionary = emotions.get("dominant", {})
	lines.append("")
	lines.append("[color=%s]── 情绪 ──[/color] 主导：%s %s %s" % [C_GOLD, str(dominant.get("label", "平静")),
		_fmt_float(float(dominant.get("value", 0.0))),
		_prov(str(dominant.get("provenance", "derived")))])
	for e in emotions.get("rows", []):
		lines.append("%s %s %+.2f" % [str(e.get("label", "?")), _bar(absf(float(e.get("value", 0.0)))), float(e.get("value", 0.0))])
	var pq: Dictionary = sel.get("mind", {}).get("primary_question", {})
	lines.append("")
	if pq.is_empty():
		lines.append("[color=%s]当前最重要问题：[/color]无明确疑问" % C_GOLD)
	else:
		# 问题内容是角色主观；“哪条最重要”是 presentation 按 stakes/tick 排序 → [推导]
		lines.append("[color=%s]当前最重要问题：[/color]%s %s" % [C_GOLD, _question_text(pq),
			_prov(str(pq.get("provenance", "derived")))])
	lines.append("")
	lines.append(_why_bbcode(sel))
	_set_rtl(needs_label, "\n".join(lines))

func _question_text(q: Dictionary) -> String:
	var kind_text: String = {"why_refused": "不明白 %s 为什么拒绝我"}.get(str(q.get("kind", "")), "")
	if kind_text != "":
		return kind_text % str(q.get("about_name", str(q.get("about", ""))))
	return "关于 %s 的疑问（%s）" % [str(q.get("about_name", str(q.get("about", "")))), str(q.get("kind", ""))]

## Why chain（确定性；节点带 provenance；LLM 不参与）
## Why（fail-closed）：整体 [推导]；决策理由（trace.reason）优先；
## 因果箭头只出现在 decision trace / live accessor 支持的节点之间；
## 需求/情绪只进“当前上下文”（无箭头，不冒充原因）。
func _why_bbcode(sel: Dictionary) -> String:
	var why: Dictionary = sel.get("why", {})
	var lines: Array = ["[color=%s]── 为什么这样做？──[/color] %s" % [C_GOLD, _prov(str(why.get("provenance", "derived")))]]
	var reason: Dictionary = why.get("decision_reason", {})
	if not reason.is_empty():
		lines.append("[color=%s]决策理由：[/color]%s %s" % [C_GOLD, str(reason.get("text", "")),
			_prov(str(reason.get("provenance", "subjective")))])
	var nodes: Array = why.get("nodes", [])
	if nodes.is_empty():
		lines.append("[color=%s]暂无因果链（等待决策留痕）[/color]" % C_DIM)
	for i in range(nodes.size()):
		var node: Dictionary = nodes[i]
		lines.append("%s %s" % [str(node.get("label", "")), _prov(str(node.get("provenance", "subjective")))])
		if i < nodes.size() - 1:
			lines.append("[color=%s]  ↓[/color] %s" % [C_DIM, _link_mark(why, i)])
	var context: Array = why.get("context", [])
	if not context.is_empty():
		lines.append("")
		lines.append("[color=%s]── 当前上下文 ──[/color] %s" % [C_GRAY, _prov("derived")])
		for row in context:
			lines.append("%s %s" % [str(row.get("label", "")), _prov(str(row.get("provenance", "derived")))])
	return "\n".join(lines)

## 链接标注：记录级链接[主观]不显示文字；显式 [推导] 链接标 (推导)
func _link_mark(why: Dictionary, index: int) -> String:
	var links: Array = why.get("links", [])
	if index >= links.size():
		return ""
	var link: Dictionary = links[index]
	if str(link.get("provenance", "")) == "derived":
		return "[color=%s](推导)[/color]" % C_GRAY
	return ""

## 计划流内相邻节点的 ↓ 是 presentation 排列（无显式因果证据字段）→ [推导]
func _link_mark_plan() -> String:
	return "[color=%s](推导)[/color]" % C_GRAY

## 决策页：当前决定/为什么/行动/阻塞/下一步 + 真实候选效用表 + Raw 节选
func _render_decision(sel: Dictionary) -> void:
	var d: Dictionary = sel.get("decision", {})
	var lines: Array = []
	lines.append("[color=%s]── 当前决定 ──[/color] %s %s" % [C_GOLD, str(d.get("chosen", "—")), _prov("subjective")])
	lines.append("[color=%s]为什么：[/color]%s" % [C_GOLD, str(d.get("reason", "")) if str(d.get("reason", "")) != "" else "—"])
	lines.append("[color=%s]当前行动：[/color]%s %s" % [C_GOLD, str(d.get("current_action", "—")), _prov("objective")])
	lines.append("[color=%s]阻塞：[/color]%s" % [C_GOLD, str(d.get("blocker", "")) if str(d.get("blocker", "")) != "" else "无"])
	lines.append("[color=%s]下一步：[/color]%s" % [C_GOLD, str(d.get("next_step", "")) if str(d.get("next_step", "")) != "" else "—"])
	var interp := str(d.get("dominant_interpretation", ""))
	if interp != "":
		lines.append("[color=%s]他对局面的解读：[/color]%s" % [C_GOLD, interp])
	var candidates: Array = d.get("candidates", [])
	if not candidates.is_empty():
		lines.append("")
		lines.append("[color=%s]── 候选行为（真实效用）──[/color] %s" % [C_GOLD, _prov("subjective")])
		for c in candidates:
			var mark := " ←" if bool(c.get("chosen", false)) else ""
			var col: String = C_ACTIVE if bool(c.get("chosen", false)) else C_BODY
			lines.append("[color=%s]%s  %.2f%s[/color]" % [col, str(c.get("action", "?")), float(c.get("utility", 0.0)), mark])
	else:
		lines.append("")
		lines.append("[color=%s]候选效用：[/color][color=%s]本轮无决策留痕（ViewModel gap: decision_candidates 于无决策 tick 时为空）[/color]" % [C_GOLD, C_DIM])
	lines.append("")
	lines.append("[color=%s]▸ Raw（节选）[/color] %s" % [C_GRAY, _raw_snippet(d)])
	_set_rtl(pages["decision"], "\n".join(lines))

## 计划页：竖向 flow（目标→计划→步骤→阻塞→子目标），状态图标与色集中定义
func _render_plan(sel: Dictionary) -> void:
	var p: Dictionary = sel.get("plan", {})
	var nodes: Array = p.get("nodes", [])
	var lines: Array = ["[color=%s]── 计划流 ──[/color] %s" % [C_GOLD, _prov("subjective")]]
	if nodes.is_empty():
		lines.append("[color=%s]暂无计划/执行留痕（无 live run，也无 decision trace）[/color]" % C_DIM)
	var current_section := ""
	for i in range(nodes.size()):
		var n: Dictionary = nodes[i]
		var section := str(n.get("section", ""))
		if section != current_section:
			if section != "":
				lines.append("")
				if section == "live":
					lines.append("[color=%s]── 当前执行 LIVE ──[/color] %s" % [C_ACTIVE, _prov("subjective")])
				elif section == "snapshot":
					lines.append("[color=%s]── 上次决策快照 ──[/color] %s" % [C_GRAY, _prov("subjective")])
			current_section = section
		elif not bool(n.get("no_arrow_in", false)) and str(nodes[i - 1].get("section", "")) == section:
			lines.append("[color=%s]  ↓[/color] %s" % [C_DIM, _link_mark_plan()])
		var status := str(n.get("status", "PENDING"))
		var style: Dictionary = PLAN_STATUS.get(status, PLAN_STATUS["PENDING"])
		var value := str(n.get("value", ""))
		var line := "[color=%s]%s[/color] %s" % [str(style["color"]), str(style["icon"]), str(n.get("label", ""))]
		if value != "":
			line += " [color=%s]%s[/color]" % [C_DIM, value]
		lines.append(line)
	lines.append("")
	lines.append("[color=%s]图例：[/color][color=%s]✓完成[/color] [color=%s]▶进行[/color] [color=%s]!阻塞[/color] [color=%s]…待定[/color] [color=%s]×失败[/color] [color=%s]–取消[/color] [color=%s]?未知[/color]" % [
		C_DIM, C_POS, C_ACTIVE, C_BLOCK, C_DIM, C_NEG, C_DIM, C_DIM])
	var lr: Dictionary = p.get("live_run", {})
	if not lr.is_empty():
		lines.append("")
		lines.append("[color=%s]▸ LIVE run（公开 accessor agency_plan_run）[/color] %s" % [C_GRAY,
			_raw_snippet({"run_id": lr.get("run_id", ""), "plan_id": lr.get("plan_id", ""),
				"state": lr.get("state", ""), "current_step_id": lr.get("current_step_id", "")})])
	var ex: Dictionary = p.get("execution", {})
	if not ex.is_empty():
		lines.append("")
		lines.append("[color=%s]▸ Raw（决策时执行留痕节选）[/color] %s" % [C_GRAY, _raw_snippet(ex)])
	_set_rtl(pages["plan"], "\n".join(lines))

## 认知页：特质 bars + 信念(weight) + 未解之问 + ToM 动态谓词知识 + last seen
func _render_mind(sel: Dictionary) -> void:
	var lines: Array = []
	var personality: Dictionary = sel.get("personality", {})
	lines.append("[color=%s]── 特质 ──[/color] %s" % [C_GOLD, _prov("objective")])
	for t in personality.get("traits", []):
		lines.append("%s %s %.2f" % [str(t.get("label", "?")), _bar(float(t.get("value", 0.0))), float(t.get("value", 0.0))])
	var beliefs: Array = personality.get("beliefs", [])
	if not beliefs.is_empty():
		lines.append("")
		lines.append("[color=%s]── 信念 ──[/color] %s" % [C_GOLD, _prov("subjective")])
		for b in beliefs:
			lines.append("“%s” %.2f" % [str(b.get("text", "")), float(b.get("weight", 0.0))])
	var mind: Dictionary = sel.get("mind", {})
	var questions: Array = mind.get("open_questions", [])
	lines.append("")
	lines.append("[color=%s]── 未解之问 ──[/color] %s" % [C_GOLD, _prov("subjective")])
	if questions.is_empty():
		lines.append("[color=%s]当前没有明确疑问[/color]" % C_DIM)
	for q in questions:
		lines.append("· %s（熵 %.2f 利害 %.2f）" % [_question_text(q), float(q.get("entropy", 0.0)), float(q.get("stakes", 0.0))])
	var subjects: Array = mind.get("tom_subjects", [])
	lines.append("")
	lines.append("[color=%s]── 我知道什么（对他人的判断）──[/color] %s" % [C_GOLD, _prov("subjective")])
	if subjects.is_empty():
		lines.append("[color=%s]尚未形成对他人的判断[/color]" % C_DIM)
	for subject in subjects:
		lines.append("[color=%s]关于 %s[/color]" % [C_BODY, str(subject.get("other_name", "?"))])
		for row in subject.get("rows", []):
			lines.append("  %s %s 置信%.2f 证据tick %d" % [
				str(row.get("label", "?")), _fmt_float(float(row.get("value", 0.0))),
				float(row.get("confidence", 0.0)), int(row.get("last_evidence_tick", -1))])
		var seen: Dictionary = subject.get("last_seen", {})
		if not seen.is_empty():
			var tile: Vector2i = seen.get("tile", Vector2i.ZERO)
			lines.append("  [color=%s]最后看到：( %d, %d ) tick %d（可能过时）[/color]" % [C_DIM, tile.x, tile.y, int(seen.get("tick", -1))])
	var perr := float(mind.get("prediction_error", 0.0))
	lines.append("")
	lines.append("[color=%s]心智模型预测误差：[/color]%.3f %s" % [C_GOLD, perr, _prov("subjective")])
	_set_rtl(pages["mind"], "\n".join(lines))

## 关系页：真实关系边（有向）与 ToM 判断两层分离（R1 语义保持）
func _render_relations(sel: Dictionary) -> void:
	var rows: Array = sel.get("relationships", {}).get("rows", [])
	if rows.is_empty():
		_set_rtl(pages["relations"], "[color=%s]暂无关系数据[/color]" % C_DIM)
		return
	var me := str(sel.get("display_name", "?"))
	var lines: Array = ["[color=%s]── 关系（真实有向边）──[/color] %s" % [C_GOLD, _prov("objective")]]
	for r in rows:
		lines.append("[color=%s]%s → %s[/color] 信任%s 善意%s 可靠性%s" % [C_BODY, me, str(r.get("other_name", "?")),
			_fmt_signed(int(r.get("trust", 0))), _fmt_signed(int(r.get("benevolence", 0))), _fmt_signed(int(r.get("reliability", 0)))])
		lines.append("  亏欠%s 畏惧%s" % [_fmt_signed(int(r.get("obligation", 0))), _fmt_signed(int(r.get("fear", 0)))])
	lines.append("")
	lines.append("[color=%s]── 我对他的判断（Theory of Mind）──[/color] %s" % [C_GOLD, _prov("subjective")])
	for r in rows:
		var tom: Dictionary = r.get("tom", {})
		if tom.is_empty():
			continue
		lines.append("[color=%s]%s[/color] 有食%s 慷慨%s 可靠%s" % [C_BODY, str(r.get("other_name", "?")),
			_fmt_float(float(tom.get("has_food", 0.0))), _fmt_float(float(tom.get("generous", 0.0))), _fmt_float(float(tom.get("reliable", 0.0)))])
	_set_rtl(pages["relations"], "\n".join(lines))

## 记忆页：卡片 + 筛选（all/social/important/recent；day 与 importance 为推导）
func _render_memory(sel: Dictionary) -> void:
	var rows: Array = sel.get("memories", {}).get("rows", [])
	var filtered: Array = []
	match _memory_filter:
		"social":
			for r in rows:
				if str(r.get("counterpart", "")) != "":
					filtered.append(r)
		"important":
			for r in rows:
				if absf(float(r.get("derived_importance", 0.0))) >= 0.5:
					filtered.append(r)
		"recent":
			filtered = rows.slice(0, mini(5, rows.size()))
		_:
			filtered = rows
	var lines: Array = []
	if filtered.is_empty():
		lines.append("[color=%s]该筛选下无记忆[/color]" % C_DIM)
	for r in filtered:
		var imp := float(r.get("derived_importance", 0.0))
		var imp_col: String = C_ACTIVE if absf(imp) >= 0.5 else C_DIM
		lines.append("[color=%s]D%d E%d[/color] %s" % [C_DIM, int(r.get("day", 0)), int(r.get("seq", 0)), str(r.get("text", ""))])
		lines.append("  [color=%s]类型 %s [color=%s]重要度%.2f%s[/color][/color]" % [C_DIM, str(r.get("type", "")), imp_col, imp, _prov("derived")])
	_set_rtl(memory_list, "\n".join(lines))

## 社会页：承诺台账（只读过滤）+ 请求/持有者情报/社会事件（事件尾部派生）
func _render_social(sel: Dictionary) -> void:
	var social: Dictionary = sel.get("social", {})
	var lines: Array = []
	lines.append("[color=%s]── 承诺 / 亏欠 ──[/color] %s" % [C_GOLD, _prov("objective")])
	var commitments: Array = social.get("commitments", [])
	if commitments.is_empty():
		lines.append("[color=%s]无未了承诺[/color]" % C_DIM)
	for c in commitments:
		lines.append("%s %s：%s×%d [%s] 到期tick %d" % [
			str(c.get("direction", "")), str(c.get("counterpart_name", "?")),
			str(c.get("object", "?")), int(c.get("quantity", 0)),
			str(c.get("status", "")), int(c.get("due_tick", -1))])
	var requests: Array = social.get("recent_requests", [])
	lines.append("")
	lines.append("[color=%s]── 最近物资请求 ──[/color] %s" % [C_GOLD, _prov("objective")])
	if requests.is_empty():
		lines.append("[color=%s]无（ViewModel gap: active_material_requests——仅事件派生）[/color]" % C_DIM)
	for r in requests.slice(0, 6):
		lines.append("[color=%s]D%d E%d[/color] %s" % [C_DIM, int(r.get("day", 0)), int(r.get("seq", 0)), str(r.get("text", ""))])
	var holder: Array = social.get("holder_events", [])
	lines.append("")
	lines.append("[color=%s]── 持有者情报 ──[/color] %s" % [C_GOLD, _prov("objective")])
	if holder.is_empty():
		lines.append("[color=%s]无[/color]" % C_DIM)
	for r in holder.slice(0, 6):
		lines.append("[color=%s]D%d E%d[/color] %s" % [C_DIM, int(r.get("day", 0)), int(r.get("seq", 0)), str(r.get("text", ""))])
	var source_info: Array = social.get("source_information_events", [])
	lines.append("")
	lines.append("[color=%s]── 资源来源情报 ──[/color] %s" % [C_GOLD, _prov("objective")])
	if source_info.is_empty():
		lines.append("[color=%s]无[/color]" % C_DIM)
	for r in source_info.slice(0, 6):
		lines.append("[color=%s]D%d E%d[/color] %s" % [C_DIM, int(r.get("day", 0)), int(r.get("seq", 0)), str(r.get("text", ""))])
	var events: Array = social.get("recent_social_events", [])
	lines.append("")
	lines.append("[color=%s]── 最近社会事件 ──[/color]" % C_GOLD)
	if events.is_empty():
		lines.append("[color=%s]无[/color]" % C_DIM)
	for r in events.slice(0, 8):
		lines.append("[color=%s]D%d E%d[/color] %s" % [C_DIM, int(r.get("day", 0)), int(r.get("seq", 0)), str(r.get("text", ""))])
	_set_rtl(pages["social"], "\n".join(lines))

# ————— 底部时间线（R1 语义保持） —————

func _render_timeline(model: Dictionary) -> void:
	var lines: Array = []
	var chronicle: String = str(model.get("chronicle_text", ""))
	if chronicle != "":
		lines.append(chronicle)
	var events: Array = model.get("recent_events", [])
	for e in events.slice(maxi(0, events.size() - MAX_EVENT_LINES), events.size()):
		lines.append("[color=#aabbcc]%d[/color] %s" % [int(e.get("seq", 0)), str(e.get("text", ""))])
	events_label.clear()
	events_label.append_text("\n".join(lines) if not lines.is_empty() else "[color=#8899aa]暂无事件[/color]")
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
	_set_rtl(timeline_pages["stories"], "
".join(s_lines))
	var dialogue: Array = model.get("dialogue_transcript", [])
	var d_lines: Array = []
	if dialogue.is_empty():
		d_lines.append("[color=#8899aa]暂无对话[/color]")
	else:
		for dl in dialogue.slice(maxi(0, dialogue.size() - 8), dialogue.size()):
			d_lines.append("[color=#c0d8e8]%s：[/color]%s [color=#667788](%s)[/color]" % [
				str(dl.get("speaker", "")), str(dl.get("text", "")), str(dl.get("act", ""))])
	_set_rtl(timeline_pages["dialogue"], "
".join(d_lines))
	var chains: Array = model.get("causal_chains", [])
	var c_lines: Array = []
	if chains.is_empty():
		c_lines.append("[color=#8899aa]暂无因果链数据[/color]")
	else:
		for chain in chains:
			c_lines.append("[color=#e8c170]%s[/color]" % str(chain.get("title", "链")))
			for step in chain.get("steps", []):
				c_lines.append("  %s" % str(step))
	_set_rtl(timeline_pages["causal"], "
".join(c_lines))
	if not _timeline_autopicked:
		_timeline_autopicked = true
		if not events.is_empty():
			_set_timeline_tab("events")
		elif not threads.is_empty() or not (model.get("narrative_sentences", []) as Array).is_empty():
			_set_timeline_tab("stories")
