extends Node
## Measures how much the pursuit help actually shortens a hunt. A walker who follows the compass
## (always the open doorway that gets it closest to the prey, avoiding rooms it has been in)
## looks for a prey 12 cells away, in a real maze that builds itself around two candles, one step
## a second. The same 25 mazes are walked with no help, with the odds and doorway easing only, and
## with the guaranteed route too. Prints steps taken; fails if help does not beat no help.
## Run debug/pursuit_walk_test.tscn and read the output for "PURSUIT WALK TEST".

const SEEDS := 25
const MAX_STEPS := 1500
const PREY_CELL := Vector2i(12, 3)

var _failures := 0


func _ready() -> void:
	var none := _run("no help", func(p: Pursuit) -> void:
		p.bias_enabled = false
		p.route_enabled = false)
	var odds := _run("odds + no walls", func(p: Pursuit) -> void:
		p.route_enabled = false)
	var full := _run("default settings", func(_p: Pursuit) -> void: pass)
	_check("help shortens the hunt on average", full.mean < none.mean * 0.6, "%.0f vs %.0f steps" % [full.mean, none.mean])
	_check("and the worst hunts too", full.worst <= none.worst, "%d vs %d" % [full.worst, none.worst])
	_check("the route finds the prey almost every time", full.misses <= 1, "%d of %d missed" % [full.misses, SEEDS])
	print("PURSUIT WALK TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _run(label: String, configure: Callable) -> Dictionary:
	var counts: Array[int] = []
	var misses := 0
	for seed_value in range(1, SEEDS + 1):
		var steps := _hunt(seed_value, configure)
		counts.append(steps)
		if steps >= MAX_STEPS:
			misses += 1
	counts.sort()
	var total := 0
	for steps in counts:
		total += steps
	var result := {"mean": float(total) / counts.size(), "median": counts[counts.size() / 2], "worst": counts[-1], "misses": misses}
	print("  %-18s mean %5.0f   median %4d   worst %4d   gave up %d of %d" % [label, result.mean, result.median, result.worst, misses, SEEDS])
	return result


## One hunt in one maze: the steps the walker takes to get next to the prey (MAX_STEPS if it never does).
func _hunt(seed_value: int, configure: Callable) -> int:
	var grid := MazeGrid.new(seed_value, Vector2i(30, 30))
	grid.wrap_edges = true
	grid.generate_start(Vector2i.ZERO, &"start_chamber")
	grid.generate_landing(PREY_CELL)
	var reveal := RevealCollapse.new(grid)
	var hunter := Node3D.new()
	var prey := Node3D.new()
	add_child(hunter)
	add_child(prey)
	prey.position = RoomDefs.cell_to_world(PREY_CELL)
	var pursuit := Pursuit.new()
	add_child(pursuit)
	pursuit.bind_grid(grid)
	configure.call(pursuit)
	pursuit.set_chase(hunter, [prey])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var visits := {}
	var cell := Vector2i.ZERO
	var found := MAX_STEPS
	for step in MAX_STEPS:
		hunter.position = RoomDefs.cell_to_world(cell)
		reveal.update([_light(cell, 2), _light(PREY_CELL, 1)], 1.0)
		pursuit._physics_process(1.0)
		if _apart(grid, cell, PREY_CELL) <= 1.0:
			found = step
			break
		visits[cell] = visits.get(cell, 0) + 1
		var best := cell
		var best_score := INF
		for side in RoomDefs.SIDE_COUNT:
			var next := grid.neighbor(cell, side)
			if not grid.is_open(cell, side) or not grid.has_cell(next):
				continue
			var score: float = _apart(grid, next, PREY_CELL) + 2.5 * visits.get(next, 0) + rng.randf() * 0.4
			if score < best_score:
				best_score = score
				best = next
		cell = best
	hunter.queue_free()
	prey.queue_free()
	pursuit.queue_free()
	return found


## Cells between two cells, the short way round the loop.
func _apart(grid: MazeGrid, a: Vector2i, b: Vector2i) -> float:
	var d := (a - b).abs()
	return Vector2(mini(d.x, grid.bounds.size.x - d.x), mini(d.y, grid.bounds.size.y - d.y)).length()


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])


## A candle in `cell`, as the maze manager sees one: where it is, how far its light can be seen
## (rooms that were in sight and no longer are get swapped for new ones).
func _light(cell: Vector2i, radius: int) -> Dictionary:
	return {"cell": cell, "radius": radius, "position": RoomDefs.cell_to_world(cell), "reach": 5.5}
