extends Node
## A teammate standing behind a player must not push that player's third-person camera in: the camera only
## gives way to the maze, never to another body (it would sit against the teammate and they would blink
## in and out of view). Run debug/camera_clip_test.tscn and read the output for "CAMERA CLIP TEST".

var _failures := 0


func _ready() -> void:
	GameSettings.player_count = 2
	GameInput.configure(2)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.5)
	var rig := game.rigs[0]
	rig.set_mode(CameraRig.Mode.THIRD)
	rig.yaw = 0.0
	rig.pitch = 0.0
	var leader := game.players[0]
	var follower := game.players[1]
	leader.global_position = Vector3(0.0, 0.9, 0.0)
	# Out of the way (off to the side) first, for how far back the camera sits with only the maze about.
	follower.global_position = Vector3(1.4, 0.9, 0.0)
	await _frames(4)
	var free := rig.get_camera().global_position.distance_to(leader.global_position)
	# Now right behind the leader, on the line the camera looks back along.
	follower.global_position = Vector3(0.0, 0.9, 1.4)
	await _frames(4)
	var behind := rig.get_camera().global_position.distance_to(leader.global_position)
	_check("the camera stays where it was with a teammate right behind", absf(behind - free) < 0.05, "%.2f vs %.2f" % [behind, free])
	print("CAMERA CLIP TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
