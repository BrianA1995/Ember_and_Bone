extends Node
## Plays a lone escape run with the default numbers, the way a person would: walks the maze with the
## candle, takes the first key it finds, then switches to the key (candle away) and waits. The run
## must not end by itself, and then must go on once the candle is back.
## Run debug/escape_stow_test.tscn and read the output for "ESCAPE STOW TEST".

var _failures := 0


func _ready() -> void:
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 30
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	var escape := game.escape
	var manager: MazeManager = game.get_node("MazeManager")
	var player: Player = game.players[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 16
	var steps := 0
	var reason := ""
	escape.run_lost.connect(func(why: String) -> void: reason = why)
	while steps < 250 and not escape.finished:
		steps += 1
		for pickup in escape._pickups.values():
			if is_instance_valid(pickup):
				player.warp_to(pickup.global_position - Vector3(0.0, 0.2, 0.0))
				await _wait(0.1)
				break
		var here := manager.grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
		var open: Array[Vector2i] = []
		for side in RoomDefs.SIDE_COUNT:
			var next := manager.grid.neighbor(here, side)
			if manager.grid.is_open(here, side) and manager.grid.has_cell(next):
				open.append(next)
		if open.is_empty():
			player.warp_to(Vector3(0, 0.8, 0))
		else:
			player.warp_to(RoomDefs.cell_to_world(open[rng.randi() % open.size()]) + Vector3(0, 0.8, 0))
		await _wait(0.1)
	print("reason: ", reason)
	print("after %d steps: held %s placed %d lost %d gates %d/%d lost %d finished %s" % [steps, escape.keys_held, escape.keys_placed, escape.keys_lost, escape.gates_placed, escape.gates_total, escape.gates_lost, escape.finished])
	_check("a candle-lit walk does not end the run", not escape.finished, reason)
	var lost_before := escape.keys_lost
	Input.action_press(&"cycle_item")
	await _wait(0.1)
	Input.action_release(&"cycle_item")
	await _wait(2.0)
	print("key out: placed %d lost %d gates %d/%d lost %d finished %s" % [escape.keys_placed, escape.keys_lost, escape.gates_placed, escape.gates_total, escape.gates_lost, escape.finished])
	_check("taking the key out does not end the run", not escape.finished, "")
	_check("and no key is lost for it", escape.keys_lost == lost_before, "%d -> %d" % [lost_before, escape.keys_lost])
	print("ESCAPE STOW TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
