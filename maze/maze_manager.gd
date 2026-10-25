class_name MazeManager
extends Node3D
## Wires the maze systems together: owns the grid, feeds it every light source each
## physics tick, and tells the MazeView what to show.
##
## A light source is any node in the "light_sources" group with a `light_radius` (cells that
## exist around it) and a `change_distance` (metres beyond which its light can't be seen).

signal maze_rebuilt

@export var map_seed := 0
@export var grid_size := Vector2i(21, 21)
## The maze is a loop: leaving one edge comes out on the opposite one (see SeamWrap).
@export var wrap_edges := false
## The room the run starts in (RoomDefs.PIECES), placed with its origin cell at (0, 0).
@export var start_piece: StringName = &"start_chamber"
## Chance that a doorway the light reaches is blocked by a wall instead of leading on.
## A block only goes in if the room keeps at least two other exits (it prunes a branch).
@export_range(0.0, 1.0, 0.05) var block_chance := 0.2
## Off: any room can be built anywhere as long as it opens toward the doorway that led to it, and a
## doorway left facing a wall (the new room's or a neighbour's) is walled up. On: a new room must
## also agree with every room already beside it.
@export var match_neighbours := false
## Chance that a block may leave a room with one exit: a true dead end. Keep this low.
@export_range(0.0, 1.0, 0.05) var dead_end_chance := 0.2
## Chance that a straight corridor room has a cracked floor that gives way underfoot.
@export_range(0.0, 1.0, 0.05) var crack_chance := 0.25
## How strongly junctions are favoured after a run of plain corridor rooms.
@export_range(0.0, 2.0, 0.1) var junction_boost := 0.5
## Optional piece -> weight overrides, e.g. {&"corner": 2.0}.
@export var weights: Dictionary = {}
## A body that falls lands at least this many cells from where it fell (less if there is no room).
@export var landing_distance := 6
## Landing rooms stay this many cells inside the edge of the maze.
@export var landing_margin := 2
## Seconds into the run before the start room's floor gives way. 0 or less: it never does.
@export var start_collapse_delay := 30.0
@export_group("Collapse")
@export var collapse_enabled := true:
	set = set_collapse_enabled
## Seconds a room that is no longer next to the player (or not connected to their room
## by an open doorway) survives before it starts cracking, then until it is removed.
@export var unlit_delay := 0.15
@export var crack_duration := 0.2

var grid: MazeGrid
var reveal: RevealCollapse
## The countdown to the start room's collapse, or null if it has none.
var start_collapse: StartCollapse
## Carries lights across the edges of a wrapping maze.
var seam: SeamWrap

@onready var view: MazeView = $MazeView


func _ready() -> void:
	add_to_group("maze_manager")
	seam = SeamWrap.new()
	seam.manager = self
	add_child(seam)
	build(map_seed)


func _physics_process(delta: float) -> void:
	var sources := _light_sources()
	# A light with no radius is a player standing in the dark: rooms around them must not be seen to move.
	view.instant = sources.any(func(source: Dictionary) -> bool: return source.radius == 0)
	reveal.update(sources, delta)
	view.instant = false


## Builds a fresh maze. Seed 0 picks a random one.
func build(new_seed: int = 0) -> void:
	if new_seed == 0:
		new_seed = randi_range(1, 2147483647)
	grid = MazeGrid.new(new_seed, grid_size, weights)
	grid.match_neighbours = match_neighbours
	grid.block_chance = block_chance
	grid.dead_end_chance = dead_end_chance
	grid.crack_chance = crack_chance
	grid.junction_boost = junction_boost
	grid.wrap_edges = wrap_edges
	reveal = RevealCollapse.new(grid)
	reveal.collapse_enabled = collapse_enabled
	reveal.unlit_delay = unlit_delay
	reveal.crack_duration = crack_duration
	view.bind(grid, reveal)
	# The starting room appears fully built: the player is standing in it, and a room rising
	# through them would shove them around.
	var rise := view.rise_time
	view.rise_time = 0.0
	grid.generate_start(Vector2i.ZERO, start_piece)
	view.rise_time = rise
	if start_collapse:
		start_collapse.queue_free()
		start_collapse = null
	if start_collapse_delay > 0.0:
		start_collapse = StartCollapse.new()
		start_collapse.delay = start_collapse_delay
		add_child(start_collapse)
		start_collapse.start(view, Vector2i.ZERO)
	maze_rebuilt.emit()


## New random maze, and everything that carries light goes back to the start.
func restart() -> void:
	build(0)
	for node in get_tree().get_nodes_in_group("light_sources"):
		if node.has_method("reset_position"):
			node.reset_position()


## Where a body that fell ends up: the middle of a new room well away from where it was. The
## room is built here and now; the maze grows out from it as the light reaches, and the old
## part of the maze goes dark and collapses behind.
func landing_point(from: Vector3) -> Vector3:
	var here := RoomDefs.world_to_cell(from)
	var inner := grid.bounds.grow(-landing_margin)
	var far: Array[Vector2i] = []
	for distance in range(landing_distance, -1, -2):
		for x in range(inner.position.x, inner.end.x):
			for y in range(inner.position.y, inner.end.y):
				var cell := Vector2i(x, y)
				if maxi(absi(x - here.x), absi(y - here.y)) >= distance and not grid.has_cell(cell):
					far.append(cell)
		if not far.is_empty():
			break
	far.shuffle()
	# The room appears fully built: the body lands in it, and a floor rising through it would
	# shove it around (or drop it again).
	var rise := view.rise_time
	view.rise_time = 0.0
	var spot := from
	for cell in far:
		if grid.generate_landing(cell):
			spot = RoomDefs.cell_to_world(cell)
			break
	view.rise_time = rise
	return spot


func set_collapse_enabled(value: bool) -> void:
	collapse_enabled = value
	if reveal:
		reveal.collapse_enabled = value


func _light_sources() -> Array:
	var sources := []
	for node in get_tree().get_nodes_in_group("light_sources"):
		# A light a step past an edge, about to be carried across it, already counts as on the far side.
		var position: Vector3 = seam.wrapped(node.global_position) if seam else node.global_position
		sources.append({
			"cell": RoomDefs.world_to_cell(position),
			"radius": node.light_radius,
			"position": position,
			"reach": node.change_distance,
		})
	return sources
