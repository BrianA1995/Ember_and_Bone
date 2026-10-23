class_name MenuTheme
extends RefCounted
## The look shared by every menu: dark panels, candle-amber text and highlights.
## Placeholder styling: a real UI skin replaces this one function.

const INK := Color(0.93, 0.85, 0.68)
const EMBER := Color(1.0, 0.62, 0.28)
const DIM := Color(0.55, 0.5, 0.42)
const PANEL := Color(0.05, 0.045, 0.04, 0.94)
const BUTTON := Color(0.11, 0.095, 0.08)
const BUTTON_HOVER := Color(0.2, 0.15, 0.1)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	for type in ["Label", "Button", "OptionButton", "CheckButton"]:
		theme.set_color("font_color", type, INK)
	for type in ["Button", "OptionButton", "CheckButton"]:
		theme.set_color("font_hover_color", type, EMBER)
		theme.set_color("font_focus_color", type, EMBER)
		theme.set_color("font_pressed_color", type, EMBER)
		theme.set_color("font_disabled_color", type, DIM)
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _box(BUTTON, DIM))
		theme.set_stylebox("hover", type, _box(BUTTON_HOVER, EMBER))
		theme.set_stylebox("pressed", type, _box(BUTTON_HOVER, EMBER))
		theme.set_stylebox("focus", type, _box(BUTTON_HOVER, EMBER))
		theme.set_stylebox("disabled", type, _box(BUTTON, BUTTON))
	theme.set_stylebox("panel", "PanelContainer", _box(PANEL, DIM, 10))
	return theme


static func _box(fill: Color, border: Color, pad := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = pad + 8
	box.content_margin_right = pad + 8
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box


## A title-style label.
static func title(text: String, size := 56) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", EMBER)
	return label


static func button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(280, 44)
	button.pressed.connect(on_press)
	return button
