extends Node
## Headless logic test for the maze. Walks a fake player around many mazes and checks,
## after every step, that no connection is illegal and the player is never boxed in.
## Run debug/maze_stress_test.tscn and read the output for "MAZE STRESS TEST".
##
## It also reports how the maze feels, so it can be tuned by numbers:
##  - the mix of room types built, and how many doorways were blocked
##  - how often the player stands in a dead end / a plain passage / a junction
##  - a backtrack trial: walk forward, wait for the collapse, walk back, and see how
##    different and how branching the way back is
##
## A "seal" is a moment when every doorway in the reachable maze leads to an existing
## cell. That is normal briefly (dark cells are still waiting to collapse) but it must
## clear itself once they fall, so only a seal lasting longer than `max_seal_steps`
## (one step = one second) counts as a failure.

@export var runs := 25
@export var steps := 2000
## Cells kept alive around the player (matches Player: candle reach 1 + dark margin 1).
@export var light_radius := 2
## Rooms further than this from the player (metres) have gone dark and get replaced.
@export var change_distance := 6.0
@export var block_chance := 0.2
@export var dead_end_chance := 0.2
@export var junction_boost := 0.5
@export var max_seal_steps := 12
## How far the candle's light plus its hold position can be seen from the player, in metres
## (Candle range 6.5 + 0.5). No room may be created, blocked or removed closer than this.
@export var visible_reach := 7.0
@export var backtrack_trials := 20
@export var backtrack_length := 8


func _ready() -> void:
	var total := _new_stats()
	for run in runs:
		_run(1000 + run, total)
	var rooms := maxi(total.rooms_built, 1)
	var visits := maxi(total.visits, 1)
	var back := maxi(total.back_steps, 1)
	print("MAZE STRESS TEST: %s - %d runs x %d steps, %d failures" % [
		"PASS" if total.failures == 0 else "FAIL", runs, steps, total.failures])
	print("  rooms built %d: straight %d%%  corner %d%%  T %d%%  cross %d%%  dead-end piece %d%%" % [
		total.rooms_built, _pct(total.straight, rooms), _pct(total.corner, rooms),
		_pct(total.t_junction, rooms), _pct(total.cross, rooms), _pct(total.dead_end_piece, rooms)])
	print("  doorways blocked %d (%d left a true dead end)" % [total.blocked, total.blocked_dead_end])
	print("  walking: dead end %d%%  passage %d%%  junction (a choice) %d%% of time" % [
		_pct(total.visit_dead, visits), _pct(total.visit_pass, visits), _pct(total.visit_choice, visits)])
	print("  retreating (%d trials, %d steps): old route rebuilt differently in %d%% of trials" % [
		total.back_trials, total.back_steps, _pct(total.back_diverged, maxi(total.back_trials, 1))])
	print("    rooms on the way back that changed %d%%  |  at a dead end %d%%  |  at a junction %d%% of steps" % [
		_pct(total.back_changed, back), _pct(total.back_dead, back), _pct(total.back_choice, back)])
	print("  brief seals %d, live cells max %d" % [total.seals, total.peak_cells])
	# Straight-line distance ignores walls, so this is only a hint. Whether the player can
	# actually SEE a change is what debug/visibility_test.tscn checks, with ray casts.
	print("  closest straight-line distance from the player to a change: %.1f m (%s)" % [
		total.min_change, total.min_what])
	get_tree().quit(0 if total.failures == 0 else 1)


func _new_stats() -> Dictionary:
	return {"min_change": 1.0e9, "min_what": "", "player_world": Vector3.ZERO, "measure": false, "failures": 0, "seals": 0, "peak_cells": 0, "rooms_built": 0, "blocked": 0,
			"blocked_dead_end": 0, "straight": 0, "corner": 0, "t_junction": 0, "cross": 0,
			"dead_end_piece": 0, "visits": 0, "visit_dead": 0, "visit_pass": 0, "visit_choice": 0,
			"back_steps": 0, "back_changed": 0, "back_dead": 0, "back_choice": 0, "back_trials": 0,
			"back_diverged": 0}


func _pct(part: int, whole: int) -> int:
	return roundi(100.0 * part / whole)


func _make_grid(map_seed: int, stats: Dictionary) -> MazeGrid:
	var grid := MazeGrid.new(map_seed)
	grid.block_chance = block_chance
	grid.dead_end_chance = dead_end_chance
	grid.junction_boost = junction_boost
	grid.side_sealed.connect(func(cell: Vector2i, side: int) -> void:
		stats.blocked += 1
		if _open_sides(grid, cell) == 1:
			stats.blocked_dead_end += 1
		# The wall sits at the cell edge; count its nearest end (half a doorway width in).
		var wall := RoomDefs.cell_to_world(cell) + Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y) * 1.9
		_note_change(stats, maxf(_flat_distance(stats.player_world, wall) - 1.0, 0.0),
				"block on side %d of cell %s" % [side, cell]))
	grid.cell_removed.connect(func(cell: Vector2i) -> void:
		_note_change(stats, _cell_distance(stats.player_world, cell), "removed cell %s" % cell))
	grid.cell_added.connect(func(cell: Vector2i) -> void:
		_note_change(stats, _cell_distance(stats.player_world, cell), "created cell %s" % cell)
		stats.rooms_built += 1
		var piece: String = grid.get_cell(cell).piece
		if piece == "dead_end":
			piece = "dead_end_piece"
		stats[piece] += 1)
	return grid


## The player crosses `cell` toward `next`; near its far edge the rooms behind have gone dark.
func _walk_across(reveal: RevealCollapse, cell: Vector2i, next: Vector2i) -> void:
	var across := (RoomDefs.cell_to_world(next) - RoomDefs.cell_to_world(cell)) * 0.475
	reveal.update([_source(cell, RoomDefs.cell_to_world(cell) + across)], 0.5)


## A light source for the maze, standing at `world` (default: the middle of `cell`).
func _source(cell: Vector2i, world := Vector3.INF) -> Dictionary:
	var position := RoomDefs.cell_to_world(cell) if world == Vector3.INF else world
	return {"cell": cell, "radius": light_radius, "position": position, "reach": change_distance}


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Distance from a point to the nearest edge of a cell's square (0 if inside it).
func _cell_distance(point: Vector3, cell: Vector2i) -> float:
	var center := RoomDefs.cell_to_world(cell)
	var half := RoomDefs.CELL_SIZE / 2.0
	return Vector2(maxf(absf(point.x - center.x) - half, 0.0), maxf(absf(point.z - center.z) - half, 0.0)).length()


## Records how close to the player something changed (only while measuring).
func _note_change(stats: Dictionary, distance: float, what: String = "") -> void:
	if stats.measure and distance < stats.min_change:
		stats.min_change = distance
		stats.min_what = "%s, player at %s" % [what, stats.player_world]


## How many doorways of `cell` can be walked through, built beyond or not.
func _open_sides(grid: MazeGrid, cell: Vector2i) -> int:
	var count := 0
	for side in RoomDefs.SIDE_COUNT:
		if grid.is_open(cell, side):
			count += 1
	return count


## The neighbouring cells you can walk to from `cell`.
func _exits(grid: MazeGrid, cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for side in RoomDefs.SIDE_COUNT:
		var next := grid.neighbor(cell, side)
		if grid.is_open(cell, side) and grid.has_cell(next):
			result.append(next)
	return result


func _key(grid: MazeGrid, cell: Vector2i) -> String:
	var data := grid.get_cell(cell)
	return "%s/%d/%d" % [data.piece, data.rotation, data.sealed]


func _run(map_seed: int, stats: Dictionary) -> void:
	var grid := _make_grid(map_seed, stats)
	var reveal := RevealCollapse.new(grid)
	grid.generate_start(Vector2i.ZERO, &"cross")
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var pos := Vector2i.ZERO
	var previous := pos
	var seal_streak := 0
	stats.measure = true
	for step in steps:
		# The maze updates the instant the player crosses into a new cell, i.e. when they
		# stand on the boundary between the previous cell and this one (the worst case).
		stats.player_world = (RoomDefs.cell_to_world(previous) + RoomDefs.cell_to_world(pos)) * 0.5
		# The very first tick builds the starting area as the maze appears; it isn't an
		# update the player can watch happen, so it isn't measured.
		stats.measure = step > 0
		reveal.update([_source(pos, stats.player_world)], 1.0)
		stats.peak_cells = maxi(stats.peak_cells, grid.cell_count())
		var report := grid.validate()
		if not report.problems.is_empty():
			stats.failures += 1
			print("  seed %d step %d: %s" % [map_seed, step, report.problems[0]])
		if not grid.has_cell(pos):
			stats.failures += 1
			print("  seed %d step %d: player cell %s does not exist" % [map_seed, step, pos])
			return
		var exits := _exits(grid, pos)
		if exits.is_empty():
			stats.failures += 1
			print("  seed %d step %d: player at %s has no way out" % [map_seed, step, pos])
			return
		stats.visits += 1
		if exits.size() == 1:
			stats.visit_dead += 1
		elif exits.size() == 2:
			stats.visit_pass += 1
		else:
			stats.visit_choice += 1
		if grid.frontier_from(pos) == 0 and grid.cell_count() < grid.bounds.get_area():
			if seal_streak == 0:
				stats.seals += 1
			seal_streak += 1
			if seal_streak == max_seal_steps + 1:
				stats.failures += 1
				print("  seed %d step %d: maze stayed sealed around %s" % [map_seed, step, pos])
		else:
			seal_streak = 0
		var next: Vector2i = exits[rng.randi() % exits.size()]
		# Then the player walks across the cell toward the next one. Near its far edge the
		# rooms behind have gone dark, which is when they are replaced.
		var across := (RoomDefs.cell_to_world(next) - RoomDefs.cell_to_world(pos)) * 0.475
		stats.player_world = RoomDefs.cell_to_world(pos) + across
		reveal.update([_source(pos, stats.player_world)], 0.5)
		var walking_report := grid.validate()
		if not walking_report.problems.is_empty():
			stats.failures += 1
			print("  seed %d step %d (walking): %s" % [map_seed, step, walking_report.problems[0]])
		previous = pos
		pos = next
	stats.measure = false
	for trial in backtrack_trials:
		pos = _backtrack_trial(grid, reveal, rng, pos, stats)


## Walks forward, stands still until everything behind collapses, then walks back along
## the same path, noting how different and how branching the rebuilt way is.
func _backtrack_trial(grid: MazeGrid, reveal: RevealCollapse, rng: RandomNumberGenerator,
		start: Vector2i, stats: Dictionary) -> Vector2i:
	var path: Array[Vector2i] = [start]
	var before := {}
	var pos := start
	for i in backtrack_length:
		reveal.update([_source(pos)], 1.0)
		# What this room looks like while the player stands in it.
		before[pos] = _key(grid, pos)
		var options := _exits(grid, pos)
		if path.size() > 1 and options.size() > 1:
			options.erase(path[path.size() - 2])
		if options.is_empty():
			break
		var forward: Vector2i = options[rng.randi() % options.size()]
		_walk_across(reveal, pos, forward)
		pos = forward
		path.append(pos)
	reveal.update([_source(pos)], 0.0)
	before[pos] = _key(grid, pos)
	for second in int(reveal.unlit_delay + reveal.crack_duration) + 1:
		reveal.update([_source(pos)], 1.0)
	# Retreat: follow the old route while it still exists; once the rebuilt rooms no
	# longer connect to it, keep walking through whatever was built instead.
	var follow := path.size() - 2
	var previous := pos
	var diverged := false
	stats.back_trials += 1
	for i in backtrack_length:
		var exits := _exits(grid, pos)
		var next: Vector2i
		if follow >= 0 and exits.has(path[follow]):
			next = path[follow]
			follow -= 1
		else:
			if not diverged:
				diverged = true
				stats.back_diverged += 1
			var options: Array[Vector2i] = exits.duplicate()
			if options.size() > 1:
				options.erase(previous)
			next = options[rng.randi() % options.size()]
		_walk_across(reveal, pos, next)
		previous = pos
		pos = next
		reveal.update([_source(pos)], 1.0)
		stats.back_steps += 1
		if before.has(pos) and before[pos] != _key(grid, pos):
			stats.back_changed += 1
		var here := _exits(grid, pos)
		if here.size() == 1:
			stats.back_dead += 1
		elif here.size() >= 3:
			stats.back_choice += 1
	return pos
