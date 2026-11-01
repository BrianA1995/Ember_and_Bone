class_name MenuBackdrop
extends Node3D
## The labyrinth behind the main menu: the real maze, built around a lit wanderer who walks it forever while
## the camera looks over their shoulder, so the title screen shows the same candlelit rooms rising out of the
## dark that the game does. Nothing here reaches into the menu on top; the menu just draws over it.
##
## Placeholder look: the maze, the light and the camera are all code-made like the rest of the game.

## How fast the camera drifts through the rooms, in m/s, and how quickly it turns toward the way ahead.
@export var drift_speed := 1.1
@export var turn_rate := 1.6
## Height of the eyes above the floor, in metres.
@export var eye_height := 1.55
@export var candle_color := Color(1.0, 0.72, 0.38)

var _maze: MazeManager
var _walker := MenuWalker.new()
var _camera := Camera3D.new()
var _candle := OmniLight3D.new()
var _clock := 0.0


func _ready() -> void:
	_maze = _build_maze()
	add_child(_maze)
	add_child(MazeLighting.new())
	_walker.setup(_maze)
	_maze.add_light(_walker)
	add_child(_walker)
	_camera.fov = 72.0
	_camera.near = 0.05
	add_child(_camera)
	_camera.make_current()
	_candle.light_color = candle_color
	_candle.omni_range = 7.0
	_candle.omni_attenuation = 1.3
	_candle.shadow_enabled = true
	add_child(_candle)


func _process(delta: float) -> void:
	_clock += delta
	_walker.walk(delta, drift_speed, turn_rate)
	var eyes := _walker.global_position + Vector3(0.0, eye_height + sin(_clock * 1.3) * 0.03, 0.0)
	_camera.global_position = eyes
	_camera.global_rotation = Vector3(deg_to_rad(-3.0), _walker.heading, 0.0)
	# The flame sits a little ahead and to the side, and gutters.
	var flicker := 1.0 + 0.12 * sin(_clock * 17.0) + 0.08 * sin(_clock * 6.3)
	_candle.global_position = eyes + _camera.global_basis * Vector3(0.35, -0.25, -0.5)
	_candle.light_energy = 1.7 * flicker


## A maze of its own, as large as the game's and wrapping, with no cracked floors or collapsing start room (nobody
## stands here to fall).
static func _build_maze() -> MazeManager:
	var maze := MazeManager.new()
	maze.grid_size = Vector2i(31, 31)
	maze.wrap_edges = true
	maze.crack_chance = 0.0
	maze.start_collapse_delay = 0.0
	var view := MazeView.new()
	view.name = "MazeView"
	view.hide_ceilings = false
	maze.add_child(view)
	return maze
