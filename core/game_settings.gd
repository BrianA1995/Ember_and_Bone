extends Node
## The player's settings: display, audio and controls. Autoload "GameSettings".
## Change a value, then call `commit()` to apply it, tell listeners and save it to disk.
## Nothing here knows about the maze or the menus; they read and write it.

signal changed

enum WindowMode { WINDOWED, BORDERLESS, EXCLUSIVE }
enum SplitStyle { SIDE_BY_SIDE, STACKED }
## Escape is the real game: find keys, reach a gate, get out (see EscapeRun). New modes go on the
## end, so settings saved with the older ones still mean the same thing.
enum GameMode { FREEPLAY, TAG, ENDLESS_TAG, ESCAPE }

## Tag needs somebody to chase.
const TAG_MIN_PLAYERS := 2
const TAG_POINTS_MIN := 10
const TAG_POINTS_MAX := 600
const MAZE_MIN := 20
const MAZE_MAX := 100
const SAVE_PATH := "user://settings.cfg"
## Sizes offered in the menu. Only those that fit the screen are listed.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160),
]

var window_mode := WindowMode.WINDOWED
## The window size when windowed. In fullscreen it is the resolution the game renders at,
## stretched to fill the screen.
var resolution := Vector2i(1280, 720)
var vsync := true
## 0 to 1.
var master_volume := 0.8
## Multiplies the camera's mouse look speed.
var mouse_sensitivity := 1.0
## Vertical field of view in degrees, in the 3D views.
var field_of_view := 75.0
## How two players share the screen.
var split_style := SplitStyle.SIDE_BY_SIDE
## The test readout (seed, FPS, shortcuts).
var show_debug := false
## How many local players the next game has (1-4).
var player_count := 1
## The maze is this many cells wide and tall (it wraps around at the edges).
var maze_size := 30
## The view every player starts a game with (a CameraRig.Mode: top down, third person, first
## person). Once a game is running each player changes their own from the pause menu.
var start_view := CameraRig.Mode.TOP
## Freeplay (just explore), tag (last one standing) or endless tag (see game/tag_mode.gd).
var game_mode := GameMode.FREEPLAY
## Points each player starts a tag round with; being it costs one a second.
var tag_points := 100
## The debug map of the whole maze (M toggles it).
var show_map := false
## What each player (slot 0-3) plays with: GameInput.DEVICE_KEYBOARD, DEVICE_ARROWS, DEVICE_NONE,
## or the id of a gamepad (0, 1, ...).
var controllers: Array = GameInput.DEFAULT_DEVICES.duplicate()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameInput.ensure_menu_buttons()
	load_settings()
	apply()


## The resolutions that fit the screen, smallest first, always including the current one.
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var list: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			list.append(size)
	# The screen's own resolution is always on offer, whatever its shape.
	for extra in [screen, resolution]:
		if not list.has(extra):
			list.append(extra)
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return list


## How much of the screen's resolution the 3D view renders at (below 1 in fullscreen when a
## lower resolution is chosen, which also makes the game cheaper to run).
func render_scale() -> float:
	if window_mode == WindowMode.WINDOWED:
		return 1.0
	var screen := Vector2(DisplayServer.screen_get_size())
	return clampf(minf(resolution.x / screen.x, resolution.y / screen.y), 0.25, 1.0)


## True when the game is running inside the editor's Game tab ("Embed Game on Run"). The editor
## owns that window, so the game can't resize it or go fullscreen.
func is_embedded() -> bool:
	return OS.get_cmdline_args().has("--wid") or OS.get_cmdline_args().has("--embedded")


## Applies everything, tells listeners, and saves.
func commit() -> void:
	apply()
	changed.emit()
	save_settings()


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume, 0.0001)))
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var window := get_window()
	match window_mode:
		WindowMode.WINDOWED:
			window.mode = Window.MODE_WINDOWED
			_place_window()
			# Leaving fullscreen takes a moment; the size has to be set again once it is done.
			_place_window.call_deferred()
		WindowMode.BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		WindowMode.EXCLUSIVE:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN


## Tag can't be played alone: it takes at least two players.
func enforce_mode_rules() -> void:
	if is_tag_mode():
		player_count = maxi(player_count, TAG_MIN_PLAYERS)


## Whether the mode is one of the tag games.
func is_tag_mode() -> bool:
	return game_mode == GameMode.TAG or game_mode == GameMode.ENDLESS_TAG


## Gives `slot` the device. If another player already has it, that player takes the device
## `slot` had, so no two players share one controller.
func assign_controller(slot: int, device: int) -> void:
	var old: int = controllers[slot]
	if device != GameInput.DEVICE_NONE:
		for other in GameInput.SLOTS:
			if other != slot and controllers[other] == device:
				controllers[other] = old
	controllers[slot] = device


## Tests run headless; they must not read or change the player's saved settings.
func _persists() -> bool:
	return DisplayServer.get_name() != "headless"


## Gives the window its size and centres it (windowed mode only).
func _place_window() -> void:
	var window := get_window()
	if window_mode != WindowMode.WINDOWED or window.mode != Window.MODE_WINDOWED:
		return
	window.size = resolution
	var screen := window.current_screen
	var free_space := DisplayServer.screen_get_size(screen) - window.size
	window.position = DisplayServer.screen_get_position(screen) + free_space / 2


func save_settings() -> void:
	if not _persists():
		return
	var file := ConfigFile.new()
	for key in _keys():
		file.set_value("settings", key, get(key))
	file.save(SAVE_PATH)


func load_settings() -> void:
	if not _persists():
		return
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	for key in _keys():
		if file.has_section_key("settings", key):
			set(key, file.get_value("settings", key))
	player_count = clampi(player_count, 1, GameInput.SLOTS)
	maze_size = clampi(maze_size, MAZE_MIN, MAZE_MAX)
	tag_points = clampi(tag_points, TAG_POINTS_MIN, TAG_POINTS_MAX)
	enforce_mode_rules()
	if controllers.size() != GameInput.SLOTS:
		controllers = GameInput.DEFAULT_DEVICES.duplicate()


func _keys() -> Array[String]:
	return ["window_mode", "resolution", "vsync", "master_volume", "mouse_sensitivity",
			"field_of_view", "split_style", "show_debug", "player_count", "maze_size", "show_map",
			"controllers", "game_mode", "tag_points", "start_view"]
