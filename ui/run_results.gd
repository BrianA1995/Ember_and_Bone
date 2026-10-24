class_name RunResults
extends CanvasLayer
## The end of an escape run: "You escaped" or "The Cage keeps you", a few facts about the run,
## then Play again or back to the main menu. Pauses the game while it is open.


## `title` and `reason` (a line under it), then `facts`, one line each.
func show_results(title: String, reason: String, facts: Array[String]) -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.theme = MenuTheme.build()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 12)
	centre.add_child(page)
	page.add_child(MenuTheme.title(title, 48))
	page.add_child(_line(reason, 28, MenuTheme.EMBER))
	for fact in facts:
		page.add_child(_line(fact, 22, MenuTheme.INK))
	var again := MenuTheme.button("Play again", GameSession.start_game)
	page.add_child(again)
	page.add_child(MenuTheme.button("Main menu", GameSession.to_menu))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	again.grab_focus()


func _line(text: String, size: int, color: Color) -> Label:
	var line := Label.new()
	line.text = text
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", size)
	line.add_theme_color_override("font_color", color)
	return line
