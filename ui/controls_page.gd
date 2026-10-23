class_name ControlsPage
extends VBoxContainer
## Who plays with what: for each of the four players, a keyboard, the arrow keys or one of the
## connected gamepads. Pick from the list, or press Detect and then any button on a controller.
## A device can only belong to one player: picking one that is taken swaps it. Reads and writes
## GameSettings.controllers.

signal back_pressed

var _pickers: Array[OptionButton] = []
var _choices: Array = []
var _detect_buttons: Array[Button] = []
var _rows: Array[HBoxContainer] = []
var _status: Label
var _listening := -1


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	custom_minimum_size.x = 640
	add_child(MenuTheme.title("Controllers", 40))
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override("font_color", MenuTheme.DIM)
	add_child(_status)
	for slot in GameInput.SLOTS:
		_add_row(slot)
	add_child(MenuTheme.button("Back", func() -> void: back_pressed.emit()))
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: refresh())
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())
	refresh()


## Lists the devices that are connected right now and shows each player's choice.
func refresh() -> void:
	_listening = -1
	for slot in GameInput.SLOTS:
		_fill(slot)
		_detect_buttons[slot].text = "Detect"
		# Players who aren't in the next game are shown dimmed.
		_rows[slot].modulate = Color.WHITE if slot < GameSettings.player_count else Color(1, 1, 1, 0.45)
	var pads := Input.get_connected_joypads().size()
	_status.text = "%d gamepad%s connected. Playing with %d player%s." % [
			pads, "" if pads == 1 else "s", GameSettings.player_count, "" if GameSettings.player_count == 1 else "s"]


func focus_first() -> void:
	_pickers[0].grab_focus()


func _add_row(slot: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "Player %d" % (slot + 1)
	label.add_theme_color_override("font_color", Player.SLOT_COLORS[slot])
	label.custom_minimum_size.x = 100
	row.add_child(label)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(index: int) -> void: _picked(slot, index))
	row.add_child(picker)
	var detect := Button.new()
	detect.text = "Detect"
	detect.custom_minimum_size.x = 150
	detect.pressed.connect(func() -> void: _start_detecting(slot))
	row.add_child(detect)
	add_child(row)
	_pickers.append(picker)
	_detect_buttons.append(detect)
	_rows.append(row)
	_choices.append([])


func _fill(slot: int) -> void:
	var picker := _pickers[slot]
	var devices: Array[int] = [GameInput.DEVICE_KEYBOARD, GameInput.DEVICE_ARROWS]
	for pad in Input.get_connected_joypads():
		devices.append(pad)
	var current: int = GameSettings.controllers[slot]
	if not devices.has(current) and current != GameInput.DEVICE_NONE:
		devices.append(current)
	devices.append(GameInput.DEVICE_NONE)
	_choices[slot] = devices
	picker.clear()
	for device in devices:
		picker.add_item(device_name(device))
	picker.select(devices.find(current))


## What to call a device in the list.
static func device_name(device: int) -> String:
	match device:
		GameInput.DEVICE_KEYBOARD:
			return "Keyboard and mouse (WASD)"
		GameInput.DEVICE_ARROWS:
			return "Keyboard (arrow keys)"
		GameInput.DEVICE_NONE:
			return "Nobody"
	if not Input.get_connected_joypads().has(device):
		return "Gamepad %d (not connected)" % (device + 1)
	return "Gamepad %d: %s" % [device + 1, Input.get_joy_name(device)]


func _picked(slot: int, index: int) -> void:
	_assign(slot, _choices[slot][index])


func _assign(slot: int, device: int) -> void:
	GameSettings.assign_controller(slot, device)
	GameSettings.commit()
	refresh()


func _start_detecting(slot: int) -> void:
	_listening = slot
	for other in GameInput.SLOTS:
		_detect_buttons[other].text = "Press a button..." if other == slot else "Detect"


## While detecting, the next gamepad button press picks that gamepad for the player; Esc gives up.
func _input(event: InputEvent) -> void:
	if _listening < 0 or not visible:
		return
	if event is InputEventJoypadButton and event.pressed:
		var slot := _listening
		_assign(slot, event.device)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		refresh()
		get_viewport().set_input_as_handled()
