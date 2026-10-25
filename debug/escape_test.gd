extends Node
## Plays the escape run in the real game scene: the key and gate numbers by player count, keys and
## gates appearing in the maze (never more than the plan), picking a key up (one at a time with
## company, any number alone), holding a key out and a teammate taking it, a gate staying shut until
## enough prisoners hold their key and opening with them, and the two ways to lose.
## Run debug/escape_test.tscn and read the output for "ESCAPE TEST".

var _failures := 0


func _ready() -> void:
	_check_plans()
	await _play()
	await _play_alone()
	await _play_dark()
	await _play_last_gate()
	print("ESCAPE TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_plans() -> void:
	print("-- the plan")
	var one := EscapeRun.plan_for(1)
	var three := EscapeRun.plan_for(3)
	var four := EscapeRun.plan_for(4)
	_check("1 player: 4 keys in the maze, 3 needed to get out, 2 gates, 1 inside", [one.keys, one.per_prisoner, one.gates, one.at_gate] == [4, 3, 2, 1], "%s" % [one])
	_check("2-3 players: 6 keys, 1 each, 3 gates, 2 inside", [three.keys, three.per_prisoner, three.gates, three.at_gate] == [6, 1, 3, 2], "%s" % [three])
	_check("4 players: 8 keys, 1 each, 3 gates, 2 inside", [four.keys, four.per_prisoner, four.gates, four.at_gate] == [8, 1, 3, 2], "%s" % [four])
	_check("the menu lists every mode", MainMenu.MODE_NAMES.size() == GameSettings.GameMode.size(), "")
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.enforce_mode_rules()
	_check("escape can be played alone, tag can't", GameSettings.player_count == 1 and not GameSettings.is_tag_mode(), "")
	GameSettings.game_mode = GameSettings.GameMode.TAG
	_check("tag is a tag mode", GameSettings.is_tag_mode(), "")
	GameInput.configure(1, [0, GameInput.DEVICE_ARROWS, 1, 2])
	var pad_buttons: Array = []
	for event in InputMap.action_get_events(&"interact"):
		if event is InputEventJoypadButton:
			pad_buttons.append(event.button_index)
	_check("on a gamepad A interacts", pad_buttons == [JOY_BUTTON_A], "%s" % [pad_buttons])
	var pad_out: Array = []
	for event in InputMap.action_get_events(&"hold_flame"):
		pad_out.append(event is InputEventJoypadButton or event is InputEventJoypadMotion)
	_check("and the left trigger or bumper holds the flame (and the key) out", pad_out == [true, true], "%s" % [pad_out])
	GameInput.configure(1)


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
	_check("2 players: 6 keys in the maze, one each to get out, 2 inside the gate", escape.keys_total == 6 and escape.keys_per_prisoner == 1 and escape.at_gate_needed == 2, "")
	_check("with company a prisoner carries one key", escape.capacity() == 1, "")
	var won := []
	var lost := []
	escape.run_won.connect(func(escaped: Array) -> void: won.append(escaped))
	escape.run_lost.connect(func(reason: String) -> void: lost.append(reason))
	# Keep the run from ending on its own while the walker ignores most keys.
	escape.rooms_per_key = 2
	escape.restart()
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
		escape.keys_total = 999
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
	escape.keys_total = 6
	_check("keys were built into alcoves, no more than the plan", escape.keys_placed >= 1 and escape.keys_placed <= 6, "%d of 6" % escape.keys_placed)
	_check("a key was picked up by walking into it", picked and escape.keys_collected >= 1, "after %d steps" % steps)
	_check("a prisoner never carries more than one", escape.keys_held[0] <= 1 and escape.keys_held[1] <= 1, "%s" % [escape.keys_held])
	_check("a gate was built", not escape._gates.is_empty() and escape.gates_placed <= escape.gates_total, "%d of %d" % [escape.gates_placed, escape.gates_total])

	print("-- one key at a time, and passing it")
	escape.keys_total = 999
	# Keys the maze built during the walk would be picked up by the teammate warped about.
	for lying in game.find_children("*", "KeyPickup", true, false):
		lying.queue_free()
	await _wait(0.1)
	escape.keys_held[0] = 1
	escape.keys_held[1] = 0
	var spot := walker.global_position
	other.warp_to(spot + Vector3(10.0, 0, 0))
	var spare := _drop_key(game, escape, spot)
	await _wait(0.2)
	_check("holding a key, a second one is left lying for someone with a free hand", is_instance_valid(spare) and not spare.is_queued_for_deletion() and escape.keys_held[0] == 1, "valid %s queued %s held %s" % [is_instance_valid(spare), is_instance_valid(spare) and spare.is_queued_for_deletion(), escape.keys_held])
	if is_instance_valid(spare):
		spare.queue_free()
	escape.keys_held[0] = 1
	escape.keys_held[1] = 0
	var passed := []
	escape.key_passed.connect(func(from: int, to: int) -> void: passed.append([from, to]))
	_press(&"p2_interact")
	await _wait(0.2)
	_release(&"p2_interact")
	_check("pressing interact takes nothing while nobody holds a key out", escape.keys_held == ([1, 0] as Array[int]), "%s" % [escape.keys_held])
	other.warp_to(spot + Vector3(1.0, 0, 0))
	_press(&"hold_flame")
	await _wait(0.2)
	_check("with the candle in hand, holding F holds the candle up, not the key out", not escape._carriers[0].offering and walker.is_candle_lit(), "")
	_release(&"hold_flame")
	_press(&"cycle_item")
	await _wait(0.1)
	_release(&"cycle_item")
	_check("the switch button takes out the key and puts the candle away", escape.equipped[0] == 1 and not walker.is_candle_lit(), "%s" % [escape.equipped])
	_press(&"hold_flame")
	await _wait(0.2)
	_check("holding the button holds the key out", escape._carriers[0].offering, "")
	_check("and the teammate is told they can take it", "take the key" in escape.prompt(1), escape.prompt(1))
	other.warp_to(spot + Vector3(6.0, 0, 0))
	await _wait(0.1)
	_press(&"p2_interact")
	await _wait(0.2)
	_release(&"p2_interact")
	_check("too far away to take it", escape.keys_held == ([1, 0] as Array[int]), "%s" % [escape.keys_held])
	other.warp_to(spot + Vector3(1.0, 0, 0))
	await _wait(0.1)
	_press(&"p2_interact")
	await _wait(0.2)
	_release(&"p2_interact")
	_release(&"hold_flame")
	_check("beside them, interact takes the key", escape.keys_held == ([0, 1] as Array[int]) and passed == [[0, 1]], "%s %s" % [escape.keys_held, passed])
	_check("the one who gave it has their candle back", escape.equipped[0] == 0 and walker.is_candle_lit(), "%s" % [escape.equipped])
	_check("the one who took it keeps the candle in hand", escape.equipped[1] == 0 and other.is_candle_lit(), "%s" % [escape.equipped])
	escape.keys_held[0] = 1
	escape.equipped[0] = 1
	await _wait(0.1)
	_press(&"hold_flame")
	await _wait(0.2)
	_press(&"p2_interact")
	await _wait(0.2)
	_release(&"p2_interact")
	_release(&"hold_flame")
	_check("someone who already has a key can't take another", escape.keys_held == ([1, 1] as Array[int]), "%s" % [escape.keys_held])

	print("-- the gate")
	if escape._gates.is_empty():
		game.queue_free()
		await get_tree().process_frame
		return
	escape.keys_total = 999
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
	escape.keys_held[0] = 1
	await _wait(1.5)
	_check("one key between two prisoners is not enough: each needs their own", won.is_empty(), "")
	other.warp_to(middle + Vector3(40, 0, 40))
	escape.keys_held[1] = 1
	await _wait(1.5)
	_check("a prisoner with a key but outside the gate does not count", won.is_empty(), "")
	other.warp_to(beside)
	await _wait(0.5)
	_check("both inside with their keys: it starts to unlock", escape.unlock_progress > 0.0 and escape.gate_status(0).begins_with("Unlocking"), escape.gate_status(0))
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
	escape.keys_lost = escape.keys_total - escape.keys_required() + 1
	escape._check_lost()
	_check("too few keys left loses the run", lost.size() == 1 and "keys" in lost[0], "%s" % [lost])
	escape.restart()
	escape.gates_placed = escape.gates_total
	escape._gates.clear()
	escape._check_lost()
	_check("every gate lost loses the run", lost.size() == 2 and "gate" in lost[1], "%s" % [lost])
	escape.restart()
	_check("a new maze starts a fresh run", not escape.finished and escape.keys_collected == 0 and escape.keys_lost == 0, "")
	get_tree().paused = false
	game.queue_free()
	await get_tree().process_frame


## A lone prisoner carries any number of keys and needs three to get out.
func _play_alone() -> void:
	print("-- alone")
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	var escape := game.escape
	_check("alone: 4 keys in the maze, 3 needed to get out", escape.keys_total == 4 and escape.keys_per_prisoner == 3 and escape.keys_required() == 3, "")
	_check("and three can be carried, so four slots in all", escape.capacity() == 3, "")
	var player: Player = game.players[0]
	var at := player.global_position
	for i in 3:
		var key := _drop_key(game, escape, at)
		key.taken.connect(escape._on_key_taken.bind(Vector2i(900 + i, 0), null))
	await _wait(0.3)
	_check("alone, all the keys that lie there are taken", escape.keys_held[0] == 3, "%s" % [escape.keys_held])
	for step in 3:
		_press(&"cycle_item")
		await _wait(0.1)
		_release(&"cycle_item")
		await _wait(0.1)
		_check("switching goes on through the keys (step %d)" % (step + 1), escape.equipped[0] == (step + 1) % 4, "%s" % [escape.equipped])
	_press(&"cycle_item")
	await _wait(0.1)
	_release(&"cycle_item")
	_check("and round to the candle again", escape.equipped[0] == 0 and player.is_candle_lit(), "%s" % [escape.equipped])
	game.queue_free()
	await get_tree().process_frame


## A key lying at `at`, taken the way the run's own are.
func _drop_key(game: Node, escape: EscapeRun, at: Vector3) -> KeyPickup:
	var key := KeyPickup.new()
	key.accepts = func(player: Player) -> bool: return escape.keys_held[player.slot] < escape.capacity()
	game.add_child(key)
	key.global_position = at
	return key


func _press(action: StringName) -> void:
	Input.action_press(action)


func _release(action: StringName) -> void:
	Input.action_release(action)


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])


## The candle put away: the rooms around vanish, the view goes grey, another's candle brings colour back.
func _play_dark() -> void:
	print("-- without the candle")
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 2
	GameInput.configure(2)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	var escape := game.escape
	var manager := game.get_node("MazeManager") as MazeManager
	var one: Player = game.players[0]
	var two: Player = game.players[1]
	escape.keys_held[0] = 1
	one.warp_to(Vector3(0, 0.8, 0))
	two.warp_to(Vector3(0, 0.8, 0))
	await _wait(0.5)
	var around := manager.reveal.lit.size()
	escape.equipped[0] = 1
	two.warp_to(Vector3(RoomDefs.CELL_SIZE * 8.0, 0.8, 0))
	await _wait(1.0)
	_check("with the candle away, the player lights only their own room", one.light_radius == 0 and not one.is_candle_lit(), "radius %d" % one.light_radius)
	var here := RoomDefs.world_to_cell(one.global_position)
	var neighbours := 0
	for side in RoomDefs.SIDE_COUNT:
		var next := manager.grid.neighbor(here, side)
		# (The start room is bigger than a cell: its other cells are part of the room they stand in.)
		if manager.grid.has_cell(next) and not manager.grid.room_cells(here).has(next):
			neighbours += 1
	_check("and the rooms around them are gone", manager.grid.has_cell(here) and neighbours == 0, "%d left" % neighbours)
	var sight := escape._sight
	_check("their view goes nearly grey", sight.amount[0] > 0.8 and sight.amount[1] < 0.05, "%s" % [sight.amount])
	two.warp_to(one.global_position + Vector3(1.0, 0, 0))
	await _wait(1.2)
	_check("a burning candle beside them brings the colour back", sight.amount[0] < 0.05, "%s" % [sight.amount])
	escape.equipped[0] = 0
	await _wait(0.3)
	_check("lighting the candle again restores its light", one.light_radius > 0 and one.is_candle_lit(), "radius %d" % one.light_radius)
	game.queue_free()
	await get_tree().process_frame


## The last gate waits until enough keys have turned up; with the menu option on it lingers in the dark.
func _play_last_gate() -> void:
	print("-- the last gate")
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 2
	GameInput.configure(2)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	var escape := game.escape
	escape._deck.clear()
	escape._deck.append({"at": 0, "kind": &"gate"})
	escape.gates_placed = 0
	_check("an early gate may come before any key has", escape._gate_may_come(), "")
	escape.gates_placed = escape.gates_total - 1
	escape.keys_placed = escape.keys_required() - 1
	_check("the last gate waits while too few keys have turned up", not escape._gate_may_come(), "")
	escape.keys_placed = escape.keys_required()
	_check("and comes once enough have, taken or not", escape._gate_may_come() and escape.keys_collected == 0, "")
	var cell := Vector2i(5, 5)
	escape._gate_cells[cell] = cell
	escape.gates_lost = escape.gates_total - 1
	GameSettings.gate_grace = false
	_check("with the option off the last gate does not linger", escape._extra_unlit(cell) == 0.0, "")
	GameSettings.gate_grace = true
	_check("with it on, it does", escape._extra_unlit(cell) == escape.last_gate_grace, "")
	escape.gates_lost = 0
	_check("a gate that is not the last one does not", escape._extra_unlit(cell) == 0.0, "")
	GameSettings.gate_grace = false
	game.queue_free()
	await get_tree().process_frame
