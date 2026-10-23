extends Node
## Starts the real game scene for 1 to 4 local players and checks the co-op layer: every player
## has a body, a rig and a view, the views tile the window, each player's own input moves only
## them, and the pause menu stops and restarts the game.
## Run debug/local_coop_test.tscn and read the output for "LOCAL COOP TEST".

var _failures := 0


func _ready() -> void:
	for count in range(1, GameInput.SLOTS + 1):
		await _try_players(count)
	await _try_pause()
	await _try_controllers()
	_check_rects()
	print("LOCAL COOP TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _try_players(count: int) -> void:
	print("-- %d player(s)" % count)
	GameSettings.player_count = count
	GameInput.configure(count)
	var game := await _start_game()
	_check("%d bodies, rigs and views" % count,
			game.players.size() == count and game.rigs.size() == count and game.get_node("Views/SplitScreen").view_count() == count,
			"%d / %d / %d" % [game.players.size(), game.rigs.size(), game.get_node("Views/SplitScreen").view_count()])
	var spots := {}
	for player in game.players:
		spots[player.global_position] = true
	_check("nobody starts on top of anybody", spots.size() == count, "")
	for i in count:
		_check("rig %d follows body %d" % [i + 1, i + 1], game.rigs[i].target == game.players[i] and game.rigs[i].slot == i, "")
		_check("rig %d's camera is in its own view" % [i + 1], game.rigs[i].get_camera().get_viewport() is SubViewport, "")
	# Only the player whose action is pressed moves.
	var before: Array[Vector3] = []
	for player in game.players:
		before.append(player.global_position)
	var mover := count - 1
	var action := GameInput.action(mover, &"move_right")
	Input.action_press(action)
	await _wait(0.5)
	Input.action_release(action)
	for i in count:
		var moved: bool = game.players[i].global_position.distance_to(before[i]) > 0.3
		_check("player %d %s when only player %d presses right" % [i + 1, "moves" if i == mover else "stays", mover + 1],
				moved == (i == mover), "moved %.2f" % game.players[i].global_position.distance_to(before[i]))
	game.queue_free()
	await get_tree().process_frame


func _try_pause() -> void:
	print("-- pause")
	GameSettings.player_count = 2
	GameInput.configure(2)
	var game := await _start_game()
	var pause := game.get_node("PauseMenu") as PauseMenu
	var start: Vector3 = game.players[0].global_position
	pause.open()
	var action := GameInput.action(0, &"move_right")
	Input.action_press(action)
	await _wait(0.3)
	Input.action_release(action)
	_check("the game is paused", get_tree().paused and pause.is_open(), "")
	_check("nobody moves while paused", game.players[0].global_position.distance_to(start) < 0.01, "")
	pause.close()
	_check("closing resumes", not get_tree().paused and not pause.is_open(), "")
	var event := InputEventAction.new()
	event.action = GameInput.PAUSE
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("the pause action opens it", pause.is_open(), "")
	pause.close()
	game.queue_free()
	await get_tree().process_frame


## Controllers go where they are assigned, and a device never belongs to two players.
func _try_controllers() -> void:
	print("-- controllers")
	GameSettings.controllers = GameInput.DEFAULT_DEVICES.duplicate()
	GameSettings.assign_controller(0, GameInput.DEVICE_ARROWS)
	_check("taking a device someone has swaps it", GameSettings.controllers == [GameInput.DEVICE_ARROWS, GameInput.DEVICE_KEYBOARD, 0, 1], "%s" % [GameSettings.controllers])
	GameSettings.assign_controller(2, GameInput.DEVICE_NONE)
	_check("'nobody' can be given to anyone", GameSettings.controllers[2] == GameInput.DEVICE_NONE, "")
	GameSettings.controllers = [GameInput.DEVICE_NONE, GameInput.DEVICE_KEYBOARD, 3, 1]
	GameSettings.player_count = 3
	GameInput.configure(3, GameSettings.controllers)
	_check("a player with no device has no keys", InputMap.action_get_events(&"move_left").is_empty(), "")
	_check("the keyboard player has WASD", InputMap.action_get_events(GameInput.action(1, &"move_left")).size() == 1, "")
	var pad_events := InputMap.action_get_events(GameInput.action(2, &"move_left"))
	_check("a gamepad player has that gamepad's stick, and only that one",
			pad_events.size() == 1 and pad_events[0] is InputEventJoypadMotion and pad_events[0].device == 3, "")
	var game := await _start_game()
	_check("only the keyboard player's camera uses the mouse",
			not game.rigs[0].uses_mouse and game.rigs[1].uses_mouse and not game.rigs[2].uses_mouse, "")
	game.queue_free()
	await get_tree().process_frame
	GameSettings.controllers = GameInput.DEFAULT_DEVICES.duplicate()
	GameInput.configure(1)


## The views cover the window without overlapping.
func _check_rects() -> void:
	print("-- view layout")
	for count in range(1, 5):
		for stacked in [false, true]:
			var area := 0.0
			var overlap := false
			for i in count:
				var rect := SplitScreen.view_rect(i, count, stacked)
				area += rect.get_area()
				for j in range(i + 1, count):
					overlap = overlap or rect.intersects(SplitScreen.view_rect(j, count, stacked))
			var full := is_equal_approx(area, 1.0) or count == 3 and is_equal_approx(area, 1.0)
			_check("%d views%s don't overlap%s" % [count, " stacked" if stacked else "", "" if full else " (gaps)"],
					not overlap and area <= 1.001, "area %.2f" % area)


func _start_game() -> LocalGame:
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	return game


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
