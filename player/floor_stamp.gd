class_name FloorStamp
extends Node
## Hold the interact key next to a cracked floor tile to stamp it down early (design doc:
## "the best way to cut off a chasing Lurker"). It must be a tile you are NOT standing on,
## within `reach` of your body. While you hold, the tile shakes and its cracks glow; keep
## holding for `hold_time` and it collapses. Let go early and the effort fades.
##
## A child of the body that stamps: its parent supplies the position.

## How close, in metres, the body must be to the tile's edge.
@export var reach := 1.6
## Seconds of holding it takes to bring the tile down.
@export var hold_time := 0.7
## How fast unfinished progress fades, in progress per second.
@export var fade_speed := 2.0

var _progress := 0.0
var _target: CrackedFloor


func _physics_process(delta: float) -> void:
	var body := get_parent() as Node3D
	var tile := _find_tile(body) if Input.is_action_pressed(&"interact") else null
	if tile != _target:
		_release_target()
		_progress = 0.0
		_target = tile
	if _target:
		_progress += delta
		_target.set_stamping(_progress / hold_time, body.global_position)
		if _progress >= hold_time:
			_target.collapse_now()
			_release_target()
			_progress = 0.0
	else:
		_progress = maxf(_progress - fade_speed * delta, 0.0)


## The nearest intact tile within reach that `body` isn't standing on, or null.
func _find_tile(body: Node3D) -> CrackedFloor:
	var best: CrackedFloor = null
	var best_distance := reach
	for node in get_tree().get_nodes_in_group("cracked_floors"):
		var tile := node as CrackedFloor
		if tile == null or not tile.is_intact() or tile.is_occupied_by(body):
			continue
		var distance := _distance_to_tile(body.global_position, tile.global_position)
		if distance <= best_distance:
			best = tile
			best_distance = distance
	return best


## Flat distance from a point to the edge of a tile (0 if over it).
func _distance_to_tile(point: Vector3, tile_centre: Vector3) -> float:
	var half := RoomDefs.CELL_SIZE / 2.0
	return Vector2(maxf(absf(point.x - tile_centre.x) - half, 0.0),
			maxf(absf(point.z - tile_centre.z) - half, 0.0)).length()


func _release_target() -> void:
	if is_instance_valid(_target):
		_target.set_stamping(0.0)
	_target = null
