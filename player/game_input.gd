class_name GameInput
extends RefCounted
## Registers the game's input actions in code so they work without editing project settings.
##
## Every local player has their own copy of each action (a "slot", 0-3). Slot 0 uses the plain
## names ("move_left"), the others carry a prefix ("p2_move_left"); ask for a name with
## `GameInput.action(slot, "move_left")`. What each slot plays with is a device:
##   DEVICE_KEYBOARD  WASD, with the mouse for looking (with one player, the arrow keys too)
##   DEVICE_ARROWS    the arrow keys
##   0, 1, 2 ...      that gamepad (left stick moves, right stick looks)
##   DEVICE_NONE      no controls
## `configure(player_count, devices)` rebuilds the actions. Rebinding keys belongs here.

const SLOTS := 4
const DEVICE_KEYBOARD := -1
const DEVICE_ARROWS := -2
const DEVICE_NONE := -3
## Who plays with what until the player says otherwise.
const DEFAULT_DEVICES := [DEVICE_KEYBOARD, DEVICE_ARROWS, 0, 1]
## Actions every slot has, each with the events that trigger it for each kind of device.
const PER_SLOT := [
	&"move_forward", &"move_back", &"move_left", &"move_right", &"sprint", &"interact",
	&"camera_cycle", &"camera_top", &"camera_third", &"camera_first",
	&"look_left", &"look_right", &"look_up", &"look_down",
]
## Pauses the game, from any device.
const PAUSE := &"pause"
## Shows or hides the debug map.
const TOGGLE_MAP := &"toggle_map"
const STICK_DEADZONE := 0.25

const _WASD := {
	&"move_forward": KEY_W, &"move_back": KEY_S, &"move_left": KEY_A, &"move_right": KEY_D,
	&"sprint": KEY_SHIFT, &"interact": KEY_E,
	&"camera_cycle": KEY_V, &"camera_top": KEY_1, &"camera_third": KEY_2, &"camera_first": KEY_3,
}
const _ARROWS := {
	&"move_forward": KEY_UP, &"move_back": KEY_DOWN, &"move_left": KEY_LEFT, &"move_right": KEY_RIGHT,
	&"sprint": KEY_CTRL, &"interact": KEY_ENTER, &"camera_cycle": KEY_BACKSLASH,
}

static var _configured_for := 0
static var _devices: Array = DEFAULT_DEVICES.duplicate()


## The name of `base` for the player in `slot`.
static func action(slot: int, base: StringName) -> StringName:
	return base if slot == 0 else StringName("p%d_%s" % [slot + 1, base])


## Menus: the gamepad's A button accepts and B cancels, from any gamepad (the engine's own
## menu actions don't include them here). Safe to call more than once.
static func ensure_menu_buttons() -> void:
	_add_menu_button(&"ui_accept", JOY_BUTTON_A)
	_add_menu_button(&"ui_cancel", JOY_BUTTON_B)


static func _add_menu_button(action_name: StringName, button: JoyButton) -> void:
	if not InputMap.has_action(action_name):
		return
	for event in InputMap.action_get_events(action_name):
		if event is InputEventJoypadButton and event.button_index == button:
			return
	InputMap.action_add_event(action_name, _button(button, -1))


## Registers the actions for a one-player game, unless some game has already set them up.
static func ensure_actions() -> void:
	if _configured_for == 0:
		configure(1)


static func configure(player_count: int, devices: Array = DEFAULT_DEVICES) -> void:
	_configured_for = clampi(player_count, 1, SLOTS)
	_devices = devices.duplicate()
	for slot in SLOTS:
		for base in PER_SLOT:
			var name := action(slot, base)
			if InputMap.has_action(name):
				InputMap.erase_action(name)
			InputMap.add_action(name, STICK_DEADZONE)
			for event in _events(slot, base):
				InputMap.action_add_event(name, event)
	if not InputMap.has_action(PAUSE):
		InputMap.add_action(PAUSE)
		InputMap.action_add_event(PAUSE, _key(KEY_ESCAPE))
		InputMap.action_add_event(PAUSE, _button(JOY_BUTTON_START, -1))
	if not InputMap.has_action(TOGGLE_MAP):
		InputMap.add_action(TOGGLE_MAP)
		InputMap.action_add_event(TOGGLE_MAP, _key(KEY_M))


static func _events(slot: int, base: StringName) -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	var device: int = _devices[slot] if slot < _devices.size() else DEVICE_NONE
	match device:
		DEVICE_KEYBOARD:
			if _WASD.has(base):
				events.append(_key(_WASD[base]))
			if _configured_for == 1 and _ARROWS.has(base):
				events.append(_key(_ARROWS[base]))
		DEVICE_ARROWS:
			if _ARROWS.has(base):
				events.append(_key(_ARROWS[base]))
		DEVICE_NONE:
			pass
		_:
			events.append_array(_pad_events(base, device))
	return events


## What `base` is on a gamepad: left stick moves, right stick looks, right bumper or trigger (or
## a click of the left stick) sprints, X interacts, Y cycles the view.
static func _pad_events(base: StringName, device: int) -> Array[InputEvent]:
	var events: Array[InputEvent] = []
	match base:
		&"move_forward": events.append(_axis(JOY_AXIS_LEFT_Y, -1.0, device))
		&"move_back": events.append(_axis(JOY_AXIS_LEFT_Y, 1.0, device))
		&"move_left": events.append(_axis(JOY_AXIS_LEFT_X, -1.0, device))
		&"move_right": events.append(_axis(JOY_AXIS_LEFT_X, 1.0, device))
		&"look_up": events.append(_axis(JOY_AXIS_RIGHT_Y, -1.0, device))
		&"look_down": events.append(_axis(JOY_AXIS_RIGHT_Y, 1.0, device))
		&"look_left": events.append(_axis(JOY_AXIS_RIGHT_X, -1.0, device))
		&"look_right": events.append(_axis(JOY_AXIS_RIGHT_X, 1.0, device))
		&"sprint":
			events.append(_button(JOY_BUTTON_RIGHT_SHOULDER, device))
			events.append(_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0, device))
			events.append(_button(JOY_BUTTON_LEFT_STICK, device))
		&"interact": events.append(_button(JOY_BUTTON_X, device))
		&"camera_cycle": events.append(_button(JOY_BUTTON_Y, device))
	return events


static func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	return event


static func _button(button: JoyButton, device: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.device = device
	return event


static func _axis(axis: JoyAxis, value: float, device: int) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = value
	event.device = device
	return event
