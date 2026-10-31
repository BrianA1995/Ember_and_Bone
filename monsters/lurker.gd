class_name Lurker
extends Monster
## Waits in a corridor and does nothing until a lit prisoner MOVES in its line. Then a red streak
## shows along the floor, and a moment later it charges: every prisoner standing in that straight
## line, however far apart, is hit at once. Only open space counts as a line: a wall breaks it. A
## prisoner who stands still when they see it is not attacked, and one who steps out of the streak, or
## round a corner, before it charges is not hit.
##
## Tell: the red streak (the charge lane). Survive: leave the line, or keep still.

@export_group("Lurker")
## The longest line, in rooms, it can strike along.
@export_range(1, 10) var longest_lane := 5
## Seconds between the streak showing and the charge.
@export_range(0.2, 3.0, 0.05, "suffix:s") var windup := 1.2
@export var charge_speed := 14.0
## How far to either side of the line's middle, in metres, a prisoner is still in it.
@export var lane_half_width := 1.3
## Seconds it rests after a charge.
@export_range(0.0, 20.0, 0.5, "suffix:s") var rest_seconds := 6.0
## A prisoner moving slower than this (m/s) counts as standing still.
@export var moving_speed := 0.8

enum State { WAIT, WINDUP, CHARGE, REST }

var _state := State.WAIT
var _timer := 0.0
var _side := 0
var _goal := Vector3.ZERO
var _streak: MeshInstance3D


func _init() -> void:
	hits_on_touch = false


func _ready() -> void:
	super()
	_streak = part(box(Vector3(0.7, 0.03, 1.0)), Color(0.9, 0.05, 0.03), Vector3.ZERO, 2.0)
	_streak.visible = false
	add_child(_streak)


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


## A place with a straight run of at least two rooms to strike along.
func suits(at: Vector2i) -> bool:
	for side in RoomDefs.SIDE_COUNT:
		if director.lane(at, side, 3).size() >= 2:
			return true
	return false


func _act(delta: float) -> void:
	match _state:
		State.WAIT:
			_watch()
		State.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_strike()
		State.CHARGE:
			if move_toward_point(_goal, charge_speed, delta):
				_rest(rest_seconds)
		State.REST:
			_timer -= delta
			if _timer <= 0.0:
				_state = State.WAIT


func on_stunned() -> void:
	_rest(rest_seconds * 0.5)


## Something moving in a lane it can strike along, with a lit candle: start the windup.
func _watch() -> void:
	for side in RoomDefs.SIDE_COUNT:
		var rooms := director.lane(cell, side, longest_lane)
		if rooms.is_empty():
			continue
		for player in director.players:
			if player.is_candle_lit() and player.floor_speed() > moving_speed and _in_lane(player, side, rooms):
				_begin(side, rooms)
				return


func _begin(side: int, rooms: Array[Vector2i]) -> void:
	_state = State.WINDUP
	_timer = windup
	_side = side
	var direction := Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y)
	rotation.y = atan2(-direction.x, -direction.z)
	var length := rooms.size() * RoomDefs.CELL_SIZE + RoomDefs.CELL_SIZE * 0.5
	(_streak.mesh as BoxMesh).size.z = length
	_streak.position = Vector3(0.0, 0.03, -length * 0.5)
	_streak.visible = true


## Everyone in the line now is hit, then it charges to the far end.
func _strike() -> void:
	var rooms := director.lane(cell, _side, longest_lane)
	for player in director.players:
		if _in_lane(player, _side, rooms):
			director.hit(self, player)
	if rooms.is_empty():
		_rest(rest_seconds)
		return
	_goal = RoomDefs.cell_to_world(rooms[-1])
	_state = State.CHARGE
	_streak.visible = false


func _rest(seconds: float) -> void:
	_state = State.REST
	_timer = seconds
	_streak.visible = false


## Is `player` in the line from this room out through `side` (the rooms in `rooms`), near its middle?
func _in_lane(player: Player, side: int, rooms: Array[Vector2i]) -> bool:
	if cell != director.cell_at(player.global_position) and not rooms.has(director.cell_at(player.global_position)):
		return false
	var to := director.offset(global_position, player.global_position)
	var direction := Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y)
	var along := to.dot(direction)
	return along > -1.0 and (to - direction * along).length() <= lane_half_width
