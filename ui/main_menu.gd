class_name MainMenu
extends Control
## The first screen: Play, number of local players, Settings, Quit. Built in code.
## Main scene of the project (ui/main_menu.tscn).

var _main_page: VBoxContainer
var _settings_page: SettingsPage
var _play_button: Button
var _players_label: Label


func _ready() -> void:
	theme = MenuTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.018, 0.016)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	_main_page = _build_main_page()
	_settings_page = SettingsPage.new()
	_settings_page.visible = false
	_settings_page.back_pressed.connect(func() -> void: _show_settings(false))
	var holder := VBoxContainer.new()
	holder.add_child(_main_page)
	holder.add_child(_settings_page)
	centre.add_child(holder)
	_refresh_players()
	_play_button.grab_focus()


func _build_main_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(MenuTheme.title("EMBER & BONE"))
	_play_button = MenuTheme.button("Play", GameSession.start_game)
	page.add_child(_play_button)
	page.add_child(_build_players_row())
	page.add_child(MenuTheme.button("Settings", func() -> void: _show_settings(true)))
	page.add_child(MenuTheme.button("Quit", GameSession.quit))
	return page


## "<  2 players  >" for choosing how many local players join.
func _build_players_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var less := MenuTheme.button("<", func() -> void: _add_players(-1))
	var more := MenuTheme.button(">", func() -> void: _add_players(1))
	less.custom_minimum_size = Vector2(60, 44)
	more.custom_minimum_size = Vector2(60, 44)
	_players_label = Label.new()
	_players_label.custom_minimum_size.x = 150
	_players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(less)
	row.add_child(_players_label)
	row.add_child(more)
	return row


func _add_players(step: int) -> void:
	GameSettings.player_count = clampi(GameSettings.player_count + step, 1, GameInput.SLOTS)
	GameSettings.save_settings()
	_refresh_players()


func _refresh_players() -> void:
	var count := GameSettings.player_count
	_players_label.text = "%d player%s" % [count, "" if count == 1 else "s"]


func _show_settings(shown: bool) -> void:
	_main_page.visible = not shown
	_settings_page.visible = shown
	if shown:
		_settings_page.focus_first()
	else:
		_play_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _settings_page.visible:
		_settings_page.back_pressed.emit()
		get_viewport().set_input_as_handled()
