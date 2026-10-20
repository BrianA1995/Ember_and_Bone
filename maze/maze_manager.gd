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
@export var start_piece: StringName = &"cross"
## Chance that a doorway the light reaches is blocked by a wall instead of leading on.
## A block only goes in if the room keeps at least two other exits (it prunes a branch).
@export_range(0.0, 1.0, 0.05) var block_chance := 0.2
## Chance that a block may leave a room with one exit: a true dead end. Keep this low.
@export_range(0.0, 1.0, 0.05) var dead_end_chance := 0.2
## Chance that a straight corridor room has a cracked floor that gives way underfoot.
@export_range(0.0, 1.0, 0.05) var crack_chance := 0.25
## How strongly junctions are favoured after a run of plain corridor rooms.
@export_range(0.0, 2.0, 0.1) var junction_boost := 0.5
## Optional piece -> weight overrides, e.g. {&"corner": 2.0}.
@export var weights: Dictionary = {}
@export_group("Collapse")
@export var collapse_enabled := true:
	set = set_collapse_enabled
## Seconds a room that is no longer next to the player (or not connected to their room
## by an open doorway) survives before it starts cracking, then until it is removed.
@export var unlit_delay := 0.15
@export var crack_duration := 0.2

var grid: MazeGrid
var reveal: RevealCollapse

@onready var view: MazeView = $MazeView


func _ready() -> void:
	add_to_group("maze_manager")
	build(map_seed)


func _physics_process(delta: float) -> void:
	reveal.update(_light_sources(), delta)


## Builds a fresh maze. Seed 0 picks a random one.
func build(new_seed: int = 0) -> void:
	if new_seed == 0:
		new_seed = randi_range(1, 2147483647)
	grid = MazeGrid.new(new_seed, grid_size, weights)
	grid.block_chance = block_chance
	grid.dead_end_chance = dead_end_chance
	grid.crack_chance = crack_chance
	grid.junction_boost = junction_boost
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
	maze_rebuilt.emit()


## New random maze, and everything that carries light goes back to the start.
func restart() -> void:
	build(0)
	for node in get_tree().get_nodes_in_group("light_sources"):
		if node.has_method("reset_position"):
			node.reset_position()


func set_collapse_enabled(value: bool) -> void:
	collapse_enabled = value
	if reveal:
		reveal.collapse_enabled = value


func _light_sources() -> Array:
	var sources := []
	for node in get_tree().get_nodes_in_group("light_sources"):
		sources.append({
			"cell": RoomDefs.world_to_cell(node.global_position),
			"radius": node.light_radius,
			"position": node.global_position,
			"reach": node.change_distance,
		})
	return sources
