class_name SplitScreen
extends Control
## Shows one view per local player, side by side or in a grid, all of the same world.
##   1 player   the whole window
##   2 players  side by side or stacked (GameSettings.split_style)
##   3 players  two above, one wide below
##   4 players  a 2x2 grid
## Each view is a SubViewport that shares the main world, with a player's camera moved into it.
## The cameras' rigs stay where they were built, so their input still arrives as normal.

## Space between views, in pixels.
const GAP := 3.0

var _panes: Array[Control] = []
var _viewports: Array[SubViewport] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)


## Gives a player a view: their rig's camera is shown in a new pane.
func add_view(camera: Camera3D, slot: int, color: Color) -> void:
	var pane := Control.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.clip_contents = true
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	var viewport := SubViewport.new()
	viewport.world_3d = get_viewport().world_3d
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.handle_input_locally = false
	container.add_child(viewport)
	pane.add_child(container)
	var tag := Label.new()
	tag.text = "P%d" % (slot + 1)
	tag.position = Vector2(10, 6)
	tag.add_theme_color_override("font_color", color)
	tag.add_theme_font_size_override("font_size", 22)
	tag.visible = false
	pane.add_child(tag)
	add_child(pane)
	camera.reparent(viewport, false)
	camera.make_current()
	_panes.append(pane)
	_viewports.append(viewport)
	_layout()
	apply_settings()


## How many views there are.
func view_count() -> int:
	return _panes.size()


## Picks up resolution scale from the settings.
func apply_settings() -> void:
	for viewport in _viewports:
		viewport.scaling_3d_scale = GameSettings.render_scale()
	_layout()


## The rectangle (as fractions of the window) for view `index` of `count`.
static func view_rect(index: int, count: int, stacked: bool) -> Rect2:
	match count:
		1:
			return Rect2(0, 0, 1, 1)
		2:
			return Rect2(0, index * 0.5, 1, 0.5) if stacked else Rect2(index * 0.5, 0, 0.5, 1)
		3:
			return Rect2(index * 0.5, 0, 0.5, 0.5) if index < 2 else Rect2(0, 0.5, 1, 0.5)
	return Rect2((index % 2) * 0.5, (index / 2) * 0.5, 0.5, 0.5)


func _layout() -> void:
	var count := _panes.size()
	var stacked := GameSettings.split_style == GameSettings.SplitStyle.STACKED
	for i in count:
		var fraction := view_rect(i, count, stacked)
		var rect := Rect2(fraction.position * size, fraction.size * size)
		if count > 1:
			rect = rect.grow(-GAP / 2.0)
		_panes[i].position = rect.position
		_panes[i].size = rect.size
		_panes[i].get_child(1).visible = count > 1
