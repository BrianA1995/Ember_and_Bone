class_name SeamWrap
extends Node
## Makes a wrapping maze (MazeGrid.wrap_edges) walkable: a light source that steps over an edge
## of the maze is moved to the opposite edge, so a doorway on the east side of the maze leads
## into the room on the west side, and so on. The grid already treats those rooms as neighbours,
## so the room is built before anyone arrives.
##
## The move is a cut, not a seamless view: beyond an edge doorway there is only darkness.
## Anything in the "light_sources" group is moved; one with a `warp_to(position)` method is moved
## through it (so it can reset what it needs to), others just get a new position.

var manager: MazeManager


## The corner of the maze (world x, z) and its size in metres.
func world_extent() -> Rect2:
	var bounds := manager.grid.bounds
	var cell := RoomDefs.CELL_SIZE
	return Rect2((Vector2(bounds.position) - Vector2(0.5, 0.5)) * cell, Vector2(bounds.size) * cell)


## Where `position` ends up after crossing a seam (unchanged if it is inside the maze).
func wrapped(position: Vector3) -> Vector3:
	if manager == null or manager.grid == null or not manager.grid.wrap_edges:
		return position
	var extent := world_extent()
	var result := position
	for axis in [0, 2]:
		var low: float = extent.position.x if axis == 0 else extent.position.y
		var span: float = extent.size.x if axis == 0 else extent.size.y
		if result[axis] >= low + span:
			result[axis] -= span
		elif result[axis] < low:
			result[axis] += span
	return result


func _physics_process(_delta: float) -> void:
	if manager == null or manager.grid == null or not manager.grid.wrap_edges:
		return
	for node in get_tree().get_nodes_in_group("light_sources"):
		var body := node as Node3D
		var target := wrapped(body.global_position)
		if target == body.global_position:
			continue
		if body.has_method("warp_to"):
			body.warp_to(target)
		else:
			body.global_position = target
