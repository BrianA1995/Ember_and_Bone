extends Node
## Checks how a lost hunter is helped: the route finder plans a walkable route through empty
## space across the seam and the maze builds it open as someone walks it, a flame leans toward
## the nearest prey (only for the hunter), and the lost meter and the room odds behave: close
## prey means no help, far prey after a long time means the most.
## Run debug/pursuit_test.tscn and read the output for "PURSUIT TEST".

var _failures := 0


func _ready() -> void:
	_route_through_empty_space()
	await _tag_game()
	print("PURSUIT TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _route_through_empty_space() -> void:
	print("-- route finder")
	var grid := MazeGrid.new(7, Vector2i(30, 30))
	grid.wrap_edges = true
	grid.generate_start(Vector2i.ZERO, &"start_chamber")
	var goal := Vector2i(-12, 9)
	_check("a far cell can be made a goal", grid.generate_landing(goal), "")
	var from := Vector2i.ZERO
	var path := RouteFinder.find(grid, from, goal)
	_check("a route is found across the empty space", path.size() > 1 and path[0] == from and path[-1] == goal, "%d cells" % path.size())
	var apart := (goal - from).abs()
	var shortest := mini(apart.x, 30 - apart.x) + mini(apart.y, 30 - apart.y)
	_check("it takes the short way round the loop (%d steps at best)" % shortest, path.size() - 1 >= shortest and path.size() - 1 <= shortest + 4, "%d steps" % (path.size() - 1))
	var contiguous := true
	for i in path.size() - 1:
		contiguous = contiguous and (path[i] - path[i + 1]).abs().x + (path[i] - path[i + 1]).abs().y in [1, 29]
	_check("every step goes to a neighbouring cell", contiguous, "")

	print("-- building the route as someone walks it")
	grid.route = RouteFinder.required_sides(grid, path)
	var walked := true
	for i in path.size() - 1:
		var side := -1
		for s in RoomDefs.SIDE_COUNT:
			if grid.neighbor(path[i], s) == path[i + 1]:
				side = s
		walked = walked and grid.is_open(path[i], side) and grid.reveal_beyond(path[i], side) and grid.is_open(path[i + 1], RoomDefs.opposite(side))
		if not walked:
			print("    stuck at step %d, %s -> %s" % [i, path[i], path[i + 1]])
			break
	_check("the rooms along the route are built open, end to end", walked, "")
	_check("and the maze is still legal", grid.validate().problems.is_empty(), "%s" % [grid.validate().problems])
	_check("a wall already in the way is respected, not overridden", _walled_route_ok(), "")


## A built room's wall is never planned through, and a side its neighbour closed is not forced open.
func _walled_route_ok() -> bool:
	var grid := MazeGrid.new(3, Vector2i(30, 30))
	grid.wrap_edges = true
	grid.generate_start(Vector2i.ZERO, &"start_chamber")
	var goal := Vector2i(6, 0)
	grid.generate_landing(goal)
	var path := RouteFinder.find(grid, Vector2i.ZERO, goal)
	for i in path.size() - 1:
		for s in RoomDefs.SIDE_COUNT:
			if grid.neighbor(path[i], s) == path[i + 1]:
				if grid.has_cell(path[i]) and not grid.is_open(path[i], s):
					return false
				if grid.has_cell(path[i + 1]) and not grid.is_open(path[i + 1], RoomDefs.opposite(s)):
					return false
	return not path.is_empty()


func _tag_game() -> void:
	print("-- a lost hunter")
	GameSettings.game_mode = GameSettings.GameMode.TAG
	GameSettings.player_count = 2
	GameSettings.tag_points = 500
	GameSettings.maze_size = 30
	GameInput.configure(2)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	var pursuit: Pursuit = game.get_node("Pursuit")
	var tag := game.tag
	tag.head_start = 0.0
	tag.reset()
	pursuit.ramp_seconds = 5.0
	pursuit.near_cells = 3.0
	pursuit.far_cells = 8.0
	pursuit.route_pressure = 0.7
	pursuit.route_refresh = 0.5
	await _wait(0.2)
	var hunter: Player = game.players[tag.it_slot]
	var runner: Player = game.players[1 - tag.it_slot]
	_check("the one who is it is the hunter", pursuit.hunter == hunter and pursuit.prey == [runner], "")

	hunter.warp_to(Vector3(0, 0.8, 0))
	runner.warp_to(Vector3(8, 0.8, 0))
	runner.set_physics_process(false)
	await _wait(1.0)
	_check("close prey: no pressure however long", pursuit.pressure == 0.0, "%.2f" % pursuit.pressure)
	_check("the flame still leans toward them", hunter.flame_lean() > 0.5, "%.2f rad" % hunter.flame_lean())
	_check("and only the hunter's flame", runner.flame_lean() < 0.01, "%.2f rad" % runner.flame_lean())
	var grid: MazeGrid = game.get_node("MazeManager").grid
	_check("and no route is laid", grid.route.is_empty(), "")

	runner.warp_to(Vector3(-44, 0.8, 0))
	await _wait(1.0)
	_check("far prey, some time passed: some pressure", pursuit.pressure > 0.0 and pursuit.pressure < 1.0, "%.2f" % pursuit.pressure)
	_check("the flame points the short way, across the seam", hunter.flame_lean() > 0.5, "")
	var toward := pursuit.room_weight(Vector2i(0, 0), 1 << 3)
	var away := pursuit.room_weight(Vector2i(0, 0), 1 << 1)
	_check("rooms opening toward the prey are likelier (west is short way round)", toward > 1.0 and away <= 1.0 + 0.001, "toward %.2f away %.2f" % [toward, away])
	var far_cell_weight := pursuit.room_weight(Vector2i(15, 0), 1 << 3)
	_check("rooms far from the hunter are left alone", far_cell_weight == 1.0, "%.2f" % far_cell_weight)

	await _wait(5.0)
	_check("lost for long enough: full pressure", pursuit.pressure > 0.95, "%.2f" % pursuit.pressure)
	_check("so a route is laid", not grid.route.is_empty(), "%d cells" % grid.route.size())
	var full := pursuit.room_weight(Vector2i(0, 0), 1 << 3)
	_check("and the odds reach the maximum", absf(full - pursuit.bias_max) < 0.5, "%.2f" % full)

	runner.warp_to(Vector3(8, 0.8, 0))
	await _wait(0.5)
	_check("prey close again: the route is taken away", grid.route.is_empty() and pursuit.pressure == 0.0, "")

	print("-- passing the tag")
	pursuit.ramp_seconds = 300.0
	await _wait(0.5)
	tag.pass_tag(1 - tag.it_slot)
	await _wait(0.2)
	_check("the new hunter's clock starts at zero", pursuit.hunter == runner and pursuit.lost_time < 0.5, "%.2f" % pursuit.lost_time)
	await _wait(1.0)
	_check("the old hunter's flame stands up again", hunter.flame_lean() < 0.2 and runner.flame_lean() > 0.5, "%.2f / %.2f" % [hunter.flame_lean(), runner.flame_lean()])
	game.queue_free()
	await get_tree().process_frame


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
