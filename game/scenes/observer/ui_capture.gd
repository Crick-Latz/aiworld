extends Node
## UI-R1 截图工具（开发工具，不属于正式游戏流；归 m01 入口装配模块）。
## 用法（参数写在 -- 之后）：
##   mode=preview fixture=NPC_SELECTED tab=memory out=D:/abs/path.png frames=60
##   mode=observer select=npc_weila tab=overview bottom=events out=D:/abs/path.png frames=240
## 窗口尺寸由启动参数决定（默认 1920x1080；1366x768 用 --resolution 1366x768）。

const PREVIEW_SCENE := preload("res://scenes/ui/ui_preview.tscn")
const OBSERVER_SCENE := preload("res://scenes/observer/observer_main.tscn")

func _ready() -> void:
	await _run()

func _run() -> void:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var mode := str(args.get("mode", "preview"))
	var frames := int(args.get("frames", "90"))
	var out := str(args.get("out", ""))
	var hud: CanvasLayer = null
	if mode == "observer":
		var inst = OBSERVER_SCENE.instantiate()
		add_child(inst)
		await _wait_frames(20) # 装配 + 地形投影 + 首次 HUD 渲染
		var select := str(args.get("select", ""))
		if select != "" and inst.has_method("select_actor"):
			inst.select_actor(select)
			await _wait_frames(10)
		await _wait_frames(frames)
		hud = inst.get_node("ObserverHud")
	else:
		OS.set_environment("AIW_PREVIEW_FIXTURE", str(args.get("fixture", "DEFAULT")))
		var tab_env := str(args.get("tab", ""))
		if tab_env != "":
			OS.set_environment("AIW_PREVIEW_TAB", tab_env)
		var pv = PREVIEW_SCENE.instantiate()
		add_child(pv)
		await _wait_frames(maxi(10, frames))
		hud = pv.get_node("ObserverHud")
	var bottom := str(args.get("bottom", ""))
	if bottom != "" and hud != null:
		hud.set_timeline_tab(bottom)
	var tab_after := str(args.get("tab", ""))
	if tab_after != "" and mode == "observer" and hud != null:
		hud.set_inspector_tab(tab_after)
	# 证据工具：滚动当前 Inspector 页（RichTextLabel）到指定行，供 relations 等长页取证
	var scroll_line := str(args.get("scroll", ""))
	if scroll_line != "" and hud != null:
		var page = hud.pages.get(hud._inspector_tab if "_inspector_tab" in hud else tab_after, null)
		if page != null and page is RichTextLabel:
			var rtl := page as RichTextLabel
			rtl.scroll_to_line(int(scroll_line))
			print("UI_CAPTURE scrolled %s to line %s (lines=%d)" % [str(tab_after), scroll_line, rtl.get_line_count()])
	var dump := str(args.get("dump", ""))
	if dump != "" and hud != null:
		var page2 = hud.pages.get(tab_after, null)
		if page2 != null and page2 is RichTextLabel:
			var rng: PackedStringArray = dump.split("-", true, 1)
			var lo := int(rng[0])
			var hi := int(rng[1]) if rng.size() > 1 else lo
			var rtl2 := page2 as RichTextLabel
			for ln in range(lo, mini(hi + 1, rtl2.get_line_count())):
				var t: String = rtl2.get_line(ln).strip_edges()
				if t != "":
					print("DUMP %d|%s" % [ln, t])
	await _wait_frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var target := Vector2i(DisplayServer.window_get_size())
	if img.get_size() != target:
		img.resize(target.x, target.y, Image.INTERPOLATE_NEAREST)
	var err := img.save_png(out)
	print("UI_CAPTURE saved=%s err=%d size=%s" % [out, err, img.get_size()])
	get_tree().quit(0 if err == OK else 1)

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
