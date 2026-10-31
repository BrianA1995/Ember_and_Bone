extends Node
## Plays the items in the real game scene (escape mode): the pack keeps counts up to a cap, the dealer
## deals three cards a prisoner and puts each on the floor of an ordinary room, walking over one takes
## it, one whose room goes dark is dealt again, and a snuffed candle is lit again with matches (hold the
## button, one is used) or a spare candle (press it), matches first.
## Run debug/item_test.tscn and read the output for "ITEM TEST".

var _failures := 0
var _game: LocalGame
var _bag: ItemBag
var _dealer: ItemDealer
var _manager: MazeManager


func _ready() -> void:
	GameSettings.monsters = true
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 30
	GameInput.configure(1)
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(_game)
	await _wait(0.5)
	_bag = _game.get_node("ItemBag")
	_dealer = _game.get_node("ItemDealer")
	_manager = _game.get_node("MazeManager")
	(_game.get_node("MonsterDirector") as MonsterDirector).enabled = false
	_pack()
	await _dealing()
	await _relighting()
	print("ITEM TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _pack() -> void:
	print("-- the pack")
	_bag.setup(1)
	_check("it starts empty", _bag.summary(0) == "", "")
	_check("matches come three to a box", _bag.add(0, &"matches", 3) == 3 and _bag.count(0, &"matches") == 3, "")
	_check("a pack holds only so many", _bag.add(0, &"matches", 9) == 3 and not _bag.has_room(0, &"matches"), "")
	_check("using one takes one", _bag.take(0, &"matches") and _bag.count(0, &"matches") == 5, "")
	_check("you cannot use what you do not have", not _bag.take(0, &"spare_candle"), "")
	_bag.add(0, &"spare_candle", 1)
	_check("the line lists what is carried", _bag.summary(0) == "Matches 5    Spare candle 1", _bag.summary(0))
	_bag.setup(1)


func _dealing() -> void:
	print("-- dealing")
	_check("three cards for a lone prisoner", _dealer.deck.size() == 3, "%d" % _dealer.deck.size())
	var kinds: Array = _dealer.deck.map(func(card: Dictionary) -> StringName: return card.kind)
	_check("matches, a spare candle, matches", kinds == [&"matches", &"spare_candle", &"matches"], "%s" % [kinds])
	var grid: MazeGrid = _manager.grid
	var cell := Vector2i.ZERO
	for candidate in grid.cells():
		var data := grid.get_cell(candidate)
		if data.anchor == candidate and not RoomDefs.is_special(data.piece):
			cell = candidate
			break
	_check("an ordinary room is built", cell != Vector2i.ZERO or not RoomDefs.is_special(grid.get_cell(cell).piece), "")
	var placed := []
	_dealer.placed.connect(func(kind: StringName, where: Vector2i) -> void: placed.append([kind, where]))
	_dealer.deck[0].at = 0
	_dealer.builds = 5
	_dealer._on_cell_added(cell)
	_check("a due card puts its item in the room just built", placed.size() == 1 and placed[0][1] == cell, "%s" % [placed])
	var room := _manager.view.room_at(cell)
	var pickups := room.find_children("*", "ItemPickup", false, false)
	_check("lying on the floor there", pickups.size() == 1, "%d" % pickups.size())
	var decks := _dealer.deck.size()
	_dealer._on_cell_removed(cell)
	_check("an item whose room goes dark is dealt again", _dealer.deck.size() == decks + 1, "%d -> %d" % [decks, _dealer.deck.size()])
	var player := _game.players[0]
	player.global_position = (pickups[0] as Node3D).global_position + Vector3(0.0, 0.3, 0.0)
	await _wait(0.4)
	_check("walking over it takes it", _bag.count(0, &"matches") == 3, "%d" % _bag.count(0, &"matches"))
	_check("and the pane shows it", _game.escape.hud_at(0)._gear.text == "Matches 3", _game.escape.hud_at(0)._gear.text)


func _relighting() -> void:
	print("-- relighting with items")
	var player := _game.players[0]
	var relighting := _game.get_node("Relighting") as Relighting
	var button := GameInput.action(0, &"interact")
	_bag.setup(1)
	player.snuff()
	await _wait(0.2)
	_check("with nothing it says what to look for", relighting.hint(player).begins_with("Your candle is out"), relighting.hint(player))
	Input.action_press(button)
	await _wait(1.6)
	Input.action_release(button)
	_check("and holding the button does nothing", player.is_snuffed(), "")
	_bag.add(0, &"matches", 2)
	_bag.add(0, &"spare_candle", 1)
	_check("with matches the hint is to strike one", relighting.hint(player).contains("strike a match (2 left)"), relighting.hint(player))
	Input.action_press(button)
	await _wait(0.4)
	_check("a match takes a moment to strike", player.is_snuffed(), "")
	await _wait(1.6)
	Input.action_release(button)
	_check("then the candle burns again", not player.is_snuffed() and player.is_candle_lit(), "")
	_check("with one match used, the spare candle kept", _bag.count(0, &"matches") == 1 and _bag.count(0, &"spare_candle") == 1, "")
	player.snuff()
	_bag.take(0, &"matches")
	await _wait(0.2)
	_check("with no matches the hint is the spare candle", relighting.hint(player).contains("spare candle"), relighting.hint(player))
	Input.action_press(button)
	await _wait(0.2)
	Input.action_release(button)
	await _wait(0.2)
	_check("one press lights the spare at once", not player.is_snuffed() and _bag.count(0, &"spare_candle") == 0, "")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s%s" % ["ok  " if ok else "FAIL", label, "" if ok or detail.is_empty() else "  (%s)" % detail])
	if not ok:
		_failures += 1
