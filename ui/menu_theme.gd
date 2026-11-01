class_name MenuTheme
extends RefCounted
## The look shared by every menu: a dark panel with an ember edge, candle-amber text, buttons that light up
## with a bar down their left edge. Placeholder styling made in code: a real UI skin replaces this one file.

const INK := Color(0.93, 0.85, 0.68)
const EMBER := Color(1.0, 0.62, 0.28)
const DIM := Color(0.55, 0.5, 0.42)
const PANEL := Color(0.035, 0.03, 0.026, 0.9)
const BUTTON := Color(0.1, 0.085, 0.07, 0.88)
const BUTTON_HOVER := Color(0.23, 0.15, 0.08, 0.95)
const BUTTON_PRIMARY := Color(0.34, 0.17, 0.06, 0.95)
const SHADOW := Color(0.0, 0.0, 0.0, 0.7)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 21
	for type in ["Label", "Button", "OptionButton", "CheckButton"]:
		theme.set_color("font_color", type, INK)
	for type in ["Button", "OptionButton", "CheckButton"]:
		theme.set_color("font_hover_color", type, EMBER)
		theme.set_color("font_focus_color", type, EMBER)
		theme.set_color("font_pressed_color", type, EMBER)
		theme.set_color("font_disabled_color", type, DIM)
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _button_box(BUTTON, DIM, 3))
		theme.set_stylebox("hover", type, _button_box(BUTTON_HOVER, EMBER, 7))
		theme.set_stylebox("pressed", type, _button_box(BUTTON_PRIMARY, EMBER, 7))
		theme.set_stylebox("focus", type, _button_box(BUTTON_HOVER, EMBER, 7))
		theme.set_stylebox("disabled", type, _button_box(BUTTON, BUTTON, 3))
	theme.set_stylebox("panel", "PanelContainer", _panel_box())
	return theme


## A button's look: a filled block with a bar down its left edge `bar` pixels wide.
static func _button_box(fill: Color, edge: Color, bar: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.border_width_left = bar
	box.set_corner_radius_all(2)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return box


## The panel the menu sits in: nearly black, an ember line down the left, a soft shadow.
static func _panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_color = EMBER
	box.set_border_width_all(1)
	box.border_width_left = 4
	box.border_blend = true
	box.set_corner_radius_all(4)
	box.shadow_color = SHADOW
	box.shadow_size = 28
	box.content_margin_left = 34
	box.content_margin_right = 34
	box.content_margin_top = 30
	box.content_margin_bottom = 30
	return box


## The game's name, or a page's: big, amber, with a dark outline so it reads over the maze.
static func title(text: String, size := 56) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", EMBER)
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.03, 0.0))
	label.add_theme_constant_override("outline_size", 8)
	return label


## A page's own heading under the title.
static func heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	return label


## A line of small print.
static func caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", DIM)
	return label


## A thin ember line between parts of a page.
static func rule() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(EMBER, 0.55)
	line.custom_minimum_size = Vector2(0, 2)
	return line


## A menu button; `primary` marks the one the player most likely wants (Play, Start, Resume).
static func button(text: String, on_press: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(440, 52)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if primary:
		button.add_theme_stylebox_override("normal", _button_box(BUTTON_PRIMARY, EMBER, 5))
		button.add_theme_color_override("font_color", EMBER)
	button.pressed.connect(on_press)
	return button
