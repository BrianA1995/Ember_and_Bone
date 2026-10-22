class_name CrackedFloor
extends StaticBody3D
## A floor tile that gives way (design doc, "Hazards and falls").
##
## Stepping on it arms it. While you stand on it the cracks spread outward from your feet,
## and they stop the moment you step off: the tile stays standing, cracked as far as it got.
## It collapses when the total time anything has stood on it reaches `warning_time` (the
## cracks have then covered the whole tile). So walking across is safe, and lingering drops
## you through. Stamping next to it (see FloorStamp) cracks it too, and collapses it at once
## if held long enough. A collapsed tile is a pit: its collision is gone, so anything on it falls.
##
## "Standing on" means the middle of the body is over the tile. Merely being close beside it,
## or having the candle held out over it, does not count.
##
## The tell is visual: the cracks (drawn by hazards/cracked_floor.gdshader). There is no shake
## and no colour cue; the tile simply breaks once the cracks have covered it.
##
## Scene layout (hazards/cracked_floor.tscn): Mesh and Collision. Bodies in the "players"
## group are the ones that can stand on it.

signal collapsed(tile: CrackedFloor)

enum State { INTACT, ARMED, COLLAPSED }

## Seconds of standing, in total, that bring the tile down.
@export var warning_time := 3.0
## How far stamping alone can spread the cracks (0 to 1). Less than 1: only standing
## brings a tile down by cracking.
@export var stamp_spread := 0.9
## Which crack pattern this tile has. Negative picks one at random.
@export var pattern_seed := -1.0
## A body whose middle is more than this far above the tile (metres) isn't standing on it.
@export var stand_height := 2.0
## Off for a floor that only breaks on a schedule (the start chamber): standing on it does nothing.
@export var breaks_when_stood_on := true

var state := State.INTACT

var _half := RoomDefs.CELL_SIZE / 2.0
var _occupied := false
var _stand_total := 0.0
var _spread := 0.0
var _spread_origin := Vector2.ZERO

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _collision: CollisionShape3D = $Collision


func _ready() -> void:
	add_to_group("cracked_floors")
	# Every tile gets its own crack pattern from the one shared material.
	var pattern := pattern_seed if pattern_seed >= 0.0 else randf() * 100.0
	_mesh.set_instance_shader_parameter(&"pattern_seed", pattern)


func _physics_process(delta: float) -> void:
	if state == State.COLLAPSED or not breaks_when_stood_on:
		return
	var standing := _bodies_standing_on_it()
	_occupied = not standing.is_empty()
	if not _occupied:
		return
	if state == State.INTACT:
		state = State.ARMED
	_stand_total += delta
	# The cracks grow out from the feet of whoever is standing here, and only while they are.
	spread_cracks(standing[0].global_position, _stand_total / warning_time)
	if _stand_total >= warning_time:
		_collapse()


func _process(_delta: float) -> void:
	if state == State.COLLAPSED:
		return
	_mesh.set_instance_shader_parameter(&"spread", _spread)
	_mesh.set_instance_shader_parameter(&"spread_origin", _spread_origin)


## Collapses the tile now.
func collapse_now() -> void:
	if state != State.COLLAPSED:
		_collapse()


## Called every physics tick while a body stamps next to the tile. `amount` is 0 to 1 (how
## far through the stamp it is) and `source` is where the stamper stands: the cracks spread
## in from there. The cracks stay when the stamping stops.
func set_stamping(amount: float, source := Vector3.INF) -> void:
	if amount > 0.0 and source != Vector3.INF:
		spread_cracks(source, clampf(amount, 0.0, 1.0) * stamp_spread)


## Spreads the cracks out from a world position until they cover `amount` (0 to 1) of the
## tile. They never shrink. Standing and stamping both use this; so can a preview.
func spread_cracks(from_position: Vector3, amount: float) -> void:
	_spread = maxf(_spread, clampf(amount, 0.0, 1.0))
	var local := to_local(from_position)
	_spread_origin = Vector2(local.x, local.z)


func is_intact() -> bool:
	return state != State.COLLAPSED


## True if the middle of `body` is over the tile (see the class description).
func is_occupied_by(body: Node3D) -> bool:
	var local := to_local(body.global_position)
	return local.x >= -_half and local.x < _half and local.z >= -_half and local.z < _half \
			and local.y > -0.3 and local.y < stand_height


## How far the cracks have spread, 0 (just the old cracks) to 1 (the whole tile).
func crack_spread() -> float:
	return _spread


## Seconds of standing left before the tile gives way, or -1 if nothing has stepped on it yet.
## It only counts down while someone is standing on it.
func seconds_left() -> float:
	if state != State.ARMED:
		return -1.0
	return warning_time - _stand_total


func _bodies_standing_on_it() -> Array[Node3D]:
	var standing: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("players"):
		var body := node as Node3D
		if body and is_occupied_by(body):
			standing.append(body)
	return standing


func _collapse() -> void:
	state = State.COLLAPSED
	_collision.set_deferred(&"disabled", true)
	_mesh.visible = false
	FloorDebris.burst(self)
	collapsed.emit(self)
