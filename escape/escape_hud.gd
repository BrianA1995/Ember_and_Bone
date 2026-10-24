class_name EscapeHud
extends Control
## One player's readout for the escape run, drawn inside their own pane of the split screen: the
## keys they carry, how the team is doing, what the gate they stand in is waiting for, and a hint
## for what they can do right now (take a held-out key, hold out their own).

var _keys: Label
var _gate: Label
var _hint: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys = _label(26, MenuTheme.INK, 0.0, 12.0)
	_gate = _label(34, MenuTheme.EMBER, 0.0, 52.0)
	_hint = _label(24, MenuTheme.EMBER, 1.0, -96.0)
	_gate.visible = false
	_hint.visible = false


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
