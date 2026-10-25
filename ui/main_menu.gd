class_name MainMenu
extends Control
## The first screen: Play, number of local players, Settings, Quit. Built in code.
## Main scene of the project (ui/main_menu.tscn).

const MODE_NAMES := ["Freeplay", "Tag (last one standing)", "Endless tag", "Escape (find the keys)"]

var _main_page: VBoxContainer
var _settings_page: SettingsPage
var _play_button: Button
var _players_label: Label
var _mode_label: Label
var _points_label: Label
var _points_row: HBoxContainer
var _grace_check: CheckButton


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
	_refresh_rows()
	_play_button.grab_focus()


func _build_main_page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	page.add_child(MenuTheme.title("EMBER & BONE"))
	_play_button = MenuTheme.button("Play", GameSession.start_game)
	page.add_child(_play_button)
	var label_out := []
	page.add_child(_stepper(_add_mode, label_out))
	page.add_child(_stepper(_add_players, label_out))
	_points_row = _stepper(_add_points, label_out)
	page.add_child(_points_row)
	_grace_check = CheckButton.new()
	_grace_check.text = "Last gate lingers (20 s)"
	_grace_check.toggled.connect(func(on: bool) -> void:
		GameSettings.gate_grace = on
		GameSettings.save_settings())
	page.add_child(_grace_check)
	_mode_label = label_out[0]
	_players_label = label_out[1]
	_points_label = label_out[2]
	page.add_child(MenuTheme.button("Settings", func() -> void: _show_settings(true)))
	page.add_child(MenuTheme.button("Quit", GameSession.quit))
	return page


## A row "<  value  >" with two buttons that call `on_step` with -1 and +1. Returns the row and
## puts the label that shows the value in `label_out[0]`.
func _stepper(on_step: Callable, label_out: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	var less := MenuTheme.button("<", func() -> void: on_step.call(-1))
	var more := MenuTheme.button(">", func() -> void: on_step.call(1))
	less.custom_minimum_size = Vector2(60, 44)
	more.custom_minimum_size = Vector2(60, 44)
	var label := Label.new()
	label.custom_minimum_size.x = 220
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(less)
	row.add_child(label)
	row.add_child(more)
	label_out.append(label)
	return row


func _add_players(step: int) -> void:
	var least := GameSettings.TAG_MIN_PLAYERS if GameSettings.is_tag_mode() else 1
	GameSettings.player_count = clampi(GameSettings.player_count + step, least, GameInput.SLOTS)
	_save_and_refresh()


func _add_mode(step: int) -> void:
	GameSettings.game_mode = posmod(GameSettings.game_mode + step, MODE_NAMES.size()) as GameSettings.GameMode
	GameSettings.enforce_mode_rules()
	_save_and_refresh()


func _add_points(step: int) -> void:
	GameSettings.tag_points = clampi(GameSettings.tag_points + step * 10, GameSettings.TAG_POINTS_MIN, GameSettings.TAG_POINTS_MAX)
	_save_and_refresh()


func _save_and_refresh() -> void:
	GameSettings.save_settings()
	_refresh_rows()


func _refresh_rows() -> void:
	var count := GameSettings.player_count
	_players_label.text = "%d player%s" % [count, "" if count == 1 else "s"]
	_mode_label.text = "Mode: %s" % MODE_NAMES[GameSettings.game_mode]
	_points_row.visible = GameSettings.is_tag_mode()
	_grace_check.visible = GameSettings.game_mode == GameSettings.GameMode.ESCAPE
	_grace_check.set_pressed_no_signal(GameSettings.gate_grace)
	_points_label.text = "%d points each" % GameSettings.tag_points


func _show_settings(shown: bool) -> void:
	_main_page.visible = not shown
	_settings_page.visible = shown
	if shown:
		_settings_page.focus_first()
	else:
		_play_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and _settings_page.visible:
		_settings_page.go_back()
		get_viewport().set_input_as_handled()
