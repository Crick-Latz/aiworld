extends CanvasLayer
## 观察 HUD（OBS-01，M15/23-B）：独立场景，只暴露 render(ViewModel) 与意图信号。
## 内部节点路径不外泄；不读写 Simulation 内部状态；修改布局不需改装配/模拟。

signal pause_requested
signal speed_requested(multiplier: int)
signal save_requested
signal scenario_requested(scenario_name: String)

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var tick_label: Label = $Panel/VBox/TickLabel
@onready var sel_name: Label = $Panel/VBox/SelPanel/VBox/SelName
@onready var sel_goal: Label = $Panel/VBox/SelPanel/VBox/SelGoal
@onready var sel_activity: Label = $Panel/VBox/SelPanel/VBox/SelActivity
@onready var sel_location: Label = $Panel/VBox/SelPanel/VBox/SelLocation
@onready var events_label: RichTextLabel = $Panel/VBox/EventsPanel/EventsLabel
@onready var pause_btn: Button = $Panel/VBox/BottomBar/PauseBtn
@onready var x1_btn: Button = $Panel/VBox/BottomBar/X1Btn
@onready var x2_btn: Button = $Panel/VBox/BottomBar/X2Btn
@onready var x4_btn: Button = $Panel/VBox/BottomBar/X4Btn
@onready var save_btn: Button = $Panel/VBox/BottomBar/SaveBtn
@onready var baseline_btn: Button = $Panel/VBox/BottomBar/BaselineBtn
@onready var control_btn: Button = $Panel/VBox/BottomBar/ControlBtn
@onready var lag_label: Label = $Panel/VBox/LagLabel
@onready var hint_label: Label = $HintLabel

func _ready() -> void:
	pause_btn.pressed.connect(func(): pause_requested.emit())
	x1_btn.pressed.connect(func(): speed_requested.emit(1))
	x2_btn.pressed.connect(func(): speed_requested.emit(2))
	x4_btn.pressed.connect(func(): speed_requested.emit(4))
	save_btn.pressed.connect(func(): save_requested.emit())
	baseline_btn.pressed.connect(func(): scenario_requested.emit("baseline"))
	control_btn.pressed.connect(func(): scenario_requested.emit("control"))

## model: {view_schema_version, state_revision, time_label, paused, speed_multiplier,
##         lag_ticks, selected_actor:{id,display_name,activity_text,goal_text,location_text}|null,
##         recent_events:[{seq,text,cause_seq,actor_ids}], warning_text}
func render(model: Dictionary) -> void:
	var warning := str(model.get("warning_text", ""))
	title_label.text = warning if warning != "" else "灰雾港 · 观察模式"
	tick_label.text = "%s · %s · %d×%s" % [
		str(model.get("time_label", "-")),
		"已暂停" if bool(model.get("paused", false)) else "运行中",
		int(model.get("speed_multiplier", 1)),
		(" · 滞后 %d tick" % int(model.get("lag_ticks", 0))) if int(model.get("lag_ticks", 0)) > 0 else ""]
	var sel = model.get("selected_actor", null)
	if sel != null and typeof(sel) == TYPE_DICTIONARY:
		sel_name.text = "姓名：%s" % str(sel.get("display_name", "-"))
		sel_goal.text = "目标：%s" % str(sel.get("goal_text", "-"))
		sel_activity.text = "活动：%s" % str(sel.get("activity_text", "-"))
		sel_location.text = "地点：%s" % str(sel.get("location_text", "-"))
		var inv_text: String = str(sel.get("inventory_text", ""))
		if inv_text != "":
			sel_location.text += "\n物资：%s" % inv_text
	else:
		sel_name.text = "姓名：—"
		sel_goal.text = "目标：—"
		sel_activity.text = "活动：—"
		sel_location.text = "地点：—"
	var world_facts: String = str(model.get("world_facts_text", ""))
	if world_facts != "":
		tick_label.text += "\n" + world_facts
	var events: Array = model.get("recent_events", [])
	var lines: Array = []
	for e in events.slice(maxi(0, events.size() - 14), events.size()):
		lines.append("[color=#aabbcc]%d[/color] %s" % [int(e.get("seq", 0)), str(e.get("text", ""))])
	events_label.clear()
	events_label.append_text("\n".join(lines))
	var lag: int = int(model.get("lag_ticks", 0))
	lag_label.visible = lag > 0
	if lag > 0:
		lag_label.text = "⚠ 模拟滞后 %d tick（欠账保留，不丢帧）" % lag
	var hint := str(model.get("hint_text", ""))
	if hint != "":
		hint_label.text = hint
