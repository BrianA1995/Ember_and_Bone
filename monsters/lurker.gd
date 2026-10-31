class_name Lurker
extends Monster
## Creeps up on a prisoner, silently, red eyes in the dark, and gives nothing else away. It reacts to
## being noticed: when a lit prisoner it can be seen by first moves or turns the camera in a straight open
## line from it, it freezes and gives `grace_seconds` (once) to stop. After that, any movement or turning
## of the camera (small bumps allowed) in its line makes it shoot down the line: everyone standing in it,
## however far apart, is hit at once, and it is gone (it never rests and comes back). A prisoner who keeps
## completely still, camera and all, for `still_seconds` beside it is left alone: it wanders off and
## disappears. It does not hang around either way: after `life_seconds` it loses interest and leaves.
## The Director allows only one at a time, with a long gap between them.
## Only open space counts as a line: a wall breaks it.
##
## Survive: freeze when you see it, put the candle away, or break the line round a corner.

@export_group("Lurker")
## How fast it creeps toward a prisoner.
@export var creep_speed := 1.3
## How far, in rooms, it can sense a prisoner to creep toward.
@export_range(1, 12) var sense_cells := 6
## The longest line, in rooms, it can strike along.
@export_range(1, 10) var longest_lane := 5
## Seconds a prisoner in its line has to stop moving and looking about before it charges.
@export_range(0.2, 5.0, 0.1, "suffix:s") var grace_seconds := 2.0
@export var charge_speed := 14.0
## How far to either side of the line's middle, in metres, a prisoner is still in it.
@export var lane_half_width := 1.3
## A prisoner moving slower than this (m/s) counts as standing still, and so does one turning slower than
## `turning_speed` (degrees a second).
@export var moving_speed := 0.8
@export var turning_speed := 35.0
## How close, in metres, it creeps up to a prisoner and then stands.
@export var stand_off := 1.4
@export_group("Leaving")
## Seconds a prisoner must stay still beside it before it loses interest and leaves.
@export_range(0.5, 20.0, 0.5, "suffix:s") var still_seconds := 4.0
## Seconds after it appears that it gives up and leaves, whatever happens.
@export_range(5.0, 300.0, 1.0, "suffix:s") var life_seconds := 40.0
## Seconds it spends walking away before it disappears.
@export_range(0.5, 20.0, 0.5, "suffix:s") var leave_seconds := 4.0

enum State { STALK, CHARGE, LEAVE }

var _state := State.STALK
var _timer := 0.0
## Seconds of grace left once it has been noticed (below 0 until then), and whether it is spent.
var _grace := -1.0
var _armed := false
var _still := 0.0
var _age := 0.0
var _side := 0
var _goal := Vector3.ZERO
## Where each prisoner was looking last tick, to tell when they turn.
var _looking: Dictionary = {}
var _turning: Dictionary = {}


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
	_watch_looking(delta)
	match _state:
		State.STALK:
			_age += delta
			_stalk(delta)
		State.CHARGE:
			if move_toward_point(_goal, charge_speed, delta):
				fade_out(0.4)
		State.LEAVE:
			_leave(delta)


func on_stunned() -> void:
	_still = 0.0


## Creeps toward the nearest prisoner; while one moves or looks about in its line it stands still and
## counts down. Beside a prisoner who keeps perfectly still it soon loses interest.
func _stalk(delta: float) -> void:
	if _age >= life_seconds:
		_start_leaving()
		return
	var side := _noticed_in_line()
	# The first time it is noticed it freezes and the grace period starts, whatever the prisoner then does.
	if side >= 0 and _grace < 0.0 and not _armed:
		_grace = grace_seconds
	if _grace > 0.0:
		_grace -= delta
		if _grace <= 0.0:
			_armed = true
		return
	# Once the grace is spent any movement or turning of the camera in its line sets it off; a prisoner
	# who then stays still beside it makes it lose interest.
	if _armed:
		if side >= 0:
			_side = side
			_strike()
			return
		_still += delta
		if _still >= still_seconds:
			_start_leaving()
		return
	var target := nearest_player(func(player: Player) -> bool:
		return director.offset(global_position, player.global_position).length() <= sense_cells * RoomDefs.CELL_SIZE)
	if target == null:
		wander(creep_speed * 0.6, delta)
		return
	if director.offset(global_position, target.global_position).length() > stand_off:
		_still = 0.0
		go_to(director.cell_at(target.global_position), target.global_position, creep_speed, delta)
	else:
		_still += delta
		if _still >= still_seconds:
			_start_leaving()


## The side of a line a lit prisoner who can see it is moving or turning in, or -1.
func _noticed_in_line() -> int:
	for side in RoomDefs.SIDE_COUNT:
		var rooms := director.lane(cell, side, longest_lane)
		for player in director.players:
			if _gives_away(player) and director.is_lit(player, cell) and _in_lane(player, side, rooms):
				return side
	return -1


## Is `player` moving about, or turning the camera, with a lit candle?
func _gives_away(player: Player) -> bool:
	return player.is_candle_lit() and (player.floor_speed() > moving_speed or _turning.get(player, false))


## Remembers which way each prisoner faces, to tell when they are turning.
func _watch_looking(delta: float) -> void:
	for player in director.players:
		var now := player.facing()
		if _looking.has(player) and delta > 0.0:
			_turning[player] = rad_to_deg(now.angle_to(_looking[player])) / delta > turning_speed
		_looking[player] = now


## Everyone in the line now is hit, then it shoots to the far end and is gone.
func _strike() -> void:
	var rooms := director.lane(cell, _side, longest_lane)
	var direction := Vector3(RoomDefs.DIRS[_side].x, 0.0, RoomDefs.DIRS[_side].y)
	rotation.y = atan2(-direction.x, -direction.z)
	for player in director.players:
		if _in_lane(player, _side, rooms):
			director.hit(self, player)
	if rooms.is_empty():
		fade_out(0.4)
		return
	_goal = RoomDefs.cell_to_world(rooms[-1])
	_state = State.CHARGE


func _start_leaving() -> void:
	_state = State.LEAVE
	_timer = leave_seconds


## Wanders away from the prisoners, then disappears.
func _leave(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		fade_out()
		return
	var threats: Array[Vector2i] = []
	for player in director.players:
		threats.append(director.cell_at(player.global_position))
	var step: Variant = director.step_away(cell, threats)
	if step != null:
		move_toward_point(RoomDefs.cell_to_world(step), creep_speed, delta)


## Is `player` in the line from this room out through `side` (the rooms in `rooms`), near its middle?
func _in_lane(player: Player, side: int, rooms: Array[Vector2i]) -> bool:
	var there := director.cell_at(player.global_position)
	if cell != there and not rooms.has(there):
		return false
	var to := director.offset(global_position, player.global_position)
	var direction := Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y)
	var along := to.dot(direction)
	return along > -1.0 and (to - direction * along).length() <= lane_half_width
