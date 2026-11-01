class_name PauseMenu
extends CanvasLayer
## Esc (or the gamepad's Start) pauses the game and opens this menu: Resume, Settings, a new maze, back to the
## main menu, quit. It is a MenuShell over a frosted copy of the frozen game, so it looks and navigates like the
## main menu. Works in any game scene; it only pauses the tree.

## The maze and the players' camera rigs of the game this menu pauses; set them with setup() before it opens.
var maze: MazeManager
var rigs: Array[CameraRig] = []

var shell := MenuShell.new()
var settings_page := SettingsPage.new()

var _pause_page := MenuPage.new()
var _resume_button: Button


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameInput.ensure_actions()
	shell.shade = MenuShell.Shade.BLUR
	shell.heading = "PAUSED"
	shell.visible = false
	add_child(shell)
	_build_pause_page()
	settings_page.back_pressed.connect(shell.back)
	shell.backed_out.connect(close)
	shell.add_page(&"pause", _pause_page)
	shell.add_page(&"settings", settings_page)


func setup(p_maze: MazeManager, p_rigs: Array[CameraRig]) -> void:
	maze = p_maze
	rigs = p_rigs
	settings_page.rigs = p_rigs


func is_open() -> bool:
	return shell.visible


func open() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	shell.visible = true
	shell.reset_to(&"pause")
	get_tree().paused = true


func close() -> void:
	shell.visible = false
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_for_game()


## Shows the settings page.
func show_settings() -> void:
	shell.open_page(&"settings")


## The mouse is captured while the player using it looks around in 3D, free otherwise.
func _mouse_mode_for_game() -> Input.MouseMode:
	for rig in rigs:
		if rig.uses_mouse and rig.mode != CameraRig.Mode.TOP:
			return Input.MOUSE_MODE_CAPTURED
	return Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(GameInput.PAUSE):
		return
	# The shell has already taken Esc as "back" when the menu is open; this is the pause button itself.
	if is_open():
		shell.back()
	else:
		open()
	get_viewport().set_input_as_handled()


func _build_pause_page() -> void:
	_resume_button = MenuTheme.button("Resume", close, true)
	_pause_page.add_child(_resume_button)
	_pause_page.add_child(MenuTheme.button("Settings", show_settings))
	_pause_page.add_child(MenuTheme.button("New maze", _new_maze))
	_pause_page.add_child(MenuTheme.button("Main menu", GameSession.to_menu))
	_pause_page.add_child(MenuTheme.button("Quit to desktop", GameSession.quit))


## Throws the maze away and puts everyone back at the start of a fresh one.
func _new_maze() -> void:
	maze.restart()
	close()
