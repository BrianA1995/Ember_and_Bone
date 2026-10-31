extends Node
## Plays the items in the real game scene (escape mode): the pack keeps counts up to a cap, the scatter
## deals three cards a prisoner and puts each on the floor of an ordinary room, walking over one takes
## it, one whose room goes dark is dealt again, and a snuffed candle is lit again with matches (hold the
## button, one is used) or a spare candle (press it), matches first.
## Run debug/item_test.tscn and read the output for "ITEM TEST".

var _failures := 0
var _game: LocalGame
var _bag: ItemBag
var _scatter: ItemScatter
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
	_scatter = _game.get_node("ItemScatter")
	_manager = _game.get_node("MazeManager")
	(_game.get_node("MonsterDirector") as MonsterDirector).enabled = false
	_pack()
	await _dealing()
	await _relighting()
	await _using()
	print("ITEM TEST: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _pack() -> void:
	print("-- the pack")
	_bag.setup(1)
	_game.escape.keys_held[0] = 0
	_check("a lone prisoner has the three keys they need, and one more", _bag.total_slots(0) == 4, "%d" % _bag.total_slots(0))
	_check("it starts empty", _bag.summary(0) == "", "")
	_check("matches come three to a slot", _bag.add(0, &"matches", 3) == 3 and _bag.used_slots(0) == 1, "")
	_check("a second box takes a second slot", _bag.add(0, &"matches", 3) == 3 and _bag.used_slots(0) == 2, "")
	_check("a pack holds only so many matches", _bag.add(0, &"matches", 3) == 0, "")
	_check("using one takes one", _bag.take(0, &"matches") and _bag.count(0, &"matches") == 5 and _bag.used_slots(0) == 2, "")
	_check("you cannot use what you do not have", not _bag.take(0, &"spare_candle"), "")
	_check("a lamp takes a slot", _bag.add(0, &"lamp", 1) == 1 and _bag.free_slots(0) == 1, "")
	_check("a string takes the last", _bag.add(0, &"string", 1) == 1 and _bag.free_slots(0) == 0, "")
	_check("then nothing more fits", not _bag.has_room(0, &"chalk") and not _bag.has_room(0, &"spare_candle"), "")
	_check("a pouch needs no slot and gives one", _bag.add(0, &"pouch", 1) == 1 and _bag.total_slots(0) == 5 and _bag.free_slots(0) == 1, "")
	_game.escape.keys_held[0] = 1
	_check("a carried key uses a slot too", _bag.free_slots(0) == 0 and not _bag.has_room(0, &"chalk"), "")
	_game.escape.keys_held[0] = 0
	_check("the pouch can be worn twice, not three times", _bag.add(0, &"pouch", 1) == 1 and _bag.add(0, &"pouch", 1) == 0, "")
	_bag.setup(1)


func _dealing() -> void:
	print("-- scattering")
	_check("there is no deck", not "deck" in _scatter, "")
	var grid: MazeGrid = _manager.grid
	var cell := Vector2i.ZERO
	for candidate in grid.cells():
		var data := grid.get_cell(candidate)
		if data.anchor == candidate and not RoomDefs.is_special(data.piece):
			cell = candidate
			break
	_check("an ordinary room is built", cell != Vector2i.ZERO or not RoomDefs.is_special(grid.get_cell(cell).piece), "")
	_scatter.since_last = 0
	_check("no item right after one", _scatter.chance() == 0.0, "")
	_scatter.since_last = _scatter.min_gap
	var first := _scatter.chance()
	_scatter.since_last = _scatter.min_gap + 20
	_check("the chance grows with every room built since the last", _scatter.chance() > first and first == _scatter.base_chance, "%.3f -> %.3f" % [first, _scatter.chance()])
	_bag.setup(1)
	var counts := {}
	for i in 600:
		var kind := _scatter._pick_kind()
		counts[kind] = counts.get(kind, 0) + 1
	_check("every sort turns up but a walkie-talkie for a lone prisoner", counts.size() == 6 and not counts.has(&"walkie"), "%s" % [counts])
	_check("matches are the commonest when nobody has any", counts[&"matches"] > counts[&"pouch"], "%s" % [counts])
	_bag.add(0, &"matches", 3)
	_bag.add(0, &"matches", 3)
	var again := {}
	for i in 600:
		var kind := _scatter._pick_kind()
		again[kind] = again.get(kind, 0) + 1
	_check("and rarer once the pack holds all it can", again.get(&"matches", 0) < counts[&"matches"] / 2, "%s" % [again])
	_bag.setup(1)
	var placed := []
	_scatter.placed.connect(func(kind: StringName, where: Vector2i) -> void: placed.append([kind, where]))
	_scatter.base_chance = 1.0
	_scatter.since_last = 50
	_scatter._on_cell_added(cell)
	_check("a room built when an item is due holds one", placed.size() == 1 and placed[0][1] == cell, "%s" % [placed])
	_check("and the count starts again", _scatter.since_last == 0, "")
	var room := _manager.view.room_at(cell)
	var pickups := room.find_children("*", "ItemPickup", false, false)
	_check("lying on the floor there", pickups.size() == 1, "%d" % pickups.size())
	_scatter._on_cell_removed(cell)
	_check("a scattered item whose room goes dark is gone, not owed", _scatter.owed.is_empty(), "%d owed" % _scatter.owed.size())
	_scatter.base_chance = 0.02
	_scatter.drop(&"lamp", cell, (pickups[0] as Node3D).global_position, 1)
	_scatter._on_cell_removed(cell)
	_check("one a prisoner put down is owed back", _scatter.owed.size() == 1 and _scatter.owed[0].kind == &"lamp", "%d owed" % _scatter.owed.size())
	_scatter.builds = 100
	_scatter.owed[0].at = 0
	_scatter._on_cell_added(cell)
	_check("and laid in the next room built", _scatter.owed.is_empty(), "")
	var found := _manager.view.room_at(cell).find_children("*", "ItemPickup", false, false)
	var player := _game.players[0]
	_bag.setup(1)
	_scatter.since_last = 0
	player.global_position = (found[found.size() - 1] as Node3D).global_position + Vector3(0.0, 0.3, 0.0)
	await _wait(1.6)
	_check("walking over it takes it", _bag.used_slots(0) >= 1, "%d" % _bag.used_slots(0))


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


func _using() -> void:
	print("-- using and dropping")
	var player := _game.players[0]
	var escape := _game.escape
	var use := _game.get_node("ItemUse") as ItemUse
	var cell := _manager.grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
	var room := _manager.view.room_at(cell)
	_bag.setup(1)
	player.relight()
	_bag.add(0, &"lamp", 1)
	escape.equipped[0] = 1
	await _wait(0.1)
	_check("an item in hand puts the candle away", not player.is_candle_lit(), "")
	_check("and the hint names the button", escape.prompt(0).contains("set the lamp down") and escape.prompt(0).contains("put down"), escape.prompt(0))
	player.snuff()
	await _wait(0.1)
	_check("with the candle snuffed the hints still follow the item in hand, and say how to relight", escape.prompt(0).contains("set the lamp down") and escape.prompt(0).contains("Your candle is out"), escape.prompt(0))
	player.relight()
	escape.equipped[0] = 1
	use._use(player)
	_check("the lamp is set down and used up", _bag.count(0, &"lamp") == 0 and get_tree().get_nodes_in_group("light_sources").any(func(n: Node) -> bool: return n is Lamp), "")
	await _wait(0.1)
	_check("the candle is back in hand", player.is_candle_lit() and escape.equipped[0] == 0, "")
	_bag.add(0, &"matches", 3)
	escape.equipped[0] = 1
	use._drop(player)
	_check("a dropped stack leaves the pack", _bag.count(0, &"matches") == 0, "")
	var lying := _manager.view.room_at(_manager.grid.wrap_cell(RoomDefs.world_to_cell(player.global_position + player.facing() * 0.7))).find_children("*", "ItemPickup", false, false)
	_check("and lies on the floor ahead", lying.size() >= 1, "%d" % lying.size())
	await _wait(0.3)
	_check("it is not taken straight back", _bag.count(0, &"matches") == 0, "")
	escape.keys_held[0] = 1
	escape.keys_collected = 1
	escape.equipped[0] = 1
	use._drop(player)
	_check("a key can be put down", escape.keys_held[0] == 0 and escape._loose.size() >= 1, "")
	escape.equipped[0] = 0
	use._drop(player)
	_check("the candle cannot be dropped", escape.hand_items(0).size() == 1, "")
	_check("chalk writes a message on the wall", use.chalk.mark(player, "Key here") and room.find_children("*", "Label3D", false, false).size() == 1, "")
	use._broadcast(player, "Come here")
	_check("the walkie-talkie shows the message in the pane", escape.hud_at(0)._message.visible and escape.hud_at(0)._message.text.contains("Come here"), "")
	_bag.setup(1)
	_bag.add(0, &"string", 1)
	escape.equipped[0] = 1
	use._use(player)
	_check("the string is tied on", _bag.count(0, &"string") == 0 and use._strings.has(0) and use._strings[0].active, "")
	await _wait(0.1)
	player.global_position += Vector3(2.0, 0.0, 0.0)
	await _wait(0.3)
	use._use(player)
	_check("using it again ties it off", not use._strings[0].active, "")
	await _wait(0.2)
	_check("a loose string fades and goes", use._strings[0]._fading, "")
	var line := use._strings[0] as StringLine
	line.fade_seconds = 0.5
	await _wait(0.8)
	_check("with its rooms let go", not is_instance_valid(line), "")
	_bag.add(0, &"string", 1)
	escape.equipped[0] = 1
	use._use(player)
	line = use._strings[0]
	line.max_rooms = 2
	for step in 4:
		player.global_position += Vector3(RoomDefs.CELL_SIZE, 0.0, 0.0)
		await _wait(0.1)
	_check("a string that has run through its rooms comes away", not line.active and line.rooms() <= 2, "%d" % line.rooms())
	line.queue_free()
	_bag.add(0, &"string", 1)
	escape.equipped[0] = 1
	use._use(player)
	line = use._strings[0]
	player.fell.emit()
	_check("falling breaks the string", not line.active, "")
	_bag.add(0, &"matches", 3)
	escape.equipped[0] = 1
	player.snuff()
	player.relight()
	_check("a match used puts the hand back on the candle", escape.equipped[0] == 0, "")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(label: String, ok: bool, detail: String) -> void:
	print("%s  %s%s" % ["ok  " if ok else "FAIL", label, "" if ok or detail.is_empty() else "  (%s)" % detail])
	if not ok:
		_failures += 1
