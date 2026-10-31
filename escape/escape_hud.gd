class_name EscapeHud
extends Control
## One player's readout for the escape run, drawn inside their own pane of the split screen: the
## keys they carry, how the team is doing, what the gate they stand in is waiting for, and a hint
## for what they can do right now (take a held-out key, hold out their own).

var _keys: Label
var _gate: Label
var _hint: Label
var _message: Label
var _message_left := 0.0
var _inventory := InventoryBar.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys = _label(26, MenuTheme.INK, 0.0, 12.0)
	_gate = _label(34, MenuTheme.EMBER, 0.0, 52.0)
	_hint = _label(24, MenuTheme.EMBER, 1.0, -96.0)
	_message = _label(26, MenuTheme.INK, 0.5, 60.0)
	_message.visible = false
	_gate.visible = false
	_hint.visible = false
	add_child(_inventory)


## A note across the middle of the pane for `seconds` (a teammate's message, a warning).
func show_message(text: String, seconds := 5.0) -> void:
	_message.text = text
	_message.visible = true
	_message_left = seconds


func _process(delta: float) -> void:
	if _message_left > 0.0:
		_message_left -= delta
		_message.visible = _message_left > 0.0


## The pack in the bottom right: what is carried, how many slots there are, which is in hand (0 the candle).
func show_inventory(contents: Array[Dictionary], slots: int, equipped: int, candle_lit: bool) -> void:
	_inventory.set_state(contents, slots, equipped, candle_lit)


## `held` keys on this player, of the `needed` each prisoner needs to get out. Alone (needing more
## than one) that is the whole readout; with company it is whether they have their key, and how many
## prisoners have one (`carrying`) of the `at_gate` who must be inside the gate. `gate` is a line
## about the gate they stand in, `hint` what they can do now; either is "" when there is nothing.
func show_state(held: int, needed: int, carrying: int, at_gate: int, gate: String, hint: String) -> void:
	if needed > 1:
		_keys.text = "Keys %d / %d" % [held, needed]
	else:
		_keys.text = "Key: %s     Prisoners with a key %d / %d" % ["yes" if held > 0 else "none", carrying, at_gate]
	_gate.visible = not gate.is_empty()
	_gate.text = gate
	_hint.visible = not hint.is_empty()
	_hint.text = hint


## A label across the whole width of the pane, centred, `offset_y` pixels from `anchor_y` (0 = the
## top of the pane, 1 = the bottom).
func _label(size: int, color: Color, anchor_y: float, offset_y: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_right = 1.0
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.offset_top = offset_y
	label.offset_bottom = offset_y + size * 1.5
	add_child(label)
	return label
