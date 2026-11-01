extends Node
## Saves pictures of the candle at full, low and burnt down, and of a wax shrine before and after use, to the
## folder in the SHOT_DIR environment variable. Needs a real window (not --headless).


func _ready() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.monsters = false
	GameSettings.player_count = 1
	GameSettings.maze_size = 40
	GameSettings.candle_minutes = 3
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	var player := game.players[0]
	var rig := game.rigs[0]
	rig.set_mode(CameraRig.Mode.THIRD)
	await _frames(60)
	_save(dir + "/candle_full.png")
	player.wax.left = player.wax.total * 0.15
	await _frames(40)
	_save(dir + "/candle_low.png")
	player.wax.left = 0.3
	await _frames(60)
	_save(dir + "/candle_out.png")
	# A shrine.
	var shrines := game.get_node("WaxShrines") as WaxShrines
	var manager := game.get_node("MazeManager") as MazeManager
	manager.grid.weights[&"wax_shrine"] = 1000.0
	var heading := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for step in 2500:
		if not shrines._shrines.is_empty():
			break
		var here := manager.grid.cell_at(player.global_position)
		var open: Array[int] = []
		for side in RoomDefs.SIDE_COUNT:
			if manager.grid.is_open(here, side) and manager.grid.has_cell(manager.grid.neighbor(here, side)):
				open.append(side)
		if open.is_empty():
			player.warp_to(Vector3(0, 0.8, 0))
		else:
			if not open.has(heading) or rng.randf() < 0.2:
				heading = open[rng.randi() % open.size()]
			player.warp_to(RoomDefs.cell_to_world(manager.grid.neighbor(here, heading)) + Vector3(0, 0.8, 0))
		await _frames(3)
	if not shrines._shrines.is_empty():
		var cell: Vector2i = shrines._shrines.keys()[0]
		player.warp_to(RoomDefs.cell_to_world(cell) + Vector3(0, 0.8, 0.9))
		await _frames(60)
		_save(dir + "/shrine_lit.png")
		shrines.use(cell)
		await _frames(30)
		_save(dir + "/shrine_dark.png")
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)
