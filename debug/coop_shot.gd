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
	menu.queue_free()
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
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
