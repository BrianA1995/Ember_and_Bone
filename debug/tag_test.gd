extends Node
## Plays tag in the real game scene with three players and checks the rules: one player is it and
## only they are told, being it costs a point a second, touching passes the tag (no instant tag
## back), the head start holds everything, a player who runs out is sent to the sealed room and
## the last one left wins, and endless tag never ends.
## Run debug/tag_test.tscn and read the output for "TAG TEST".

var _failures := 0


func _ready() -> void:
	await _tag_game()
	await _endless_game()
	print("TAG TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _tag_game() -> void:
	GameSettings.game_mode = GameSettings.GameMode.TAG
	GameSettings.player_count = 3
	GameSettings.tag_points = 50
	GameInput.configure(3)
	var game := await _start()
	var tag := game.tag
	_check("a tag game has tag rules", tag != null and tag.eliminate, "")
	_check("everybody starts with the chosen points", tag.points == [50.0, 50.0, 50.0], "%s" % [tag.points])
	_check("someone is it", tag.it_slot >= 0 and tag.it_slot < 3, "%d" % tag.it_slot)
	_check("only the one who is it is told", _banners(tag) == [tag.it_slot], "%s" % [_banners(tag)])

	print("-- head start")
	tag.head_start = 1.0
	tag.reset()
	var first := tag.it_slot
	await _wait(0.5)
	_check("nothing is lost during the head start", tag.points[first] == 50.0, "%.2f" % tag.points[first])
	game.players[(first + 1) % 3].warp_to(game.players[first].global_position + Vector3(0.3, 0, 0))
	await _wait(0.3)
	_check("and nobody can be tagged", tag.it_slot == first, "")

	print("-- being it")
	game.players[(first + 1) % 3].warp_to(Vector3(6, 0.8, 0))
	await _wait(1.2)
	var lost := 50.0 - tag.points[first]
	_check("after the head start it costs a point a second", lost > 0.5 and lost < 1.5, "%.2f lost" % lost)
	_check("and the others lose nothing", tag.points[(first + 1) % 3] == 50.0 and tag.points[(first + 2) % 3] == 50.0, "")

	print("-- passing the tag")
	tag.head_start = 0.0
	tag.reset()
	var holder := tag.it_slot
	var target := (holder + 1) % 3
	game.players[holder].warp_to(Vector3(-6, 0.8, 0))
	game.players[target].warp_to(Vector3(6, 0.8, 0))
	game.players[(holder + 2) % 3].warp_to(Vector3(0, 0.8, 6))
	await _wait(0.3)
	_check("apart, nothing happens", tag.it_slot == holder, "")
	game.players[target].warp_to(game.players[holder].global_position + Vector3(0.5, 0, 0))
	await _wait(0.2)
	_check("touching passes the tag", tag.it_slot == target, "now %d, was %d" % [tag.it_slot, holder])
	_check("and only the new one is told", _banners(tag) == [target], "%s" % [_banners(tag)])
	await _wait(0.4)
	_check("it can't be passed straight back", tag.it_slot == target, "")
	game.players[target].warp_to(Vector3(6, 0.8, 0))
	var kept := tag.points[holder]
	await _wait(1.0)
	_check("the one who passed it stops losing points", tag.points[holder] == kept, "")

	print("-- running out of points")
	var out := []
	var results := []
	tag.player_out.connect(func(slot: int) -> void: out.append(slot))
	tag.round_over.connect(func(standings: Array) -> void: results.append(standings))
	var loser := tag.it_slot
	tag.points[loser] = 0.4
	await _wait(1.0)
	var body: Player = game.players[loser]
	_check("running out sends the player out of the round", out == [loser] and not tag.alive[loser], "%s" % [out])
	_check("they are in the sealed room, far from the maze", body.global_position.distance_to(HoldingRoom.LOCATION) < 4.0, "%s" % body.global_position)
	await _wait(1.0)
	_check("standing on its floor", absf(body.global_position.y - 0.8) < 0.1 and not body.get("_falling"), "height %.2f" % body.global_position.y)
	_check("they no longer light the maze", not body.is_in_group("light_sources"), "")
	_check("somebody still in is it", tag.alive[tag.it_slot] and tag.it_slot != loser, "%d" % tag.it_slot)
	_check("the round goes on with two players", not tag.finished and results.is_empty(), "")
	var second := tag.it_slot
	tag.points[second] = 0.4
	await _wait(1.0)
	_check("with one player left the round ends", tag.finished and results.size() == 1, "")
	var standings: Array = results[0] if results.size() else []
	var winner := 3 - loser - second
	_check("the one left wins, then the others in the order they lasted",
			standings.size() == 3 and standings[0].slot == winner and standings[1].slot == second and standings[2].slot == loser,
			"%s" % [standings])
	_check("a results screen appeared and paused the game", get_tree().paused and _has_results(game), "")
	get_tree().paused = false

	print("-- a new maze")
	game.get_node("MazeManager").restart()
	await _wait(0.3)
	_check("starts a new round with everyone back in", not tag.finished and tag.points.all(func(p: float) -> bool: return p > 49.0) and tag.alive == [true, true, true], "%s" % [tag.points])
	_check("the player who was out is back at the start and lights the maze again",
			body.is_in_group("light_sources") and body.global_position.length() < 20.0, "%s" % body.global_position)

	print("-- rules")
	GameSettings.player_count = 1
	GameSettings.enforce_mode_rules()
	_check("tag needs at least two players", GameSettings.player_count == 2, "")
	game.queue_free()
	await get_tree().process_frame


func _endless_game() -> void:
	print("-- endless tag")
	GameSettings.game_mode = GameSettings.GameMode.ENDLESS_TAG
	GameSettings.player_count = 2
	GameInput.configure(2)
	var game := await _start()
	var tag := game.tag
	_check("endless tag has tag rules and nobody is ever out", tag != null and not tag.eliminate, "")
	tag.head_start = 0.0
	tag.reset()
	tag.points[tag.it_slot] = 0.3
	await _wait(1.5)
	_check("points stop at zero", tag.points[tag.it_slot] == 0.0, "")
	_check("nobody is sent away and the game goes on", tag.alive == [true, true] and not tag.finished, "")
	game.queue_free()
	await get_tree().process_frame

	print("-- freeplay")
	GameSettings.game_mode = GameSettings.GameMode.FREEPLAY
	GameSettings.player_count = 1
	GameInput.configure(1)
	var free := await _start()
	_check("freeplay has no tag rules", free.tag == null, "")
	free.queue_free()
	await get_tree().process_frame


func _start() -> LocalGame:
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await _wait(0.3)
	return game


## Which players have the "you are it" banner showing.
func _banners(tag: TagMode) -> Array:
	var shown := []
	for slot in tag._huds.size():
		if tag._huds[slot]._banner.visible:
			shown.append(slot)
	return shown


func _has_results(game: Node) -> bool:
	for child in game.get_children():
		if child is TagResults:
			return true
	return false


func _wait(seconds: float) -> void:
	for i in roundi(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(what: String, passed: bool, detail: String) -> void:
	if not passed:
		_failures += 1
	print("  %s: %s%s" % ["ok  " if passed else "FAIL", what, "" if detail.is_empty() else " (%s)" % detail])
