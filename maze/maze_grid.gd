class_name MazeGrid
extends RefCounted
## Pure maze data: which room sits in which cell. No nodes, no rendering.
##
## Legality rules, enforced when a cell is generated:
##  - two touching cells agree: either both open toward each other or both closed
##  - nothing opens through the outer wall (the edge of `bounds`)
##  - a new cell always opens toward the cell that revealed it, so every path connects
##  - a doorway is never left leading nowhere: it either gets a room or gets blocked
##  - nothing is allowed to seal the player's reachable maze with no way onward
##
## Dead ends are not rooms. When light reaches a doorway the maze may block it instead
## of building the room beyond (`block_chance`): the corridor looked like it continued,
## then a wall rises across the end. A blocked side counts as closed from then on.

signal cell_added(cell: Vector2i)
signal cell_removed(cell: Vector2i)
signal side_sealed(cell: Vector2i, side: int)

var bounds: Rect2i
var seed_value: int
## Optional piece -> weight overrides; anything missing uses RoomDefs.PIECES.
var weights: Dictionary = {}
## Chance that a revealed doorway is blocked with a wall instead of leading to a new room.
## A block only goes in if the room keeps at least two other exits, so it closes one branch
## of a junction instead of capping a plain corridor.
var block_chance := 0.2
## Chance that a block is allowed to leave the room with a single exit, i.e. a real dead end.
var dead_end_chance := 0.2
## Chance that a room whose piece allows it (RoomDefs: straights) gets a cracked floor.
var crack_chance := 0.25
## Each room generated since the last junction (T or cross) makes junctions this much more
## likely: the odds are multiplied by 1 + streak * junction_boost.
var junction_boost := 0.5

## cell -> {piece, rotation, mask, sealed, known, cracked}. `mask` is how the room is drawn,
## `sealed` are sides blocked afterwards; a side is only open if in mask and not sealed.
## `cracked` means the room's floor is a CrackedFloor (see hazards/).
## `known` are sides that used to lead to a room which has since collapsed: the way back.
## A known doorway is never blocked, so you can always retreat; what is rebuilt behind
## it is a different room.
var _cells: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _rooms_since_junction := 0


func _init(p_seed: int = 1, p_size: Vector2i = Vector2i(21, 21), p_weights: Dictionary = {}) -> void:
	seed_value = p_seed
	_rng.seed = p_seed
	@warning_ignore("integer_division")
	bounds = Rect2i(-(p_size / 2), p_size)
	weights = p_weights


func cells() -> Array:
	return _cells.keys()


func cell_count() -> int:
	return _cells.size()


func has_cell(cell: Vector2i) -> bool:
	return _cells.has(cell)


## {piece, rotation, mask, sealed}, or {} if the cell is empty.
func get_cell(cell: Vector2i) -> Dictionary:
	return _cells.get(cell, {})


func in_bounds(cell: Vector2i) -> bool:
	return bounds.has_point(cell)


func neighbor(cell: Vector2i, side: int) -> Vector2i:
	return cell + RoomDefs.DIRS[side]


## True if you can walk through this side of the cell (drawn open and not blocked).
func is_open(cell: Vector2i, side: int) -> bool:
	if not _cells.has(cell):
		return false
	var data: Dictionary = _cells[cell]
	return RoomDefs.has_side(data.mask & ~data.sealed, side)


## How many doorways in the maze have been blocked so far.
func sealed_count() -> int:
	var total := 0
	for data in _cells.values():
		for side in RoomDefs.SIDE_COUNT:
			if RoomDefs.has_side(data.sealed, side):
				total += 1
	return total


## Places a specific piece with no checks. Used for the starting room.
func generate_start(cell: Vector2i, piece: StringName) -> void:
	_cells[cell] = _make_cell({"piece": piece, "rotation": 0, "mask": RoomDefs.PIECES[piece].mask})
	cell_added.emit(cell)


## Resolves what lies beyond the open doorway on `side` of `from`: a new room, or a wall
## across the doorway. Returns true if a room exists beyond afterwards.
func reveal_beyond(from: Vector2i, side: int) -> bool:
	var cell := neighbor(from, side)
	if _cells.has(cell):
		return true
	if not in_bounds(cell) or not is_open(from, side):
		return false
	var known: bool = RoomDefs.has_side(_cells[from].known, side)
	if not known and _rng.randf() < block_chance:
		var keep_exits := 1 if _rng.randf() < dead_end_chance else 2
		if _try_seal(from, side, keep_exits):
			return false
	var pool := candidates(cell, false)
	if pool.is_empty():
		# Only a dead end would fit here, so block the doorway instead if that is safe.
		if not known and _try_seal(from, side, 1):
			return false
		return generate_cell(cell)
	return _place(cell, pool)


## Rolls a legal room for an empty cell (dead ends allowed). False if nothing fits.
func generate_cell(cell: Vector2i) -> bool:
	if _cells.has(cell):
		return true
	if not in_bounds(cell):
		return false
	return _place(cell, candidates(cell))


## Swaps an existing room for a different legal one, still matching every neighbour (so the
## doorway you came through stays open). Used when a room has gone dark, so what you find
## when you return is not what you left. Returns false, leaving the room alone, if no
## other room fits or every option would seal the maze.
func reroll_cell(cell: Vector2i) -> bool:
	if not _cells.has(cell):
		return false
	var old: Dictionary = _cells[cell]
	var pool: Array[Dictionary] = []
	for variant in candidates(cell, false):
		if variant.piece != old.piece or variant.rotation != old.rotation:
			pool.append(variant)
	var replaced := false
	while not pool.is_empty() and not replaced:
		var pick := _pick_weighted(pool)
		pool.erase(pick)
		_cells[cell] = _make_cell(pick, old.known)
		replaced = frontier_from(cell) > 0
	if not replaced:
		_cells[cell] = old
		return false
	cell_removed.emit(cell)
	cell_added.emit(cell)
	return true


func remove_cell(cell: Vector2i) -> void:
	if not _cells.has(cell):
		return
	# Neighbours that connected to this room remember the doorway as a way back.
	for side in RoomDefs.SIDE_COUNT:
		var back := RoomDefs.opposite(side)
		var n := neighbor(cell, side)
		if is_open(cell, side) and is_open(n, back):
			_cells[n].known |= 1 << back
	_cells.erase(cell)
	cell_removed.emit(cell)


## Which sides neighbours already decide. `fixed` bits are decided; `open` (a subset of
## `fixed`) are the ones that must be open. Outer-wall sides are fixed closed.
func constraints(cell: Vector2i) -> Dictionary:
	var fixed := 0
	var open := 0
	for side in RoomDefs.SIDE_COUNT:
		var n := neighbor(cell, side)
		if not in_bounds(n):
			fixed |= 1 << side
		elif _cells.has(n):
			fixed |= 1 << side
			if is_open(n, RoomDefs.opposite(side)):
				open |= 1 << side
	return {"fixed": fixed, "open": open}


## Every room placement that satisfies the neighbours of `cell` and has a way out.
func candidates(cell: Vector2i, allow_dead_ends := true) -> Array[Dictionary]:
	var rules := constraints(cell)
	var fixed: int = rules.fixed
	var open: int = rules.open
	var result: Array[Dictionary] = []
	for variant in RoomDefs.variants():
		var mask: int = variant.mask
		if mask == 0 or (mask & fixed) != open:
			continue
		# Special rooms (alcoves, shrines) may have one opening; plain dead ends may not.
		if not allow_dead_ends and RoomDefs.is_dead_end(mask) and not RoomDefs.is_special(variant.piece):
			continue
		result.append(variant)
	return result


## Open doorways, anywhere in the maze connected to `start`, that lead to cells not
## generated yet. Zero means the reachable maze is sealed.
func frontier_from(start: Vector2i) -> int:
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var frontier := 0
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_back()
		for side in RoomDefs.SIDE_COUNT:
			if not is_open(cell, side):
				continue
			var n := neighbor(cell, side)
			if not in_bounds(n):
				continue
			if not _cells.has(n):
				frontier += 1
			elif not seen.has(n):
				seen[n] = true
				queue.append(n)
	return frontier


## Checks every connection. `problems` must always be empty; `pending` counts open
## doorways whose far cell has not been generated yet (normal at the edge of the light).
func validate() -> Dictionary:
	var problems: Array[String] = []
	var pending := 0
	for cell in _cells:
		var data: Dictionary = _cells[cell]
		if (data.mask & ~data.sealed) == 0:
			problems.append("%s has no way out" % cell)
		for side in RoomDefs.SIDE_COUNT:
			var open := is_open(cell, side)
			var n := neighbor(cell, side)
			if not in_bounds(n):
				if open:
					problems.append("%s side %d opens through the outer wall" % [cell, side])
			elif _cells.has(n):
				if open != is_open(n, RoomDefs.opposite(side)):
					problems.append("%s side %d and %s disagree" % [cell, side, n])
			elif open:
				pending += 1
	return {"problems": problems, "pending": pending}


## Blocks a doorway if the room keeps at least `keep_exits` other ways out and the
## reachable maze stays open.
func _try_seal(from: Vector2i, side: int, keep_exits: int) -> bool:
	var data: Dictionary = _cells[from]
	var before: int = data.sealed
	data.sealed = before | (1 << side)
	var exits := 0
	for s in RoomDefs.SIDE_COUNT:
		if is_open(from, s):
			exits += 1
	if exits >= keep_exits and frontier_from(from) > 0:
		side_sealed.emit(from, side)
		return true
	data.sealed = before
	return false


func _place(cell: Vector2i, pool: Array[Dictionary]) -> bool:
	if pool.is_empty():
		push_warning("MazeGrid: no legal room fits cell %s" % cell)
		return false
	# Try options in weighted order; _cells[cell] ends up holding the accepted
	# option, or the last one tried if every option would seal the maze.
	var boxed_in := true
	while not pool.is_empty() and boxed_in:
		var pick := _pick_weighted(pool)
		pool.erase(pick)
		_cells[cell] = _make_cell(pick)
		boxed_in = frontier_from(cell) == 0
	var placed_mask: int = _cells[cell].mask
	_rooms_since_junction = 0 if RoomDefs.is_junction(placed_mask) else _rooms_since_junction + 1
	cell_added.emit(cell)
	return true


## The data for a new room from a placement ({piece, rotation, mask}). `cracked` is rolled
## here, from the seed, so the same maze always has the same cracked floors.
func _make_cell(variant: Dictionary, known := 0) -> Dictionary:
	var cracked: bool = RoomDefs.always_cracked(variant.piece) \
			or (RoomDefs.can_crack(variant.piece) and _rng.randf() < crack_chance)
	return {"piece": variant.piece, "rotation": variant.rotation, "mask": variant.mask,
			"sealed": 0, "known": known, "cracked": cracked}


func _pick_weighted(pool: Array[Dictionary]) -> Dictionary:
	# A piece's weight is split across its rotations so rotation count doesn't skew odds.
	var per_piece := {}
	for variant in pool:
		per_piece[variant.piece] = per_piece.get(variant.piece, 0) + 1
	var junction_factor := 1.0 + _rooms_since_junction * junction_boost
	var total := 0.0
	var shares: Array[float] = []
	for variant in pool:
		var share: float = _weight_of(variant.piece) / per_piece[variant.piece]
		if RoomDefs.is_junction(variant.mask):
			share *= junction_factor
		shares.append(share)
		total += share
	var roll := _rng.randf() * total
	for i in pool.size():
		roll -= shares[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


func _weight_of(piece: StringName) -> float:
	return weights.get(piece, RoomDefs.PIECES[piece].weight)
