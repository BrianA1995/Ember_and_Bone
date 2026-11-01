extends Node
## The special rooms that act on the monsters, in the real escape game: a safe niche shuts monsters out while a
## prisoner in it has their flame lit (they cannot hit, walk in or be placed there), and an echo hall makes every
## sound in it carry (even someone standing still is heard).
## Run debug/rooms_test.tscn and read the output for "ROOMS TEST".

var _failures := 0
var _game: LocalGame
var _player: Player
var _manager: MazeManager
var _director: MonsterDirector


func _ready() -> void:
	GameSettings.monsters = true
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 40
	GameInput.configure(1)
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(_game)
	await _wait(0.5)
	_player = _game.players[0]
	_manager = _game.get_node("MazeManager")
	_director = _game.get_node("MonsterDirector")
	_director.enabled = false
	await _niche()
	await _echo_hall()
	print("ROOMS TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## Walks the maze until a room of `piece` has been built; its cell, or (-9999, -9999).
func _find(piece: StringName, limit: int) -> Vector2i:
	_manager.grid.weights[piece] = 1000.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var heading := 0
	var found := Vector2i(-9999, -9999)
	for step in limit:
		for cell in _manager.grid.cells():
			if _manager.grid.get_cell(cell).piece == piece:
				found = cell
				break
		if found != Vector2i(-9999, -9999):
			break
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
	_manager.grid.weights[piece] = 0.0
	return found


func _niche() -> void:
	print("-- safe niche")
	var cell := await _find(&"safe_niche", 1500)
	_check("a safe niche gets built", cell != Vector2i(-9999, -9999), "")
	if cell == Vector2i(-9999, -9999):
		return
	var thief := _director.spawn(&"thief", cell) as Thief
	thief.set_physics_process(false)
	_player.warp_to(RoomDefs.cell_to_world(cell) + Vector3(0, 0.8, 0))
	_player.relight()
	await _wait(0.4)
	_check("with the flame lit it is a sanctuary", _director.is_sanctuary(cell) and _player.is_candle_lit(), "")
	_director._immune.clear()
	_check("nothing can hit a prisoner in it", not _director.hit(thief, _player), "")
	_check("it says so", _director.place_hint(_player).contains("cannot follow"), _director.place_hint(_player))
	var outside := Vector2i(-9999, -9999)
	for side in RoomDefs.SIDE_COUNT:
		if _manager.grid.is_open(cell, side):
			outside = _manager.grid.neighbor(cell, side)
	_check("a monster outside cannot walk in", outside != Vector2i(-9999, -9999) and not _director.can_pass(outside, _side_to(outside, cell)), "")
	_player.snuff()
	await _wait(0.3)
	_check("with the flame out it is just a room", not _director.is_sanctuary(cell), "")
	_player.relight()
	await _wait(0.2)
	_director._immune.clear()
	_player.snuff()
	await _wait(0.2)
	_director._immune.clear()
	_check("and a monster can hit there", _director.hit(thief, _player), "")
	thief.queue_free()
	_player.relight()


func _side_to(from: Vector2i, to: Vector2i) -> int:
	for side in RoomDefs.SIDE_COUNT:
		if _manager.grid.neighbor(from, side) == to:
			return side
	return 0


func _echo_hall() -> void:
	print("-- echo hall")
	var cell := await _find(&"echo_hall", 3000)
	_check("an echo hall gets built", cell != Vector2i(-9999, -9999), "")
	if cell == Vector2i(-9999, -9999):
		return
	_player.warp_to(RoomDefs.cell_to_world(cell) + Vector3(0, 0.8, 0))
	await _wait(0.4)
	var sounds := _director.sounds()
	_check("standing still in the hall is heard", sounds.size() == 1, "%d" % sounds.size())
	_check("softly, but carried", sounds.size() == 1 and is_equal_approx(sounds[0].loudness, _director.echo_standing * _director.echo_boost), "")
	_player.warp_to(Vector3(0, 0.8, 0))
	await _wait(0.4)
	_check("a prisoner standing still elsewhere is not heard", _director.sounds().is_empty(), "%s" % [_director.sounds()])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s%s" % ["ok  " if ok else "FAIL", label, "" if ok or detail.is_empty() else "  (%s)" % detail])
	if not ok:
		_failures += 1
