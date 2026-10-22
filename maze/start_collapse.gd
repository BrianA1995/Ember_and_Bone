class_name StartCollapse
extends Node
## The start chamber gives way (design doc: it collapses about 30 s into the run, forcing
## everyone out). Its floor is cracked from the start; the cracks spread across every tile
## over `delay` seconds, and the moment they cover the floor, all of it drops. What is left
## is a pit, so anyone still inside has to be gone by then.
##
## If the room is already gone when the time comes (everyone left and it collapsed on its
## own) there is nothing to do.

signal finished

enum Phase { SPREADING, DONE }

## Seconds from the start of the run until the floor drops.
@export var delay := 30.0

var phase := Phase.DONE

var _clock := 0.0
var _tiles: Array[Node3D] = []


## Cracks the floor of the room at `cell` and starts the countdown.
func start(view: MazeView, cell: Vector2i) -> void:
	_clock = 0.0
	_tiles.clear()
	var room := view.room_at(cell)
	if room == null:
		_finish()
		return
	_tiles = view.crack_floor(room)
	for tile in _tiles:
		(tile as CrackedFloor).breaks_when_stood_on = false
	phase = Phase.SPREADING


## Seconds until the floor drops, or 0 once it has.
func seconds_left() -> float:
	return maxf(delay - _clock, 0.0) if phase == Phase.SPREADING else 0.0


func _physics_process(delta: float) -> void:
	if phase != Phase.SPREADING:
		return
	_clock += delta
	var amount := clampf(_clock / delay, 0.0, 1.0)
	for tile in _tiles:
		if is_instance_valid(tile):
			(tile as CrackedFloor).spread_cracks(tile.global_position, amount)
	if _clock >= delay:
		for tile in _tiles:
			if is_instance_valid(tile):
				(tile as CrackedFloor).collapse_now()
		_finish()


func _finish() -> void:
	phase = Phase.DONE
	finished.emit()
