class_name EscapeRun
extends Node
## The escape run, on top of a LocalGame: find keys, carry them to a gate, get out together.
## The design doc's "Keys, gates and escape" section, without monsters or wax yet.
##
##  - A fixed number of keys and gates exist per run (by player count, see plan_for). Rooms are
##    rolled live as light reaches them, so they are not placed in advance: the odds of a key alcove
##    (or gate chamber) climb with every ordinary room built since the last one, until one comes up.
##    Once all of them have been built, none comes up again.
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
##  - Lost: too few keys still exist to open a gate, or every gate has been lost to the dark.
##
## The maze scripts know nothing about this: it listens to the grid, hands the generator new odds
## through MazeGrid.weights, and puts keys in the rooms the view built.

signal key_taken(slot: int)
signal key_passed(from_slot: int, to_slot: int)
signal run_won(escaped: Array)
signal run_lost(reason: String)

@export_group("Placement")
## About how many ordinary rooms get built between one key alcove and the next.
@export_range(5, 200, 1) var rooms_per_key := 25
## The same for gate chambers.
@export_range(5, 400, 1) var rooms_per_gate := 60
## Gates only start to appear once the team has taken this many keys.
@export_range(0, 10, 1) var gate_after_keys := 2
## The weight a key alcove or gate chamber has right after one was built, and at the end of its
## stretch; between the two the weight climbs, steeply at the end. (An ordinary room is about 3.)
@export_range(0.0, 1.0, 0.01) var rarity_floor := 0.05
@export_range(1.0, 200.0, 1.0) var rarity_ceiling := 40.0

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

var _manager: MazeManager
var _grid: MazeGrid
var _huds: Array[EscapeHud] = []
var _carriers: Array[KeyCarrier] = []
var _sight: DarkSight
## key alcove cell -> its KeyPickup, while the key lies there.
var _pickups: Dictionary = {}
## gate anchor cell -> true, and every cell of a standing gate -> its anchor.
var _gates: Dictionary = {}
var _gate_cells: Dictionary = {}
var _unlocking := Vector2i.ZERO
var _since_key := 0
var _since_gate := 0


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
	_gates.clear()
	_gate_cells.clear()
	_since_key = 0
	_since_gate = 0
	_grid = _manager.grid
	# The manager's weights belong to the manager; this run changes its own copy.
	_grid.weights = _grid.weights.duplicate()
	if not _grid.cell_added.is_connected(_on_cell_added):
		_grid.cell_added.connect(_on_cell_added)
		_grid.cell_removed.connect(_on_cell_removed)
	_update_weights()
	_refresh()


func _physics_process(delta: float) -> void:
	if finished or _grid == null:
		return
	elapsed += delta
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
	if keys_held[slot] < capacity() and _offerer_near(player) != null:
		return "%s: take the key" % _button_name(slot, &"interact")
	if players.size() > 1 and equipped[slot] > 0:
		return "Hold %s to hold out your key" % _button_name(slot, &"hold_flame")
	if keys_held[slot] > 0:
		return "%s: %s" % [_button_name(slot, &"cycle_item"), "take out the candle" if equipped[slot] > 0 else "take out a key"]
	return ""


## Rolls the next room's odds: key alcoves and gate chambers get likelier the longer none has come up.
func _update_weights() -> void:
	var key_weight := 0.0
	if keys_placed < keys_total:
		key_weight = _rarity(_since_key, rooms_per_key)
	var gate_weight := 0.0
	if gates_placed < gates_total and keys_collected >= gate_after_keys:
		gate_weight = _rarity(_since_gate, rooms_per_gate)
	_grid.weights[&"key_alcove"] = key_weight
	_grid.weights[&"gate_chamber"] = gate_weight


func _rarity(since: int, per: int) -> float:
	return lerpf(rarity_floor, rarity_ceiling, pow(clampf(float(since) / per, 0.0, 1.0), 2.0))


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
			_since_key += 1
			_since_gate += 1
	_update_weights()


func _on_cell_removed(cell: Vector2i) -> void:
	if _pickups.has(cell):
		var pickup = _pickups[cell]
		_pickups.erase(cell)
		if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
			keys_lost += 1
			_check_lost()
	if _gate_cells.has(cell):
		var anchor: Vector2i = _gate_cells[cell]
		for member in _gate_cells.keys():
			if _gate_cells[member] == anchor:
				_gate_cells.erase(member)
		if _gates.erase(anchor):
			gates_lost += 1
			if _unlocking == anchor:
				unlock_progress = 0.0
			_check_lost()


func _place_key(cell: Vector2i) -> void:
	_since_key = 0
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
	_since_gate = 0
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
		_huds[slot].show_inventory(keys_held[slot], capacity(), equipped[slot], equipped[slot] == 0)
		_huds[slot].show_state(keys_held[slot], keys_per_prisoner, carrying, at_gate_needed, gate_status(slot), prompt(slot))
