class_name ItemScatter
extends Node
## Puts items in the maze for the prisoners to find. It has nothing to do with the escape run's keys or
## the monsters, and it keeps no deck: every ordinary room the light builds gets a chance to hold an
## item, and that chance grows with every room built since the last item was laid (a "pity timer"),
## so items turn up at an even pace however the maze comes and goes. What turns up leans toward what
## the team is short of: matches when nobody has any, never more of what everyone already carries a
## full set of. An item in a room that goes dark is simply gone; the chance makes up for it.
##
## Items a prisoner put down or a monster dropped or gave up are different: they are owed back, and are
## laid again in a room built a little later if their room goes dark first (`owed`).
##
## Knows nothing about the escape run; it needs only the maze and the players' bags.

signal placed(kind: StringName, cell: Vector2i)

@export_group("Pace")
## Chance that the first room built after an item is laid holds one.
@export_range(0.0, 1.0, 0.005) var base_chance := 0.02
## How much the chance grows with each room built since the last item was laid.
@export_range(0.0, 0.2, 0.001) var chance_per_room := 0.003
## Rooms to wait after an item is laid before the next may be.
@export_range(0, 40) var min_gap := 4
@export_group("Kinds")
## How likely each kind is, before the team's needs are taken into account (0 is never).
@export var weights := {&"matches": 4.0, &"spare_candle": 2.0, &"lamp": 2.0, &"string": 2.0, &"chalk": 2.0, &"walkie": 1.0, &"pouch": 1.0}
## Multiplied into a kind's weight when nobody carries any, and when everybody has all they can carry.
@export var wanted_factor := 3.0
@export var full_factor := 0.2

var bag: ItemBag
## Rooms built since an item was last laid.
var since_last := 0
## Items owed back: {at, kind}, laid in the first ordinary room built once `builds` reaches `at`.
var owed: Array[Dictionary] = []
var builds := 0

var _manager: MazeManager
var _grid: MazeGrid
## ItemPickup -> {cell, kind, amount, owed}, for the items on the floor now.
var _lying: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _players := 0


func setup(p_manager: MazeManager, p_bag: ItemBag, player_count: int) -> void:
	_manager = p_manager
	bag = p_bag
	_players = player_count
	_manager.maze_rebuilt.connect(_restart)
	_restart()


func _restart() -> void:
	_lying.clear()
	owed.clear()
	builds = 0
	since_last = 0
	_grid = _manager.grid
	_rng.seed = _grid.seed_value + 31
	bag.setup(_players)
	_grid.cell_added.connect(_on_cell_added)
	_grid.cell_removed.connect(_on_cell_removed)


## The chance that the next ordinary room built holds an item.
func chance() -> float:
	if since_last < min_gap:
		return 0.0
	return clampf(base_chance + chance_per_room * (since_last - min_gap), 0.0, 1.0)


func _on_cell_added(cell: Vector2i) -> void:
	var data := _grid.get_cell(cell)
	# A room bigger than a cell is announced once per cell; special rooms (keys, gates) keep their own business.
	if data.is_empty() or data.anchor != cell or RoomDefs.is_special(data.piece):
		return
	builds += 1
	since_last += 1
	for entry in owed:
		if entry.at <= builds:
			owed.erase(entry)
			_place(entry.kind, cell, true)
			return
	if _rng.randf() < chance():
		var kind := _pick_kind()
		if kind != &"":
			_place(kind, cell, false)


## A kind to lay, by weight and by what the team is short of; &"" if nothing is wanted.
func _pick_kind() -> StringName:
	var odds := {}
	var total := 0.0
	for kind in weights:
		var weight: float = weights[kind] * _need(kind)
		if weight > 0.0:
			odds[kind] = weight
			total += weight
	if total <= 0.0:
		return &""
	var roll := _rng.randf() * total
	for kind in odds:
		roll -= odds[kind]
		if roll <= 0.0:
			return kind
	return odds.keys()[-1]


## 0 for what is no use (a walkie-talkie with nobody to talk to), more for what nobody has, less for what everyone has all of.
func _need(kind: StringName) -> float:
	if kind == &"walkie" and _players < 2:
		return 0.0
	var holders := 0
	var full := 0
	for slot in _players:
		var have := bag.count(slot, kind)
		if have > 0:
			holders += 1
		if have >= ItemDefs.ITEMS[kind].cap:
			full += 1
	if full >= _players:
		return full_factor
	return wanted_factor if holders == 0 else 1.0


func _place(kind: StringName, cell: Vector2i, was_owed: bool) -> void:
	if not _lay(kind, cell, null, ItemDefs.ITEMS[kind].gives, 0.0, was_owed):
		if was_owed:
			_owe(kind)
		return
	since_last = 0
	placed.emit(kind, cell)


## Lays `amount` of `kind` on the floor of `cell`'s room, at `where` (a world position; null for the
## middle). False if there is no room there.
func _lay(kind: StringName, cell: Vector2i, where: Variant, amount: int, delay := 0.0, was_owed := false) -> bool:
	var room := _manager.view.room_at(cell)
	if room == null:
		return false
	var pickup := ItemPickup.new()
	pickup.kind = kind
	pickup.delay = delay
	pickup.accepts = func(player: Player) -> bool: return bag.has_room(player.slot, kind, amount)
	pickup.taken.connect(func(player: Player) -> void:
		_lying.erase(pickup)
		bag.add(player.slot, kind, amount))
	room.add_child(pickup)
	if where == null:
		pickup.position = Vector3(0.0, 0.45, 0.0)
	else:
		pickup.global_position = Vector3(where.x, 0.45, where.z)
	_lying[pickup] = {"cell": cell, "kind": kind, "amount": amount, "owed": was_owed}
	return true


## `amount` of `kind` dropped at `where` (by a monster, or a prisoner who put it down). If its room
## is gone it is owed instead. Nobody can take it for a moment, so a prisoner who dropped it
## does not pick it straight up again.
func drop(kind: StringName, cell: Vector2i, where: Vector3, amount := 1) -> void:
	if not _lay(kind, cell, where, amount, 1.2, true):
		_owe(kind)


## Takes `kind` back out of the maze: it is laid again a little later.
func return_item(kind: StringName) -> void:
	_owe(kind)


func _on_cell_removed(cell: Vector2i) -> void:
	for pickup in _lying.keys():
		if _lying[pickup].cell == cell:
			var entry: Dictionary = _lying[pickup]
			_lying.erase(pickup)
			# What was owed comes back; what was simply scattered is gone.
			if entry.owed and is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
				_owe(entry.kind)


func _owe(kind: StringName) -> void:
	owed.append({"at": builds + _rng.randi_range(8, 25), "kind": kind})
