class_name StartCollapse
extends Node
## The start chamber gives way (design doc: it collapses about 30 s into the run, forcing
## everyone out). After `delay` seconds the floor of the room at `cell` cracks all over, then
## its tiles drop one after another, in random order. What is left is a pit, so anyone still
## inside has to be gone by then.
##
## If the room is already gone when the time comes (everyone left and it collapsed on its
## own) there is nothing to do.

signal cracking
signal finished

enum Phase { WAITING, CRACKING, COLLAPSING, DONE }

## Seconds from the start of the run until the floor begins to crack.
@export var delay := 30.0
## Seconds the cracks spread across the whole floor before the first tile goes.
@export var warning_time := 3.0
## Seconds between one tile dropping and the next.
@export var tile_interval := 0.5

var phase := Phase.WAITING

var _view: MazeView
var _cell := Vector2i.ZERO
var _clock := 0.0
var _tiles: Array[Node3D] = []
var _dropped := 0


## Starts the countdown for the room at `cell`.
func start(view: MazeView, cell: Vector2i) -> void:
	_view = view
	_cell = cell
	_clock = 0.0
	phase = Phase.WAITING


## Seconds until the floor starts to crack, or 0 once it has.
func seconds_left() -> float:
	return maxf(delay - _clock, 0.0) if phase == Phase.WAITING else 0.0


func _physics_process(delta: float) -> void:
	_clock += delta
	match phase:
		Phase.WAITING:
			if _clock >= delay:
				_begin_cracking()
		Phase.CRACKING:
			var amount := clampf(_clock / warning_time, 0.0, 1.0)
			for tile in _tiles:
				if is_instance_valid(tile):
					(tile as CrackedFloor).set_stamping(amount, tile.global_position)
			if _clock >= warning_time:
				phase = Phase.COLLAPSING
				_clock = 0.0
		Phase.COLLAPSING:
			while _dropped < _tiles.size() and _clock >= _dropped * tile_interval:
				var tile := _tiles[_dropped]
				if is_instance_valid(tile):
					(tile as CrackedFloor).collapse_now()
				_dropped += 1
			if _dropped >= _tiles.size():
				_finish()


func _begin_cracking() -> void:
	var room := _view.room_at(_cell)
	if room == null:
		_finish()
		return
	_tiles = _view.crack_floor(room)
	_tiles.shuffle()
	phase = Phase.CRACKING
	_clock = 0.0
	cracking.emit()


func _finish() -> void:
	phase = Phase.DONE
	finished.emit()
