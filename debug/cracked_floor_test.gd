extends Node3D
## Checks the cracked floor tile's rules on their own, with real physics. A stand-in body in
## the "players" group is moved on and off tiles. Run debug/cracked_floor_test.tscn and read
## the output for "CRACKED FLOOR TEST".
##
## Rules under test: a tile does nothing until stepped on; it collapses once bodies have stood
## on it for 3 s in total (and not otherwise: stepping off leaves it standing); the cracks
## spread while someone stands on it and stop when they step off; it can be collapsed at once;
## and once collapsed its floor is gone.

const TILE_SCENE := preload("res://hazards/cracked_floor.tscn")

## How far from 3.0 s a collapse may land (detection takes a tick or two).
@export var tolerance := 0.25

var _failures := 0
var _tick := 0
var _tiles_made := 0


func _physics_process(_delta: float) -> void:
	_tick += 1


func _ready() -> void:
	await _untouched_tile_stays()
	await _stepping_off_leaves_it_standing()
	await _standing_close_beside_it_is_not_standing_on_it()
	await _standing_still_drops_you()
	await _standing_time_adds_up_across_visits()
	await _cracks_spread_only_while_you_stand_on_it()
	_stamping_collapses_at_once()
	await _stamping_alone_does_not_collapse_an_untouched_tile()
	await _collapsed_tile_has_no_floor()
	print("CRACKED FLOOR TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _untouched_tile_stays() -> void:
	var tile := _new_tile()
	await _wait(4.0)
	_check("an untouched tile never collapses", tile.is_intact() and tile.seconds_left() < 0.0,
			"state %s" % tile.state)


func _stepping_off_leaves_it_standing() -> void:
	var tile := _new_tile()
	var visitor := _new_visitor()
	_put_on(visitor, tile)
	await _wait(1.0)
	_check("stepping on arms the tile", tile.state == CrackedFloor.State.ARMED, "state %s" % tile.state)
	_take_off(visitor)
	await _wait(5.0)
	_check("after you step off the tile stays standing (no countdown)", tile.is_intact(),
			"state %s after 5 s away" % tile.state)


func _standing_close_beside_it_is_not_standing_on_it() -> void:
	var tile := _new_tile()
	var visitor := _new_visitor(true)
	# Right beside the tile: the middle of the body is 0.2 m outside its edge, and the candle
	# held out toward it reaches well over the tile.
	visitor.global_position = tile.global_position + Vector3(2.2, 0.8, 0.0)
	await _wait(4.0)
	_check("standing close beside a tile, candle held over it, does nothing",
			tile.state == CrackedFloor.State.INTACT and tile.crack_spread() == 0.0,
			"state %s, spread %.2f" % [tile.state, tile.crack_spread()])
	visitor.global_position = tile.global_position + Vector3(1.9, 0.8, 0.0)
	await _wait(0.3)
	_check("with the middle of the body just over the edge it does arm", tile.state == CrackedFloor.State.ARMED,
			"state %s" % tile.state)


func _standing_still_drops_you() -> void:
	var tile := _new_tile()
	var visitor := _new_visitor()
	_put_on(visitor, tile)
	var elapsed := await _time_to_collapse(tile)
	_check("standing on it for 3 s collapses it under you", absf(elapsed - 3.0) <= tolerance,
			"%.2f s after stepping on" % elapsed)


func _standing_time_adds_up_across_visits() -> void:
	var tile := _new_tile()
	var visitor := _new_visitor()
	_put_on(visitor, tile)
	await _wait(0.5)
	_take_off(visitor)
	await _wait(2.0)
	_check("the tile stays standing while you are away", tile.is_intact(), "")
	_put_on(visitor, tile)
	var elapsed := await _time_to_collapse(tile)
	_check("coming back on, only the remaining standing time is left", absf(elapsed - 2.5) <= tolerance,
			"%.2f s after coming back (expected 2.5)" % elapsed)


func _cracks_spread_only_while_you_stand_on_it() -> void:
	var tile := _new_tile()
	var visitor := _new_visitor()
	_check("a fresh tile has no spread", tile.crack_spread() == 0.0, "%.2f" % tile.crack_spread())
	_put_on(visitor, tile)
	await _wait(1.0)
	var after_one_second := tile.crack_spread()
	_check("cracks spread while you stand on it (a third after 1 s)", absf(after_one_second - 1.0 / 3.0) <= 0.07,
			"%.2f" % after_one_second)
	_take_off(visitor)
	await _wait(0.2)  # the sensor takes a tick or two to notice the body has gone
	var frozen_at := tile.crack_spread()
	await _wait(1.0)
	_check("cracks stop spreading when you step off (flat for a full second)",
			absf(tile.crack_spread() - frozen_at) <= 0.001, "%.3f then %.3f" % [frozen_at, tile.crack_spread()])
	_put_on(visitor, tile)
	await _wait(1.0)
	_check("coming back, they carry on from where they stopped (two thirds)",
			absf(tile.crack_spread() - 2.0 / 3.0) <= 0.08, "%.2f" % tile.crack_spread())


func _stamping_collapses_at_once() -> void:
	var tile := _new_tile()
	tile.collapse_now()
	_check("stamping collapses it at once", not tile.is_intact(), "state %s" % tile.state)


func _stamping_alone_does_not_collapse_an_untouched_tile() -> void:
	var tile := _new_tile()
	var stamper := tile.global_position + Vector3(2.5, 0.8, 0.0)
	tile.set_stamping(1.0, stamper)
	await _wait(1.0)
	_check("stamping cracks the tile but doesn't collapse it", tile.is_intact() and tile.crack_spread() >= 0.85,
			"state %s, spread %.2f" % [tile.state, tile.crack_spread()])
	tile.set_stamping(0.0)
	await _wait(0.2)
	_check("the stamp cracks stay when the stamping stops", tile.crack_spread() >= 0.85,
			"%.2f" % tile.crack_spread())


func _collapsed_tile_has_no_floor() -> void:
	var tile := _new_tile()
	_check("an intact tile has a floor", _has_floor(tile), "")
	tile.collapse_now()
	await _wait(0.2)
	_check("a collapsed tile has no floor (it is a pit)", not _has_floor(tile), "")


## The seconds until the tile collapses, counted from now, or -1 if it never does.
func _time_to_collapse(tile: CrackedFloor, limit := 6.0) -> float:
	var start := _tick
	while tile.is_intact() and _seconds_since(start) < limit:
		await get_tree().physics_frame
	return -1.0 if tile.is_intact() else _seconds_since(start)


func _seconds_since(start_tick: int) -> float:
	return (_tick - start_tick) / float(Engine.physics_ticks_per_second)


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _new_tile() -> CrackedFloor:
	var tile := TILE_SCENE.instantiate() as CrackedFloor
	tile.position = Vector3(_tiles_made * 8.0, 0.0, 0.0)
	_tiles_made += 1
	add_child(tile)
	return tile


## A stand-in for the player: a body in the "players" group, parked out of the way. With
## `with_candle`, it also has a small box held out to its left (toward -X), like the candle's.
func _new_visitor(with_candle := false) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	shape.shape = capsule
	body.add_child(shape)
	if with_candle:
		var candle := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.14, 0.42, 0.14)
		candle.shape = box
		candle.position = Vector3(-0.55, 0.1, 0.0)
		body.add_child(candle)
	body.add_to_group("players")
	body.position = Vector3(0.0, 100.0, 0.0)
	add_child(body)
	return body


func _put_on(body: Node3D, tile: Node3D) -> void:
	body.global_position = tile.global_position + Vector3(0.0, 0.8, 0.0)


func _take_off(body: Node3D) -> void:
	body.global_position = Vector3(0.0, 100.0, 0.0)


func _has_floor(tile: Node3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
			tile.global_position + Vector3(0.0, 1.0, 0.0), tile.global_position + Vector3(0.0, -1.0, 0.0))
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
