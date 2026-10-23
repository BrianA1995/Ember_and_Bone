class_name SettingsPage
extends VBoxContainer
## The settings screen: display, audio, controls. Reads and writes GameSettings, so it works
## the same from the main menu and the pause menu. Changes apply at once and are saved when
## the page is left.

signal back_pressed

const MODE_NAMES := ["Windowed", "Fullscreen (borderless)", "Fullscreen (exclusive)"]
const SPLIT_NAMES := ["Side by side", "Stacked"]

var _mode: OptionButton
var _resolution: OptionButton
var _vsync: CheckButton
var _volume: HSlider
var _sensitivity: HSlider
var _fov: HSlider
var _split: OptionButton
var _debug: CheckButton
var _resolutions: Array[Vector2i] = []
var _loading := false


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size.x = 560
	add_child(MenuTheme.title("Settings", 40))
	_mode = _add_options("Display mode", MODE_NAMES, func(i: int) -> void: _change(&"window_mode", i))
	_resolution = _add_options("Resolution", [], func(i: int) -> void: _change(&"resolution", _resolutions[i]))
	_vsync = _add_check("Vertical sync", func(on: bool) -> void: _change(&"vsync", on))
	_volume = _add_slider("Master volume", 0.0, 1.0, 0.05, func(v: float) -> void: _change(&"master_volume", v))
	_sensitivity = _add_slider("Mouse sensitivity", 0.25, 3.0, 0.05, func(v: float) -> void: _change(&"mouse_sensitivity", v))
	_fov = _add_slider("Field of view", 60.0, 110.0, 1.0, func(v: float) -> void: _change(&"field_of_view", v))
	_split = _add_options("Two-player split", SPLIT_NAMES, func(i: int) -> void: _change(&"split_style", i))
	_debug = _add_check("Show debug info", func(on: bool) -> void: _change(&"show_debug", on))
	add_child(MenuTheme.button("Back", _on_back))
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	refresh()


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
	_debug.button_pressed = GameSettings.show_debug
	_loading = false


func focus_first() -> void:
	_mode.grab_focus()


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


func _on_back() -> void:
	GameSettings.save_settings()
	back_pressed.emit()


# --- Row builders ----------------------------------------------------------------------

func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 220
	row.add_child(label)
	add_child(row)
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


func _add_slider(label_text: String, low: float, high: float, step: float, on_changed: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 60
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = "%.2f" % v if step < 1.0 else "%d" % v)
	slider.value_changed.connect(on_changed)
	var row := _row(label_text)
	row.add_child(slider)
	row.add_child(value_label)
	return slider
