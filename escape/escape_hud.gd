class_name EscapeHud
extends Control
## One player's readout for the escape run, drawn inside their own pane of the split screen: the
## keys they carry, the team's keys against the number needed, and what the gate they stand in is
## waiting for.

var _keys: Label
var _gate: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys = _label(26, MenuTheme.INK, 12.0)
	_gate = _label(34, MenuTheme.EMBER, 52.0)
	_gate.visible = false


## `held` keys on this player, `team` keys held by everyone against `needed`. `gate` is a line about
## the gate they stand in ("" when they are not in one).
func show_state(held: int, team: int, needed: int, gate: String) -> void:
	_keys.text = "Keys %d     Team %d / %d" % [held, team, needed]
	_gate.visible = not gate.is_empty()
	_gate.text = gate


## A label across the whole width of the pane, centred, `offset_y` pixels below its top.
func _label(size: int, color: Color, offset_y: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_right = 1.0
	label.offset_top = offset_y
	label.offset_bottom = offset_y + size * 1.5
	add_child(label)
	return label
