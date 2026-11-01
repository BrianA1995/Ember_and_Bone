extends Node
## Looks for a teammate's body blinking out of view. Two players in the real window: player 1 wanders,
## player 2 follows. Every frame it records, from player 2's camera, whether player 1's body should be
## drawn (visible, on a layer the camera draws, in the view, nothing solid in between) and how bright the
## picture is where the body should be. Anything that should be seen but is dark is written to
## `user://blink_log.txt`. Run it in the editor (not headless), then read the log.

@export var seconds := 900.0
@export var speed := 1.0

var _game: LocalGame
var _director: MonsterDirector
var _average := 0.0
var _log: FileAccess
var _clock := 0.0
var _frames := 0
var _bad := 0
var _was_bad := false
var _held := {}


func _ready() -> void:
	_log = FileAccess.open("user://blink_log.txt", FileAccess.WRITE)
	# The monster director is only used for its room-to-room routes; it spawns nothing.
	GameSettings.monsters = true
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 2
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(_game)
	_director = _game.get_node("MonsterDirector")
	_director.enabled = false
	Engine.time_scale = speed


func _say(text: String) -> void:
	var line := "[%6.1f s] %s" % [_clock, text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


func _hold(slot: int, action_name: StringName, on: bool) -> void:
	var action := GameInput.action(slot, action_name)
	if on and not _held.has(action):
		Input.action_press(action)
		_held[action] = true
	elif not on and _held.has(action):
		Input.action_release(action)
		_held.erase(action)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock > seconds:
		_say("done: %d frames, %d bad" % [_frames, _bad])
		_log.close()
		get_tree().quit()
		return
	# Player 1 is a person. Player 2 walks the doorways after them, staying 2.5 m back.
	var leader := _game.players[0]
	var follower := _game.players[1]
	_walk(1, follower, _director.cell_at(leader.global_position), 2.5, leader.global_position)


## Walks `body` toward room `goal` along the open doorways (as a player would), and, in the goal room, toward
## `point` until within `stop_within` metres of it.
func _walk(slot: int, body: Player, goal: Vector2i, stop_within: float, point := Vector3.INF) -> void:
	var cell := _director.cell_at(body.global_position)
	var target := RoomDefs.cell_to_world(goal) if point == Vector3.INF else point
	if cell != goal:
		var step: Variant = _director.next_step(cell, goal, 40, true)
		if step != null:
			target = _through_door(body, cell, step)
	var to := _director.offset(body.global_position, target)
	var rig: CameraRig = _game.rigs[slot]
	if to.length() > 0.05:
		rig.yaw = lerp_angle(rig.yaw, atan2(-to.x, -to.z), 0.5)
	var close_enough := cell == goal and _director.offset(body.global_position, target).length() < maxf(stop_within, 0.15)
	_hold(slot, &"move_forward", not close_enough)
	_hold(slot, &"sprint", false)


## Line up with the middle of the room, then go through the doorway into `step`.
func _through_door(body: Player, from: Vector2i, step: Vector2i) -> Vector3:
	var middle := RoomDefs.cell_to_world(from)
	var way := _director.offset(middle, RoomDefs.cell_to_world(step)).normalized()
	var rel := _director.offset(middle, body.global_position)
	var along := rel.dot(way)
	var lateral := rel - way * along
	if lateral.length() > 0.3 and along < 1.2:
		return middle + way * minf(along, 0.0)
	return RoomDefs.cell_to_world(step)


func _process(_delta: float) -> void:
	if _game == null or _game.players.size() < 2:
		return
	_frames += 1
	var body := _game.players[1]
	var visual := body.get_node("Visual") as MeshInstance3D
	var camera := _game.rigs[0].get_camera()
	var centre := visual.global_position
	var problems: Array[String] = []
	if not visual.is_visible_in_tree():
		problems.append("body not visible in tree")
	if visual.layers & camera.cull_mask == 0:
		problems.append("layers %d not in the camera mask %d" % [visual.layers, camera.cull_mask])
	if not camera.is_position_in_frustum(centre):
		return
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, centre)
	query.exclude = [body.get_rid(), _game.players[0].get_rid()]
	if not camera.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return
	var viewport := camera.get_viewport()
	if _frames % 3 == 0 and viewport is SubViewport:
		var image := viewport.get_texture().get_image()
		var at := Vector2i(camera.unproject_position(centre))
		var brightest := 0.0
		for dx in range(-4, 5, 2):
			for dy in range(-4, 5, 2):
				var spot := at + Vector2i(dx, dy)
				if spot.x >= 0 and spot.y >= 0 and spot.x < image.get_width() and spot.y < image.get_height():
					brightest = maxf(brightest, image.get_pixelv(spot).get_luminance())
		# The body is dim, so compare with how bright it has been: a blink is a sudden drop.
		if _average > 0.03 and brightest < _average * 0.4:
			problems.append("picture is dark where the body is (%.3f, was %.3f)" % [brightest, _average])
		_average = brightest if _average == 0.0 else lerpf(_average, brightest, 0.1)
	var bad := not problems.is_empty()
	if bad:
		_bad += 1
	if bad != _was_bad:
		_was_bad = bad
		_say("%s: %s (distance %.1f, leader %s, follower %s)" % [
			"SHOULD BE SEEN BUT IS NOT" if bad else "back", ", ".join(problems),
			camera.global_position.distance_to(centre), _game.players[0].global_position.snappedf(0.1),
			body.global_position.snappedf(0.1)])
