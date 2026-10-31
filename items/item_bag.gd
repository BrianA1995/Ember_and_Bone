class_name ItemBag
extends Node
## What each prisoner carries besides the candle and keys: counts of items by kind (see ItemDefs). It
## only keeps the numbers; whoever uses an item takes it out (take), and ItemPickup puts them in (add).

signal changed(slot: int)

var _counts: Array[Dictionary] = []


## Empties every pack, for `count` prisoners.
func setup(count: int) -> void:
	_counts.clear()
	for i in count:
		_counts.append({})
		changed.emit(i)


func count(slot: int, kind: StringName) -> int:
	return _counts[slot].get(kind, 0)


func has_room(slot: int, kind: StringName) -> bool:
	return count(slot, kind) < ItemDefs.ITEMS[kind].cap


## Adds `amount` of `kind`, up to what can be carried. Returns how many were taken.
func add(slot: int, kind: StringName, amount: int) -> int:
	var taken := mini(amount, ItemDefs.ITEMS[kind].cap - count(slot, kind))
	if taken > 0:
		_counts[slot][kind] = count(slot, kind) + taken
		changed.emit(slot)
	return taken


## Uses up one of `kind`. False if there is none.
func take(slot: int, kind: StringName) -> bool:
	if count(slot, kind) <= 0:
		return false
	_counts[slot][kind] -= 1
	changed.emit(slot)
	return true


## "Matches 3    Spare candle 1" (only what is carried), or "".
func summary(slot: int) -> String:
	var parts: Array[String] = []
	for kind in ItemDefs.ITEMS:
		if count(slot, kind) > 0:
			parts.append("%s %d" % [ItemDefs.label(kind), count(slot, kind)])
	return "    ".join(parts)
