extends Node
## Checks the wrapping maze: the grid stays legal when rooms join across the seam (a long
## random walk over several seeds), positions wrap, and a real player walking out of a doorway
## on the east edge comes out of the west edge standing on a floor.
## Run debug/wrap_test.tscn and read the output for "WRAP TEST".

const SIZE := 20

var _failures := 0


func _ready() -> void:
	_check_neighbours()
	for seed_value in [11, 22, 33, 44, 55]:
		_walk(seed_value)
	await _walk_through_the_seam()
	print("WRAP TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _check_neighbours() -> void:
	print("-- neighbours")
	var grid := MazeGrid.new(1, Vector2i(SIZE, SIZE))
	var east := Vector2i(SIZE / 2 - 1, 3)
	_check("without wrapping, the edge has nothing beyond it", not grid.in_bounds(grid.neighbor(east, 1)), "")
	grid.wrap_edges = true
	_check("wrapping, east of the east edge is the west edge", grid.neighbor(east, 1) == Vector2i(-SIZE / 2, 3), "%s" % grid.neighbor(east, 1))
	_check("and north of the north edge is the south edge", grid.neighbor(Vector2i(2, -SIZE / 2), 0) == Vector2i(2, SIZE / 2 - 1), "")
	_check("a cell inside is untouched", grid.wrap_cell(Vector2i(3, -4)) == Vector2i(3, -4), "")


## A light wanders at random through open doorways for a long time; the grid must never
## contain an illegal connection, including across the seam.
func _walk(seed_value: int) -> void:
	var grid := MazeGrid.new(seed_value, Vector2i(SIZE, SIZE))
	grid.wrap_edges = true
	grid.generate_start(Vector2i.ZERO, &"start_chamber")
	var reveal := RevealCollapse.new(grid)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cell := Vector2i.ZERO
	var crossings := 0
	var problems := 0
	for step in 6000:
		reveal.update([{"cell": cell, "radius": 2}], 0.5)
		var open: Array[int] = []
		for side in RoomDefs.SIDE_COUNT:
			if grid.is_open(cell, side) and grid.has_cell(grid.neighbor(cell, side)):
				open.append(side)
		if open.is_empty():
			cell = Vector2i.ZERO if grid.has_cell(Vector2i.ZERO) else cell
			continue
		var next := grid.neighbor(cell, open[rng.randi() % open.size()])
		if absi(next.x - cell.x) > 1 or absi(next.y - cell.y) > 1:
			crossings += 1
		cell = next
		if step % 25 == 0:
			problems += grid.validate().problems.size()
	_check("seed %d: legal everywhere, %d seam crossings" % [seed_value, crossings], problems == 0 and crossings > 0, "%d problems" % problems)


func _walk_through_the_seam() -> void:
	print("-- walking through the seam")
	GameSettings.player_count = 1
	GameSettings.maze_size = SIZE
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	var manager: MazeManager = game.get_node("MazeManager")
	manager.start_collapse_delay = 0.0
	var seam: SeamWrap = null
	for child in manager.get_children():
		if child is SeamWrap:
			seam = child
	_check("the maze wraps and has a size of %d" % SIZE, manager.grid.wrap_edges and manager.grid.bounds.size == Vector2i(SIZE, SIZE), "%s" % manager.grid.bounds)
	_check("a point past the east edge wraps to the west", seam != null and is_equal_approx(seam.wrapped(Vector3(38.5, 0.8, 0.0)).x, -41.5), "")
	_check("and one past the north edge to the south", seam != null and is_equal_approx(seam.wrapped(Vector3(0.0, 0.8, -42.5)).z, 37.5), "")
	var player: Player = game.players[0]
	var east_x := SIZE / 2 - 1
	var found := false
	for z in range(-SIZE / 2 + 2, SIZE / 2 - 2):
		player.warp_to(Vector3(east_x * 4.0, 0.8, z * 4.0))
		await _wait(0.8)
		if manager.grid.is_open(Vector2i(east_x, z), 1):
			found = true
			break
	_check("found a doorway on the east edge", found, "")
	if found:
		var row := RoomDefs.world_to_cell(player.global_position).y
		Input.action_press(&"move_right")
		await _wait(2.0)
		Input.action_release(&"move_right")
		var cell := RoomDefs.world_to_cell(player.global_position)
		_check("the player came out on the west edge, same row", cell.x < -SIZE / 2 + 2 and cell.y == row, "cell %s" % cell)
		_check("standing on the floor, not falling", absf(player.global_position.y - 0.8) < 0.05 and not player.get("_falling"), "height %.2f" % player.global_position.y)
		await _wait(1.0)
		_check("the maze is still legal", manager.grid.validate().problems.is_empty(), "")
	game.queue_free()


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
