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
##  - A gate is a big chamber. When enough prisoners stand inside it and between them carry enough keys,
##    it starts unlocking; if they all stay for `unlock_seconds` they escape and the run is won.
##  - Lost: too few keys still exist to open a gate, or every gate has been lost to the dark.
##
## The maze scripts know nothing about this: it listens to the grid, hands the generator new odds
## through MazeGrid.weights, and puts keys in the rooms the view built.

signal key_taken(slot: int)
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

## What a run of this many players holds: keys in the maze, keys needed at a gate, gates in the
## maze, prisoners who must be inside the gate.
const PLANS := [
	{"up_to": 1, "keys": 4, "needed": 3, "gates": 2, "at_gate": 1},
	{"up_to": 3, "keys": 6, "needed": 4, "gates": 3, "at_gate": 2},
	{"up_to": 5, "keys": 8, "needed": 5, "gates": 3, "at_gate": 2},
	{"up_to": 8, "keys": 10, "needed": 6, "gates": 4, "at_gate": 3},
]

var keys_total := 0
var keys_needed := 0
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
var elapsed := 0.0
var finished := false
## How far the gate that is unlocking has got, in seconds (0 when none is).
var unlock_progress := 0.0
var players: Array[Player] = []

var _manager: MazeManager
var _grid: MazeGrid
var _huds: Array[EscapeHud] = []
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
	restart()


## Everything back to the start of a run, in the maze the manager has now.
func restart() -> void:
	var plan := plan_for(players.size())
	keys_total = plan.keys
	keys_needed = plan.needed
	gates_total = plan.gates
	at_gate_needed = plan.at_gate
	keys_placed = 0
	keys_lost = 0
	keys_collected = 0
	gates_placed = 0
	gates_lost = 0
	keys_held.clear()
	for i in players.size():
		keys_held.append(0)
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
	_update_gate(delta)
	_refresh()


## The line about the gate player `slot` stands in, or "" when they are not in one.
func gate_status(slot: int) -> String:
	var anchor = _gate_around(players[slot])
	if anchor == null:
		return ""
	var inside := _inside(anchor)
	var keys := _keys_of(inside)
	if inside.size() >= at_gate_needed and keys >= keys_needed:
		return "Unlocking  %d" % ceili(unlock_seconds - unlock_progress)
	return "Gate: %d of %d prisoners, %d of %d keys inside" % [inside.size(), at_gate_needed, keys, keys_needed]


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


## The gate is unlocking while enough prisoners stand in it with enough keys between them.
func _update_gate(delta: float) -> void:
	var ready_anchor = null
	for anchor in _gates:
		var inside := _inside(anchor)
		if inside.size() >= at_gate_needed and _keys_of(inside) >= keys_needed:
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
		for player in _inside(ready_anchor):
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


## The anchor of the gate `player` stands in, or null.
func _gate_around(player: Player) -> Variant:
	var cell := _grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
	return _gate_cells.get(cell)


func _keys_of(list: Array[Player]) -> int:
	var total := 0
	for player in list:
		total += keys_held[player.slot]
	return total


## Ends the run if escape has become impossible.
func _check_lost() -> void:
	if finished:
		return
	if keys_total - keys_lost < keys_needed:
		_lose("Too few keys are left in the labyrinth.")
	elif gates_placed >= gates_total and _gates.is_empty():
		_lose("Every gate has been lost to the dark.")


func _lose(reason: String) -> void:
	finished = true
	run_lost.emit(reason)


func _refresh() -> void:
	for slot in _huds.size():
		_huds[slot].show_state(keys_held[slot], keys_collected, keys_needed, gate_status(slot))
