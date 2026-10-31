class_name ButtonMap
extends VBoxContainer
## What every button does, for the keyboard and mouse (WASD and the mouse), the arrow keys for a second
## player, and a gamepad. Read-only: the rows come from GameInput.keyboard_map().

signal back_pressed

var _back: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size.x = 760
	add_child(MenuTheme.title("Button map", 40))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 560.0)
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for heading in ["", "Keyboard + mouse", "Arrow keys", "Gamepad"]:
		grid.add_child(_cell(heading, MenuTheme.EMBER))
	for row in GameInput.keyboard_map():
		grid.add_child(_cell(row.what, MenuTheme.INK))
		grid.add_child(_cell(" / ".join(row.keys), MenuTheme.DIM))
		grid.add_child(_cell(row.arrows, MenuTheme.DIM))
		grid.add_child(_cell(row.pad, MenuTheme.DIM))
	var note := _cell("Clicking in the game window captures the mouse; Esc pauses and frees it.", MenuTheme.DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(note)
	_back = MenuTheme.button("Back", func() -> void: back_pressed.emit())
	add_child(_back)


func focus_first() -> void:
	_back.grab_focus()


func _cell(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
