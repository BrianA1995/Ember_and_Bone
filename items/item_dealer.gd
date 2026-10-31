class_name ItemDealer
extends Node
## Puts items in the maze for the prisoners to find. Like the escape run's keys, they come from a
## shuffled deck of room builds: every ordinary room the light builds is the next card, and a card that
## is due puts an item on the floor of the room built next. The cards are spread evenly through the deck
## but each lands at a random spot in its own stretch (`spread`). An item whose room goes dark before
## anyone takes it is dealt again a little later: no item is ever lost.
##
## Knows nothing about the escape run; it needs only the maze, the players' bags and the cards to deal.

signal placed(kind: StringName, cell: Vector2i)

## About how many rooms get built between one item and the next.
@export_range(5, 300, 1) var rooms_per_item := 70
## How much of its stretch an item may land in, around the middle (0 exactly in the middle, 1 anywhere).
@export_range(0.0, 1.0, 0.05) var spread := 0.6
## What each prisoner is dealt over a run, one card each.
@export var per_prisoner: Array[StringName] = [&"matches", &"spare_candle", &"matches"]

var bag: ItemBag
## The cards still to play: {at, kind}.
var deck: Array[Dictionary] = []
var builds := 0

var _manager: MazeManager
var _grid: MazeGrid
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
	builds = 0
	_grid = _manager.grid
	_rng.seed = _grid.seed_value + 31
	bag.setup(_players)
	_deal()
	_grid.cell_added.connect(_on_cell_added)
	_grid.cell_removed.connect(_on_cell_removed)


func _deal() -> void:
	deck.clear()
	var cards: Array[StringName] = []
	for i in _players:
		cards.append_array(per_prisoner)
	var low := 0.5 - spread / 2.0
	for i in cards.size():
		deck.append({"at": i * rooms_per_item + roundi(rooms_per_item * (low + _rng.randf() * spread)), "kind": cards[i]})


func _on_cell_added(cell: Vector2i) -> void:
	var data := _grid.get_cell(cell)
	# A room bigger than a cell is announced once per cell; special rooms (keys, gates) keep their own business.
	if data.is_empty() or data.anchor != cell or RoomDefs.is_special(data.piece):
		return
	builds += 1
	for card in deck:
		if card.at <= builds:
			deck.erase(card)
			_place(card.kind, cell)
			return


func _place(kind: StringName, cell: Vector2i) -> void:
	if not _lay(kind, cell, null, ItemDefs.ITEMS[kind].gives):
		_redeal(kind)
		return
	placed.emit(kind, cell)


## Lays `amount` of `kind` on the floor of `cell`'s room, at `where` (a world position; null for the
## middle). False if there is no room there.
func _lay(kind: StringName, cell: Vector2i, where: Variant, amount: int) -> bool:
	var room := _manager.view.room_at(cell)
	if room == null:
		return false
	var pickup := ItemPickup.new()
	pickup.kind = kind
	pickup.accepts = func(player: Player) -> bool: return bag.has_room(player.slot, kind)
	pickup.taken.connect(func(player: Player) -> void:
		_lying.erase(pickup)
		bag.add(player.slot, kind, amount))
	room.add_child(pickup)
	if where == null:
		pickup.position = Vector3(0.0, 0.45, 0.0)
	else:
		pickup.global_position = Vector3(where.x, 0.45, where.z)
	_lying[pickup] = {"cell": cell, "kind": kind}
	return true


## One `kind` dropped where a monster let it fall. If its room is gone it is dealt again instead.
func drop(kind: StringName, cell: Vector2i, where: Vector3) -> void:
	if not _lay(kind, cell, where, 1):
		_redeal(kind)


## Takes `kind` back out of the maze: it is dealt again a little later.
func return_item(kind: StringName) -> void:
	_redeal(kind)


func _on_cell_removed(cell: Vector2i) -> void:
	for pickup in _lying.keys():
		if _lying[pickup].cell == cell:
			var kind: StringName = _lying[pickup].kind
			_lying.erase(pickup)
			if is_instance_valid(pickup) and not pickup.is_queued_for_deletion():
				_redeal(kind)


func _redeal(kind: StringName) -> void:
	deck.append({"at": builds + _rng.randi_range(8, 25), "kind": kind})
