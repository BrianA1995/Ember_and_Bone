extends Node
## Plays the escape run in the real game scene: the key and gate numbers by player count, keys and
## gates appearing in the maze (never more than the plan), a key being picked up, a gate staying
## shut without enough prisoners or keys and opening with both, and the two ways to lose.
## Run debug/escape_test.tscn and read the output for "ESCAPE TEST".

var _failures := 0


func _ready() -> void:
	_check_plans()
	await _play()
	print("ESCAPE TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_plans() -> void:
	print("-- the plan")
	var one := EscapeRun.plan_for(1)
	var three := EscapeRun.plan_for(3)
	var four := EscapeRun.plan_for(4)
	_check("1 player: 4 keys, 3 needed, 2 gates, 1 inside", [one.keys, one.needed, one.gates, one.at_gate] == [4, 3, 2, 1], "%s" % [one])
	_check("2-3 players: 6 keys, 4 needed, 3 gates, 2 inside", [three.keys, three.needed, three.gates, three.at_gate] == [6, 4, 3, 2], "%s" % [three])
	_check("4 players: 8 keys, 5 needed, 3 gates, 2 inside", [four.keys, four.needed, four.gates, four.at_gate] == [8, 5, 3, 2], "%s" % [four])
	_check("the menu lists every mode", MainMenu.MODE_NAMES.size() == GameSettings.GameMode.size(), "")
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.enforce_mode_rules()
	_check("escape can be played alone, tag can't", GameSettings.player_count == 1 and not GameSettings.is_tag_mode(), "")
	GameSettings.game_mode = GameSettings.GameMode.TAG
	_check("tag is a tag mode", GameSettings.is_tag_mode(), "")


func _play() -> void:
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 2
	GameSettings.maze_size = 30
	GameInput.configure(2)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	var escape := game.escape
	var manager: MazeManager = game.get_node("MazeManager")
	_check("an escape game has the escape rules", escape != null and game.tag == null, "")
	_check("2 players: 6 keys in the maze, 4 needed", escape.keys_total == 6 and escape.keys_needed == 4 and escape.at_gate_needed == 2, "")
	var won := []
	var lost := []
	escape.run_won.connect(func(escaped: Array) -> void: won.append(escaped))
	escape.run_lost.connect(func(reason: String) -> void: lost.append(reason))
	# Keep the run from ending on its own while the walker ignores most keys.
	escape.keys_needed = 0
	escape.rooms_per_key = 2
	escape.rooms_per_gate = 2
	escape.gate_after_keys = 0
	escape.rarity_ceiling = 200.0
	escape.key_collapse_delay = 0.5
	escape.unlock_seconds = 1.0

	print("-- keys and gates appear")
	var walker: Player = game.players[0]
	var other: Player = game.players[1]
	var picked := false
	var steps := 0
	var cell := Vector2i.ZERO
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	while steps < 4000 and (escape._gates.is_empty() or not picked):
		steps += 1
		if not picked:
			for pickup in escape._pickups.values():
				if is_instance_valid(pickup):
					walker.warp_to(pickup.global_position - Vector3(0.0, 0.2, 0.0))
					await _wait(0.1)
					picked = escape.keys_held[0] == 1
					break
		var open: Array[Vector2i] = []
		var here := manager.grid.wrap_cell(RoomDefs.world_to_cell(walker.global_position))
		for side in RoomDefs.SIDE_COUNT:
			var next := manager.grid.neighbor(here, side)
			if manager.grid.is_open(here, side) and manager.grid.has_cell(next):
				open.append(next)
		if open.is_empty():
			walker.warp_to(Vector3(0, 0.8, 0))
		else:
			cell = open[rng.randi() % open.size()]
			walker.warp_to(RoomDefs.cell_to_world(cell) + Vector3(0, 0.8, 0))
		other.warp_to(walker.global_position + Vector3(0.5, 0, 0))
		await _wait(0.1)
		_check_never_more(escape)
	_check("keys were built into alcoves, no more than the plan", escape.keys_placed >= 1 and escape.keys_placed <= escape.keys_total, "%d of %d" % [escape.keys_placed, escape.keys_total])
	_check("a key was picked up by walking into it", picked and escape.keys_collected >= 1, "after %d steps" % steps)
	_check("a gate was built", not escape._gates.is_empty() and escape.gates_placed <= escape.gates_total, "%d of %d" % [escape.gates_placed, escape.gates_total])

	print("-- the gate")
	if escape._gates.is_empty():
		game.queue_free()
		await get_tree().process_frame
		return
	escape.keys_needed = 4
	escape.keys_held[0] = 0
	escape.keys_held[1] = 0
	var anchor: Vector2i = escape._gates.keys()[0]
	var members := manager.grid.room_cells(anchor)
	var middle := RoomDefs.cell_to_world(members[0]) + Vector3(0, 0.8, 0)
	var beside := RoomDefs.cell_to_world(members[1]) + Vector3(0, 0.8, 0)
	walker.warp_to(middle)
	other.warp_to(beside)
	await _wait(1.5)
	_check("with no keys the gate stays shut", won.is_empty() and escape.unlock_progress == 0.0, "")
	_check("and says what it is waiting for", escape.gate_status(0).begins_with("Gate:"), escape.gate_status(0))
	escape.keys_held[0] = 4
	other.warp_to(middle + Vector3(40, 0, 40))
	await _wait(1.5)
	_check("with keys but one prisoner too few it stays shut", won.is_empty(), "")
	other.warp_to(beside)
	await _wait(0.5)
	_check("with both prisoners and the keys it starts to unlock", escape.unlock_progress > 0.0 and escape.gate_status(0).begins_with("Unlocking"), escape.gate_status(0))
	await _wait(1.5)
	_check("and they escape", won.size() == 1 and escape.finished and won[0] == [0, 1], "%s" % [won])
	var results_up := false
	for child in game.get_children():
		results_up = results_up or child is RunResults
	_check("a results screen appeared and paused the game", results_up and get_tree().paused, "")
	get_tree().paused = false

	print("-- losing")
	lost.clear()
	escape.restart()
	escape.keys_lost = escape.keys_total - escape.keys_needed + 1
	escape._check_lost()
	_check("too few keys left loses the run", lost.size() == 1 and "keys" in lost[0], "%s" % [lost])
	escape.restart()
	escape.gates_placed = escape.gates_total
	escape._check_lost()
	_check("every gate lost loses the run", lost.size() == 2 and "gate" in lost[1], "%s" % [lost])
	escape.restart()
	_check("a new maze starts a fresh run", not escape.finished and escape.keys_collected == 0 and escape.keys_lost == 0, "")
	game.queue_free()
	await get_tree().process_frame


func _check_never_more(escape: EscapeRun) -> void:
	if escape.keys_placed > escape.keys_total or escape.gates_placed > escape.gates_total:
		_check("never more keys or gates than the plan", false, "%d keys, %d gates" % [escape.keys_placed, escape.gates_placed])
		escape.keys_placed = 0
		escape.gates_placed = 0


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
