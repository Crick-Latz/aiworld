extends Node
## 暂停控制器（WP-04）。process_mode = PROCESS_MODE_ALWAYS（在 tscn 设置）。
## Esc 只切换暂停/继续；暂停时 get_tree().paused=true（玩家物理、相机跟随/Tween、
## 交互随 PAUSABLE 停止）；继续按钮或再按 Esc 恢复；退出按钮 quit(0)。
## world_active=false（如错误页）时 Esc 不响应，不显示可继续游玩的世界。

signal pause_changed(paused: bool)

var world_active := true

var _menu: Control = null

func setup(menu: Control) -> void:
	_menu = menu
	if _menu == null:
		return
	_menu.visible = false
	var continue_btn: Button = _menu.get_node_or_null("Panel/VBox/ContinueBtn")
	var quit_btn: Button = _menu.get_node_or_null("Panel/VBox/QuitBtn")
	if continue_btn:
		continue_btn.pressed.connect(resume)
	if quit_btn:
		quit_btn.pressed.connect(_quit)

func set_world_active(active: bool) -> void:
	world_active = active
	if not active and is_paused():
		resume()

func is_paused() -> bool:
	return get_tree().paused

func toggle() -> void:
	if is_paused():
		resume()
	else:
		pause()

func pause() -> void:
	if not world_active or is_paused():
		return
	get_tree().paused = true
	if _menu:
		_menu.visible = true
	pause_changed.emit(true)

func resume() -> void:
	if not is_paused():
		return
	get_tree().paused = false
	if _menu:
		_menu.visible = false
	pause_changed.emit(false)

func _quit() -> void:
	get_tree().paused = false
	get_tree().quit(0)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("cancel"):
		toggle()
		get_viewport().set_input_as_handled()
