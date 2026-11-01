extends Node
## The candle's wax in the real game scene (escape mode): a candle that lasts the time chosen in the setup, burns
## faster raised and slower put away, goes out for good when it is used up (slow, no sprint, matches and teammates
## cannot help), is refilled only by a spare candle (or a wax shrine), shortens as it burns, and can be blown out
## to save the wax (a match lights it again).
## Run debug/wax_test.tscn and read the output for "WAX TEST".

var _failures := 0
var _game: LocalGame
var _player: Player
var _bag: ItemBag


func _ready() -> void:
	GameSettings.monsters = false
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 30
	GameSettings.candle_minutes = 3
	GameInput.configure(1)
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(_game)
	await _wait(0.5)
	_player = _game.players[0]
	_bag = _game.get_node("ItemBag")
	_bag.setup(1)
	await _burning()
	await _blowing_out()
	await _burning_down()
	print("WAX TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	GameSettings.candle_minutes = 10
	get_tree().quit(0 if _failures == 0 else 1)


func _burning() -> void:
	print("-- burning")
	_check("the candle lasts what the setup chose", is_equal_approx(_player.wax.total, 180.0), "%.0f" % _player.wax.total)
	_check("and starts full", _player.wax.fraction() > 0.95, "%.2f" % _player.wax.fraction())
	var before := _player.wax.left
	await _wait(1.0)
	var plain := before - _player.wax.left
	_check("a lit candle burns a second a second", plain > 0.8 and plain < 1.3, "%.2f" % plain)
	before = _player.wax.left
	Input.action_press(GameInput.action(0, &"hold_flame"))
	await _wait(1.0)
	var raised := before - _player.wax.left
	_check("raised in front of the face it burns faster", raised > plain * 2.0, "%.2f vs %.2f" % [raised, plain])
	Input.action_release(GameInput.action(0, &"hold_flame"))
	await _wait(0.5)
	_game.escape.equipped[0] = 1
	_game.escape.keys_held[0] = 1
	await _wait(0.3)
	before = _player.wax.left
	await _wait(1.0)
	var away := before - _player.wax.left
	_check("put away in the hand it burns slower", away < plain * 0.8 and away > 0.0, "%.2f vs %.2f" % [away, plain])
	_game.escape.equipped[0] = 0
	_game.escape.keys_held[0] = 0
	await _wait(0.3)


func _blowing_out() -> void:
	print("-- blowing out")
	var hold := GameInput.action(0, &"hold_flame")
	var use := GameInput.action(0, &"use_item")
	Input.action_press(hold)
	await _wait(0.6)
	_check("the flame is up", _player.flame_raised(), "")
	Input.action_press(use)
	await _wait(0.1)
	Input.action_release(use)
	Input.action_release(hold)
	await _wait(0.2)
	_check("using it blows the candle out", not _player.is_candle_lit() and _player.is_snuffed(), "")
	var kept := _player.wax.left
	await _wait(1.0)
	_check("a candle blown out does not burn", is_equal_approx(_player.wax.left, kept), "%.2f" % (kept - _player.wax.left))
	_check("it is not burnt out, only out", not _player.is_burnt_out(), "")
	_bag.add(0, &"matches", 1)
	var button := GameInput.action(0, &"interact")
	Input.action_press(button)
	await _wait(1.6)
	Input.action_release(button)
	await _wait(0.2)
	_check("a match lights it again", _player.is_candle_lit() and not _player.is_snuffed(), "")
	_check("the wax is as it was", _player.wax.left <= kept and _player.wax.left > kept - 1.0, "")


func _burning_down() -> void:
	print("-- burning down")
	_player.wax.left = 4.0
	await _wait(0.2)
	var stick := _player.get_node("Candle")._stick as MeshInstance3D
	var short_height := (stick.mesh as CylinderMesh).height
	_check("a low candle is shorter", short_height < Candle.STICK_HEIGHT * 0.4, "%.3f" % short_height)
	await _wait(4.5)
	_check("it burns out", _player.is_burnt_out() and not _player.is_candle_lit(), "")
	_check("and the prisoner sees only their own room", _player.view_radius() == 0, "")
	var relighting := _game.get_node("Relighting") as Relighting
	_check("it says where to find wax", relighting.hint(_player).contains("wax shrine"), relighting.hint(_player))
	var walk := GameInput.action(0, &"move_forward")
	Input.action_press(walk)
	Input.action_press(GameInput.action(0, &"sprint"))
	await _wait(0.6)
	var pace := _player.floor_speed()
	Input.action_release(walk)
	Input.action_release(GameInput.action(0, &"sprint"))
	_check("they walk slower than a sprint, even trying to sprint", pace > 0.5 and pace < _player.walk_speed * 0.9, "%.2f m/s" % pace)
	# Matches cannot light it.
	_bag.add(0, &"matches", 2)
	var button := GameInput.action(0, &"interact")
	Input.action_press(button)
	await _wait(1.8)
	Input.action_release(button)
	_check("matches do nothing for it", _player.is_burnt_out() and _bag.count(0, &"matches") == 2, "")
	# A teammate's light cannot help either.
	_player.relight()
	_check("nor can being relit", _player.is_burnt_out() and not _player.is_candle_lit(), "")
	# A spare candle can.
	_bag.add(0, &"spare_candle", 1)
	_check("the hint is the spare candle", relighting.hint(_player).contains("spare candle"), relighting.hint(_player))
	Input.action_press(button)
	await _wait(0.2)
	Input.action_release(button)
	await _wait(0.3)
	_check("a spare candle is a whole new one", not _player.is_burnt_out() and _player.is_candle_lit() and _player.wax.fraction() > 0.95, "%.2f" % _player.wax.fraction())
	_check("and is used up", _bag.count(0, &"spare_candle") == 0, "")
	var stick_after := (stick.mesh as CylinderMesh).height
	_check("the stick is long again", stick_after > Candle.STICK_HEIGHT * 0.9, "%.3f" % stick_after)
	# A setup of 0 never burns down.
	_player.set_wax_life(0.0)
	await _wait(0.5)
	_check("a candle set to never burn down does not", _player.wax.is_endless() and _player.wax.fraction() == 1.0, "")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s%s" % ["ok  " if ok else "FAIL", label, "" if ok or detail.is_empty() else "  (%s)" % detail])
	if not ok:
		_failures += 1
