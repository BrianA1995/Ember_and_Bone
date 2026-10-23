class_name MazeMap
extends Control
## Test-time map of the whole maze, top right of the screen: every room that exists right now
## (the maze only keeps rooms near the players) and a dot for each player. The edges of the
## square are the seams of the wrapping maze. Safe to delete from the game scene later.

## Largest the map gets, in pixels.
const MAX_SIZE := 340
const MARGIN := 12
const BACKGROUND := Color(0.0, 0.0, 0.0, 0.72)
const ROOM := Color(0.62, 0.52, 0.36)
const CRACKED := Color(0.75, 0.3, 0.25)
const SPECIAL := Color(0.35, 0.75, 0.6)
const BIG := Color(0.45, 0.55, 0.85)
const WALL := Color(0.05, 0.04, 0.03)

var _manager: MazeManager
var _cell_px := 4


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_manager = get_tree().get_first_node_in_group("maze_manager") as MazeManager


func _process(_delta: float) -> void:
	if not visible or _manager == null or _manager.grid == null:
		return
	var bounds := _manager.grid.bounds
	_cell_px = clampi(MAX_SIZE / maxi(bounds.size.x, bounds.size.y), 2, 14)
	custom_minimum_size = Vector2(bounds.size) * _cell_px
	size = custom_minimum_size
	position = Vector2(get_viewport_rect().size.x - size.x - MARGIN, MARGIN)
	queue_redraw()


func _draw() -> void:
	if _manager == null or _manager.grid == null:
		return
	var grid := _manager.grid
	var origin := grid.bounds.position
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	for cell in grid.cells():
		var data := grid.get_cell(cell)
		var rect := Rect2(Vector2(cell - origin) * _cell_px, Vector2(_cell_px, _cell_px))
		draw_rect(rect, _color_of(data))
		if _cell_px >= 7:
			_draw_walls(grid, cell, rect)
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.5), false, 1.0)
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		var at := (Vector2(player.global_position.x, player.global_position.z) / RoomDefs.CELL_SIZE
				- Vector2(origin) + Vector2(0.5, 0.5)) * _cell_px
		draw_circle(at, maxf(_cell_px * 0.7, 4.0), Player.SLOT_COLORS[player.slot % Player.SLOT_COLORS.size()])
		draw_arc(at, maxf(_cell_px * 0.7, 4.0), 0.0, TAU, 12, Color.BLACK, 1.0)


func _color_of(data: Dictionary) -> Color:
	if RoomDefs.is_multi(data.piece):
		return BIG
	if RoomDefs.is_special(data.piece):
		return SPECIAL
	return CRACKED if data.cracked else ROOM


## A dark line along every side of the room that is closed.
func _draw_walls(grid: MazeGrid, cell: Vector2i, rect: Rect2) -> void:
	var corners := [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.end,
			rect.position + Vector2(0.0, rect.size.y)]
	for side in RoomDefs.SIDE_COUNT:
		if not grid.is_open(cell, side):
			# Sides are N, E, S, W; corners run clockwise from the top left.
			draw_line(corners[side], corners[(side + 1) % 4], WALL, 2.0)
