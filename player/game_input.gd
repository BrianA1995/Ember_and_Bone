class_name GameInput
extends RefCounted
## Registers the game's input actions in code so they work without editing project settings.
## Later this is where rebinding and controller support belong.

const BINDINGS := {
	&"move_forward": [KEY_W, KEY_UP],
	&"move_back": [KEY_S, KEY_DOWN],
	&"move_left": [KEY_A, KEY_LEFT],
	&"move_right": [KEY_D, KEY_RIGHT],
	&"sprint": [KEY_SHIFT],
	&"interact": [KEY_E],
	&"camera_cycle": [KEY_V],
	&"camera_top": [KEY_1],
	&"camera_third": [KEY_2],
	&"camera_first": [KEY_3],
}


static func ensure_actions() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in BINDINGS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
