class_name Stepper
extends HBoxContainer
## A row "<  value  >": two buttons step a setting down and up, and a label shows its value.

## The player pressed < (-1) or > (+1).
signal stepped(direction: int)

var _label := Label.new()


func _init() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 12)
	var less := MenuTheme.button("<", func() -> void: stepped.emit(-1))
	var more := MenuTheme.button(">", func() -> void: stepped.emit(1))
	less.custom_minimum_size = Vector2(60, 44)
	more.custom_minimum_size = Vector2(60, 44)
	less.alignment = HORIZONTAL_ALIGNMENT_CENTER
	more.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.custom_minimum_size.x = 300
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(less)
	add_child(_label)
	add_child(more)


func set_text(text: String) -> void:
	_label.text = text
