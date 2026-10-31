class_name Monster
extends Node3D
## What every monster shares. A monster stands on the floor (its origin is its feet) and is a Node3D
## the MonsterDirector put in the maze; it asks the Director about the world and does nothing the
## Director has not allowed (it only walks rooms that exist, and falls with the room under it).
##
## A kind is a script that extends this and fills in the blanks:
##   build_model()  what it looks like (a placeholder built in code: replace it with a real model)
##   suits(cell)    whether `cell` is a good place for one to start
##   _act(delta)    what it does each physics tick (not while stunned or after a hit)
##   on_hit(player) what it does to a prisoner it hits, besides snuffing their candle
##   on_stunned(), on_fall()  what happens when it is stunned, or the room under it goes
## and sets hits_on_touch false if it hits some other way (the Lurker's charge).
##
## Every monster is stunned for a moment by a raised flame held up toward it.

## How fast it walks, in m/s.
@export var move_speed := 1.5
## How close, in metres, it must get to a prisoner to hit them by touching.
@export var reach := 0.9
@export var hits_on_touch := true
## How many rooms ahead it plans a walk.
@export var path_depth := 14
## Whether a web across a doorway stops it.
@export var crosses_webs := false
@export_group("Stun")
@export var stun_seconds := 2.0
## Seconds after a stun ends during which it cannot be stunned again, so a held-up flame cannot pin it for ever.
@export var stun_immunity := 1.5
## A prisoner holding the flame up within this many metres, facing it, within the cone (degrees), stuns it.
@export var stun_range := 5.0
@export var stun_cone_degrees := 40.0
@export_group("After a hit")
## Seconds it stands still after hitting someone.
@export var after_hit_pause := 3.0

var director: MonsterDirector
## The room it stands in.
var cell := Vector2i.ZERO
var model: Node3D

var _stun_left := 0.0
var _stun_immune := 0.0
var _pause_left := 0.0
var _falling := false
var _replan := 0.0
var _planned_in := Vector2i(-9999, -9999)
var _step: Variant = null
var _wander_left := 0.0
var _wander_goal := Vector2i.ZERO


func _ready() -> void:
	model = build_model()
	add_child(model)
	cell = director.cell_at(global_position)


func _physics_process(delta: float) -> void:
	if director == null or _falling:
		return
	cell = director.cell_at(global_position)
	if _stun_left > 0.0:
		_stun_left -= delta
		if _stun_left <= 0.0:
			_stun_immune = stun_immunity
			model.rotation.z = 0.0
		return
	_stun_immune = maxf(_stun_immune - delta, 0.0)
	if _stun_immune <= 0.0 and _flame_held_at_me():
		stun(stun_seconds)
		return
	if _pause_left > 0.0:
		_pause_left -= delta
		return
	_act(delta)
	if hits_on_touch and not _falling:
		_touch()


# --- To fill in ------------------------------------------------------------------------

## The placeholder body: about the height of a person, feet at the origin. Replace it with a real model.
func build_model() -> Node3D:
	var body := Node3D.new()
	body.add_child(part(CapsuleMesh.new(), Color(0.3, 0.3, 0.3), Vector3(0.0, 0.9, 0.0)))
	return body


## Is `at` a good place for this kind to start?
func suits(_at: Vector2i) -> bool:
	return true


func _act(_delta: float) -> void:
	pass


## Called when this monster hits `player` (their candle is already out).
func on_hit(_player: Player) -> void:
	pass


func on_stunned() -> void:
	pass


## Called when the room under it goes, just before it falls.
func on_fall() -> void:
	pass


# --- Shared behaviour ------------------------------------------------------------------

## Freezes it for `seconds`.
func stun(seconds: float) -> void:
	_stun_left = seconds
	model.rotation.z = 0.35
	on_stunned()


func is_stunned() -> bool:
	return _stun_left > 0.0


## Stands still for `seconds` (used after a hit).
func pause(seconds: float) -> void:
	_pause_left = seconds


## The room under it has gone: it sinks out of sight and is gone for good.
func fall() -> void:
	if _falling:
		return
	_falling = true
	on_fall()
	var tween := create_tween()
	tween.tween_property(self, "position:y", -4.0, 0.5)
	tween.tween_callback(queue_free)


## Heads straight for `goal` (a point on the floor); true once it is there.
func move_toward_point(goal: Vector3, speed: float, delta: float) -> bool:
	var to := director.offset(global_position, goal)
	var distance := to.length()
	if distance < 0.05:
		return true
	var step := minf(speed * delta, distance)
	face(to / distance, delta)
	global_position = director.wrap_world(global_position + to / distance * step)
	return distance <= speed * delta


## Walks toward `goal_position` in room `goal_cell` along the open doorways: through the middle of each
## room, and straight to the point once it is in the goal room. False if there is no way there.
func go_to(goal_cell: Vector2i, goal_position: Vector3, speed: float, delta: float) -> bool:
	if goal_cell == cell:
		move_toward_point(goal_position, speed, delta)
		return true
	_replan -= delta
	if _replan <= 0.0 or _planned_in != cell:
		_replan = 0.3
		_planned_in = cell
		_step = director.next_step(cell, goal_cell, path_depth, crosses_webs)
	if _step == null:
		return false
	var middle := RoomDefs.cell_to_world(cell)
	if director.offset(global_position, middle).length() > 0.5:
		move_toward_point(middle, speed, delta)
	else:
		move_toward_point(RoomDefs.cell_to_world(_step), speed, delta)
	return true


## Strolls: picks a room within `depth` steps of `around` every few seconds and walks there.
func wander(speed: float, delta: float, around := Vector2i(-9999, -9999), depth := 4) -> void:
	if around == Vector2i(-9999, -9999):
		around = cell
	_wander_left -= delta
	if _wander_left <= 0.0 or _wander_goal == cell:
		_wander_left = director.rng.randf_range(3.0, 6.0)
		var rooms: Array = director.reachable(around, depth, crosses_webs).keys()
		_wander_goal = rooms[director.rng.randi() % rooms.size()]
	go_to(_wander_goal, RoomDefs.cell_to_world(_wander_goal), speed, delta)


## Turns to face `direction` (on the floor plane).
func face(direction: Vector3, delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 1.0 - exp(-10.0 * delta))


## The prisoner nearest to this monster (the short way round), or null; `only` filters them.
func nearest_player(only := Callable()) -> Player:
	var best: Player = null
	var best_distance := INF
	for player in director.players:
		if only.is_valid() and not only.call(player):
			continue
		var distance := director.offset(global_position, player.global_position).length()
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _flame_held_at_me() -> bool:
	for player in director.players:
		if not player.flame_raised():
			continue
		var to := director.offset(player.global_position, global_position)
		if to.length() > stun_range or player.facing().angle_to(to) > deg_to_rad(stun_cone_degrees):
			continue
		if director.line_clear(player.candle_position(), player.candle_position() + to):
			return true
	return false


func _touch() -> void:
	for player in director.players:
		if director.offset(global_position, player.global_position).length() <= reach and director.hit(self, player):
			_pause_left = after_hit_pause
			return


# --- Placeholder building blocks -------------------------------------------------------

## A coloured primitive for building placeholder bodies; `glow` makes it shine a little by itself.
static func part(mesh: Mesh, color: Color, at := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	if glow > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = glow
	instance.material_override = material
	return instance


static func box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func ball(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return mesh
