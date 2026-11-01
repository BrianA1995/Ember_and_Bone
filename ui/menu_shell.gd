class_name MenuShell
extends Control
## The frame every menu sits in: a shaded backdrop, a panel down the left with the game's name over it, and a
## stack of pages inside the panel. The main menu and the pause menu both use it, so they look and navigate the
## same way: a page is shown with open_page(), and Esc / the back button return to the one before it.
##
## A page is any Control. If it has a `go_back()` method it gets the first go at a back press (a settings page
## closing its own sub-page); otherwise the shell simply shows the previous page.

## Esc was pressed on the first page: there is nowhere further back to go (the pause menu resumes).
signal backed_out

## What shades the screen behind the panel: a darkening toward the left edge, or a frosted blur of whatever the
## screen shows (the paused game).
enum Shade { EDGE, BLUR }

@export var shade := Shade.EDGE
@export var heading := "EMBER & BONE"
@export var subheading := ""

var _pages: Dictionary = {}
var _stack: Array[StringName] = []
var _holder: VBoxContainer


func _ready() -> void:
	theme = MenuTheme.build()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_shade()
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "bottom", "right"]:
		margin.add_theme_constant_override("margin_" + side, 56)
	add_child(margin)
	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 540
	centre.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	column.add_child(MenuTheme.title(heading, 54))
	if not subheading.is_empty():
		column.add_child(MenuTheme.caption(subheading))
	column.add_child(MenuTheme.rule())
	_holder = VBoxContainer.new()
	_holder.add_theme_constant_override("separation", 12)
	column.add_child(_holder)


## Adds a page under `key` (hidden until opened).
func add_page(key: StringName, page: Control) -> void:
	page.visible = false
	_pages[key] = page
	_holder.add_child(page)


## The page on show, or &"" before any.
func current() -> StringName:
	return _stack.back() if not _stack.is_empty() else &""


func current_page() -> Control:
	return _pages.get(current())


## Shows page `key` on top of the ones before it.
func open_page(key: StringName) -> void:
	if not _pages.has(key):
		return
	if not _stack.is_empty():
		_pages[_stack.back()].visible = false
	_stack.append(key)
	_pages[key].visible = true
	_focus_page(_pages[key])


## Shows `key` as the only page (the first screen again).
func reset_to(key: StringName) -> void:
	for page in _pages.values():
		page.visible = false
	_stack.clear()
	open_page(key)


## One page back; on the first page, `backed_out`.
func back() -> void:
	if _stack.size() <= 1:
		backed_out.emit()
		return
	_pages[_stack.pop_back()].visible = false
	_pages[_stack.back()].visible = true
	_focus_page(_pages[_stack.back()])


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed(&"ui_cancel"):
		return
	var page := current_page()
	if page != null and page.has_method(&"go_back"):
		page.call(&"go_back")
	else:
		back()
	get_viewport().set_input_as_handled()


## Puts the keyboard / pad focus on the page's first button or control that can take it.
func _focus_page(page: Control) -> void:
	if page.has_method(&"focus_first"):
		page.call(&"focus_first")
		return
	for node in page.find_children("*", "BaseButton", true, false):
		if (node as Control).visible and (node as Control).focus_mode != Control.FOCUS_NONE:
			(node as Control).grab_focus()
			return


func _build_shade() -> void:
	var cover := ColorRect.new()
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = _blur_shader() if shade == Shade.BLUR else _edge_shader()
	cover.material = material
	add_child(cover)


static func _edge_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	// Dark on the left where the panel is, thinning out to a light vignette over the maze.
	float across = clamp(UV.x * 1.6, 0.0, 1.0);
	float edge = 1.0 - smoothstep(0.0, 1.0, across);
	float vignette = length(UV - vec2(0.5)) * 0.7;
	COLOR = vec4(0.015, 0.012, 0.01, clamp(0.25 + edge * 0.62 + vignette * 0.4, 0.0, 0.94));
}
"""
	return shader


static func _blur_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec3 frosted = textureLod(screen, SCREEN_UV, 3.0).rgb;
	float vignette = length(SCREEN_UV - vec2(0.5)) * 0.9;
	vec3 tint = frosted * vec3(0.38, 0.34, 0.3);
	COLOR = vec4(tint * (1.0 - vignette * 0.5), 0.96);
}
"""
	return shader
