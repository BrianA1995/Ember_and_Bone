class_name InventoryBar
extends Control
## One player's items, in the bottom right of their pane: the candle first (it is always there), then
## a slot for each key they can carry. The item in hand has a bright frame. Placeholder pictures, drawn
## in code; replace the two icon functions with real art later.

const SLOT := 64.0
const GAP := 8.0
const MARGIN := 20.0

var _slots := 0
var _contents: Array[Dictionary] = []
var _equipped := 0
var _candle_lit := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0


## `contents` the keys and item stacks carried (each {type, kind, count}, one per slot taken), `slots` the
## slots there are beside the candle; `equipped` is 0 for the candle, else which one is in hand.
func set_state(contents: Array[Dictionary], slots: int, equipped: int, candle_lit: bool) -> void:
	if contents == _contents and slots + 1 == _slots and equipped == _equipped and candle_lit == _candle_lit:
		return
	_contents = contents.duplicate(true)
	_slots = slots + 1
	_equipped = equipped
	_candle_lit = candle_lit
	var width := _slots * SLOT + (_slots - 1) * GAP
	offset_left = -(width + MARGIN)
	offset_right = -MARGIN
	offset_top = -(SLOT + MARGIN)
	offset_bottom = -MARGIN
	queue_redraw()


func _draw() -> void:
	for i in _slots:
		var box := Rect2(i * (SLOT + GAP), 0.0, SLOT, SLOT)
		var filled := i == 0 or i <= _contents.size()
		var chosen := i == _equipped
		draw_rect(box, Color(0.05, 0.045, 0.04, 0.85 if filled else 0.45))
		draw_rect(box, MenuTheme.EMBER if chosen else MenuTheme.DIM, false, 3.0 if chosen else 1.5)
		if i == 0:
			_draw_candle(box.get_center())
		elif filled:
			var entry := _contents[i - 1]
			if entry.type == &"key":
				_draw_key(box.get_center())
			else:
				_draw_item(box, entry.kind, entry.count)


## An item's placeholder picture: its colour in a rounded block, with its first letter and, if more than one, its count.
func _draw_item(box: Rect2, kind: StringName, count: int) -> void:
	var color: Color = ItemDefs.ITEMS[kind].color
	var inner := box.grow(-14.0)
	draw_rect(inner, color.darkened(0.35))
	draw_rect(inner, color, false, 2.0)
	var font := ThemeDB.fallback_font
	var letter := ItemDefs.label(kind).substr(0, 1)
	draw_string(font, inner.position + Vector2(0.0, inner.size.y * 0.72), letter, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 26, Color.WHITE)
	if count > 1:
		draw_string(font, box.position + Vector2(0.0, SLOT - 4.0), str(count), HORIZONTAL_ALIGNMENT_RIGHT, SLOT - 6.0, 18, MenuTheme.INK)


func _draw_candle(centre: Vector2) -> void:
	draw_rect(Rect2(centre + Vector2(-6.0, -4.0), Vector2(12.0, 26.0)), Color(0.92, 0.86, 0.72))
	var flame := Color(1.0, 0.7, 0.3) if _candle_lit else Color(0.4, 0.38, 0.36)
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(0.0, -24.0), centre + Vector2(6.0, -12.0),
		centre + Vector2(0.0, -4.0), centre + Vector2(-6.0, -12.0)]), flame)


func _draw_key(centre: Vector2) -> void:
	var gold := Color(1.0, 0.78, 0.3)
	draw_arc(centre + Vector2(0.0, -12.0), 8.0, 0.0, TAU, 24, gold, 4.0)
	draw_line(centre + Vector2(0.0, -4.0), centre + Vector2(0.0, 22.0), gold, 4.0)
	draw_line(centre + Vector2(0.0, 16.0), centre + Vector2(9.0, 16.0), gold, 4.0)
	draw_line(centre + Vector2(0.0, 22.0), centre + Vector2(9.0, 22.0), gold, 4.0)
