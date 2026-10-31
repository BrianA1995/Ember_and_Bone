class_name EscapeRun
extends Node
## The escape run, on top of a LocalGame: find keys, carry them to a gate, get out together.
## The design doc's "Keys, gates and escape" section, without monsters or wax yet.
##
##  - A fixed number of keys and gates exist per run (by player count, see plan_for). Their places
##    are decided up front, as cards in a shuffled deck of room builds: every room the light builds
##    is the next card, and a key or gate card makes the room built next a key alcove (or gate
##    chamber). The keys are spread evenly through the deck but each lands at a random spot inside its
##    own stretch (`spread`), so they are never bunched and never at a fixed distance.
##  - A key lies in its alcove (KeyPickup). Taking it starts the alcove floor's collapse. A key whose
##    alcove goes dark before anyone takes it is lost for good.
##  - Each prisoner needs one key to get out, and can carry only one. Alone you carry three and need
##    all three. Items: the candle (always there) and the keys. Only one is in hand: switching
##    (Tab, or the D-pad) to a key puts the candle away, and without a candle only the room you stand
##    in exists around you (see Player.set_candle_lit and DarkSight). A prisoner holds the key in hand
##    out (the button that raises the flame: F, or the left trigger or bumper) and a teammate beside
##    them takes it with interact (E, or A).
##  - A gate is a big chamber. When enough prisoners with keys stand inside it, it starts unlocking;
##    if they all stay for `unlock_seconds` they escape and the run is won.
##  - Lost: too few keys still exist to open a gate, or every gate has been seen and left behind. A key
##    or gate counts as seen once the candle's light reaches its room; one that goes dark before that,
##    or while someone has their candle away, is dealt again a little later instead.
##
## The maze scripts know nothing about this: it listens to the grid, hands the generator new odds
## through MazeGrid.weights, and puts keys in the rooms the view built.

signal key_taken(slot: int)
signal key_passed(from_slot: int, to_slot: int)
signal run_won(escaped: Array)
signal run_lost(reason: String)

@export_group("Placement")
## About how many rooms get built between one key alcove and the next. (The run's deck is the keys
## times this long, and the gates are spread through it the same way; see debug/escape_pace_test.)
@export_range(10, 500, 1) var rooms_per_key := 90
## How much of its stretch of the deck a key or gate may land in, around the middle: 0 puts it exactly
## in the middle of its stretch (even and predictable), 1 anywhere in it (random, may bunch).
@export_range(0.0, 1.0, 0.05) var spread := 0.6
## With the menu option on, how long the last gate left stays up after its light goes, in seconds.
@export_range(0.0, 120.0, 1.0, "suffix:s") var last_gate_grace := 20.0

@export_group("Rules")
## Seconds everyone has to stay in the gate while it unlocks.
@export_range(1.0, 60.0, 0.5, "suffix:s") var unlock_seconds := 10.0
## Seconds after a key is taken before its alcove's floor gives way.
@export_range(0.0, 20.0, 0.5, "suffix:s") var key_collapse_delay := 3.0
## How close, in metres, a teammate has to stand to take a key that is held out.
@export_range(0.5, 4.0, 0.1, "suffix:m") var hand_over_distance := 1.8

## What a run of this many players holds: keys in the maze, keys each prisoner needs to get out,
## gates in the maze, prisoners who must be inside the gate. Only a lone player carries more than one.
const PLANS := [
	{"up_to": 1, "keys": 4, "per_prisoner": 3, "gates": 2, "at_gate": 1},
	{"up_to": 3, "keys": 6, "per_prisoner": 1, "gates": 3, "at_gate": 2},
	{"up_to": 5, "keys": 8, "per_prisoner": 1, "gates": 3, "at_gate": 2},
	{"up_to": 8, "keys": 10, "per_prisoner": 1, "gates": 4, "at_gate": 3},
]

var keys_total := 0
var keys_per_prisoner := 1
var gates_total := 0
var at_gate_needed := 0
## Keys built into alcoves so far, keys lost with their alcove, keys taken by the team.
var keys_placed := 0
var keys_lost := 0
var keys_collected := 0
var gates_placed := 0
var gates_lost := 0
## Keys each player carries, by slot.
var keys_held: Array[int] = []
## What each player has in hand, by slot: 0 the candle, n the n-th key they carry.
var equipped: Array[int] = []
var elapsed := 0.0
var finished := false
## How far the gate that is unlocking has got, in seconds (0 when none is).
var unlock_progress := 0.0
var players: Array[Player] = []
## Called as snuffed_hint.call(player) -> String for what a snuffed prisoner can do ("{interact}" is
## replaced by the button's name); set by whoever knows how a candle is lit again.
var snuffed_hint := Callable()

var _manager: MazeManager
var _grid: MazeGrid
var _huds: Array[EscapeHud] = []
var _carriers: Array[KeyCarrier] = []
var _sight: DarkSight
## key alcove cell -> its KeyPickup, while the key lies there.
var _pickups: Dictionary = {}
## KeyPickup -> the cell it lies in, for keys a monster let fall (not in an alcove).
var _loose: Dictionary = {}
## gate anchor cell -> true, and every cell of a standing gate -> its anchor.
var _gates: Dictionary = {}
var _gate_cells: Dictionary = {}
## Alcoves and gates (by cell) that a prisoner has been close enough to see. One that goes dark
## before that was never seen: it is built again later instead of counting as lost.
var _seen: Dictionary = {}
var _unlocking := Vector2i.ZERO
## The deck: the build numbers at which a key or gate is due, as {at, kind} (kind is &"key" or
## &"gate"), and how many rooms have been built so far. A due card waits until its room is built.
var _deck: Array[Dictionary] = []
var _builds := 0
## The weight that makes the next room a key alcove or gate chamber once one is due (an ordinary room is about 3).
const DUE_WEIGHT := 1000.0
var _rng := RandomNumberGenerator.new()


## The numbers for a run of `count` players.
static func plan_for(count: int) -> Dictionary:
	for plan in PLANS:
		if count <= plan.up_to:
			return plan
	return PLANS[-1]


## How many keys a prisoner can carry, and so how many slots they have beside the candle: what a
## prisoner needs to get out (three alone, one with company).
func capacity() -> int:
	return keys_per_prisoner


## Keys the team needs in all for the gate to open: what each prisoner needs, for each who must be inside.
func keys_required() -> int:
	return at_gate_needed * keys_per_prisoner


## Starts a run for `p_players`, with a readout in each one's pane of `split`. A new maze (from the
## pause menu) starts a new run.
func setup(p_players: Array[Player], split: SplitScreen) -> void:
	players = p_players
	_manager = get_tree().get_first_node_in_group("maze_manager") as MazeManager
	_manager.maze_rebuilt.connect(restart)
	for i in players.size():
		var hud := EscapeHud.new()
		split.pane_at(i).add_child(hud)
		_huds.append(hud)
		var carrier := KeyCarrier.new()
		players[i].add_child(carrier)
		_carriers.append(carrier)
	_sight = DarkSight.new()
	add_child(_sight)
	_sight.setup(players, split)
	restart()


## Everything back to the start of a run, in the maze the manager has now.
func restart() -> void:
	var plan := plan_for(players.size())
	keys_total = plan.keys
	keys_per_prisoner = plan.per_prisoner
	gates_total = plan.gates
	at_gate_needed = plan.at_gate
	keys_placed = 0
	keys_lost = 0
	keys_collected = 0
	gates_placed = 0
	gates_lost = 0
	keys_held.clear()
	equipped.clear()
	for i in players.size():
		keys_held.append(0)
		equipped.append(0)
	elapsed = 0.0
	finished = false
	unlock_progress = 0.0
	_pickups.clear()
	_loose.clear()
	_gates.clear()
	_gate_cells.clear()
	_seen.clear()
	_builds = 0
	_rng.seed = _manager.grid.seed_value
	_build_deck()
	_grid = _manager.grid
	# The manager's weights belong to the manager; this run changes its own copy.
	_grid.weights = _grid.weights.duplicate()
	if not _grid.cell_added.is_connected(_on_cell_added):
		_grid.cell_added.connect(_on_cell_added)
		_grid.cell_removed.connect(_on_cell_removed)
	_manager.reveal.extra_unlit = _extra_unlit
	_update_weights()
	_refresh()


func _physics_process(delta: float) -> void:
	if finished or _grid == null:
		return
	elapsed += delta
	_note_seen()
	_switch_items()
	_hand_over_keys()
	_update_gate(delta)
	_refresh()


## The line about the gate player `slot` stands in, or "" when they are not in one.
func gate_status(slot: int) -> String:
	var anchor = _gate_around(players[slot])
	if anchor == null:
		return ""
	var inside := _inside(anchor)
	if _with_keys(inside).size() >= at_gate_needed:
		return "Unlocking  %d" % ceili(unlock_seconds - unlock_progress)
	if keys_per_prisoner > 1:
		return "Gate: %d of %d keys" % [keys_held[players[slot].slot], keys_per_prisoner]
	return "Gate: %d of %d prisoners with a key" % [_with_keys(inside).size(), at_gate_needed]


## What player `slot` can do right now, as a hint ("" for nothing).
func prompt(slot: int) -> String:
	var player := players[slot]
	if player.is_snuffed():
		var text: String = snuffed_hint.call(player) if snuffed_hint.is_valid() else "Your candle is out: hold {interact} beside a lit candle"
		return text.replace("{interact}", _button_name(slot, &"interact"))
	if keys_held[slot] < capacity() and _offerer_near(player) != null:
		return "%s: take the key" % _button_name(slot, &"interact")
	if players.size() > 1 and equipped[slot] > 0:
		return "Hold %s to hold out your key" % _button_name(slot, &"hold_flame")
	if keys_held[slot] > 0:
		return "%s: %s" % [_button_name(slot, &"cycle_item"), "take out the candle" if equipped[slot] > 0 else "take out a key"]
	return ""


## Lays out the deck: one stretch of `rooms_per_key` builds for each key, with the key somewhere in the
## middle `spread` of it. The gates are dealt the same way across the whole deck, so they come
## scattered among the keys. The last gate waits until enough keys have turned up to open it.
func _build_deck() -> void:
	_deck.clear()
	for i in keys_total:
		_deck.append({"at": _slot_in(i * rooms_per_key, rooms_per_key), "kind": &"key"})
	var stretch := keys_total * rooms_per_key / gates_total
	for i in gates_total:
		_deck.append({"at": _slot_in(i * stretch, stretch), "kind": &"gate"})



## A random build number in the middle `spread` of the stretch that starts at `start`.
func _slot_in(start: int, length: int) -> int:
	var low := 0.5 - spread / 2.0
	return start + roundi(length * (low + _rng.randf() * spread))


## Is a card of this kind due: its room is the next one that may be built?
func _due(kind: StringName) -> bool:
	for card in _deck:
		if card.kind == kind and card.at <= _builds:
			return true
	return false


## Takes the due card of this kind out of the deck, once its room is built.
func _play_card(kind: StringName) -> void:
	for card in _deck:
		if card.kind == kind and card.at <= _builds:
			_deck.erase(card)
			return


## Puts a card back a little way ahead, for a key or gate that went dark before anyone saw it.
func _redeal(kind: StringName) -> void:
	_deck.append({"at": _builds + _rng.randi_range(8, 25), "kind": kind})


## A gate is due, and (for the last one) enough keys have turned up, taken or not, to open it.
func _gate_may_come() -> bool:
	if gates_placed >= gates_total or not _due(&"gate"):
		return false
	return gates_placed < gates_total - 1 or keys_placed >= keys_required()


## Extra seconds a room survives in the dark: the last gate left, if the menu option is on.
func _extra_unlit(cell: Vector2i) -> float:
	if GameSettings.gate_grace and _gate_cells.has(cell) and gates_total - gates_lost == 1:
		return last_gate_grace
	return 0.0


## The next room is a key alcove or gate chamber if one is due, else the generator's usual odds.
func _update_weights() -> void:
	_grid.weights[&"key_alcove"] = DUE_WEIGHT if keys_placed < keys_total and _due(&"key") else 0.0
	_grid.weights[&"gate_chamber"] = DUE_WEIGHT if _gate_may_come() else 0.0


func _on_cell_added(cell: Vector2i) -> void:
	var data := _grid.get_cell(cell)
	# A room bigger than a cell is announced once per cell; it is handled once, at its anchor.
	if data.is_empty() or data.anchor != cell:
		return
	match data.piece:
		&"key_alcove":
			_place_key(cell)
		&"gate_chamber":
			_place_gate(cell)
		_:
			_builds += 1
	_update_weights()


func _on_cell_removed(cell: Vector2i) -> void:
	for loose in _loose.keys():
		if _loose[loose] == cell:
			_loose.erase(loose)
			# A key a monster dropped in a room that went dark is not lost: it turns up again later.
			if is_instance_valid(loose) and not loose.is_queued_for_deletion():
				key_returned()
	if _pickups.has(cell):
		var pickup = _pickups[cell]
		_pickups.erase(cell)
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
			# Rooms that vanish because a candle was put away aren't the team's loss: the key comes back later.
			if _seen.has(cell) and not _someone_in_the_dark():
				keys_lost += 1
				_check_lost()
			else:
				keys_placed -= 1
				_redeal(&"key")
				_update_weights()
	if _gate_cells.has(cell):
		var anchor: Vector2i = _gate_cells[cell]
		for member in _gate_cells.keys():
			if _gate_cells[member] == anchor:
				_gate_cells.erase(member)
		if _gates.erase(anchor):
			if _seen.has(anchor) and not _someone_in_the_dark():
				# Seen, and left behind: that gate is gone for good.
				gates_lost += 1
			else:
				# Never seen (or gone with a candle put away): another is dealt a little later.
				gates_placed -= 1
				_redeal(&"gate")
			_update_weights()
			if _unlocking == anchor:
				unlock_progress = 0.0
			_check_lost()


## The readout in player `slot`'s pane.
func hud_at(slot: int) -> EscapeHud:
	return _huds[slot]


## The anchor cells of the gates standing now.
func gate_anchors() -> Array:
	return _gates.keys()


## A monster takes a key from `player` (false if they have none). The key is no longer collected.
func take_key_from(player: Player) -> bool:
	if keys_held[player.slot] <= 0:
		return false
	keys_held[player.slot] -= 1
	keys_collected -= 1
	return true


## A key lies loose at `position` in `cell`'s room, dropped by a monster. Anyone with a free hand can take it.
func drop_key(position: Vector3, cell: Vector2i) -> void:
	var room := _manager.view.room_at(cell)
	if room == null:
		key_returned()
		return
	var pickup := KeyPickup.new()
	pickup.accepts = func(player: Player) -> bool: return keys_held[player.slot] < capacity()
	pickup.taken.connect(func(player: Player) -> void:
		_loose.erase(pickup)
		keys_held[player.slot] += 1
		keys_collected += 1)
	room.add_child(pickup)
	pickup.global_position = Vector3(position.x, 1.0, position.z)
	_loose[pickup] = cell


## A key a monster took has gone from the maze for now: another alcove is dealt for it a little later.
func key_returned() -> void:
	keys_placed -= 1
	_redeal(&"key")
	_update_weights()


func _someone_in_the_dark() -> bool:
	for player in players:
		if not player.is_candle_lit():
			return true
	return false


## Marks the key alcoves and gates a prisoner can actually see: the rooms their candle lights (the room
## they stand in and those joined to it by open doorways, as far as the light reaches), or without a
## candle only the room they stand in. A room just out of the light, or behind a wall, is not seen.
func _note_seen() -> void:
	for player in players:
		var here := _grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
		var radius := ceili(player.candle_reach) if player.is_candle_lit() else 0
		var lit := LightField.compute(_grid, [{"cell": here, "radius": radius}], false)
		for cell in _pickups:
			if lit.has(cell):
				_seen[cell] = true
		for anchor in _gates:
			for member in _grid.room_cells(anchor):
				if lit.has(member):
					_seen[anchor] = true


func _place_key(cell: Vector2i) -> void:
	_play_card(&"key")
	if keys_placed >= keys_total:
		return
	keys_placed += 1
	var room := _manager.view.room_at(cell)
	if room == null:
		return
	var pickup := KeyPickup.new()
	var spawn := room.get_node_or_null("KeySpawn") as Node3D
	pickup.position = spawn.position if spawn else Vector3(0.0, 1.0, 0.0)
	pickup.accepts = func(player: Player) -> bool: return keys_held[player.slot] < capacity()
	pickup.taken.connect(_on_key_taken.bind(cell, room))
	room.add_child(pickup)
	_pickups[cell] = pickup


func _place_gate(anchor: Vector2i) -> void:
	_play_card(&"gate")
	gates_placed += 1
	_gates[anchor] = true
	for member in _grid.room_cells(anchor):
		_gate_cells[member] = anchor


## A player took the key in `cell`'s alcove. Its floor gives way a moment later.
func _on_key_taken(player: Player, cell: Vector2i, room: Node3D) -> void:
	_pickups.erase(cell)
	keys_held[player.slot] += 1
	keys_collected += 1
	key_taken.emit(player.slot)
	_update_weights()
	if key_collapse_delay > 0.0:
		await get_tree().create_timer(key_collapse_delay).timeout
	if is_instance_valid(room):
		for tile in room.find_children("*", "CrackedFloor", true, false):
			(tile as CrackedFloor).collapse_now()


## Pressing the switch button moves on to the next item: candle, first key, second key ... candle.
func _switch_items() -> void:
	for player in players:
		if Input.is_action_just_pressed(GameInput.action(player.slot, &"cycle_item")):
			equipped[player.slot] = (equipped[player.slot] + 1) % (keys_held[player.slot] + 1)


## A prisoner with a free hand takes a key from a teammate who is holding one out, when they press interact.
func _hand_over_keys() -> void:
	for taker in players:
		if keys_held[taker.slot] >= capacity():
			continue
		if not Input.is_action_just_pressed(GameInput.action(taker.slot, &"interact")):
			continue
		var giver := _offerer_near(taker)
		if giver == null:
			continue
		keys_held[giver.slot] -= 1
		keys_held[taker.slot] += 1
		equipped[giver.slot] = mini(equipped[giver.slot], keys_held[giver.slot])
		key_passed.emit(giver.slot, taker.slot)


## The nearest teammate within reach of `taker` who is holding a key out, or null.
func _offerer_near(taker: Player) -> Player:
	var best: Player = null
	var best_distance := hand_over_distance
	for other in players:
		if other == taker or keys_held[other.slot] <= 0 or not _carriers[other.slot].offering:
			continue
		var apart := other.global_position - taker.global_position
		var distance := Vector2(apart.x, apart.z).length()
		if distance <= best_distance:
			best_distance = distance
			best = other
	return best


## The gate is unlocking while enough prisoners with keys stand in it.
func _update_gate(delta: float) -> void:
	var ready_anchor = null
	for anchor in _gates:
		if _with_keys(_inside(anchor)).size() >= at_gate_needed:
			ready_anchor = anchor
			break
	if ready_anchor == null:
		unlock_progress = 0.0
		return
	if _unlocking != ready_anchor:
		_unlocking = ready_anchor
		unlock_progress = 0.0
	unlock_progress += delta
	if unlock_progress >= unlock_seconds:
		var escaped: Array = []
		for player in _with_keys(_inside(ready_anchor)):
			escaped.append(player.slot)
		finished = true
		run_won.emit(escaped)


## The prisoners standing in the gate whose anchor cell is `anchor`.
func _inside(anchor: Vector2i) -> Array[Player]:
	var inside: Array[Player] = []
	for player in players:
		if _gate_around(player) == anchor:
			inside.append(player)
	return inside


## The prisoners of `list` who have the keys they need to get out.
func _with_keys(list: Array[Player]) -> Array[Player]:
	var ready: Array[Player] = []
	for player in list:
		if keys_held[player.slot] >= keys_per_prisoner:
			ready.append(player)
	return ready


## The anchor of the gate `player` stands in, or null.
func _gate_around(player: Player) -> Variant:
	var cell := _grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
	return _gate_cells.get(cell)


## Ends the run if escape has become impossible.
func _check_lost() -> void:
	if finished:
		return
	if keys_total - keys_lost < keys_required():
		_lose("Too few keys are left in the labyrinth.")
	elif gates_placed >= gates_total and _gates.is_empty():
		_lose("Every gate has been lost to the dark.")


func _lose(reason: String) -> void:
	finished = true
	run_lost.emit(reason)


## What `base` is called on the device player `slot` plays with.
func _button_name(slot: int, base: StringName) -> String:
	var device: int = GameSettings.controllers[slot] if slot < GameSettings.controllers.size() else GameInput.DEVICE_KEYBOARD
	var names := {
		GameInput.DEVICE_KEYBOARD: {&"interact": "E", &"hold_flame": "F", &"cycle_item": "Tab"},
		GameInput.DEVICE_ARROWS: {&"interact": "Enter", &"hold_flame": "/", &"cycle_item": "."},
	}
	if names.has(device):
		return names[device][base]
	return {&"interact": "A", &"hold_flame": "LT", &"cycle_item": "D-pad"}[base]


func _refresh() -> void:
	var carrying := 0
	for held in keys_held:
		carrying += 1 if held > 0 else 0
	for slot in _huds.size():
		# A key that was handed on (or lost) can't stay in hand.
		equipped[slot] = mini(equipped[slot], keys_held[slot])
		players[slot].set_candle_lit(equipped[slot] == 0)
		_carriers[slot].set_state(keys_held[slot], equipped[slot] > 0)
		_huds[slot].show_inventory(keys_held[slot], capacity(), equipped[slot], players[slot].is_candle_lit())
		_huds[slot].show_state(keys_held[slot], keys_per_prisoner, carrying, at_gate_needed, gate_status(slot), prompt(slot))
