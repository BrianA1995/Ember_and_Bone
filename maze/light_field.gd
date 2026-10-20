class_name LightField
extends RefCounted
## Which cells are lit. Light flows outward from each source along open doorways only:
## never through a wall, never diagonally around a corner, never through a blocked doorway.
##
## A source is {cell: Vector2i, radius: int}. Radius counts cells: 1 lights the source's
## own cell plus every cell directly connected to it.


## Returns a set (Dictionary of cell -> true). With `reveal` on, the light also decides
## what lies beyond each open doorway it reaches (a new room, or a blocking wall).
static func compute(grid: MazeGrid, sources: Array, reveal := true) -> Dictionary:
	var lit := {}
	for source in sources:
		var origin: Vector2i = source.cell
		if reveal and not grid.has_cell(origin):
			grid.generate_cell(origin)
		if grid.has_cell(origin):
			_flood(grid, origin, source.radius, lit, reveal)
	return lit


static func _flood(grid: MazeGrid, origin: Vector2i, radius: int, lit: Dictionary, reveal: bool) -> void:
	var depth := {origin: 0}
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		lit[cell] = true
		if depth[cell] >= radius:
			continue
		for side in RoomDefs.SIDE_COUNT:
			if not grid.is_open(cell, side):
				continue
			var next := grid.neighbor(cell, side)
			if reveal and not grid.has_cell(next):
				grid.reveal_beyond(cell, side)
			if grid.has_cell(next) and not depth.has(next):
				depth[next] = depth[cell] + 1
				queue.append(next)
