class_name MenuPage
extends VBoxContainer
## One screen of a menu, shown inside a MenuShell. A page with something to go back to has a back button that
## emits `back_pressed`; the shell also calls go_back() when Esc is pressed. Pages build their own contents.

## The player asked to leave this page.
signal back_pressed


func _init() -> void:
	add_theme_constant_override("separation", 12)


## A page with nothing of its own to close just asks to be left.
func go_back() -> void:
	back_pressed.emit()


## Focus for keyboard and pad: the first button that can take it.
func focus_first() -> void:
	for node in find_children("*", "BaseButton", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
			control.grab_focus()
			return
