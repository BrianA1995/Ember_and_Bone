class_name TagHud
extends Control
## One player's tag readout, drawn inside their own pane of the split screen: their points, a
## "YOU ARE IT" banner that only they see, and the head-start countdown. Nobody can see
## anybody else's state from here: that is the point of the game.

const IT_COLOR := Color(1.0, 0.25, 0.2)

var _points: Label
var _banner: Label
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_points = _label(28, MenuTheme.INK, 1.0, -56.0)
	_banner = _label(44, IT_COLOR, 0.0, 40.0)
	_status = _label(26, MenuTheme.EMBER, 0.5, 70.0)
	_banner.text = "YOU ARE IT"
	_banner.visible = false
	_status.visible = false


## Shows this player's points and whether they are it. `head_start` is the seconds left before
## tag begins (0 once it has). A player who is `out` is told to wait for the round to end.
func show_state(points: float, is_it: bool, head_start: float, out := false) -> void:
	_points.text = "Points  %d" % ceili(points)
	_points.add_theme_color_override("font_color", IT_COLOR if is_it else MenuTheme.INK)
	_banner.visible = is_it
	_status.visible = out or head_start > 0.0
	_status.text = ("You are out." + char(10) + "Wait for the round to end.") if out \
			else "Tag starts in %d" % ceili(head_start)


## A label across the whole width of the pane, centred, `offset_y` pixels below the point at
## `anchor_y` (0 = top of the pane, 1 = bottom).
func _label(size: int, color: Color, anchor_y: float, offset_y: float) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_top = offset_y
	label.offset_bottom = offset_y + size * 1.5
	add_child(label)
	return label
