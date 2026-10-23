class_name TagResults
extends CanvasLayer
## The end of a tag round: the standings, then Play again or back to the main menu.
## Pauses the game while it is open.


## Shows the standings. `standings` is [{slot, points}], best first.
func show_results(standings: Array) -> void:
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
	page.add_child(MenuTheme.title("Player %d wins" % (standings[0].slot + 1), 48))
	for place in standings.size():
		var entry: Dictionary = standings[place]
		var line := Label.new()
		line.text = "%d.  Player %d    %d points%s" % [place + 1, entry.slot + 1, ceili(entry.points), "   (out)" if entry.get("out", false) else ""]
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 28)
		line.add_theme_color_override("font_color", Player.SLOT_COLORS[entry.slot % Player.SLOT_COLORS.size()])
		page.add_child(line)
	var again := MenuTheme.button("Play again", GameSession.start_game)
	page.add_child(again)
	page.add_child(MenuTheme.button("Main menu", GameSession.to_menu))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true
	again.grab_focus()
