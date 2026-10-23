extends Node
## Moves between the menu and a game, and knows how many local players the game has.
## Autoload "GameSession". The game itself lives in game/local_game.gd.

const MENU_SCENE := "res://ui/main_menu.tscn"
const GAME_SCENE := "res://game/game.tscn"


## Starts a game for GameSettings.player_count local players.
func start_game() -> void:
	GameInput.configure(GameSettings.player_count, GameSettings.controllers)
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


func to_menu() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)


func quit() -> void:
	get_tree().quit()
