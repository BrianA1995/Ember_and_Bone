class_name ItemUse
extends Node
## What the use button (R, or X on a pad) and the drop button (Q, or B) do with the item in hand:
##  - lamp: set it down, it keeps its room alive and lit for a while (Lamp);
##  - string: tie it here and walk on; use it again to tie it off (StringLine);
##  - chalk: choose a message and write it on the wall (ChalkMarks, MessagePicker);
##  - walkie-talkie: choose a message and every teammate hears it;
##  - drop: a key or a stack of items is put down in front of you and can be picked up again after a moment.
## Matches and the spare candle are used by Relighting (with the interact button, when the candle is out).

## How far in front of the prisoner a dropped thing lands, in metres.
@export var drop_distance := 0.7

var players: Array[Player] = []
var escape: EscapeRun
var bag: ItemBag
var dealer: ItemDealer
var chalk: ChalkMarks

var _manager: MazeManager
var _pickers: Array[MessagePicker] = []
var _strings: Dictionary = {}
## What each pane's open message list does with the text chosen.
var _pending: Array[Callable] = []


func setup(p_players: Array[Player], p_escape: EscapeRun, p_bag: ItemBag, p_dealer: ItemDealer, p_manager: MazeManager) -> void:
	players = p_players
	escape = p_escape
	bag = p_bag
	dealer = p_dealer
	_manager = p_manager
	chalk = ChalkMarks.new()
	chalk.name = "ChalkMarks"
	add_child(chalk)
	chalk.setup(_manager)
	for i in players.size():
		var picker := MessagePicker.new()
		escape.hud_at(i).add_child(picker)
		_pickers.append(picker)
		_pending.append(Callable())
		picker.chosen.connect(_on_chosen.bind(i))
	_manager.maze_rebuilt.connect(_clear_strings)
	escape.use_hint = hint


## What the use button does with `kind` in hand ("" for nothing); {use} is the button's name.
func hint(player: Player, kind: StringName) -> String:
	match kind:
		&"candle":
			if _strings.has(player.slot) and _strings[player.slot].active:
				return "{use}: tie off the string"
		&"lamp":
			return "{use}: set the lamp down"
		&"string":
			return "{use}: tie the string here"
		&"chalk":
			return "{use}: write on the wall (%d)" % bag.count(player.slot, kind)
		&"walkie":
			return "{use}: send a message"
	return ""


func _physics_process(_delta: float) -> void:
	for player in players:
		if player.controls_locked or _pickers[player.slot].is_open():
			continue
		if Input.is_action_just_pressed(GameInput.action(player.slot, &"use_item")):
			_use(player)
		elif Input.is_action_just_pressed(GameInput.action(player.slot, &"drop_item")):
			_drop(player)


func _use(player: Player) -> void:
	var held := escape.held_item(player.slot)
	if held.type == &"candle" and _strings.has(player.slot) and _strings[player.slot].active:
		_strings[player.slot].tie_off()
		return
	if held.type != &"item":
		return
	match held.kind:
		&"lamp":
			_set_lamp(player)
		&"string":
			_use_string(player)
		&"chalk":
			_ask(player, "Write on the wall", func(text: String) -> void:
				if chalk.mark(player, text):
					bag.take(player.slot, &"chalk")
					escape.equipped[player.slot] = 0)
		&"walkie":
			_ask(player, "Send a message", func(text: String) -> void: _broadcast(player, text))


func _drop(player: Player) -> void:
	var held := escape.held_item(player.slot)
	var spot := player.global_position + player.facing() * drop_distance
	var cell := _manager.grid.wrap_cell(RoomDefs.world_to_cell(spot))
	if held.type == &"key":
		escape.put_down_key(player, spot, cell)
	elif held.type == &"item":
		var amount := bag.take_stack(player.slot, held.kind)
		if amount > 0:
			dealer.drop(held.kind, cell, spot, amount)
	else:
		return
	escape.equipped[player.slot] = 0


func _set_lamp(player: Player) -> void:
	var spot := player.global_position + player.facing() * drop_distance
	var room := _manager.view.room_at(_manager.grid.wrap_cell(RoomDefs.world_to_cell(spot)))
	if room == null or not bag.take(player.slot, &"lamp"):
		return
	var lamp := Lamp.new()
	room.add_child(lamp)
	lamp.global_position = Vector3(spot.x, 0.0, spot.z)
	escape.equipped[player.slot] = 0


func _use_string(player: Player) -> void:
	var old: StringLine = _strings.get(player.slot)
	if old != null and old.active:
		return
	if not bag.take(player.slot, &"string"):
		return
	var line := StringLine.new()
	add_child(line)
	line.start(player)
	line.ran_out.connect(func() -> void: escape.hud_at(player.slot).show_message("The string has run out"))
	_strings[player.slot] = line
	# The string pays out as they walk with the candle in hand; the use button then ties it off.
	escape.equipped[player.slot] = 0


func _ask(player: Player, title: String, then: Callable) -> void:
	_pending[player.slot] = then
	_pickers[player.slot].open(player, title)


func _on_chosen(text: String, slot: int) -> void:
	if _pending[slot].is_valid():
		_pending[slot].call(text)
	_pending[slot] = Callable()


func _broadcast(from: Player, text: String) -> void:
	for player in players:
		var message := "Player %d: %s" % [from.slot + 1, text]
		escape.hud_at(player.slot).show_message(message if player != from else "You: " + text)


func _clear_strings() -> void:
	for line in _strings.values():
		if is_instance_valid(line):
			line.queue_free()
	_strings.clear()
