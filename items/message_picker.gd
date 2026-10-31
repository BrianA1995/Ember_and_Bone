class_name MessagePicker
extends Control
## A small list in one player's pane for choosing what to write (chalk) or say (walkie-talkie): the
## forward and back buttons move, interact picks, the drop button cancels. Players on the keyboard can
## also choose "Write your own" and type. The player cannot move while it is open.

signal chosen(text: String)
signal cancelled

const PRESETS: Array[String] = ["Key here", "Gate here", "Monster!", "Safe here", "Need help", "Come here", "Dead end"]
const OWN := "Write your own..."

var player: Player

var _title := ""
var _options: Array[String] = []
var _index := 0
var _list: Label
var _edit: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_list = Label.new()
	_list.add_theme_font_size_override("font_size", 26)
	_list.add_theme_color_override("font_color", MenuTheme.INK)
	_list.add_theme_color_override("font_outline_color", Color.BLACK)
	_list.add_theme_constant_override("outline_size", 6)
	_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_list.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_list.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_list.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_list)
	_edit = LineEdit.new()
	_edit.max_length = 40
	_edit.placeholder_text = "Type a message, Enter to send, Esc to cancel"
	_edit.custom_minimum_size = Vector2(420.0, 40.0)
	_edit.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_edit.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_edit.visible = false
	_edit.text_submitted.connect(_on_typed)
	_edit.gui_input.connect(_on_edit_input)
	add_child(_edit)


func is_open() -> bool:
	return visible


## Opens the list for `p_player` under `title`; `chosen` or `cancelled` follows.
func open(p_player: Player, title: String) -> void:
	player = p_player
	_title = title
	_options = PRESETS.duplicate()
	if p_player.slot < GameSettings.controllers.size() and GameSettings.controllers[p_player.slot] < 0:
		_options.append(OWN)
	_index = 0
	player.controls_locked = true
	visible = true
	_redraw()


func _physics_process(_delta: float) -> void:
	if not visible or _edit.visible:
		return
	if Input.is_action_just_pressed(GameInput.action(player.slot, &"move_forward")):
		_index = (_index + _options.size() - 1) % _options.size()
		_redraw()
	elif Input.is_action_just_pressed(GameInput.action(player.slot, &"move_back")):
		_index = (_index + 1) % _options.size()
		_redraw()
	elif Input.is_action_just_pressed(GameInput.action(player.slot, &"interact")):
		if _options[_index] == OWN:
			_list.visible = false
			_edit.text = ""
			_edit.visible = true
			_edit.grab_focus()
		else:
			_finish(_options[_index])
	elif Input.is_action_just_pressed(GameInput.action(player.slot, &"drop_item")):
		_finish("")


func _redraw() -> void:
	var lines: Array[String] = [_title, ""]
	for i in _options.size():
		lines.append(("> %s <" if i == _index else "%s") % _options[i])
	_list.text = "\n".join(lines)


func _on_typed(text: String) -> void:
	_finish(text.strip_edges())


func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_edit.accept_event()
		_finish("")


func _finish(text: String) -> void:
	visible = false
	_edit.visible = false
	_edit.release_focus()
	_list.visible = true
	if is_instance_valid(player):
		player.controls_locked = false
	if text == "":
		cancelled.emit()
	else:
		chosen.emit(text)
