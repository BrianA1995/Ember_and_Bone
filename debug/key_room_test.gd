extends Node
## Every key lying in the maze must lie in a key alcove (a dead end with one doorway): walks a lone
## escape run and checks each key against the room the maze says is there.
## Read the output for "KEY ROOM TEST".


func _ready() -> void:
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 40
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await get_tree().physics_frame
	var escape := game.escape
	escape.rooms_per_key = 12
	escape.rooms_per_gate = 12
	escape.restart()
	escape.keys_total = 999
	var manager: MazeManager = game.get_node("MazeManager")
	var player: Player = game.players[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var heading := 0
	var checked := 0
	var bad := 0
	for step in 1500:
		for cell in escape._pickups:
			var pickup = escape._pickups[cell]
			if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
				continue
			checked += 1
			var data := manager.grid.get_cell(cell)
			var exits := 0
			for side in RoomDefs.SIDE_COUNT:
				if manager.grid.is_open(cell, side):
					exits += 1
			if data.is_empty() or data.piece != &"key_alcove" or exits != 1 or pickup.get_parent() != manager.view.room_at(cell):
				bad += 1
				print("  BAD: key at %s in %s with %d exits" % [cell, data.get("piece"), exits])
		var here := manager.grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
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
		for i in 4:
			await get_tree().physics_frame
	print("KEY ROOM TEST: %s (%d checks, %d bad)" % ["PASS" if bad == 0 and checked > 0 else "FAIL", checked, bad])
	get_tree().quit(0 if bad == 0 else 1)
