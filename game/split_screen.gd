class_name SplitScreen
extends Control
## Shows one view per local player, side by side or in a grid, all of the same world.
##   1 player   the whole window
##   2 players  side by side or stacked (GameSettings.split_style)
##   3 players  two above, one wide below
##   4 players  a 2x2 grid
## Each view is a SubViewport that shares the main world, with a player's camera moved into it,
## shown by a TextureRect. The viewport is sized in real screen pixels (the interface is scaled to
## the window, so its own units are not pixels), times the resolution scale in the settings.
## The cameras' rigs stay where they were built, so their input still arrives as normal.

## Space between views, in pixels.
const GAP := 3.0

var _panes: Array[Control] = []
var _viewports: Array[SubViewport] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)
	get_window().size_changed.connect(_layout)


## Gives a player a view: their rig's camera is shown in a new pane.
func add_view(camera: Camera3D, slot: int, color: Color) -> void:
	var pane := Control.new()
	pane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.clip_contents = true
	var viewport := SubViewport.new()
	viewport.world_3d = get_viewport().world_3d
	viewport.msaa_3d = get_viewport().msaa_3d
	viewport.handle_input_locally = false
	viewport.size = Vector2i(2, 2)
	var picture := TextureRect.new()
	picture.texture = viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pane.add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tag := Label.new()
	tag.text = "P%d" % (slot + 1)
	tag.position = Vector2(10, 6)
	tag.add_theme_color_override("font_color", color)
	tag.add_theme_font_size_override("font_size", 22)
	tag.visible = false
	pane.add_child(tag)
	pane.add_child(viewport)
	add_child(pane)
	camera.reparent(viewport, false)
	camera.make_current()
	_panes.append(pane)
	_viewports.append(viewport)
	_layout()
	apply_settings()


## The area of view `index`, for drawing something over that player's view only.
func pane_at(index: int) -> Control:
	return _panes[index]


## The picture of view `index` (what the camera sees), for giving it a screen effect.
func picture_at(index: int) -> TextureRect:
	return _panes[index].get_child(0) as TextureRect


## How many views there are.
func view_count() -> int:
	return _panes.size()


## Picks up the resolution scale from the settings.
func apply_settings() -> void:
	_layout()


## How many screen pixels one unit of the interface is (the window is bigger than the interface's
## base size, so one unit is more than a pixel).
func _pixels_per_unit() -> float:
	return maxf(get_viewport().get_screen_transform().get_scale().x, 0.25)


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
		var pixels := (rect.size * _pixels_per_unit() * GameSettings.render_scale()).round()
		_viewports[i].size = Vector2i(maxi(int(pixels.x), 2), maxi(int(pixels.y), 2))
		_panes[i].get_child(1).visible = count > 1
