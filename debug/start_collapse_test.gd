extends Node
## Plays the real game scene and checks the start chamber: its floor is cracked from the
## start, the cracks spread over the delay (standing on it changes nothing), the whole floor
## then drops at once, a new maze starts the countdown again, and a body that falls lands in
## a safe new room far away.
## Run debug/start_collapse_test.tscn and read the output for "START COLLAPSE TEST".

const DELAY := 5.0

var _failures := 0


func _ready() -> void:
	var game: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().physics_frame
	var manager: MazeManager = game.get_node("MazeManager")
	# The player stands in the room (and so is a body a tile could react to), but its own
	# physics are off so it stays put and can't fall.
	var player: Player = game.get_node("Player")
	player.set_physics_process(false)
	manager.start_collapse.delay = DELAY
	await _wait(0.3)
	var room := manager.view.room_at(Vector2i.ZERO)
	_check("the start room has eight floor tiles", _tiles(room).size() == 8, "%d" % _tiles(room).size())
	_check("the floor is cracked from the start", _cracked(room).size() == 8, "%d cracked" % _cracked(room).size())
	_check("and none has dropped", _gone(room) == 0, "%d gone" % _gone(room))
	_check("the overlay can read the time left", manager.start_collapse.seconds_left() > 0.0, "")
	await _wait(DELAY * 0.5)
	var spread := _spread(room)
	_check("halfway, the cracks are about halfway across", absf(spread - 0.5) < 0.15, "%.2f" % spread)
	_check("standing on the floor for longer than a normal tile allows breaks nothing", _gone(room) == 0, "%d gone" % _gone(room))
	await _wait(DELAY * 0.5 + 0.5)
	_check("then every tile drops", _gone(room) == 8, "%d gone" % _gone(room))
	_check("and the countdown is done", manager.start_collapse.phase == StartCollapse.Phase.DONE, "")
	# Now the floor is gone: the body falls, and wakes somewhere else.
	player.set_physics_process(true)
	await _wait(5.0)
	var cell := RoomDefs.world_to_cell(player.global_position)
	_check("a body that falls wakes far from the start room", maxi(absi(cell.x), absi(cell.y)) >= manager.landing_distance - 1, "now in cell %s" % cell)
	_check("standing on the floor of its new room", absf(player.global_position.y - 0.8) < 0.05 and not player.get("_falling"), "height %.2f" % player.global_position.y)
	await _landing_is_safe_and_far(manager)
	manager.restart()
	await _wait(0.3)
	var fresh := manager.view.room_at(Vector2i.ZERO)
	_check("a new maze has a new start room, cracked and intact", fresh != room and _cracked(fresh).size() == 8 and _gone(fresh) == 0, "")
	_check("and the countdown starts again", manager.start_collapse.phase == StartCollapse.Phase.SPREADING, "")
	print("START COLLAPSE TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## A fall lands the body in a plain, uncracked room, well away from where it fell.
func _landing_is_safe_and_far(manager: MazeManager) -> void:
	var bad := 0
	var near := 0
	for trial in 20:
		manager.restart()
		await _wait(0.1)
		var from := Vector3(randi_range(-6, 6) * 4.0, 0.0, randi_range(-6, 6) * 4.0)
		var spot := manager.landing_point(from)
		var cell := RoomDefs.world_to_cell(spot)
		var data := manager.grid.get_cell(cell)
		var distance := maxi(absi(cell.x - RoomDefs.world_to_cell(from).x), absi(cell.y - RoomDefs.world_to_cell(from).y))
		if data.is_empty() or data.cracked or RoomDefs.is_special(data.piece):
			bad += 1
		if distance < manager.landing_distance - 1:
			near += 1
	_check("a landing room is always a plain, uncracked room", bad == 0, "%d of 20 were not" % bad)
	_check("and well away from where the body fell", near == 0, "%d of 20 were close" % near)


func _tiles(room: Node3D) -> Array[Node]:
	return room.get_children().filter(func(child: Node) -> bool: return str(child.name).begins_with("Floor"))


func _cracked(room: Node3D) -> Array[Node]:
	return _tiles(room).filter(func(tile: Node) -> bool: return tile is CrackedFloor)


func _gone(room: Node3D) -> int:
	return _cracked(room).filter(func(tile: Node) -> bool: return not (tile as CrackedFloor).is_intact()).size()


func _spread(room: Node3D) -> float:
	var tile := _cracked(room)[0] as CrackedFloor
	return tile.crack_spread()


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
