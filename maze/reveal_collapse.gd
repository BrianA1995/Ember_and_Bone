class_name RevealCollapse
extends RefCounted
## Keeps the maze in step with the light each tick.
##  - Reveal: the light decides what lies beyond each doorway it reaches (the grid emits
##    cell_added for a new room, or side_sealed when a doorway is blocked instead).
##  - Change: a room the candle could see a moment ago but can no longer light is replaced
##    by a different legal room, so the maze behind you is never what you left. This happens
##    beyond the candle's reach, so it can't be seen.
##  - Collapse: a room outside the ring of rooms kept around the player is removed after
##    `unlit_delay` seconds, cracking for `crack_duration` first (the grid emits cell_removed).
##
## A source is {cell, radius, position?, reach?}: `radius` is how many cells around it
## exist; `position` (world) and `reach` (metres) say how far its light can be seen, and
## are needed for rooms to change as they go dark.

signal cell_cracking(cell: Vector2i)
signal cell_restored(cell: Vector2i)

var grid: MazeGrid
var collapse_enabled := true
## Rooms outside the ring around the player start cracking after this long, so a room
## doesn't flicker away when the player stands on a cell boundary.
var unlit_delay := 0.15
var crack_duration := 0.2
## Replace rooms as they leave the candle's light (see above).
var change_when_dark := true
## The cells that exist around the player on the most recent update.
var lit: Dictionary = {}

var _unlit_time: Dictionary = {}
var _cracking: Dictionary = {}
var _was_visible: Dictionary = {}


func _init(p_grid: MazeGrid) -> void:
	grid = p_grid


func update(sources: Array, delta: float) -> void:
	lit = LightField.compute(grid, sources)
	if change_when_dark:
		_change_rooms_that_went_dark(sources)
	if not collapse_enabled:
		_reset_timers()
		return
	for cell in grid.cells():
		# A big room can go while we are looping, taking its other cells with it.
		if not grid.has_cell(cell):
			continue
		if _is_lit(cell):
			_unlit_time.erase(cell)
			if _cracking.erase(cell):
				cell_restored.emit(cell)
			continue
		var unlit_for: float = _unlit_time.get(cell, 0.0) + delta
		_unlit_time[cell] = unlit_for
		if unlit_for >= unlit_delay + crack_duration:
			for member in grid.room_cells(cell):
				_unlit_time.erase(member)
				_cracking.erase(member)
				_was_visible.erase(member)
			grid.remove_cell(cell)
		elif unlit_for >= unlit_delay and not _cracking.has(cell):
			_cracking[cell] = true
			cell_cracking.emit(cell)


## A room is lit while any of the cells it covers is.
func _is_lit(cell: Vector2i) -> bool:
	if lit.has(cell):
		return true
	for member in grid.room_cells(cell):
		if lit.has(member):
			return true
	return false


## Rooms the light could reach last update but cannot now are swapped for new ones.
func _change_rooms_that_went_dark(sources: Array) -> void:
	var visible_now := {}
	for cell in lit:
		if _in_light(cell, sources):
			visible_now[cell] = true
		elif _was_visible.has(cell):
			grid.reroll_cell(cell)
	_was_visible = visible_now


## True if any source's light can be seen on part of this cell. Sources that don't say where
## their light is count as lighting everything, so nothing is changed for them.
func _in_light(cell: Vector2i, sources: Array) -> bool:
	var centre := RoomDefs.cell_to_world(cell)
	var half := RoomDefs.CELL_SIZE / 2.0
	for source in sources:
		if not source.has("position"):
			return true
		var position: Vector3 = source.position
		var gap := Vector2(maxf(absf(position.x - centre.x) - half, 0.0),
				maxf(absf(position.z - centre.z) - half, 0.0))
		if gap.length() <= source.reach:
			return true
	return false


func _reset_timers() -> void:
	for cell in _cracking:
		cell_restored.emit(cell)
	_cracking.clear()
	_unlit_time.clear()
