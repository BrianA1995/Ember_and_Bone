extends Node
## Can a gamepad drive the menus? A presses the focused button, B backs out of settings.
## Run debug/pad_menu_test.tscn and read the output for "PAD MENU TEST".

var _failures := 0


func _ready() -> void:
	GameSettings.player_count = 2
	var menu := (load("res://ui/main_menu.tscn") as PackedScene).instantiate() as MainMenu
	add_child(menu)
	await _frames(2)
	var more: Button = menu._players_label.get_parent().get_child(2)
	more.grab_focus()
	await _tap(JOY_BUTTON_A)
	_check("A presses the focused button", GameSettings.player_count == 3, "%d players" % GameSettings.player_count)
	menu._show_settings(true)
	await _frames(2)
	await _tap(JOY_BUTTON_B)
	_check("B backs out of the settings", not menu._settings_page.visible and menu._main_page.visible, "")
	menu.queue_free()
	await _play_with_a_pad()
	GameSettings.player_count = 1
	print("PAD MENU TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## A gamepad player walks with the stick, and runs faster with the right bumper.
func _play_with_a_pad() -> void:
	GameSettings.player_count = 1
	GameSettings.controllers = [0, GameInput.DEVICE_ARROWS, 1, 2]
	GameInput.configure(1, GameSettings.controllers)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _frames(20)
	var player: Player = game.players[0]
	var walked := await _walk_distance(player, false)
	var ran := await _walk_distance(player, true)
	_check("the left stick walks the player", walked > 0.8, "%.2f m" % walked)
	_check("the right bumper makes the player run", ran > walked * 1.4, "%.2f m vs %.2f m" % [ran, walked])
	_check("the keyboard does nothing for a gamepad player", not Input.is_action_pressed(&"move_left"), "")
	game.queue_free()
	await _frames(2)
	GameSettings.controllers = GameInput.DEFAULT_DEVICES.duplicate()
	GameInput.configure(1)


## Holds the stick (and bumper) for a second and returns how far the player moved.
func _walk_distance(player: Player, sprint: bool) -> float:
	player.warp_to(Vector3(0.0, 0.8, 0.0))
	await _frames(5)
	var start := player.global_position
	_pad_axis(JOY_AXIS_LEFT_X, 1.0)
	if sprint:
		_pad_button(JOY_BUTTON_RIGHT_SHOULDER, true)
	for i in 60:
		await get_tree().physics_frame
	_pad_axis(JOY_AXIS_LEFT_X, 0.0)
	_pad_button(JOY_BUTTON_RIGHT_SHOULDER, false)
	await _frames(3)
	return player.global_position.distance_to(start)


func _pad_axis(axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)


func _pad_button(button: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = 0
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(1)
	var release := event.duplicate() as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
