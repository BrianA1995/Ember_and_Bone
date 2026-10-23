class_name SettingsPage
extends VBoxContainer
## The settings screen: display, audio, controls, maze. Reads and writes GameSettings, so it
## works the same from the main menu and the pause menu. Changes apply at once and are saved
## when the page is left. The controller page opens inside it; `go_back()` steps out of
## whichever page is showing.

signal back_pressed

const MODE_NAMES := ["Windowed", "Fullscreen (borderless)", "Fullscreen (exclusive)"]
const SPLIT_NAMES := ["Side by side", "Stacked"]
## In the order of CameraRig.Mode.
const VIEW_NAMES := ["Top down", "Third person", "First person"]

var _rows: VBoxContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _controls: ControlsPage
var _mode: OptionButton
var _resolution: OptionButton
var _vsync: CheckButton
var _volume: HSlider
var _sensitivity: HSlider
var _fov: HSlider
var _split: OptionButton
var _start_view_row: HBoxContainer
var _start_view: OptionButton
var _game_views: VBoxContainer
var _maze_size: HSlider
var _debug: CheckButton
var _map: CheckButton
var _resolutions: Array[Vector2i] = []
var _loading := false


func _ready() -> void:
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_rows.custom_minimum_size.x = 600
	add_child(_rows)
	_rows.add_child(MenuTheme.title("Settings", 40))
	# The settings scroll if the window is too short to show them all; Back stays in view.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_rows.add_child(_scroll)
	if GameSettings.is_embedded():
		var note := Label.new()
		note.text = "The game is running inside the editor, so the window can't be resized or go fullscreen. Turn off \"Embed Game on Run\" in the editor's Game tab, or run the game on its own."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 560
		note.add_theme_color_override("font_color", MenuTheme.EMBER)
		_list.add_child(note)
	_mode = _add_options("Display mode", MODE_NAMES, func(i: int) -> void: _change(&"window_mode", i))
	_resolution = _add_options("Resolution", [], func(i: int) -> void: _change(&"resolution", _resolutions[i]))
	_vsync = _add_check("Vertical sync", func(on: bool) -> void: _change(&"vsync", on))
	_volume = _add_slider("Master volume", 0.0, 1.0, 0.05, func(v: float) -> void: _change(&"master_volume", v))
	_sensitivity = _add_slider("Mouse sensitivity", 0.25, 3.0, 0.05, func(v: float) -> void: _change(&"mouse_sensitivity", v))
	_fov = _add_slider("Field of view", 60.0, 110.0, 1.0, func(v: float) -> void: _change(&"field_of_view", v))
	_start_view = _add_options("Starting view", VIEW_NAMES, func(i: int) -> void: _change(&"start_view", i))
	_start_view_row = _start_view.get_parent()
	_game_views = VBoxContainer.new()
	_game_views.add_theme_constant_override("separation", 8)
	_list.add_child(_game_views)
	_split = _add_options("Two-player split", SPLIT_NAMES, func(i: int) -> void: _change(&"split_style", i))
	_maze_size = _add_slider("Maze size (new game)", GameSettings.MAZE_MIN, GameSettings.MAZE_MAX, 1.0,
			func(v: float) -> void: _change(&"maze_size", int(v)), func(v: float) -> String: return "%d x %d" % [v, v])
	_debug = _add_check("Show debug info", func(on: bool) -> void: _change(&"show_debug", on))
	_map = _add_check("Show debug map (M)", func(on: bool) -> void: _change(&"show_map", on))
	_rows.add_child(MenuTheme.button("Controllers...", func() -> void: _show_controls(true)))
	_rows.add_child(MenuTheme.button("Back", go_back))
	_controls = ControlsPage.new()
	_controls.visible = false
	_controls.back_pressed.connect(func() -> void: _show_controls(false))
	add_child(_controls)
	visibility_changed.connect(func() -> void:
		if visible:
			_show_controls(false)
			refresh())
	get_viewport().size_changed.connect(_fit_scroll)
	refresh()


## Makes the list as tall as it needs to be, or as tall as the window allows.
func _fit_scroll() -> void:
	var room := get_viewport_rect().size.y - 230.0
	_scroll.custom_minimum_size = Vector2(0.0, clampf(_list.get_combined_minimum_size().y, 120.0, maxf(room, 120.0)))


## Shows the current settings.
func refresh() -> void:
	_loading = true
	_mode.select(GameSettings.window_mode)
	_fill_resolutions()
	_vsync.button_pressed = GameSettings.vsync
	_volume.value = GameSettings.master_volume
	_sensitivity.value = GameSettings.mouse_sensitivity
	_fov.value = GameSettings.field_of_view
	_split.select(GameSettings.split_style)
	_start_view.select(GameSettings.start_view)
	_fill_game_views()
	_maze_size.value = GameSettings.maze_size
	_debug.button_pressed = GameSettings.show_debug
	_map.button_pressed = GameSettings.show_map
	for slider in [_volume, _sensitivity, _fov, _maze_size]:
		slider.value_changed.emit(slider.value)
	_loading = false
	_fit_scroll.call_deferred()


## While a game is running, each player's own view is chosen here (and the starting view, which
## only matters for the next game, is hidden). Without a game, only the starting view shows.
func _fill_game_views() -> void:
	for row in _game_views.get_children():
		_game_views.remove_child(row)
		row.queue_free()
	var rigs: Array[CameraRig] = []
	for node in get_tree().get_nodes_in_group("camera_rig"):
		rigs.append(node as CameraRig)
	rigs.sort_custom(func(a: CameraRig, b: CameraRig) -> bool: return a.slot < b.slot)
	_start_view_row.visible = rigs.is_empty()
	for rig in rigs:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Player %d view" % (rig.slot + 1)
		label.custom_minimum_size.x = 240
		label.add_theme_color_override("font_color", Player.SLOT_COLORS[rig.slot % Player.SLOT_COLORS.size()])
		row.add_child(label)
		var options := OptionButton.new()
		options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for view_name in VIEW_NAMES:
			options.add_item(view_name)
		options.select(rig.mode)
		options.item_selected.connect(func(index: int) -> void: rig.set_mode(index as CameraRig.Mode))
		row.add_child(options)
		_game_views.add_child(row)


func focus_first() -> void:
	_mode.grab_focus()


## One step back: out of the controller page if it is showing, else out of the settings.
func go_back() -> void:
	if _controls.visible:
		_show_controls(false)
		return
	GameSettings.save_settings()
	back_pressed.emit()


func _show_controls(shown: bool) -> void:
	_rows.visible = not shown
	_controls.visible = shown
	if shown:
		_controls.focus_first()
	else:
		focus_first()


func _fill_resolutions() -> void:
	_resolutions = GameSettings.available_resolutions()
	_resolution.clear()
	for size in _resolutions:
		_resolution.add_item("%d x %d" % [size.x, size.y])
	_resolution.select(maxi(_resolutions.find(GameSettings.resolution), 0))


## Stores a value, applies it and tells listeners (saving waits until the page is left).
func _change(key: StringName, value: Variant) -> void:
	if _loading:
		return
	GameSettings.set(key, value)
	GameSettings.apply()
	GameSettings.changed.emit()


# --- Row builders ----------------------------------------------------------------------

func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 240
	row.add_child(label)
	_list.add_child(row)
	return row


func _add_options(label_text: String, items: Array, on_selected: Callable) -> OptionButton:
	var options := OptionButton.new()
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for item in items:
		options.add_item(item)
	options.item_selected.connect(on_selected)
	_row(label_text).add_child(options)
	return options


func _add_check(label_text: String, on_toggled: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.toggled.connect(on_toggled)
	_row(label_text).add_child(check)
	return check


## A slider with its value written beside it; `format` turns the value into that text.
func _add_slider(label_text: String, low: float, high: float, step: float, on_changed: Callable,
		format := Callable()) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 90
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float) -> void:
		if format.is_valid():
			value_label.text = format.call(v)
		else:
			value_label.text = "%.2f" % v if step < 1.0 else "%d" % v)
	slider.value_changed.connect(on_changed)
	var row := _row(label_text)
	row.add_child(slider)
	row.add_child(value_label)
	return slider
