class_name Wax
extends RefCounted
## How much of a candle is left. It is only ever shown by the candle itself (it shortens and gutters), never as a
## number. `total` is how many seconds of plain burning a full candle gives; 0 means it never burns down.

## The candle has just burned down to nothing.
signal burned_out

var total := 0.0
var left := 0.0


## A fresh candle that lasts `seconds` (0: never burns down).
func set_life(seconds: float) -> void:
	total = maxf(seconds, 0.0)
	left = total


func is_endless() -> bool:
	return total <= 0.0


## Nothing left to burn.
func is_out() -> bool:
	return not is_endless() and left <= 0.0


## How much is left, 0 to 1 (1 for a candle that never burns down).
func fraction() -> float:
	return 1.0 if is_endless() else clampf(left / total, 0.0, 1.0)


## Burns `seconds` of wax.
func burn(seconds: float) -> void:
	if is_endless() or left <= 0.0:
		return
	left = maxf(left - seconds, 0.0)
	if left <= 0.0:
		burned_out.emit()


## Brings the candle back up to `fraction` of a full one (never lowers it).
func fill(fraction := 1.0) -> void:
	left = maxf(left, total * clampf(fraction, 0.0, 1.0))
