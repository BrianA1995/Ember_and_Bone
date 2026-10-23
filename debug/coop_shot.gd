extends Node
## Saves pictures of the game for 1-4 players, the main menu, settings and pause menu, to the
## folder in the SHOT_DIR environment variable. Needs a real window (not --headless).

func _ready() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	var menu := (load("res://ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu)
	await _frames(10)
	_save(dir + "/menu.png")
	menu._show_settings(true)
	await _frames(5)
	_save(dir + "/settings.png")
	menu._settings_page._show_controls(true)
	await _frames(5)
	_save(dir + "/controllers.png")
	menu.queue_free()
	GameSettings.show_map = true
	GameSettings.maze_size = 40
	for count in [2, 3, 4]:
		GameSettings.player_count = count
		GameInput.configure(count)
		var game := (load("res://game/game.tscn") as PackedScene).instantiate()
		add_child(game)
		for rig in game.rigs:
			rig.set_mode(CameraRig.Mode.THIRD)
		await _frames(90)
		_save(dir + "/game_%d.png" % count)
		if count == 4:
			game.get_node("PauseMenu").open()
			await _frames(5)
			_save(dir + "/pause.png")
			game.get_node("PauseMenu").close()
		game.queue_free()
		await _frames(3)
	GameSettings.game_mode = GameSettings.GameMode.TAG
	GameSettings.player_count = 2
	GameInput.configure(2)
	var menu2 := (load("res://ui/main_menu.tscn") as PackedScene).instantiate()
	add_child(menu2)
	await _frames(5)
	_save(dir + "/menu_tag.png")
	menu2.queue_free()
	var tag_game := (load("res://game/game.tscn") as PackedScene).instantiate()
	add_child(tag_game)
	tag_game.tag.head_start = 0.0
	tag_game.tag.reset()
	await _frames(60)
	_save(dir + "/tag.png")
	tag_game.tag.points[1 - tag_game.tag.it_slot] = 0.0
	tag_game.tag._send_out(1 - tag_game.tag.it_slot) if false else null
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
