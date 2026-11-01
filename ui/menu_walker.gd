class_name MenuWalker
extends Node3D
## The light the menu backdrop follows. It walks the maze room to room along open doorways (never turning
## straight back unless it must) and lights the rooms around it like a player's candle does, so the maze keeps
## growing ahead of the camera. It is a light source for the MazeManager: `light_radius` and `change_distance`
## are what the manager reads. At the edge of the wrapping maze the manager carries it across, like a player.

## Rooms that exist around it, and the distance (metres) beyond which its light cannot be seen.
var light_radius := 2
var change_distance := 7.5
## The way it faces, in radians about the up axis (0 looks along -Z).
var heading := 0.0

var _maze: MazeManager
var _rng := RandomNumberGenerator.new()
var _target := Vector3.ZERO
## The side of the room it came in by, so it does not go straight back.
var _came_by := -1


func setup(maze: MazeManager) -> void:
	_maze = maze
	_rng.randomize()
	# Set before it is in the tree, so a local position (the backdrop sits at the origin).
	position = RoomDefs.cell_to_world(Vector2i.ZERO)
	_target = position


## Moves `speed` m/s toward the next room, turning to face the way it goes.
func walk(delta: float, speed: float, turn_rate: float) -> void:
	var to := _target - global_position
	to.y = 0.0
	if to.length() < 0.05:
		_choose_next()
		to = _target - global_position
		to.y = 0.0
	if to.length() < 0.001:
		return
	heading = lerp_angle(heading, atan2(-to.x, -to.z), 1.0 - exp(-turn_rate * delta))
	global_position += to.normalized() * minf(speed * delta, to.length())


## Picks an open doorway of the room it stands in and aims for the middle of the room beyond.
func _choose_next() -> void:
	var grid := _maze.grid
	var cell := RoomDefs.world_to_cell(global_position)
	var middle := RoomDefs.cell_to_world(cell)
	var forward: Array[int] = []
	var backward: Array[int] = []
	for side in RoomDefs.SIDE_COUNT:
		var wrapped := grid.wrap_cell(cell)
		if not grid.is_open(wrapped, side) or not grid.has_cell(grid.neighbor(wrapped, side)):
			continue
		(backward if side == _came_by else forward).append(side)
	var choices := forward if not forward.is_empty() else backward
	if choices.is_empty():
		_target = middle
		return
	var side: int = choices[_rng.randi() % choices.size()]
	_came_by = RoomDefs.opposite(side)
	_target = middle + Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y) * RoomDefs.CELL_SIZE
