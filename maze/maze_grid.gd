class_name MazeGrid
extends RefCounted
## Pure maze data: which room sits in which cell. No nodes, no rendering.
##
## Legality rules, enforced when a cell is generated:
##  - two touching cells agree: either both open toward each other or both closed
##  - nothing opens through the outer wall (the edge of `bounds`), unless `wrap_edges` is on: then
##    the edge is a seam, and the room across it is the one on the opposite side of the maze
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
## The maze is a loop: walking off one edge comes out on the opposite edge (see SeamWrap, which
## moves whoever crosses). Rooms bigger than a cell never straddle the seam.
var wrap_edges := false
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

## A room bigger than one cell (RoomDefs `cells`) fills one entry per cell it covers. Every
## entry has the same piece and `anchor` (the cell its origin sits on); each has its own `mask`.
## Such a room is built, changed and removed as one.
##
## cell -> {piece, rotation, mask, sealed, known, cracked, anchor}. `mask` is how the room is drawn,
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


## The cell next to `cell` on `side`; across the seam when the maze wraps.
func neighbor(cell: Vector2i, side: int) -> Vector2i:
	return wrap_cell(cell + RoomDefs.DIRS[side])


## `cell` brought back inside the bounds, if the maze wraps (otherwise unchanged).
func wrap_cell(cell: Vector2i) -> Vector2i:
	if not wrap_edges:
		return cell
	return bounds.position + Vector2i(posmod(cell.x - bounds.position.x, bounds.size.x),
			posmod(cell.y - bounds.position.y, bounds.size.y))


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
	var cells := RoomDefs.footprint(piece, 0)
	_store({"piece": piece, "rotation": 0, "cells": cells, "anchor": cell})
	_announce(cell)


## Every cell covered by the room in `cell` (just `cell` for an ordinary room).
func room_cells(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [cell]
	var data: Dictionary = _cells.get(cell, {})
	if data.is_empty() or not RoomDefs.is_multi(data.piece):
		return result
	result.clear()
	for offset in RoomDefs.footprint(data.piece, data.rotation):
		result.append(data.anchor + offset)
	return result


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


## Builds a safe place to land in an empty cell: an ordinary corridor room, never a special
## room and never a cracked floor. It has no connection to anything yet; the light builds the
## maze outward from it. False if the cell can't take one.
func generate_landing(cell: Vector2i) -> bool:
	if _cells.has(cell) or not in_bounds(cell):
		return false
	var pool: Array[Dictionary] = []
	for variant in candidates(cell, false, false):
		if not RoomDefs.is_special(variant.piece):
			pool.append(variant)
	var saved := crack_chance
	crack_chance = 0.0
	var placed := _place(cell, pool)
	crack_chance = saved
	return placed


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
	# A big room stays as it is until it goes.
	if RoomDefs.is_multi(old.piece):
		return false
	var pool: Array[Dictionary] = []
	for variant in candidates(cell, false, false):
		if variant.piece != old.piece or variant.rotation != old.rotation:
			pool.append(variant)
	var replaced := false
	while not pool.is_empty() and not replaced:
		var pick := _pick_weighted(pool)
		pool.erase(pick)
		_store(pick, old.known)
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
	var members := room_cells(cell)
	# Neighbours that connected to this room remember the doorway as a way back.
	for member in members:
		for side in RoomDefs.SIDE_COUNT:
			var back := RoomDefs.opposite(side)
			var n := neighbor(member, side)
			if not members.has(n) and is_open(member, side) and is_open(n, back):
				_cells[n].known |= 1 << back
	for member in members:
		_cells.erase(member)
	for member in members:
		cell_removed.emit(member)


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


## Every room placement that satisfies the neighbours of `cell` and has a way out. A placement
## is {piece, rotation, mask, cells, anchor}: `mask` is what `cell` gets, `anchor` where the
## room's origin lands. Rooms bigger than a cell are included unless `allow_multi` is off;
## they need every cell they cover to be empty and to agree with its neighbours.
func candidates(cell: Vector2i, allow_dead_ends := true, allow_multi := true) -> Array[Dictionary]:
	var rules := constraints(cell)
	var result: Array[Dictionary] = []
	for variant in RoomDefs.variants():
		if RoomDefs.is_start_only(variant.piece):
			continue
		var shape: Dictionary = variant.cells
		if shape.size() > 1:
			if not allow_multi:
				continue
			for offset in shape:
				var anchor: Vector2i = cell - offset
				if _fits(anchor, shape):
					result.append({"piece": variant.piece, "rotation": variant.rotation,
							"mask": shape[offset], "cells": shape, "anchor": anchor})
			continue
		var mask: int = variant.mask
		if mask == 0 or (mask & rules.fixed) != rules.open:
			continue
		# Special rooms (alcoves, shrines) may have one opening; plain dead ends may not.
		if not allow_dead_ends and RoomDefs.is_dead_end(mask) and not RoomDefs.is_special(variant.piece):
			continue
		result.append({"piece": variant.piece, "rotation": variant.rotation, "mask": mask,
				"cells": shape, "anchor": cell})
	return result


## Could a room with this footprint sit with its origin on `anchor`? Every cell it covers must
## be empty, inside the bounds, and agree with the rooms around it.
func _fits(anchor: Vector2i, shape: Dictionary) -> bool:
	for offset in shape:
		var cell: Vector2i = anchor + offset
		if not in_bounds(cell) or _cells.has(cell):
			return false
		var rules := constraints(cell)
		if (shape[offset] & rules.fixed) != rules.open:
			return false
	return true


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
		for member in room_cells(cell):
			if not _cells.has(member) or _cells[member].anchor != data.anchor:
				problems.append("%s is missing part of its room at %s" % [cell, member])
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
	# Try options in weighted order; the cells end up holding the accepted option, or the
	# last one tried if every option would seal the maze.
	var boxed_in := true
	var pick := {}
	while not pool.is_empty() and boxed_in:
		if not pick.is_empty():
			_unstore(pick)
		pick = _pick_weighted(pool)
		pool.erase(pick)
		_store(pick)
		boxed_in = frontier_from(cell) == 0
	var placed_mask: int = _cells[cell].mask
	_rooms_since_junction = 0 if RoomDefs.is_junction(placed_mask) else _rooms_since_junction + 1
	_announce(cell)
	return true


## Tells listeners about every cell of the room now in `cell`.
func _announce(cell: Vector2i) -> void:
	for member in room_cells(cell):
		cell_added.emit(member)


## Writes a placement ({piece, rotation, cells, anchor}) into the grid, one entry per cell it
## covers. `cracked` is rolled here, from the seed, so the same maze always has the same
## cracked floors.
func _store(pick: Dictionary, known := 0) -> void:
	var cracked: bool = RoomDefs.always_cracked(pick.piece) \
			or (RoomDefs.can_crack(pick.piece) and _rng.randf() < crack_chance)
	for offset in pick.cells:
		_cells[pick.anchor + offset] = {"piece": pick.piece, "rotation": pick.rotation,
				"mask": pick.cells[offset], "sealed": 0, "known": known, "cracked": cracked,
				"anchor": pick.anchor}


## Takes back a placement that was written but not kept.
func _unstore(pick: Dictionary) -> void:
	for offset in pick.cells:
		_cells.erase(pick.anchor + offset)


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
		if RoomDefs.is_junction(variant.mask) and not RoomDefs.is_multi(variant.piece):
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
