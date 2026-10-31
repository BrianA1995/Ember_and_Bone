class_name Lurker
extends Monster
## Creeps up on the nearest prisoner, silently, and gives nothing away. It reacts to movement: when a
## lit prisoner MOVES in a straight open line from it, it freezes and counts `grace_seconds`; if the
## prisoner is still moving when that runs out it charges, and everyone standing in that line, however
## far apart, is hit at once. A prisoner who stops moving within the grace period is left alone, and a
## still prisoner is never attacked, however close it creeps. Only open space counts as a line: a
## wall breaks it.
##
## Survive: freeze when you see it, put the candle away, or break the line round a corner.

@export_group("Lurker")
## How fast it creeps toward a prisoner.
@export var creep_speed := 1.3
## How far, in rooms, it can sense a prisoner to creep toward.
@export_range(1, 12) var sense_cells := 6
## The longest line, in rooms, it can strike along.
@export_range(1, 10) var longest_lane := 5
## Seconds a prisoner in its line has to stop moving before it charges.
@export_range(0.2, 5.0, 0.1, "suffix:s") var grace_seconds := 1.5
@export var charge_speed := 14.0
## How far to either side of the line's middle, in metres, a prisoner is still in it.
@export var lane_half_width := 1.3
## Seconds it rests after a charge.
@export_range(0.0, 20.0, 0.5, "suffix:s") var rest_seconds := 6.0
## A prisoner moving slower than this (m/s) counts as standing still.
@export var moving_speed := 0.8
## How close, in metres, it creeps up to a prisoner and then stands.
@export var stand_off := 1.4

enum State { STALK, CHARGE, REST }

var _state := State.STALK
var _timer := 0.0
var _grace := 0.0
var _side := 0
var _goal := Vector3.ZERO


func _init() -> void:
	hits_on_touch = false
	move_speed = creep_speed


func build_model() -> Node3D:
	var body := Node3D.new()
	var dark := Color(0.08, 0.07, 0.09)
	body.add_child(part(CapsuleMesh.new(), dark, Vector3(0.0, 0.95, 0.0)))
	(body.get_child(0) as MeshInstance3D).scale = Vector3(0.6, 1.0, 0.6)
	body.add_child(part(box(Vector3(0.1, 1.1, 0.1)), dark, Vector3(-0.38, 0.75, 0.0)))
	body.add_child(part(box(Vector3(0.1, 1.1, 0.1)), dark, Vector3(0.38, 0.75, 0.0)))
	body.add_child(part(ball(0.17), Color(0.75, 0.72, 0.66), Vector3(0.0, 1.85, 0.0)))
	body.add_child(part(ball(0.035), Color(0.9, 0.1, 0.05), Vector3(-0.07, 1.87, -0.14), 3.0))
	body.add_child(part(ball(0.035), Color(0.9, 0.1, 0.05), Vector3(0.07, 1.87, -0.14), 3.0))
	return body


func _act(delta: float) -> void:
	match _state:
		State.STALK:
			_stalk(delta)
		State.CHARGE:
			if move_toward_point(_goal, charge_speed, delta):
				_rest(rest_seconds)
		State.REST:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.STALK


func on_stunned() -> void:
	_grace = grace_seconds
	_rest(rest_seconds * 0.5)


## Creeps toward the nearest prisoner; while one moves in its line it stands still and counts down.
func _stalk(delta: float) -> void:
	var side := _mover_in_line()
	if side >= 0:
		_side = side
		_grace -= delta
		if _grace <= 0.0:
			_strike()
		return
	_grace = grace_seconds
	var target := nearest_player(func(player: Player) -> bool:
		return director.offset(global_position, player.global_position).length() <= sense_cells * RoomDefs.CELL_SIZE)
	if target == null:
		wander(creep_speed * 0.6, delta)
	elif director.offset(global_position, target.global_position).length() > stand_off:
		go_to(director.cell_at(target.global_position), target.global_position, creep_speed, delta)


## The side of a line a lit prisoner is moving in, or -1.
func _mover_in_line() -> int:
	for side in RoomDefs.SIDE_COUNT:
		var rooms := director.lane(cell, side, longest_lane)
		for player in director.players:
			if player.is_candle_lit() and player.floor_speed() > moving_speed and _in_lane(player, side, rooms):
				return side
	return -1


## Everyone in the line now is hit, then it charges to the far end.
func _strike() -> void:
	var rooms := director.lane(cell, _side, longest_lane)
	var direction := Vector3(RoomDefs.DIRS[_side].x, 0.0, RoomDefs.DIRS[_side].y)
	rotation.y = atan2(-direction.x, -direction.z)
	for player in director.players:
		if _in_lane(player, _side, rooms):
			director.hit(self, player)
	if rooms.is_empty():
		_rest(rest_seconds)
		return
	_goal = RoomDefs.cell_to_world(rooms[-1])
	_state = State.CHARGE


func _rest(seconds: float) -> void:
	_state = State.REST
	_timer = seconds


## Is `player` in the line from this room out through `side` (the rooms in `rooms`), near its middle?
func _in_lane(player: Player, side: int, rooms: Array[Vector2i]) -> bool:
	var there := director.cell_at(player.global_position)
	if cell != there and not rooms.has(there):
		return false
	var to := director.offset(global_position, player.global_position)
	var direction := Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y)
	var along := to.dot(direction)
	return along > -1.0 and (to - direction * along).length() <= lane_half_width
