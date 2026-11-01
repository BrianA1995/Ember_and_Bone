class_name PlaySetupPage
extends MenuPage
## Choosing a game before it starts: the mode, how many players, the points for a tag game and the escape's
## last-gate rule. Every change is saved at once (GameSettings), and Start begins the game.

signal start_pressed

const MODE_NAMES := ["Freeplay", "Tag (last one standing)", "Endless tag", "Escape (find the keys)"]

var _mode := Stepper.new()
var _players := Stepper.new()
var _points := Stepper.new()
var _candle := Stepper.new()
var _grace := CheckButton.new()


func _ready() -> void:
	add_child(MenuTheme.heading("Choose your game"))
	_mode.stepped.connect(_change_mode)
	_players.stepped.connect(_change_players)
	_points.stepped.connect(_change_points)
	add_child(_mode)
	add_child(_players)
	add_child(_points)
	_candle.stepped.connect(_change_candle)
	add_child(_candle)
	_grace.text = "Last gate lingers (20 s)"
	_grace.toggled.connect(func(on: bool) -> void:
		GameSettings.gate_grace = on
		GameSettings.save_settings())
	add_child(_grace)
	add_child(MenuTheme.rule())
	add_child(MenuTheme.button("Start", start_pressed.emit, true))
	add_child(MenuTheme.button("Back", go_back))
	refresh()


## Shows the saved settings.
func refresh() -> void:
	var count := GameSettings.player_count
	_players.set_text("%d player%s" % [count, "" if count == 1 else "s"])
	_mode.set_text("Mode: %s" % MODE_NAMES[GameSettings.game_mode])
	_points.visible = GameSettings.is_tag_mode()
	_candle.visible = GameSettings.game_mode == GameSettings.GameMode.ESCAPE
	_candle.set_text("Candle: %s" % ("never burns down" if GameSettings.candle_minutes == 0 else "%d min" % GameSettings.candle_minutes))
	_grace.visible = GameSettings.game_mode == GameSettings.GameMode.ESCAPE
	_grace.set_pressed_no_signal(GameSettings.gate_grace)
	_points.set_text("%d points each" % GameSettings.tag_points)


func _change_players(step: int) -> void:
	var least := GameSettings.TAG_MIN_PLAYERS if GameSettings.is_tag_mode() else 1
	GameSettings.player_count = clampi(GameSettings.player_count + step, least, GameInput.SLOTS)
	_save()


func _change_mode(step: int) -> void:
	GameSettings.game_mode = posmod(GameSettings.game_mode + step, MODE_NAMES.size()) as GameSettings.GameMode
	GameSettings.enforce_mode_rules()
	_save()


func _change_points(step: int) -> void:
	GameSettings.tag_points = clampi(GameSettings.tag_points + step * 10, GameSettings.TAG_POINTS_MIN, GameSettings.TAG_POINTS_MAX)
	_save()


func _save() -> void:
	GameSettings.save_settings()
	refresh()


func _change_candle(step: int) -> void:
	var choices := GameSettings.CANDLE_CHOICES
	var at := clampi(choices.find(GameSettings.candle_minutes) + step, 0, choices.size() - 1)
	GameSettings.candle_minutes = choices[at]
	_save()
