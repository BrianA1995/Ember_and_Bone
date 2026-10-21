extends Node
## Plays the real game scene and checks that the start chamber's floor gives way on time:
## plain floor before the delay, cracks across every tile, then every tile gone, and that
## a new maze starts the countdown again.
## Run debug/start_collapse_test.tscn and read the output for "START COLLAPSE TEST".

const DELAY := 1.0

var _failures := 0


func _ready() -> void:
	var game: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().physics_frame
	var manager: MazeManager = game.get_node("MazeManager")
	# The player only stands in for the light; it must not fall or crack anything.
	var player: Player = game.get_node("Player")
	player.remove_from_group("players")
	player.set_physics_process(false)
	manager.start_collapse.delay = DELAY
	await _wait(0.3)
	var room := manager.view.room_at(Vector2i.ZERO)
	_check("the start room has eight floor tiles", _tiles(room).size() == 8, "%d" % _tiles(room).size())
	_check("they are plain floor at first", _cracked(room).is_empty(), "%d cracked" % _cracked(room).size())
	_check("the overlay can read the time left", manager.start_collapse.seconds_left() > 0.0, "")
	await _wait(DELAY + 1.5)
	_check("then every tile is cracked", _cracked(room).size() == 8, "%d cracked" % _cracked(room).size())
	_check("and none has dropped yet", _gone(room) == 0, "%d gone" % _gone(room))
	await _wait(0.5 * 8 + 1.5)
	_check("then every tile has dropped", _gone(room) == 8, "%d gone" % _gone(room))
	_check("and the countdown is done", manager.start_collapse.phase == StartCollapse.Phase.DONE, "")
	manager.restart()
	await _wait(0.3)
	var fresh := manager.view.room_at(Vector2i.ZERO)
	_check("a new maze has a new start room with plain floor", fresh != room and _cracked(fresh).is_empty(), "")
	_check("and the countdown starts again", manager.start_collapse.phase == StartCollapse.Phase.WAITING, "")
	print("START COLLAPSE TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _tiles(room: Node3D) -> Array[Node]:
	return room.get_children().filter(func(child: Node) -> bool: return str(child.name).begins_with("Floor"))


func _cracked(room: Node3D) -> Array[Node]:
	return _tiles(room).filter(func(tile: Node) -> bool: return tile is CrackedFloor)


func _gone(room: Node3D) -> int:
	return _cracked(room).filter(func(tile: Node) -> bool: return not (tile as CrackedFloor).is_intact()).size()


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
