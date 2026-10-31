extends Node
## Plays an escape run with the real monster timing (no shortened grace period) for a while, the prisoner
## wandering at random, and reports how often a monster came near: how many spawned, how long each lived,
## the closest each came to the prisoner, and how many were ever within the candle's light (1 room).
## Run debug/monster_encounter_test.tscn; seconds of play can follow `--`.

var _seconds := 180.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_seconds = float(args[0])
	GameSettings.monsters = true
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 20
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await get_tree().create_timer(0.5).timeout
	var director: MonsterDirector = game.get_node("MonsterDirector")
	var player := game.players[0]
	var log := {}
	var hits := [0]
	director.player_hit.connect(func(_m: Monster, _p: Player) -> void: hits[0] += 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var moves := [&"move_forward", &"move_back", &"move_left", &"move_right"]
	var t := 0.0
	var turn := 0.0
	var spawned := 0
	var dark := 0.0
	while t < _seconds:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		turn -= dt
		dark = dark + dt if player.is_snuffed() else 0.0
		if dark > 3.0:
			player.relight()
			dark = 0.0
		if turn <= 0.0:
			turn = rng.randf_range(0.8, 3.0)
			for action in moves:
				Input.action_release(GameInput.action(0, action))
			Input.action_press(GameInput.action(0, moves[rng.randi() % 4]))
		if int(t * 60.0) % 600 == 0:
			var cells := director._spawn_cells()
			print("t=%3.0f s  rooms %d  spawn cells %d  monsters %d / limit %d" % [t, director.grid.cell_count(), cells.size(), director.monsters.size(), director.limit()])
		for monster in director.monsters:
			if not log.has(monster):
				log[monster] = {"kind": monster.get_script().get_global_name(), "born": t, "last": t, "closest": INF}
				spawned += 1
			var entry: Dictionary = log[monster]
			entry.last = t
			entry.closest = minf(entry.closest, director.offset(player.global_position, monster.global_position).length())
	var close := 0
	var lives := []
	for entry in log.values():
		lives.append(entry.last - entry.born)
		if entry.closest <= RoomDefs.CELL_SIZE * 1.5:
			close += 1
	lives.sort()
	print("played %.0f s: %d monsters spawned, %d came within 6 m, %d hits, %d alive at the end" % [t, spawned, close, hits[0], director.monsters.size()])
	print("first spawn at %.0f s; lifetimes (s): %s" % [log.values().map(func(e: Dictionary) -> float: return e.born).min() if spawned > 0 else -1.0, lives.map(func(v: float) -> int: return int(v))])
	for entry in log.values():
		print("   %s lived %.0f s, closest %.1f m" % [entry.kind, entry.last - entry.born, entry.closest])
	print("MONSTER ENCOUNTER TEST: DONE")
	get_tree().quit(0)
