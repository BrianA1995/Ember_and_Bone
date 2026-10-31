extends Node
## Plays the monsters in the real game scene (escape mode): every kind snuffs the candle it hits and then
## does its own thing (steals a key, drags the prisoner away, ...), a Lurker only strikes at a lit
## prisoner who moves and is stopped by a wall, webs close doorways, a monster falls with its room, a
## prisoner can't be hit twice in a row, the Director spawns monsters, and a snuffed candle is lit
## again by a teammate (or, for now, by itself after a while).
## Run debug/monster_test.tscn and read the output for "MONSTER TEST".

var _failures := 0
var _game: LocalGame
var _director: MonsterDirector
var _escape: EscapeRun
var _manager: MazeManager


func _ready() -> void:
	GameSettings.monsters = true
	await _start(1)
	await _lurker()
	await _thief()
	await _crawler_and_moth()
	await _weaver()
	await _warden()
	await _falling_and_immunity()
	await _spawning()
	await _start(2)
	await _relighting()
	print("MONSTER TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _start(players: int) -> void:
	if _game:
		_game.queue_free()
		await get_tree().process_frame
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = players
	GameSettings.maze_size = 30
	GameInput.configure(players)
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(_game)
	await _wait(0.5)
	_escape = _game.escape
	_manager = _game.get_node("MazeManager")
	_director = _game.get_node("MonsterDirector")
	_director.enabled = false


## A monster that stands still until the test acts for it.
func _spawn(kind: StringName, cell: Vector2i) -> Monster:
	var monster := _director.spawn(kind, cell)
	monster.set_physics_process(false)
	return monster


func _lurker() -> void:
	print("-- lurker")
	var player := _game.players[0]
	var here := _director.cell_at(player.global_position)
	var side := _open_lane_side(here)
	_check("the start room has an open line to strike along", side >= 0, "")
	var lurker := _spawn(&"lurker", here) as Lurker
	lurker.position = player.global_position
	await _wait(0.1)
	player.velocity = Vector3.ZERO
	lurker._watch()
	_check("a lit prisoner standing still is left alone", lurker._state == Lurker.State.WAIT, "")
	player.velocity = Vector3(2.0, 0.0, 0.0)
	lurker._watch()
	_check("a lit prisoner who moves in its line starts the windup", lurker._state == Lurker.State.WINDUP, "")
	lurker._strike()
	_check("the charge snuffs the candle", player.is_snuffed() and not player.is_candle_lit(), "")
	var closed := _closed_side(here)
	_check("a wall stops the line: no lane through a closed side", closed < 0 or _director.lane(here, closed, 5).is_empty(), "")
	lurker.queue_free()
	player.relight()
	await _wait(0.1)
	_director._immune.clear()


func _thief() -> void:
	print("-- thief")
	var player := _game.players[0]
	_escape.keys_held[0] = 1
	_escape.keys_collected = 1
	var thief := _spawn(&"thief", _director.cell_at(player.global_position)) as Thief
	await _wait(0.1)
	_director.hit(thief, player)
	_check("the thief snuffs the candle", player.is_snuffed(), "")
	_check("and takes the key", _escape.keys_held[0] == 0 and thief._carrying, "%d" % _escape.keys_held[0])
	_check("a stolen key is no longer collected", _escape.keys_collected == 0, "%d" % _escape.keys_collected)
	thief.stun(2.0)
	_check("a stunned thief drops the key where it stands", not thief._carrying and _escape._loose.size() == 1, "%d" % _escape._loose.size())
	var placed := _escape.keys_placed
	thief.queue_free()
	player.relight()
	_director._immune.clear()
	var thief2 := _spawn(&"thief", _director.cell_at(player.global_position)) as Thief
	_escape.keys_held[0] = 1
	_director.hit(thief2, player)
	thief2.fall()
	_check("a thief that falls with a key gives it back to the maze to be found again", _escape.keys_placed == placed - 1, "%d vs %d" % [_escape.keys_placed, placed])
	await _wait(0.7)
	_escape.keys_held[0] = 0
	player.relight()
	_director._immune.clear()
	for loose in _escape._loose.keys():
		loose.queue_free()
	_escape._loose.clear()


func _crawler_and_moth() -> void:
	print("-- crawler and moth")
	var player := _game.players[0]
	var start := player.global_position
	var crawler := _spawn(&"crawler", _director.cell_at(start)) as Crawler
	await _wait(0.1)
	_director.hit(crawler, player)
	var moved := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check("the crawler snuffs the candle and drags the prisoner far away", player.is_snuffed() and moved > 15.0, "moved %.1f" % moved)
	crawler.queue_free()
	player.relight()
	_director._immune.clear()
	await _wait(0.3)
	var before := player.global_position
	var moth := _spawn(&"moth", _director.cell_at(before)) as Moth
	await _wait(0.1)
	_director.hit(moth, player)
	var stayed := Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	_check("the moth only snuffs the candle", player.is_snuffed() and stayed < 0.5, "moved %.1f" % stayed)
	moth.queue_free()
	player.relight()
	_director._immune.clear()


func _weaver() -> void:
	print("-- weaver")
	var player := _game.players[0]
	var here := _director.cell_at(player.global_position)
	var side := _open_lane_side(here)
	_check("a doorway is open before the web", _director.can_pass(here, side), "")
	_director.place_web(here, side)
	_check("a web closes it for walkers", not _director.can_pass(here, side), "")
	_check("and from the other side too", not _director.can_pass(_game.get_node("MazeManager").grid.neighbor(here, side), RoomDefs.opposite(side)), "")
	_check("but not for a weaver", _director.can_pass(here, side, true), "")
	var reach_with := _director.reachable(here, 3, false).size()
	var reach_through := _director.reachable(here, 3, true).size()
	_check("a monster plans around the web", reach_with < reach_through, "%d vs %d" % [reach_with, reach_through])


func _warden() -> void:
	print("-- warden")
	var player := _game.players[0]
	var start := player.global_position
	var warden := _spawn(&"warden", _director.cell_at(start)) as Warden
	warden.home = Vector2i(1, 1)
	await _wait(0.1)
	_escape.keys_held[0] = 1
	_director.hit(warden, player)
	var sent := Vector2(player.global_position.x - start.x, player.global_position.z - start.z).length()
	_check("the warden snuffs the candle, makes the prisoner drop a key and sends them away",
			player.is_snuffed() and _escape.keys_held[0] == 0 and _escape._loose.size() == 1 and sent > 15.0,
			"snuffed %s keys %d loose %d sent %.1f" % [player.is_snuffed(), _escape.keys_held[0], _escape._loose.size(), sent])
	warden.queue_free()
	player.relight()
	_escape.keys_held[0] = 0
	for loose in _escape._loose.keys():
		loose.queue_free()
	_escape._loose.clear()
	_director._immune.clear()
	var guard := _director.spawn(&"warden", _director.cell_at(player.global_position)) as Warden
	guard.home = Vector2i(-5, -5)
	await _wait(1.0)
	_check("a warden with no gate leaves", not is_instance_valid(guard) or guard._falling, "")


func _falling_and_immunity() -> void:
	print("-- falling and immunity")
	var player := _game.players[0]
	var here := _director.cell_at(player.global_position)
	var moth := _spawn(&"moth", here) as Moth
	await _wait(0.1)
	_check("a first hit lands", _director.hit(moth, player), "")
	_check("a second hit just after does not", not _director.hit(moth, player), "")
	player.relight()
	_director._immune.clear()
	_director._on_cell_removed(here)
	await _wait(0.8)
	_check("a monster falls with its room", not is_instance_valid(moth) or moth.is_queued_for_deletion(), "")
	_check("and is gone from the Director", _director.monsters.is_empty(), "%d left" % _director.monsters.size())


func _spawning() -> void:
	print("-- spawning")
	_game.players[0].reset_position()
	_game.players[0].relight()
	await _wait(1.0)
	_director.enabled = true
	_director.grace_seconds = 0.0
	_director.spawn_interval = 0.2
	_director._spawn_timer = 0.0
	await _wait(2.0)
	print("   spawn cells: %d, rooms: %d" % [_director._spawn_cells().size(), _director.grid.cell_count()])
	_check("the Director adds monsters, never more than its limit", _director.monsters.size() > 0 and _director.monsters.size() <= _director.limit(), "%d of %d" % [_director.monsters.size(), _director.limit()])
	for monster in _director.monsters:
		var apart := _director._cells_to_nearest_player(monster.cell)
		_check("a new %s is in the dark ring, not the light" % monster.get_script().get_global_name(), apart >= 1, "%d" % apart)
	_director.enabled = false


func _relighting() -> void:
	print("-- relighting")
	var a := _game.players[0]
	var b := _game.players[1]
	var relighting := _game.get_node("Relighting") as Relighting
	relighting.fallback_seconds = 0.0
	a.snuff()
	b.global_position = a.global_position + Vector3(1.0, 0.0, 0.0)
	await _wait(0.3)
	_check("a snuffed candle stays out on its own", a.is_snuffed() and not a.is_candle_lit(), "")
	_check("while the teammate's burns", b.is_candle_lit(), "")
	Input.action_press(GameInput.action(0, &"interact"))
	await _wait(0.5)
	_check("holding the button a moment is not enough", a.is_snuffed(), "")
	await _wait(1.3)
	Input.action_release(GameInput.action(0, &"interact"))
	_check("holding it beside a lit candle lights it again", not a.is_snuffed() and a.is_candle_lit(), "")
	a.snuff()
	b.global_position = a.global_position + Vector3(6.0, 0.0, 0.0)
	Input.action_press(GameInput.action(0, &"interact"))
	await _wait(2.0)
	Input.action_release(GameInput.action(0, &"interact"))
	_check("too far from the light, it stays out", a.is_snuffed(), "")
	relighting.fallback_seconds = 0.5
	await _wait(1.0)
	_check("the stand-in lights a candle by itself after a while", not a.is_snuffed(), "")


# --- Helpers ---------------------------------------------------------------------------

func _open_lane_side(cell: Vector2i) -> int:
	for side in RoomDefs.SIDE_COUNT:
		if _director.lane(cell, side, 3).size() >= 1:
			return side
	return -1


func _closed_side(cell: Vector2i) -> int:
	for side in RoomDefs.SIDE_COUNT:
		if not _director.grid.is_open(cell, side):
			return side
	return -1


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s%s" % ["ok  " if ok else "FAIL", label, "" if ok or detail.is_empty() else "  (%s)" % detail])
	if not ok:
		_failures += 1
