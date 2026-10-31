class_name ChalkMarks
extends Node
## Messages chalked on a room's wall. A mark belongs to its room: when the room goes dark and is taken
## away, the mark goes with it, and the room comes back later the way a lost item does. A card for that
## kind of room is put in the deck, the generator is told to favour it (MazeGrid.weights) once it is due,
## and the first room of that kind built is given the message again.

@export var wall_offset := 1.9
@export var mark_height := 1.4
## Rooms built between a marked room going and it coming back, from and to.
@export var return_after := Vector2i(10, 25)

var _manager: MazeManager
var _grid: MazeGrid
## anchor cell -> {piece, text}, for the marks standing now.
var _marks: Dictionary = {}
## Marked rooms taken away, waiting to come back: {piece, text, at, was}.
var _waiting: Array[Dictionary] = []
var _builds := 0
var _rng := RandomNumberGenerator.new()

const DUE_WEIGHT := 1000.0


func setup(p_manager: MazeManager) -> void:
	_manager = p_manager
	_manager.maze_rebuilt.connect(_restart)
	_restart()


func _restart() -> void:
	_marks.clear()
	_waiting.clear()
	_builds = 0
	_grid = _manager.grid
	_rng.seed = _grid.seed_value + 77
	_grid.cell_added.connect(_on_cell_added)
	_grid.cell_removed.connect(_on_cell_removed)


## Writes `text` on the wall `player` faces, in the room they stand in. False if there is no room.
func mark(player: Player, text: String) -> bool:
	var cell := _grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
	var data := _grid.get_cell(cell)
	if data.is_empty() or RoomDefs.is_special(data.piece) or _marks.has(data.anchor):
		return false
	if not _write(data.anchor, text, player.facing()):
		return false
	_marks[data.anchor] = {"piece": data.piece, "text": text}
	return true


func _write(anchor: Vector2i, text: String, toward: Vector3) -> bool:
	var room := _manager.view.room_at(anchor)
	if room == null:
		return false
	var best := 0
	var best_score := -INF
	for side in RoomDefs.SIDE_COUNT:
		var dir := Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y)
		# A wall to write on is better than a doorway; among those, the one faced.
		var score := dir.dot(toward) + (0.0 if _grid.is_open(anchor, side) else 4.0)
		if score > best_score:
			best_score = score
			best = side
	var dir := Vector3(RoomDefs.DIRS[best].x, 0.0, RoomDefs.DIRS[best].y)
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.006
	label.modulate = Color(0.95, 0.95, 0.9)
	label.outline_size = 8
	label.outline_modulate = Color(0.1, 0.1, 0.1)
	label.double_sided = false
	room.add_child(label)
	var centre := RoomDefs.cell_to_world(anchor)
	label.global_position = centre + dir * wall_offset + Vector3(0.0, mark_height, 0.0)
	# Label3D shows its +Z face: turn it to face into the room.
	label.look_at(label.global_position + dir, Vector3.UP)
	return true


func _on_cell_added(cell: Vector2i) -> void:
	var data := _grid.get_cell(cell)
	if data.is_empty() or data.anchor != cell or RoomDefs.is_special(data.piece):
		return
	_builds += 1
	for entry in _waiting:
		if entry.piece == data.piece and entry.at <= _builds:
			_waiting.erase(entry)
			_restore_weight(entry)
			if _write(cell, entry.text, Vector3.ZERO):
				_marks[cell] = {"piece": data.piece, "text": entry.text}
			return
	for entry in _waiting:
		if entry.at <= _builds:
			_grid.weights[entry.piece] = DUE_WEIGHT


func _on_cell_removed(cell: Vector2i) -> void:
	if not _marks.has(cell):
		return
	var mark: Dictionary = _marks[cell]
	_marks.erase(cell)
	_waiting.append({
		"piece": mark.piece, "text": mark.text,
		"at": _builds + _rng.randi_range(return_after.x, return_after.y),
		"was": _grid.weights.get(mark.piece, null),
	})


func _restore_weight(entry: Dictionary) -> void:
	if entry.was == null:
		_grid.weights.erase(entry.piece)
	else:
		_grid.weights[entry.piece] = entry.was
