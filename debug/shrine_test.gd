extends Node
## Wax shrines in the real escape game: they are dealt as rooms get built (none when the candle never burns
## down), each is a dead end with a lit altar, holding the interact button there fills the candle of everyone in
## the room (even one that had burned down), and then the altar goes dark for good.
## Run debug/shrine_test.tscn and read the output for "SHRINE TEST".

var _failures := 0
var _game: LocalGame
var _player: Player
var _manager: MazeManager
var _shrines: WaxShrines


func _ready() -> void:
	GameSettings.monsters = false
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 40
	GameSettings.candle_minutes = 3
	GameInput.configure(1)
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(_game)
	await _wait(0.5)
	_player = _game.players[0]
	_manager = _game.get_node("MazeManager")
	_shrines = _game.get_node("WaxShrines")
	await _dealing()
	await _using()
	_endless()
	print("SHRINE TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	GameSettings.candle_minutes = 10
	get_tree().quit(0 if _failures == 0 else 1)


## Walks the maze room to room until a shrine has been built; returns how many rooms that took.
func _walk_until_shrine(limit: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var heading := 0
	for step in limit:
		if not _shrines._shrines.is_empty():
			return step
		var here := _manager.grid.cell_at(_player.global_position)
		var open: Array[int] = []
		for side in RoomDefs.SIDE_COUNT:
			if _manager.grid.is_open(here, side) and _manager.grid.has_cell(_manager.grid.neighbor(here, side)):
				open.append(side)
		if open.is_empty():
			_player.warp_to(Vector3(0, 0.8, 0))
		else:
			if not open.has(heading) or rng.randf() < 0.2:
				heading = open[rng.randi() % open.size()]
			_player.warp_to(RoomDefs.cell_to_world(_manager.grid.neighbor(here, heading)) + Vector3(0, 0.8, 0))
		for i in 4:
			await get_tree().physics_frame
	return -1


func _dealing() -> void:
	print("-- dealing")
	_check("a 3 minute candle puts the shrines %d rooms apart" % _shrines.rooms_between, _shrines.rooms_between == roundi(180.0 * _shrines.rooms_per_second * _shrines.life_share), "")
	_check("none is due at the start", _manager.grid.weights[&"wax_shrine"] == 0.0, "")
	var steps := await _walk_until_shrine(2500)
	_check("walking on, a shrine is built", steps >= 0, "after %d steps" % steps)
	if steps < 0:
		return
	var cell: Vector2i = _shrines._shrines.keys()[0]
	var data := _manager.grid.get_cell(cell)
	var exits := 0
	for side in RoomDefs.SIDE_COUNT:
		if _manager.grid.is_open(cell, side):
			exits += 1
	_check("it is a wax shrine room with one doorway", data.piece == &"wax_shrine" and exits == 1, "%s, %d exits" % [data.piece, exits])
	_check("not before enough rooms were built", _shrines._builds >= _shrines.first_after * 0.8, "%d built, due at %d" % [_shrines._builds, _shrines.first_after])
	_check("its altar burns", _shrines._shrines[cell].flames.size() == 2 and _shrines.has_shrine(cell), "")
	_check("the next one is a long way off", _manager.grid.weights[&"wax_shrine"] == 0.0, "")


func _using() -> void:
	print("-- using one")
	if _shrines._shrines.is_empty():
		return
	var cell: Vector2i = _shrines._shrines.keys()[0]
	var shrine: Dictionary = _shrines._shrines[cell]
	_player.warp_to(RoomDefs.cell_to_world(cell) + Vector3(0, 0.8, 0))
	await _wait(0.3)
	_check("at the altar the hint says to hold the button", _shrines.hint(_player).begins_with("Hold {interact}"), _shrines.hint(_player))
	# The candle burns down first.
	_player.wax.left = 0.5
	await _wait(1.0)
	_check("the candle has burned down", _player.is_burnt_out(), "")
	var button := GameInput.action(0, &"interact")
	Input.action_press(button)
	await _wait(0.4)
	_check("a tap is not enough", _player.is_burnt_out() and _shrines.has_shrine(cell), "")
	await _wait(0.8)
	Input.action_release(button)
	await _wait(0.3)
	_check("holding the button fills the candle", not _player.is_burnt_out() and _player.is_candle_lit() and _player.wax.fraction() > 0.95, "%.2f" % _player.wax.fraction())
	_check("the altar goes dark", shrine.used and not _shrines.has_shrine(cell), "")
	var gone := true
	for flame in shrine.flames:
		gone = gone and not is_instance_valid(flame)
	_check("and its flames are out", gone, "")
	_check("the hint says so", _shrines.hint(_player) == "The shrine has gone dark", _shrines.hint(_player))
	_player.wax.left = 10.0
	Input.action_press(button)
	await _wait(1.5)
	Input.action_release(button)
	_check("it cannot be used twice", _player.wax.left < 11.0, "%.1f" % _player.wax.left)


func _endless() -> void:
	print("-- a candle that never burns down")
	GameSettings.candle_minutes = 0
	_game.escape.restart()
	_shrines.restart()
	_check("needs no shrines", _manager.grid.weights[&"wax_shrine"] == 0.0 and _shrines._builds == 0, "")
	_shrines._builds = 10000
	_shrines._update_weights()
	_check("however many rooms are built", _manager.grid.weights[&"wax_shrine"] == 0.0, "")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s%s" % ["ok  " if ok else "FAIL", label, "" if ok or detail.is_empty() else "  (%s)" % detail])
	if not ok:
		_failures += 1
