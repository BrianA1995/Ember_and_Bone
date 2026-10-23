class_name Pursuit
extends Node
## Helps a hunter find its prey in a maze that only exists near candles. A hunter and its prey
## (tag: the player who is it and everyone else; later: a monster and the players) are set with
## set_chase(). Three things then help the hunter, the second and third more the longer they have
## been lost:
##
##  1. Flame compass (always on): the hunter's candle flame leans toward the nearest prey. The maze
##     wraps, so that is the short way round, even across a seam. Walls can still make it lie.
##  2. The maze favours the hunter: rooms built near the hunter are likelier to open toward the
##     prey (MazeGrid.guide). Only a nudge on the odds, it never forces a room.
##  3. Guaranteed route: once lost enough, a walkable route to the prey is planned (RouteFinder) and
##     the rooms along it are built open as the hunter reaches them (MazeGrid.route).
##
## How lost the hunter is, `pressure` (0-1), is how long since the chase began or the tag last
## passed, times how far away the prey is. Close prey means no help, whatever the time. All the
## numbers are exports: change them in the inspector, also while the game runs.

@export_group("Flame compass")
## How far the flame leans over when it points at the prey.
@export_range(0.0, 90.0, 1.0, "suffix:°") var flame_lean_degrees := 60.0
## How quickly the flame swings round to a new direction.
@export_range(0.5, 20.0, 0.5) var flame_lean_speed := 6.0

@export_group("How lost the hunter is")
## Seconds until time alone counts for everything.
@export_range(5.0, 300.0, 1.0, "suffix:s") var ramp_seconds := 15.0
## Prey this close (in cells) counts for nothing: the hunter isn't lost.
@export_range(0.0, 30.0, 0.5) var near_cells := 4.0
## Prey this far (in cells) counts for everything.
@export_range(1.0, 60.0, 0.5) var far_cells := 8.0

@export_group("Maze favours the hunter")
@export var bias_enabled := true
## How many times likelier, at full pressure, a room that opens straight toward the prey is.
@export_range(1.0, 30.0, 0.5) var bias_max := 8.0
## Only rooms this close to the hunter (in cells) are nudged, so nobody else's maze changes.
@export_range(1.0, 20.0, 0.5) var bias_radius_cells := 6.0
## How much of the maze's habit of walling up doorways is taken away near the hunter: at full
## pressure, 1.0 means never (0 leaves it as it is).
@export_range(0.0, 1.0, 0.05) var block_relief := 1.0

@export_group("Guaranteed route")
@export var route_enabled := true
## The pressure at which a route is laid.
@export_range(0.0, 1.0, 0.05) var route_pressure := 0.3
## Seconds between re-planning the route as the players move.
@export_range(0.5, 10.0, 0.5, "suffix:s") var route_refresh := 2.0

## How lost the hunter is, 0 to 1 (read only; shown in the debug overlay).
var pressure := 0.0
## Seconds the hunter has been after this prey.
var lost_time := 0.0
var hunter: Node3D
var prey: Array[Node3D] = []

var _manager: MazeManager
var _grid: MazeGrid
var _clock_running := true
## Metres from the hunter to the nearest prey (the short way round), and the cell it is in.
var _to_prey := Vector2.ZERO
var _target_cell := Vector2i.ZERO
var _hunter_cell := Vector2i.ZERO
var _route_timer := 0.0


func _ready() -> void:
	_manager = get_tree().get_first_node_in_group("maze_manager") as MazeManager
	if _manager:
		_manager.maze_rebuilt.connect(func() -> void: bind_grid(_manager.grid))
		bind_grid(_manager.grid)


## Starts (or carries on) a chase. A new hunter starts the clock again. `clock_running` false holds
## the clock still, for a head start; the compass works regardless.
func set_chase(p_hunter: Node3D, p_prey: Array, clock_running := true) -> void:
	if p_hunter != hunter:
		_calm_hunter()
		lost_time = 0.0
		_clear_route()
	hunter = p_hunter
	prey.assign(p_prey)
	_clock_running = clock_running


## No chase: nothing helps anyone.
func stop() -> void:
	_calm_hunter()
	hunter = null
	prey.clear()
	lost_time = 0.0
	pressure = 0.0
	_clear_route()


## The odds multiplier for a room whose open sides are `mask`, built in `cell` (MazeGrid.guide).
func room_weight(cell: Vector2i, mask: int) -> float:
	if not bias_enabled or pressure <= 0.0 or hunter == null or prey.is_empty():
		return 1.0
	if _cell_delta(_hunter_cell, cell).length() > bias_radius_cells:
		return 1.0
	var toward := _cell_delta(cell, _target_cell)
	if toward.length() < 0.5:
		return 1.0
	toward = toward.normalized()
	var alignment := 0.0
	for side in RoomDefs.SIDE_COUNT:
		if RoomDefs.has_side(mask, side):
			alignment = maxf(alignment, Vector2(RoomDefs.DIRS[side]).dot(toward))
	return 1.0 + (bias_max - 1.0) * pressure * alignment


## How much to ease off blocking doorways beside `cell` (0 none, 1 never block): a doorway walled
## up ahead of a lost hunter is the cruellest kind of dead end (MazeGrid.easing).
func room_ease(cell: Vector2i) -> float:
	if not bias_enabled or pressure <= 0.0 or hunter == null or prey.is_empty():
		return 0.0
	if _cell_delta(_hunter_cell, cell).length() > bias_radius_cells:
		return 0.0
	return minf(pressure * block_relief, 1.0)


func _physics_process(delta: float) -> void:
	if hunter == null or prey.is_empty() or _grid == null:
		return
	_find_nearest_prey()
	if hunter.has_method("lean_flame"):
		hunter.lean_flame(Vector3(_to_prey.x, 0.0, _to_prey.y), flame_lean_degrees, flame_lean_speed)
	if _clock_running:
		lost_time += delta
	var time_part := clampf(lost_time / ramp_seconds, 0.0, 1.0)
	var distance_part := clampf(inverse_lerp(near_cells, far_cells, _to_prey.length() / RoomDefs.CELL_SIZE), 0.0, 1.0)
	pressure = time_part * distance_part
	_update_route(delta)


## Starts helping in `grid` (a new maze starts the count again). The maze manager's grid is bound
## automatically; this is public for anything that has a grid of its own.
func bind_grid(grid: MazeGrid) -> void:
	_grid = grid
	_grid.guide = room_weight
	_grid.easing = room_ease
	lost_time = 0.0
	pressure = 0.0


## The nearest prey by the short way round: its direction and cell.
func _find_nearest_prey() -> void:
	var span := Vector2(_grid.bounds.size) * RoomDefs.CELL_SIZE
	var here := Vector2(hunter.global_position.x, hunter.global_position.z)
	var best := INF
	for other in prey:
		var there := Vector2(other.global_position.x, other.global_position.z)
		var apart := Vector2(_short(there.x - here.x, span.x), _short(there.y - here.y, span.y))
		if apart.length() < best:
			best = apart.length()
			_to_prey = apart
			_target_cell = _grid.wrap_cell(RoomDefs.world_to_cell(other.global_position))
	_hunter_cell = _grid.wrap_cell(RoomDefs.world_to_cell(hunter.global_position))


## Lays a route while the hunter is lost enough, takes it away when they are not.
func _update_route(delta: float) -> void:
	if not route_enabled or pressure < route_pressure:
		_clear_route()
		return
	_route_timer -= delta
	if _route_timer > 0.0:
		return
	_route_timer = route_refresh
	var cells := RouteFinder.find(_grid, _hunter_cell, _target_cell)
	_grid.route = RouteFinder.required_sides(_grid, cells)


func _clear_route() -> void:
	_route_timer = 0.0
	if _grid and not _grid.route.is_empty():
		_grid.route = {}


func _calm_hunter() -> void:
	if hunter and is_instance_valid(hunter) and hunter.has_method("lean_flame"):
		hunter.lean_flame(Vector3.ZERO, flame_lean_degrees, flame_lean_speed)


## `to` relative to `from`, in cells, the short way round the loop.
func _cell_delta(from: Vector2i, to: Vector2i) -> Vector2:
	var size := _grid.bounds.size
	return Vector2(_short(to.x - from.x, size.x), _short(to.y - from.y, size.y))


## A distance along one axis that is a loop of `span`, as the shortest signed way round.
func _short(delta: float, span: float) -> float:
	var d := fposmod(delta, span)
	return d - span if d * 2.0 > span else d
