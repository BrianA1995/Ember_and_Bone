class_name Weaver
extends Monster
## A spider. It creeps toward the nearest prisoner over the ceiling while they are far off, down a wall
## as it gets near, and onto the floor to strike; it leaves a web across the doorway behind it as it
## goes from room to room. A web stops prisoners and the other monsters (never the Weaver), and a flame
## held up to it burns it away (see Web).
##
## Once it has snuffed a candle it builds a web across a doorway, hangs on it, and waits there for the
## next prisoner to come within reach; it goes on hanging and weaving until its time (`life_seconds`
## after the first snuffing) is up and it disappears. If its web is burnt away it comes down and hunts again.
##
## Tell: webs across the doorways, a shape on the ceiling. Survive: burn a way through, or go round.

@export_group("Weaver")
## How far, in rooms, it can sense a prisoner.
@export_range(1, 10) var sense_cells := 4
## The chance it spins a web in the doorway behind it when it enters a new room.
@export_range(0.0, 1.0, 0.05) var web_chance := 0.7
## Seconds after its first snuffing before it disappears.
@export_range(5.0, 300.0, 1.0, "suffix:s") var life_seconds := 45.0
## Prisoners farther than this (metres) see it on the ceiling; nearer than `wall_metres` on a wall.
@export var ceiling_metres := 5.0
@export var wall_metres := 2.5
@export var ceiling_height := 2.7
## How far a hanging Weaver can reach, in metres.
@export var perch_reach := 1.6

enum State { HUNT, PERCH }

var _state := State.HUNT
var _last_cell := Vector2i(-9999, -9999)
var _life_left := 0.0
var _web_cell := Vector2i.ZERO
var _web_side := 0
var _pose_position := Vector3.ZERO
var _pose_basis := Basis.IDENTITY
var _normal_reach := 0.9


func _init() -> void:
	move_speed = 1.1
	crosses_webs = true
	after_hit_pause = 0.0
	_normal_reach = reach


func _process(delta: float) -> void:
	if model == null or _falling:
		return
	var k := 1.0 - exp(-5.0 * delta)
	model.position = model.position.lerp(_pose_position, k)
	model.basis = model.basis.slerp(_pose_basis, k).orthonormalized()


func build_model() -> Node3D:
	var body := Node3D.new()
	var grey := Color(0.5, 0.5, 0.46)
	var shape := part(ball(0.35), grey, Vector3(0.0, 0.4, 0.0))
	shape.scale = Vector3(1.0, 0.7, 1.2)
	body.add_child(shape)
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var leg := part(box(Vector3(0.9, 0.05, 0.05)), grey, Vector3(side * 0.55, 0.35, (i / 2 - 1) * 0.3))
		leg.rotation.z = side * 0.5
		body.add_child(leg)
	body.add_child(part(ball(0.04), Color(0.9, 0.9, 0.2), Vector3(-0.1, 0.5, -0.38), 3.0))
	body.add_child(part(ball(0.04), Color(0.9, 0.9, 0.2), Vector3(0.1, 0.5, -0.38), 3.0))
	return body


func _act(delta: float) -> void:
	if _life_left > 0.0:
		_life_left -= delta
		if _life_left <= 0.0:
			fade_out()
			return
	if _state == State.PERCH:
		_hang(delta)
		return
	reach = _normal_reach
	_spin_behind()
	var found := director.reachable(cell, sense_cells, true)
	var target: Player = null
	var best := INF
	for player in director.players:
		var there := director.cell_at(player.global_position)
		if found.has(there) and found[there].steps < best:
			best = found[there].steps
			target = player
	if target:
		go_to(director.cell_at(target.global_position), target.global_position, move_speed, delta)
	else:
		wander(move_speed * 0.6, delta)
	_pose_for_distance()


## It has snuffed a candle: build a web across a doorway and hang on it.
func on_hit(player: Player) -> void:
	if _life_left <= 0.0:
		_life_left = life_seconds
	var toward := director.offset(global_position, player.global_position)
	var best := -1
	var best_alignment := -2.0
	for side in RoomDefs.SIDE_COUNT:
		if not director.can_pass(cell, side, true):
			continue
		var alignment := Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y).dot(toward.normalized())
		if alignment > best_alignment:
			best_alignment = alignment
			best = side
	if best < 0:
		return
	director.place_web(cell, best)
	_web_cell = cell
	_web_side = best
	_state = State.PERCH
	reach = perch_reach


## Hangs on its web, ready for whoever comes through. If the web is burnt away it comes down.
func _hang(delta: float) -> void:
	if not director.has_web(_web_cell, _web_side):
		_state = State.HUNT
		return
	var door := Vector3(RoomDefs.DIRS[_web_side].x, 0.0, RoomDefs.DIRS[_web_side].y)
	move_toward_point(RoomDefs.cell_to_world(_web_cell) + door * 1.75, move_speed * 2.0, delta)
	_set_pose_on_wall(door, 0.0, 1.2)


## Ceiling while the prisoners are far off, a wall as they near, the floor to strike.
func _pose_for_distance() -> void:
	var nearest := nearest_player()
	var distance := INF if nearest == null else director.offset(global_position, nearest.global_position).length()
	if distance > ceiling_metres:
		_pose_position = Vector3(0.0, ceiling_height, 0.0)
		_pose_basis = Basis(Vector3.RIGHT, PI)
	elif distance > wall_metres:
		var wall := _closed_side()
		if wall >= 0:
			_set_pose_on_wall(Vector3(RoomDefs.DIRS[wall].x, 0.0, RoomDefs.DIRS[wall].y), 1.75)
		else:
			_pose_position = Vector3(0.0, ceiling_height, 0.0)
			_pose_basis = Basis(Vector3.RIGHT, PI)
	else:
		_pose_position = Vector3.ZERO
		_pose_basis = Basis.IDENTITY


## Clings to a vertical surface in direction `world_direction` from the middle of its room.
func _set_pose_on_wall(world_direction: Vector3, out: float, up := 1.3) -> void:
	var local := Basis(Vector3.UP, -rotation.y) * world_direction
	_pose_position = local * out + Vector3(0.0, up, 0.0)
	_pose_basis = Basis(Vector3.UP.cross(local).normalized(), -PI * 0.5)


## A side of the room it is in that has a wall.
func _closed_side() -> int:
	for side in RoomDefs.SIDE_COUNT:
		if not director.grid.is_open(cell, side):
			return side
	return -1


## Left a room for the next one: maybe close the doorway it came through.
func _spin_behind() -> void:
	if cell == _last_cell:
		return
	var came_from := _last_cell
	_last_cell = cell
	if director.rng.randf() > web_chance:
		return
	for side in RoomDefs.SIDE_COUNT:
		if director.grid.neighbor(cell, side) == came_from:
			director.place_web(cell, side)
