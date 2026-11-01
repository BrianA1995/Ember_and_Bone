class_name MainMenu
extends Control
## The first screen. The labyrinth drifts by behind it (MenuBackdrop) and a panel down the left holds the
## pages (MenuShell): the title page (Play, Settings, Quit), the game setup page and the settings page.
## Main scene of the project (ui/main_menu.tscn).

const MODE_NAMES := PlaySetupPage.MODE_NAMES

var shell := MenuShell.new()
var settings_page := SettingsPage.new()

var _title_page := MenuPage.new()
var _setup_page := PlaySetupPage.new()
var _play_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(MenuBackdrop.new())
	shell.subheading = "A labyrinth that exists only in candlelight"
	add_child(shell)
	_build_title_page()
	_setup_page.back_pressed.connect(shell.back)
	_setup_page.start_pressed.connect(GameSession.start_game)
	settings_page.back_pressed.connect(shell.back)
	shell.add_page(&"title", _title_page)
	shell.add_page(&"setup", _setup_page)
	shell.add_page(&"settings", settings_page)
	shell.reset_to(&"title")


## Shows the settings page (a controller's back button leaves it again).
func show_settings() -> void:
	shell.open_page(&"settings")


func _build_title_page() -> void:
	_play_button = MenuTheme.button("Play", func() -> void:
		_setup_page.refresh()
		shell.open_page(&"setup"), true)
	_title_page.add_child(_play_button)
	_title_page.add_child(MenuTheme.button("Settings", show_settings))
	_title_page.add_child(MenuTheme.button("Quit", GameSession.quit))
