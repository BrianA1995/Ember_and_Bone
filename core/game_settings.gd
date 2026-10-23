extends Node
## The player's settings: display, audio and controls. Autoload "GameSettings".
## Change a value, then call `commit()` to apply it, tell listeners and save it to disk.
## Nothing here knows about the maze or the menus; they read and write it.

signal changed

enum WindowMode { WINDOWED, BORDERLESS, EXCLUSIVE }
enum SplitStyle { SIDE_BY_SIDE, STACKED }

const SAVE_PATH := "user://settings.cfg"
## Sizes offered in the menu. Only those that fit the screen are listed.
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3840, 2160),
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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()


## The resolutions that fit the screen, smallest first, always including the current one.
func available_resolutions() -> Array[Vector2i]:
	var screen := DisplayServer.screen_get_size()
	var list: Array[Vector2i] = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			list.append(size)
	if not list.has(resolution):
		list.append(resolution)
		list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x)
	return list


## How much of the screen's resolution the 3D view renders at (below 1 in fullscreen when a
## lower resolution is chosen, which also makes the game cheaper to run).
func render_scale() -> float:
	if window_mode == WindowMode.WINDOWED:
		return 1.0
	return clampf(float(resolution.y) / float(DisplayServer.screen_get_size().y), 0.25, 1.0)


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
			window.size = resolution
			var screen := window.current_screen
			window.position = DisplayServer.screen_get_position(screen) \
					+ (DisplayServer.screen_get_size(screen) - window.size) / 2
		WindowMode.BORDERLESS:
			window.mode = Window.MODE_FULLSCREEN
		WindowMode.EXCLUSIVE:
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN


func save_settings() -> void:
	var file := ConfigFile.new()
	for key in _keys():
		file.set_value("settings", key, get(key))
	file.save(SAVE_PATH)


func load_settings() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK:
		return
	for key in _keys():
		if file.has_section_key("settings", key):
			set(key, file.get_value("settings", key))
	player_count = clampi(player_count, 1, GameInput.SLOTS)


func _keys() -> Array[String]:
	return ["window_mode", "resolution", "vsync", "master_volume", "mouse_sensitivity",
			"field_of_view", "split_style", "show_debug", "player_count"]
