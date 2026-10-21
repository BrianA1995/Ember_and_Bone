extends Node3D
## Checks the player's falling, with the real player and real floor slabs. It must fall when
## the floor is truly gone, and never otherwise, and must never be left stuck falling.
## Run debug/player_fall_test.tscn and read the output for "PLAYER FALL TEST".
##
## Background: the floor is made of separate 4 m slabs, and a pit is a collapsed slab. The
## player once got stuck because falling started wrongly (a ray down the seam between two slabs
## found no floor) or while resting on the edge of a pit, and then nothing ever ended the fall.

const PLAYER_SCENE := preload("res://player/player.tscn")
const TILE_SCENE := preload("res://hazards/cracked_floor.tscn")

var _player: Player
var _failures := 0
var _fell_count := 0
var _ever_falling := false
var _stage := 0


func _physics_process(_delta: float) -> void:
	if _player and _player.get("_falling"):
		_ever_falling = true


func _ready() -> void:
	_player = PLAYER_SCENE.instantiate() as Player
	_player.respawn_after_fall = false
	add_child(_player)
	_player.fell.connect(func() -> void: _fell_count += 1)
	await _wait(0.2)
	await _crossing_seams_never_falls()
	await _stuck_falling_on_solid_floor_recovers()
	await _pit_edge_holds_you_up()
	await _over_the_hole_you_fall()
	print("PLAYER FALL TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## Walking across the seam between two slabs, at several alignments and speeds.
func _crossing_seams_never_falls() -> void:
	var trials := 0
	var falls := 0
	for seam_error in [0.0, 0.0001, 0.002]:
		for offset in [0.0, 0.37, -0.2]:
			for sprint in [false, true]:
				for along_x in [true, false]:
					var origin := _next_stage()
					var seam := Vector3(seam_error, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, seam_error)
					var step := Vector3.RIGHT if along_x else Vector3.BACK
					_slab(origin + seam - step * 2.0)
					_slab(origin + seam + step * 2.0)
					var side := Vector3.BACK if along_x else Vector3.RIGHT
					_place_player(origin - step * 3.0 + side * offset)
					_ever_falling = false
					# About 6 m, enough to cross the whole patch.
					var seconds := 6.0 / (_player.sprint_speed if sprint else _player.walk_speed)
					await _walk(&"move_right" if along_x else &"move_back", seconds, sprint)
					trials += 1
					if _ever_falling:
						falls += 1
	_check("walking across a seam never starts a fall", falls == 0, "%d of %d crossings fell" % [falls, trials])


## A body wrongly stuck in the falling state on solid floor must land and take control back.
func _stuck_falling_on_solid_floor_recovers() -> void:
	var origin := _next_stage()
	_slab(origin)
	_place_player(origin)
	_player.set("_falling", true)
	_player.set("_fall_speed", 900.0)
	await _wait(0.4)
	_check("a fall that finds floor ends (it lands)", not _player.get("_falling"),
			"falling after 0.4 s: %s" % _player.get("_falling"))
	_check("it lands at standing height", absf(_player.global_position.y - 0.8) < 0.05,
			"height %.2f" % _player.global_position.y)
	var before := _player.global_position.x
	await _walk(&"move_right", 0.5, false)
	_check("and the controls work again afterwards", _player.global_position.x > before + 0.5,
			"moved %.2f m" % (_player.global_position.x - before))


## The reported bug: a tile collapses while the player's body still overlaps the solid floor
## next to it. The player must stay up and be able to walk away.
func _pit_edge_holds_you_up() -> void:
	var origin := _next_stage()
	_slab(origin - Vector3(2.0, 0.0, 0.0))
	var tile := _tile(origin + Vector3(2.0, 0.0, 0.0))
	# The middle of the body is 0.2 m over the tile, but the body (0.35 m wide) still reaches
	# the solid slab beside it.
	_place_player(origin + Vector3(0.2, 0.0, 0.0))
	await _wait(0.2)
	tile.collapse_now()
	_fell_count = 0
	await _wait(1.0)
	_check("standing on the edge of a pit, you are not falling", not _player.get("_falling"),
			"falling: %s, height %.2f" % [_player.get("_falling"), _player.global_position.y])
	var before := _player.global_position.x
	await _walk(&"move_left", 0.6, false)
	_check("and you can walk away from it", _player.global_position.x < before - 0.5 and _fell_count == 0,
			"moved %.2f m, falls %d" % [before - _player.global_position.x, _fell_count])


## With the body wholly over the hole there is nothing to hold it up: it must fall.
func _over_the_hole_you_fall() -> void:
	var origin := _next_stage()
	_slab(origin - Vector3(2.0, 0.0, 0.0))
	var tile := _tile(origin + Vector3(2.0, 0.0, 0.0))
	_place_player(origin + Vector3(2.0, 0.0, 0.0))
	await _wait(0.2)
	tile.collapse_now()
	_fell_count = 0
	await _wait(3.0)
	_check("with nothing under you, you fall", _fell_count == 1, "%d falls" % _fell_count)
	_check("and the fall ends (no endless falling)", not _player.get("_falling"),
			"falling after 3 s: %s" % _player.get("_falling"))


# --- Helpers ---------------------------------------------------------------------------

## The centre of a fresh, empty patch of ground, far from the last one.
func _next_stage() -> Vector3:
	_stage += 1
	return Vector3(0.0, 0.0, _stage * 30.0)


func _slab(centre: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	shape.shape = box
	body.add_child(shape)
	body.position = centre + Vector3(0.0, -0.1, 0.0)
	add_child(body)
	return body


func _tile(centre: Vector3) -> CrackedFloor:
	var tile := TILE_SCENE.instantiate() as CrackedFloor
	tile.position = centre
	add_child(tile)
	return tile


func _place_player(at: Vector3) -> void:
	_player.set_physics_process(true)
	_player.set("_falling", false)
	_player.velocity = Vector3.ZERO
	_player.global_position = Vector3(at.x, 0.8, at.z)
	_player.reset_physics_interpolation()
	_player.set("_grace_left", 0.0)
	_player.set("_unsupported_ticks", 0)


## Holds a movement key for `seconds`, then lets go.
func _walk(action: StringName, seconds: float, sprint: bool) -> void:
	if sprint:
		Input.action_press(&"sprint")
	Input.action_press(action)
	await _wait(seconds)
	Input.action_release(action)
	Input.action_release(&"sprint")
	await _wait(0.05)


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
