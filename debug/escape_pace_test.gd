extends Node
## How long a lone run takes to find its keys and a gate. A walker that keeps going the way it faces
## (turning at walls) is led through the maze with the candle lit; every key and gate is picked
## up or entered as soon as it is built, so this measures how many rooms the maze needs to build before
## each turns up, and how long that takes at a walking pace. Run with "-- rooms_per_key rooms_per_gate".
## Read the output for "ESCAPE PACE".

const ROOMS_PER_SECOND := 0.9

var _manager: MazeManager
var _rooms := 0
var _key_rooms: Array[int] = []
var _since_key := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 40
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await get_tree().physics_frame
	var escape := game.escape
	if args.size() >= 2:
		escape.rooms_per_key = int(args[0])
		escape.restart()
	var manager: MazeManager = game.get_node("MazeManager")
	var player: Player = game.players[0]
	_manager = manager
	manager.grid.cell_added.connect(_on_added)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var heading := 0
	var steps := 0
	while steps < 4000 and _key_rooms.size() < 3:
		steps += 1
		# Whatever the maze has put down is collected at once, to keep the odds flowing.
		for pickup in escape._pickups.values():
			if is_instance_valid(pickup):
				player.warp_to(pickup.global_position - Vector3(0.0, 0.2, 0.0))
				for i in 6:
					await get_tree().physics_frame
				break
		var here := manager.grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
		var open: Array[int] = []
		for side in RoomDefs.SIDE_COUNT:
			if manager.grid.is_open(here, side) and manager.grid.has_cell(manager.grid.neighbor(here, side)):
				open.append(side)
		if open.is_empty():
			player.warp_to(Vector3(0, 0.8, 0))
			await get_tree().physics_frame
			continue
		if not open.has(heading) or rng.randf() < 0.2:
			heading = open[rng.randi() % open.size()]
		player.warp_to(RoomDefs.cell_to_world(manager.grid.neighbor(here, heading)) + Vector3(0, 0.8, 0))
		for i in 6:
			await get_tree().physics_frame
	print("steps ", steps, " finished ", escape.finished, " held ", escape.keys_held, " placed ", escape.keys_placed)
	var seconds := _rooms / ROOMS_PER_SECOND
	print("ESCAPE PACE: rooms_per_key %d: keys after %s rooms; %d rooms built, about %d s at a walking pace" % [escape.rooms_per_key, _key_rooms, _rooms, seconds])
	get_tree().quit()


func _on_added(cell: Vector2i) -> void:
	var data := _manager.grid.get_cell(cell)
	if data.is_empty() or data.anchor != cell:
		return
	if data.piece == &"key_alcove":
		_key_rooms.append(_since_key)
		_since_key = 0
	elif data.piece != &"gate_chamber":
		_rooms += 1
		_since_key += 1
