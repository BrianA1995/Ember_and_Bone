class_name RoomDefs
extends RefCounted
## Everything the maze needs to know about the room pieces, in one place.
##
## Sides are indexed clockwise from north (-Z): 0 = N, 1 = E, 2 = S, 3 = W.
## A room's openings are a 4-bit mask (bit i set = side i is open).
## Rotating a room by one step (rotation_degrees.y = 90) turns its east side to the north.
## To add a new room type, add an entry to PIECES (its mask is how it is drawn at rotation 0).

const CELL_SIZE := 4.0
const SIDE_COUNT := 4
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

## The wall piece used to plug a doorway when the maze blocks a passage.
const WALL_SCENE := "res://pieces/wall.tscn"
## Replaces a room's floor when the room has a cracked floor (see hazards/cracked_floor.gd).
const CRACKED_FLOOR_SCENE := "res://hazards/cracked_floor.tscn"

## Every kind of room, and how it is drawn and chosen:
##  scene   the room scene
##  mask    which sides are open when the room is drawn unrotated (bit 0 = N, 1 = E, 2 = S, 3 = W)
##  weight  the relative chance of the piece when several fit a cell
##  cracks  (optional) the room may be given a cracked floor (design doc: straights)
##  cracked (optional) the room always has a cracked floor (design doc: key alcoves)
##  special (optional) a rare special room; unlike plain rooms it may have a single opening
##  cells   (optional) a room bigger than one cell: offset -> mask for every cell it covers, as
##          drawn unrotated. Offsets are (x, z) in cells from the room's origin cell, the one its
##          scene is centred on. Sides between two covered cells must be open on both. `mask`
##          is the origin cell's entry. A covered cell may be left out (a pillar in the middle).
##  start   (optional) only ever used as the starting room, never rolled
##
## The maze never picks the plain dead_end on purpose (dead ends are made by blocking a
## doorway); it only appears if nothing else can legally fill a cell and blocking would trap
## the player. Special rooms are rolled rarely, so their weights are small.
const PIECES := {
	&"dead_end": {"scene": "res://rooms/dead_end.tscn", "mask": 0b0100, "weight": 1.0},
	&"straight": {"scene": "res://rooms/straight.tscn", "mask": 0b0101, "weight": 3.0, "cracks": true},
	&"corner": {"scene": "res://rooms/corner.tscn", "mask": 0b0011, "weight": 3.0},
	&"t_junction": {"scene": "res://rooms/t_junction.tscn", "mask": 0b1110, "weight": 3.0},
	&"cross": {"scene": "res://rooms/cross.tscn", "mask": 0b1111, "weight": 1.5},
	# Special rooms. Sides: N = 1, E = 2, S = 4, W = 8.
	&"key_alcove": {"scene": "res://rooms/key_alcove.tscn", "mask": 0b0100, "weight": 0.12,
			"special": true, "cracked": true},
	&"wax_shrine": {"scene": "res://rooms/wax_shrine.tscn", "mask": 0b0100, "weight": 0.06, "special": true},
	&"safe_niche": {"scene": "res://rooms/safe_niche.tscn", "mask": 0b0100, "weight": 0.06, "special": true},
	&"monster_nest": {"scene": "res://rooms/monster_nest.tscn", "mask": 0b0101, "weight": 0.15, "special": true},
	# Gate chamber: 2 x 2 cells, one doorway on the south side of the bottom-left cell.
	&"gate_chamber": {"scene": "res://rooms/gate_chamber.tscn", "mask": 0b0110, "weight": 0.03, "special": true,
			"cells": {
				Vector2i(0, 0): 0b0110, Vector2i(1, 0): 0b1100,
				Vector2i(0, 1): 0b0111, Vector2i(1, 1): 0b1001,
			}},
	# Echo hall: 2 x 3 cells. Doorways: north of the top-left cell, west of the middle-left
	# cell, south of the bottom-right cell.
	&"echo_hall": {"scene": "res://rooms/echo_hall.tscn", "mask": 0b0111, "weight": 0.12, "special": true,
			"cells": {
				Vector2i(0, 0): 0b0111, Vector2i(1, 0): 0b1100,
				Vector2i(0, 1): 0b1111, Vector2i(1, 1): 0b1101,
				Vector2i(0, 2): 0b0011, Vector2i(1, 2): 0b1101,
			}},
	# Ring-shaped start chamber: 3 x 3 cells around a solid pillar, a doorway on each outer side.
	&"start_chamber": {"scene": "res://rooms/start_chamber.tscn", "mask": 0b0110, "weight": 0.0, "start": true,
			"cells": {
				Vector2i(0, 0): 0b0110, Vector2i(1, 0): 0b1011, Vector2i(2, 0): 0b1100,
				Vector2i(0, 1): 0b1101,                         Vector2i(2, 1): 0b0111,
				Vector2i(0, 2): 0b0011, Vector2i(1, 2): 0b1110, Vector2i(2, 2): 0b1001,
			}},
}

static var _variants: Array[Dictionary] = []


static func opposite(side: int) -> int:
	return (side + 2) % SIDE_COUNT


static func has_side(mask: int, side: int) -> bool:
	return (mask & (1 << side)) != 0


## True if rooms of this piece may be given a cracked floor.
static func can_crack(piece: StringName) -> bool:
	return PIECES[piece].get("cracks", false)


## True if rooms of this piece always have a cracked floor.
static func always_cracked(piece: StringName) -> bool:
	return PIECES[piece].get("cracked", false)


## True for the rare special rooms (key alcove, wax shrine, ...).
static func is_special(piece: StringName) -> bool:
	return PIECES[piece].get("special", false)


## True for a room that covers more than one cell.
static func is_multi(piece: StringName) -> bool:
	return PIECES[piece].has("cells")


## True for a room that is only ever the starting room.
static func is_start_only(piece: StringName) -> bool:
	return PIECES[piece].get("start", false)


static func exit_count(mask: int) -> int:
	var count := 0
	for side in SIDE_COUNT:
		if has_side(mask, side):
			count += 1
	return count


## True for a mask with exactly one opening.
static func is_dead_end(mask: int) -> bool:
	return exit_count(mask) == 1


## True for a mask with three or more openings (a T-junction or a cross).
static func is_junction(mask: int) -> bool:
	return exit_count(mask) >= 3


static func rotate_mask(mask: int, steps: int) -> int:
	var result := 0
	for side in SIDE_COUNT:
		if has_side(mask, (side + steps) % SIDE_COUNT):
			result |= 1 << side
	return result


## Turns a cell offset (x, z) by `steps` quarter turns, the way a room's scene turns.
static func rotate_offset(offset: Vector2i, steps: int) -> Vector2i:
	var result := offset
	for i in steps:
		result = Vector2i(result.y, -result.x)
	return result


## Every cell a piece covers when turned `steps` quarter turns: offset -> mask.
static func footprint(piece: StringName, steps: int) -> Dictionary:
	var shape: Dictionary = PIECES[piece].get("cells", {Vector2i.ZERO: PIECES[piece].mask})
	var result := {}
	for offset in shape:
		result[rotate_offset(offset, steps)] = rotate_mask(shape[offset], steps)
	return result


## Every distinct way a piece can be placed: {piece, rotation, mask, cells}, where `cells` is
## its footprint and `mask` the mask of its origin cell.
static func variants() -> Array[Dictionary]:
	if _variants.is_empty():
		for piece in PIECES:
			var seen: Array[Dictionary] = []
			for steps in SIDE_COUNT:
				var cells := footprint(piece, steps)
				if _is_known_shape(seen, cells):
					continue
				seen.append(cells)
				_variants.append({"piece": piece, "rotation": steps, "mask": cells[Vector2i.ZERO], "cells": cells})
	return _variants


static func _is_known_shape(seen: Array[Dictionary], cells: Dictionary) -> bool:
	for other in seen:
		if other.size() != cells.size():
			continue
		var same := true
		for offset in cells:
			if other.get(offset, -1) != cells[offset]:
				same = false
				break
		if same:
			return true
	return false


## Where the two wall pieces go to plug the doorway on a room-local `side`,
## flush with the cell edge: [{pos: Vector3, rot: degrees about Y}, ...].
static func seal_spots(side: int) -> Array[Dictionary]:
	var dir := DIRS[side]
	var along := Vector3(absi(dir.y), 0.0, absi(dir.x))
	var edge := Vector3(dir.x, 0.0, dir.y) * 1.9
	var rot := 0.0 if dir.y != 0 else 90.0
	var spots: Array[Dictionary] = []
	spots.append({"pos": edge - along * 0.5, "rot": rot})
	spots.append({"pos": edge + along * 0.5, "rot": rot})
	return spots


static func world_to_cell(pos: Vector3) -> Vector2i:
	return Vector2i(roundi(pos.x / CELL_SIZE), roundi(pos.z / CELL_SIZE))


static func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, 0.0, cell.y * CELL_SIZE)
