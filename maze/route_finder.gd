class_name RouteFinder
extends RefCounted
## A* over a MazeGrid for a route that does not exist yet. Rooms only exist near a light, so
## between two far-apart players there is mostly empty space: the route runs through rooms that are
## built and through empty cells that could be. It never walks through a wall of a built room, and
## it prefers built rooms because those are certain.
##
## The result is a list of cells, start to goal. Nothing is changed; see Pursuit for what is done
## with it.

## What entering a cell costs. Built rooms are cheaper, so the route follows them where it can.
const BUILT_COST := 0.6
const EMPTY_COST := 1.0


## The cells from `start` to `goal`, both included, or an empty list if there is no route.
## The maze wraps, so the short way may cross a seam.
static func find(grid: MazeGrid, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = []
	if not grid.in_bounds(start) or not grid.in_bounds(goal):
		return route
	var open := _Heap.new()
	var cost := {start: 0.0}
	var came := {}
	var closed := {}
	open.push(_estimate(grid, start, goal), start)
	while not open.is_empty():
		var cell: Vector2i = open.pop()
		if cell == goal:
			return _unwind(came, goal)
		if closed.has(cell):
			continue
		closed[cell] = true
		for side in RoomDefs.SIDE_COUNT:
			if not _can_step(grid, cell, side):
				continue
			var next := grid.neighbor(cell, side)
			if closed.has(next):
				continue
			var through: float = cost[cell] + (BUILT_COST if grid.has_cell(next) else EMPTY_COST)
			if through < cost.get(next, INF):
				cost[next] = through
				came[next] = cell
				open.push(through + _estimate(grid, next, goal), next)
	return route


## The sides each cell of `route` must have open for the route to be walkable: toward the cell
## before it and the cell after it. {cell: mask}.
static func required_sides(grid: MazeGrid, route: Array[Vector2i]) -> Dictionary:
	var sides := {}
	for i in route.size() - 1:
		var side := _side_between(grid, route[i], route[i + 1])
		sides[route[i]] = sides.get(route[i], 0) | (1 << side)
		sides[route[i + 1]] = sides.get(route[i + 1], 0) | (1 << RoomDefs.opposite(side))
	return sides


## Whether a step from `cell` through `side` is possible: a built room's wall stops it, from
## either side; empty space does not.
static func _can_step(grid: MazeGrid, cell: Vector2i, side: int) -> bool:
	if grid.has_cell(cell) and not grid.is_open(cell, side):
		return false
	var next := grid.neighbor(cell, side)
	if grid.has_cell(next) and not grid.is_open(next, RoomDefs.opposite(side)):
		return false
	return true


static func _side_between(grid: MazeGrid, from: Vector2i, to: Vector2i) -> int:
	for side in RoomDefs.SIDE_COUNT:
		if grid.neighbor(from, side) == to:
			return side
	return 0


## Never more than the real cost: the fewest steps there could be, each at the cheapest price.
static func _estimate(grid: MazeGrid, from: Vector2i, to: Vector2i) -> float:
	var apart := (to - from).abs()
	if grid.wrap_edges:
		apart = Vector2i(mini(apart.x, grid.bounds.size.x - apart.x), mini(apart.y, grid.bounds.size.y - apart.y))
	return (apart.x + apart.y) * BUILT_COST


static func _unwind(came: Dictionary, goal: Vector2i) -> Array[Vector2i]:
	var route: Array[Vector2i] = [goal]
	var cell := goal
	while came.has(cell):
		cell = came[cell]
		route.push_front(cell)
	return route


## A minimal priority queue: the smallest key comes out first.
class _Heap:
	var _keys: Array[float] = []
	var _items: Array[Vector2i] = []

	func is_empty() -> bool:
		return _keys.is_empty()

	func push(key: float, item: Vector2i) -> void:
		_keys.append(key)
		_items.append(item)
		var i := _keys.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if _keys[parent] <= _keys[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Vector2i:
		var top := _items[0]
		var last := _keys.size() - 1
		_swap(0, last)
		_keys.pop_back()
		_items.pop_back()
		var i := 0
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < _keys.size() and _keys[left] < _keys[smallest]:
				smallest = left
			if right < _keys.size() and _keys[right] < _keys[smallest]:
				smallest = right
			if smallest == i:
				break
			_swap(i, smallest)
			i = smallest
		return top

	func _swap(a: int, b: int) -> void:
		var key := _keys[a]
		_keys[a] = _keys[b]
		_keys[b] = key
		var item := _items[a]
		_items[a] = _items[b]
		_items[b] = item
