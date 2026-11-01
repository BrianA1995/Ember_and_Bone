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
	await _sanctuary()
	await _lurker()
	await _sight_and_limits()
	await _thief()
	await _dark_rule()
	await _rules()
	await _crawler_and_moth()
	await _weaver()
	_no_way()
	await _chase()
	await _new_behaviour()
	await _warden()
	await _falling_and_immunity()
	await _spawning()
	await _start(1)
	await _mimic()
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
	# The start room would collapse after half a minute and take the test's footing with it.
	var maze := _game.get_node("MazeManager") as MazeManager
	maze.start_collapse_delay = 0.0
	# Cracked floors have their own test; here one beside the start room can drop the player mid-check.
	maze.crack_chance = 0.0
	# MAZE_SEED=<n> replays a maze (the seed of a failing run is printed below); otherwise each run is a new one.
	maze.map_seed = OS.get_environment("MAZE_SEED").to_int()
	add_child(_game)
	await _wait(0.5)
	_escape = _game.escape
	print("  (maze seed %d)" % maze.grid.seed_value)
	_manager = _game.get_node("MazeManager")
	_director = _game.get_node("MonsterDirector")
	_director.enabled = false
	# The tests fight in the start room, which is a sanctuary in the real game (_sanctuary checks that).
	_director.start_sanctuary = false


## A monster that stands still until the test acts for it.
func _spawn(kind: StringName, cell: Vector2i) -> Monster:
	var monster := _director.spawn(kind, cell)
	monster.set_physics_process(false)
	return monster


func _sanctuary() -> void:
	print("-- start chamber is safe")
	var player := _game.players[0]
	var here := _director.cell_at(player.global_position)
	_director.start_sanctuary = true
	_check("the start chamber is a sanctuary", _director.is_sanctuary(here), "")
	var thief := _spawn(&"thief", here) as Thief
	_director._immune.clear()
	_check("a monster cannot hit a prisoner standing in it", not _director.hit(thief, player), "")
	var walked_in := false
	for side in RoomDefs.SIDE_COUNT:
		var outside: Vector2i = _director.grid.neighbor(here, side)
		if not _director.is_sanctuary(outside) and _director.can_pass(outside, RoomDefs.opposite(side)):
			walked_in = true
	_check("and none can walk into it", not walked_in, "")
	_check("none is placed in it", not _director._spawn_cells().has(here), "")
	_director.start_sanctuary = false
	_director._immune.clear()
	_check("(with the sanctuary off, the same hit lands)", _director.hit(thief, player), "")
	_director._immune.clear()
	thief.queue_free()
	await _wait(0.1)


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
	for i in 30:
		lurker._act(0.1)
	_check("a lit prisoner standing still is never attacked", not player.is_snuffed(), "")
	player.velocity = Vector3(2.0, 0.0, 0.0)
	for i in 8:
		lurker._act(0.1)
	_check("a prisoner who moves in its line gets a 2 s grace period (0.8 s of it: nothing yet)", not player.is_snuffed(), "")
	player.velocity = Vector3.ZERO
	for i in 20:
		lurker._act(0.1)
	_check("and stopping within it saves them", not player.is_snuffed() and lurker._armed, "")
	player.velocity = Vector3(0.3, 0.0, 0.0)
	lurker._act(0.1)
	_check("a slight bump is allowed", not player.is_snuffed(), "")
	player.velocity = Vector3(2.0, 0.0, 0.0)
	lurker._act(0.1)
	_check("but moving once the grace is spent is hit at once", player.is_snuffed() and not player.is_candle_lit(), "")
	_check("with no red line to give it away", lurker.get_children().all(func(child: Node) -> bool: return child == lurker.model), "")
	_check("and it shoots down the line (or, with no line to shoot along, is gone at once)", lurker._state == Lurker.State.CHARGE or lurker.is_going(), "")
	for i in 40:
		lurker._act(0.1)
	_check("then it is gone: it fades out and never comes back", lurker._falling, "")
	player.relight()
	player.velocity = Vector3.ZERO
	var closed := _closed_side(here)
	_check("a wall stops the line: no lane through a closed side", closed < 0 or _director.lane(here, closed, 5).is_empty(), "")
	lurker.queue_free()
	await _wait(0.1)
	_director._immune.clear()
	# Turning the camera gives the prisoner away as well; staying perfectly still sends it away.
	var second := _spawn(&"lurker", here) as Lurker
	second.position = player.global_position + Vector3(1.0, 0.0, 0.0)
	await _wait(0.1)
	player.velocity = Vector3.ZERO
	second._act(0.1)
	for i in 8:
		player._visual.rotation.y += 0.2
		second._act(0.1)
	_check("a prisoner turning the camera in its line starts the grace period", second._grace < second.grace_seconds and second._grace > 0.0, "%.2f" % second._grace)
	for i in 25:
		player._visual.rotation.y += 0.2
		second._act(0.1)
	_check("and is hit if they keep turning", player.is_snuffed(), "")
	player.relight()
	_director._immune.clear()
	second.queue_free()
	await _wait(0.1)
	var third := _spawn(&"lurker", here) as Lurker
	third.position = player.global_position + Vector3(1.0, 0.0, 0.0)
	await _wait(0.1)
	for i in 60:
		third._act(0.1)
	_check("a prisoner who stays still beside it makes it lose interest", third._state == Lurker.State.LEAVE, "")
	for i in 60:
		third._act(0.1)
	_check("and it wanders off and disappears", third._falling and not player.is_snuffed(), "")
	third.queue_free()
	await _wait(0.1)


func _sight_and_limits() -> void:
	print("-- lit rooms, and one lurker at a time")
	var player := _game.players[0]
	var here := _director.cell_at(player.global_position)
	await _wait(0.2)
	var lit_cells: Dictionary = _director.sight.cells_for(player)
	_check("a lit candle lights the room and the rooms joined to it", lit_cells.has(here) and lit_cells.size() > 1, "%d" % lit_cells.size())
	var dark := _director.reachable(here, 2).keys().filter(func(c: Vector2i) -> bool: return not lit_cells.has(c))
	if not dark.is_empty():
		var moth := _spawn(&"moth", dark[0])
		_check("a monster in the dark ring may not chase or hit", not _director.can_chase(player, dark[0]) and not _director.hit(moth, player), "")
		moth.queue_free()
	_check("but one in a lit room may", _director.can_chase(player, here), "")
	var lit_change := player.change_distance
	player.snuff()
	await _wait(0.2)
	var own_room: Dictionary = _director.sight.cells_for(player)
	_check("with the candle out only the player's own room is lit", own_room.size() == _manager.grid.room_cells(here).size() and own_room.has(here), "%d" % own_room.size())
	_check("and the rooms around change as they are no longer seen (the distance they must be seen from shrinks)", player.change_distance < lit_change, "%.1f vs %.1f" % [player.change_distance, lit_change])
	player.relight()
	await _wait(0.2)
	_check("a lit candle sees as far as before", is_equal_approx(player.change_distance, lit_change), "")
	var lurker := _spawn(&"lurker", here)
	var saved: Dictionary = _director.weights
	_director.weights = {&"lurker": 4.0}
	for i in 5:
		_director._spawn_random()
	_check("the director never has more than one lurker about", _director.count_of(&"lurker") == 1, "%d" % _director.count_of(&"lurker"))
	_director.weights = saved
	lurker.queue_free()
	await _wait(0.1)


func _thief() -> void:
	print("-- thief")
	var player := _game.players[0]
	_escape.keys_held[0] = 1
	_escape.keys_collected = 1
	var thief := _spawn(&"thief", _director.cell_at(player.global_position)) as Thief
	await _wait(0.1)
	_director.hit(thief, player)
	_check("the thief leaves the candle burning", not player.is_snuffed(), "")
	_check("and takes the key", _escape.keys_held[0] == 0 and thief.is_carrying(), "%d" % _escape.keys_held[0])
	_check("a stolen key is no longer collected", _escape.keys_collected == 0, "%d" % _escape.keys_collected)
	thief.stun(2.0)
	_check("a stunned thief drops the key where it stands", not thief.is_carrying() and _escape._loose.size() == 1, "%d" % _escape._loose.size())
	var placed := _escape.keys_placed
	thief.queue_free()
	player.relight()
	_director._immune.clear()
	var thief2 := _spawn(&"thief", _director.cell_at(player.global_position)) as Thief
	_escape.keys_held[0] = 1
	_director.hit(thief2, player)
	thief2.fade_out()
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


func _dark_rule() -> void:
	print("-- a prisoner without a candle")
	var player := _game.players[0]
	player.reset_position()
	player.relight()
	await _wait(1.0)
	var here := Vector2i.ZERO
	var next := Vector2i.ZERO
	var found := false
	for candidate in _director.grid.cells():
		for side in RoomDefs.SIDE_COUNT:
			var n := _director.grid.neighbor(candidate, side)
			if _director.grid.has_cell(n) and not _director.grid.room_cells(candidate).has(n) and _director.grid.is_open(candidate, side):
				here = candidate
				next = n
				found = true
				break
		if found:
			break
	player.warp_to(RoomDefs.cell_to_world(here) + Vector3(0.0, 0.8, 0.0))
	await _wait(0.5)
	_check("there is a room next door", found, "")
	_escape.keys_held[0] = 1
	_escape.equipped[0] = 1
	await _wait(0.3)
	_check("the candle is away", not player.is_candle_lit(), "")
	_check("the maze around a prisoner without a candle stays", _director.grid.has_cell(next), "")
	var thief := _spawn(&"thief", next) as Thief
	_check("a monster in the next room does not go after them", _director.can_chase(player, next) == false and thief.nearest_player() == null, "")
	_check("one in their own room does", _director.can_chase(player, here) and _director.can_chase(player, _director.cell_at(player.global_position)), "")
	_escape.equipped[0] = 0
	await _wait(0.3)
	_check("with the candle burning it can be hunted from the dark", _director.can_chase(player, next), "")
	_escape.keys_held[0] = 0
	thief.queue_free()


func _rules() -> void:
	print("-- weaver path, webs, leech, sight")
	var player := _game.players[0]
	player.reset_position()
	player.relight()
	await _wait(1.0)
	var here := _director.cell_at(player.global_position)
	var found := _director.reachable(here, 4)
	# The farthest room the prisoner cannot see (a dead end near the start may leave none within two doorways).
	var far := here
	var seen: Dictionary = _director.sight.cells_for(player)
	for cell in found:
		if not seen.has(cell) and found[cell].steps > found[far].steps:
			far = cell
	var web := Web.new()
	_check("a web lasts about ten seconds", is_equal_approx(web.lifetime, 10.0), "%.1f" % web.lifetime)
	web.free()
	# The weaver crawls floor, wall, ceiling: never across the room through the air.
	var weaver := _spawn(&"weaver", here) as Weaver
	var wall := Vector3(0.0, 0.0, -1.0)
	var last := weaver._path_position(wall, 0.0)
	var smooth := true
	var on_surface := true
	var t := 0.05
	while t <= 5.0:
		var at := weaver._path_position(wall, t)
		smooth = smooth and at.distance_to(last) < 0.2
		on_surface = on_surface and (at.y < 0.01 or absf(at.z) > weaver.wall_surface - 0.4 or at.y > weaver.ceiling_height - 0.01)
		last = at
		t += 0.05
	_check("the weaver's path has no jumps", smooth, "")
	_check("and keeps to the floor, the wall and the ceiling", on_surface, "")
	_check("it ends up on the ceiling, not in the air below it", is_equal_approx(weaver._path_position(wall, 5.0).y, weaver.ceiling_height), "")
	weaver.queue_free()
	# The leech: a minute's timer, and it stays behind when the prisoner falls.
	var leech := _spawn(&"leech", here) as Leech
	_check("a leech clings for a minute", is_equal_approx(leech.slow_seconds, 60.0), "%.0f" % leech.slow_seconds)
	_director._immune.clear()
	_director.hit(leech, player)
	_check("the prisoner is slowed", player.is_slowed(), "")
	var spot := leech.global_position
	player.fell.emit()
	player.global_position += Vector3(40.0, 0.0, 0.0)
	await _wait(0.2)
	_check("a fall frees them of it", not player.is_slowed() and not leech.is_clinging(), "")
	_check("and it does not go with them", leech.global_position.distance_to(player.global_position) > 20.0 and leech.global_position.distance_to(spot) < 5.0, "")
	leech.queue_free()
	player.reset_position()
	await _wait(0.8)
	# What is in a room out of sight is not shown.
	here = _director.cell_at(player.global_position)
	var near := _spawn(&"thief", here) as Thief
	var out_of_sight := _spawn(&"thief", far) as Thief
	await _wait(0.3)
	_check("a monster in a room they can see is shown", near.visible, "")
	_check("one in a room they cannot see is hidden", not out_of_sight.visible, "")
	near.queue_free()
	out_of_sight.queue_free()
	_director._immune.clear()


func _chase() -> void:
	print("-- chasing round corners")
	var player := _game.players[0]
	player.reset_position()
	player.relight()
	await _wait(1.0)
	_director._immune.clear()
	var here := _director.cell_at(player.global_position)
	var found := _director.reachable(here, 4)
	var far := here
	for cell in found:
		if found[cell].steps == 1 and _director.is_lit(player, cell):
			far = cell
	_check("there is a lit room a doorway away to chase from", far != here, "")
	_escape.keys_held[0] = 1
	var thief := _director.spawn(&"thief", far) as Thief
	await _wait(0.1)
	var waited := 0.0
	while waited < 15.0 and is_instance_valid(thief) and not thief.is_carrying():
		await _wait(0.25)
		waited += 0.25
	_check("a thief walks the doorways to the prisoner and takes the key", is_instance_valid(thief) and thief.is_carrying(), "%d doorways, waited %.1f s" % [found[far].steps, waited])
	if is_instance_valid(thief):
		thief.queue_free()
	_escape.keys_held[0] = 0
	player.relight()
	_director._immune.clear()


func _new_behaviour() -> void:
	print("-- moth, thief, leech, weaver, mimic")
	var player := _game.players[0]
	player.reset_position()
	player.relight()
	await _wait(0.8)
	_director._immune.clear()
	var here := _director.cell_at(player.global_position)
	var moth := _spawn(&"moth", here) as Moth
	moth.global_position = Vector3(player.candle_position().x + 0.3, 0.0, player.candle_position().z)
	moth._touch()
	_check("a moth that reaches the flame snuffs it", player.is_snuffed(), "")
	_check("and burns up doing it", moth._falling, "")
	await _wait(0.8)
	_check("then it is gone", not is_instance_valid(moth), "")
	player.relight()
	_director._immune.clear()
	var bag: ItemBag = _game.get_node("ItemBag")
	bag.setup(1)
	bag.add(0, &"matches", 3)
	var thief := _spawn(&"thief", here) as Thief
	_director.hit(thief, player)
	_check("a thief takes an item when there is no key", thief.is_carrying() and bag.count(0, &"matches") == 2, "%s" % thief._loot)
	thief.stun(2.0)
	await _wait(0.1)
	var lying := _manager.view.room_at(here).find_children("*", "ItemPickup", false, false)
	_check("a stunned thief drops it where it stands (the prisoner there picks it up again)", not thief.is_carrying() and (lying.size() >= 1 or bag.count(0, &"matches") == 3), "%d lying, %d carried" % [lying.size(), bag.count(0, &"matches")])
	thief.queue_free()
	player.relight()
	_director._immune.clear()
	var leech := _spawn(&"leech", here) as Leech
	_director.hit(leech, player)
	_check("a leech snuffs the candle and clings", player.is_snuffed() and leech.is_clinging(), "")
	_check("the prisoner walks slower", player.speed_scale() < 1.0 and player.is_slowed(), "%.2f" % player.speed_scale())
	leech.slow_seconds = 0.5
	leech._timer = 0.5
	leech.set_physics_process(true)
	player._slow_left = 0.5
	await _wait(1.5)
	_check("and when its time is up the prisoner is quick again", not player.is_slowed() and player.speed_scale() == 1.0, "")
	_check("the leech fades away", not is_instance_valid(leech), "")
	player.relight()
	_director._immune.clear()
	await _exits_built(here)
	var weaver := _spawn(&"weaver", here) as Weaver
	var landed := _director.hit(weaver, player)
	var side := weaver._web_side
	_check("a weaver that snuffs a candle builds a web across a doorway and hangs on it",
			weaver._state == Weaver.State.PERCH and _director.has_web(weaver._web_cell, side), "hit %s state %d" % [landed, weaver._state])
	_manager.view.room_at(here).find_children("*", "Web", false, false).map(func(web: Node) -> void: web.queue_free())
	await _wait(0.2)
	weaver._act(0.1)
	_check("when the web is burnt away it comes down to hunt", weaver._state == Weaver.State.HUNT, "")
	weaver.queue_free()
	player.relight()
	_director._immune.clear()


func _mimic() -> void:
	print("-- mimic")
	var player := _game.players[0]
	var here := _director.cell_at(player.global_position)
	await _exits_built(here)
	var found := _director.reachable(here, 4)
	var far := here
	for cell in found:
		if found[cell].steps > found[far].steps:
			far = cell
	var near := here
	for cell in found:
		if found[cell].steps == 2:
			near = cell
	var thief := _spawn(&"thief", far) as Thief
	var mimic := _director.spawn(&"mimic", near) as Mimic
	mimic.lead_distance = 30.0
	mimic.hits_on_touch = false
	var start := _director.offset(mimic.global_position, thief.global_position).length()
	await _wait(0.3)
	_check("the mimic leads with the tag mode's chase set to it and the thief", _director.pursuit.hunter == mimic and _director.pursuit.prey.has(thief), "")
	var waited := 0.0
	while waited < 20.0 and is_instance_valid(mimic) and mimic._state != Mimic.State.AT_THIEF:
		player.global_position = mimic.global_position + Vector3(-3.0, 0.8, 0.0) if false else player.global_position
		await _wait(0.25)
		waited += 0.25
	var finish := _director.offset(mimic.global_position, thief.global_position).length() if is_instance_valid(mimic) else 999.0
	_check("it walks the course toward the thief", finish < start, "%.1f -> %.1f" % [start, finish])
	if is_instance_valid(thief):
		thief.queue_free()
	await _wait(0.3)
	_check("with the thief gone the chase stops", _director.pursuit.hunter != mimic, "")
	if is_instance_valid(mimic):
		mimic.queue_free()


## Waits (up to a few seconds) for the rooms round `cell` to be built after the prisoner came back to it.
func _exits_built(cell: Vector2i) -> void:
	var waited := 0.0
	while waited < 4.0 and _director.reachable(cell, 3).size() < 4:
		await _wait(0.25)
		waited += 0.25


func _no_way() -> void:
	print("-- no way through")
	var player := _game.players[0]
	var here := _director.cell_at(player.global_position)
	var far := player.global_position + Vector3(60.0, 0.0, 0.0)
	_check("a target in rooms that do not exist has no path", _director.next_step(here, _director.cell_at(far)) == null, "")
	var farthest := here
	var found := _director.reachable(here, 14)
	for room in found:
		if found[room].steps > found[farthest].steps:
			farthest = room
	far = RoomDefs.cell_to_world(farthest) + Vector3(RoomDefs.cell_to_world(farthest) - RoomDefs.cell_to_world(here)).normalized() * 30.0
	var step: Variant = _director.closest_step(here, far)
	_check("but a monster still steps toward it, as near as the rooms allow", step != null or _director.reachable(here, 14).size() == 1, "%s" % [step])


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
	await _wait(1.4)
	_check("a monster fades out when its room goes", not is_instance_valid(moth) or moth.is_queued_for_deletion(), "")
	_check("and is gone from the Director", _director.monsters.is_empty(), "%d left" % _director.monsters.size())


func _spawning() -> void:
	print("-- spawning")
	_game.players[0].reset_position()
	_game.players[0].relight()
	await _wait(1.0)
	_director.enabled = true
	_director.grace_seconds = 0.0
	_director.spawn_interval = 0.2
	_director.spawn_min_cells = 1
	_director._spawn_timer = 0.0
	var waited := 0.0
	while _director.monsters.is_empty() and waited < 12.0:
		await _wait(0.25)
		waited += 0.25
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
	await _wait(2.0)
	Input.action_release(GameInput.action(0, &"interact"))
	_check("holding it beside a lit candle lights it again", not a.is_snuffed() and a.is_candle_lit(), "")
	a.snuff()
	b.global_position = a.global_position + Vector3(6.0, 0.0, 0.0)
	Input.action_press(GameInput.action(0, &"interact"))
	await _wait(2.0)
	Input.action_release(GameInput.action(0, &"interact"))
	_check("too far from the light, it stays out", a.is_snuffed(), "")
	relighting.fallback_seconds = 0.5
	await _wait(2.0)
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
