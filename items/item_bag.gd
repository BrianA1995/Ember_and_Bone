class_name ItemBag
extends Node
## What each prisoner carries besides the candle: keys and items share the same inventory slots. A
## prisoner has as many slots as keys they need to get out, plus one for each pouch they wear (so one
## key and no spare room with company; three keys' worth alone). A key takes a slot, a stack of items
## takes a slot (three matches, six marks of chalk, ... see ItemDefs.per_slot), and the pouch takes none.
##
## The bag keeps the numbers and the rules; the key count and the base number of slots come from the
## escape run (`keys_of`, `base_slots`), and whoever uses an item takes it out.

signal changed(slot: int)

## Called as keys_of.call(slot) -> int: the keys that prisoner carries.
var keys_of := Callable()
## Called as base_slots.call() -> int: the slots a prisoner has before any pouch.
var base_slots := Callable()

var _counts: Array[Dictionary] = []
var _pouches: Array[int] = []


## Empties every pack, for `count` prisoners.
func setup(count: int) -> void:
	_counts.clear()
	_pouches.clear()
	for i in count:
		_counts.append({})
		_pouches.append(0)
		changed.emit(i)


func count(slot: int, kind: StringName) -> int:
	if kind == &"pouch":
		return _pouches[slot]
	return _counts[slot].get(kind, 0)


## Slots this prisoner has in all.
func total_slots(slot: int) -> int:
	return (base_slots.call() if base_slots.is_valid() else 1) + _pouches[slot]


## Slots taken by the keys and the stacks of items.
func used_slots(slot: int) -> int:
	var used: int = keys_of.call(slot) if keys_of.is_valid() else 0
	return used + stacks(slot)


func free_slots(slot: int) -> int:
	return total_slots(slot) - used_slots(slot)


## How many slots the items alone take.
func stacks(slot: int) -> int:
	var total := 0
	for kind in _counts[slot]:
		total += _stacks_for(kind, _counts[slot][kind])
	return total


## Can `amount` more of `kind` be carried now?
func has_room(slot: int, kind: StringName, amount := -1) -> bool:
	if amount < 0:
		amount = ItemDefs.ITEMS[kind].gives
	if kind == &"pouch":
		return _pouches[slot] + amount <= ItemDefs.ITEMS[kind].cap
	var have := count(slot, kind)
	if have + amount > ItemDefs.ITEMS[kind].cap:
		return false
	return _stacks_for(kind, have + amount) - _stacks_for(kind, have) <= free_slots(slot)


## Adds `amount` of `kind` if it all fits. Returns how many were taken (0 or `amount`).
func add(slot: int, kind: StringName, amount: int) -> int:
	if not has_room(slot, kind, amount):
		return 0
	if kind == &"pouch":
		_pouches[slot] += amount
	else:
		_counts[slot][kind] = count(slot, kind) + amount
	changed.emit(slot)
	return amount


## Uses up one of `kind`. False if there is none.
func take(slot: int, kind: StringName) -> bool:
	if count(slot, kind) <= 0 or kind == &"pouch":
		return false
	_counts[slot][kind] -= 1
	if _counts[slot][kind] <= 0:
		_counts[slot].erase(kind)
	changed.emit(slot)
	return true


## Takes out the whole stack of `kind` that is in the pack's first slot of it (to drop it). Returns how many.
func take_stack(slot: int, kind: StringName) -> int:
	var have := count(slot, kind)
	if have <= 0 or kind == &"pouch":
		return 0
	var out := mini(have, ItemDefs.per_slot(kind))
	for i in out:
		take(slot, kind)
	return out


## The item stacks carried, in order: [{kind, count}], one per slot taken.
func entries(slot: int) -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	for kind in ItemDefs.ITEMS:
		var left := count(slot, kind)
		if not ItemDefs.uses_slot(kind):
			continue
		while left > 0:
			list.append({"kind": kind, "count": mini(left, ItemDefs.per_slot(kind))})
			left -= ItemDefs.per_slot(kind)
	return list


## "Matches 3    Spare candle 1" (only what is carried), or "".
func summary(slot: int) -> String:
	var parts: Array[String] = []
	for kind in ItemDefs.ITEMS:
		if count(slot, kind) > 0 and ItemDefs.uses_slot(kind):
			parts.append("%s %d" % [ItemDefs.label(kind), count(slot, kind)])
	return "    ".join(parts)


## Does this prisoner carry any item (not the pouch)?
func has_items(slot: int) -> bool:
	return not _counts[slot].is_empty()


func _stacks_for(kind: StringName, amount: int) -> int:
	return ceili(float(amount) / ItemDefs.per_slot(kind))
