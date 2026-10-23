class_name PauseMenu
extends CanvasLayer
## Esc (or the gamepad's Start) pauses the game and opens this menu: Resume, Settings, a new
## maze, back to the main menu, quit. Works in any game scene; it only pauses the tree.

var _panel: Control
var _main_page: VBoxContainer
var _settings_page: SettingsPage
var _resume_button: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameInput.ensure_actions()
	_panel = Control.new()
	_panel.theme = MenuTheme.build()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(centre)
	var holder := VBoxContainer.new()
	centre.add_child(holder)
	_main_page = _build_main_page()
	_settings_page = SettingsPage.new()
	_settings_page.visible = false
	_settings_page.back_pressed.connect(func() -> void: _show_settings(false))
	holder.add_child(_main_page)
	holder.add_child(_settings_page)
	_panel.visible = false


func is_open() -> bool:
	return _panel.visible


func open() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_settings(false)
	_panel.visible = true
	get_tree().paused = true
	_resume_button.grab_focus()


func close() -> void:
	_panel.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_for_game()


## The mouse is captured while the player using it looks around in 3D, free otherwise.
func _mouse_mode_for_game() -> Input.MouseMode:
	for node in get_tree().get_nodes_in_group("camera_rig"):
		var rig := node as CameraRig
		if rig.uses_mouse and rig.mode != CameraRig.Mode.TOP:
			return Input.MOUSE_MODE_CAPTURED
	return Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	var pause := event.is_action_pressed(GameInput.PAUSE)
	var back := event.is_action_pressed(&"ui_cancel")
	if not (pause or back):
		return
	if not is_open():
		if pause:
			open()
	elif _settings_page.visible:
		_settings_page.go_back()
	elif pause:
		close()
	get_viewport().set_input_as_handled()


func _build_main_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	page.add_child(MenuTheme.title("Paused", 44))
	_resume_button = MenuTheme.button("Resume", close)
	page.add_child(_resume_button)
	page.add_child(MenuTheme.button("Settings", func() -> void: _show_settings(true)))
	page.add_child(MenuTheme.button("New maze", _new_maze))
	page.add_child(MenuTheme.button("Main menu", GameSession.to_menu))
	page.add_child(MenuTheme.button("Quit to desktop", GameSession.quit))
	return page


func _show_settings(shown: bool) -> void:
	_main_page.visible = not shown
	_settings_page.visible = shown
	if shown:
		_settings_page.focus_first()
	else:
		_resume_button.grab_focus()


## Throws the maze away and puts everyone back at the start of a fresh one.
func _new_maze() -> void:
	var manager := get_tree().get_first_node_in_group("maze_manager") as MazeManager
	if manager:
		manager.restart()
	close()
