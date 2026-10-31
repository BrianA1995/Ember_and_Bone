extends Node
## Lets a prisoner wander an escape maze full of monsters for a while (random walking, sprinting now and
## then) and reports what happened: which monsters came, how often they hit, what the prisoner lost.
## Passes if nothing broke. Run debug/monster_soak_test.tscn; seconds of play can follow `--`.

var _seconds := 60.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_seconds = float(args[0])
	GameSettings.monsters = true
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameSettings.maze_size = 30
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(game)
	await get_tree().create_timer(0.5).timeout
	var director: MonsterDirector = game.get_node("MonsterDirector")
	director.grace_seconds = 3.0
	director._spawn_timer = 3.0
	director.spawn_interval = 3.0
	var player := game.players[0]
	var hits := {}
	director.player_hit.connect(func(monster: Monster, _p: Player) -> void:
		var name: String = monster.get_script().get_global_name()
		hits[name] = hits.get(name, 0) + 1)
	var seen := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var heading := 0
	var moves := [&"move_forward", &"move_back", &"move_left", &"move_right"]
	var t := 0.0
	var turn := 0.0
	var stats := {"snuffs": 0, "dark": 0.0, "rooms": 0, "far": 0.0}
	player.snuffed.connect(func() -> void: stats.snuffs += 1)
	while t < _seconds:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		turn -= get_physics_process_delta_time()
		if turn <= 0.0:
			turn = rng.randf_range(0.8, 3.0)
			for action in moves:
				Input.action_release(GameInput.action(0, action))
			Input.action_press(GameInput.action(0, moves[rng.randi() % 4]))
			if rng.randf() < 0.4:
				Input.action_press(GameInput.action(0, &"sprint"))
			else:
				Input.action_release(GameInput.action(0, &"sprint"))
		stats.dark += get_physics_process_delta_time() if player.is_snuffed() else 0.0
		stats.rooms = maxi(stats.rooms, director.grid.cell_count())
		stats.far = maxf(stats.far, player.global_position.length())
		for monster in director.monsters:
			seen[monster.get_script().get_global_name()] = true
	print("monsters seen: %s" % [seen.keys()])
	print("hits by kind: %s, candle snuffed %d times (%.0f s in the dark), %d monsters at the end, most rooms at once %d, furthest from start %.0f m" % [hits, stats.snuffs, stats.dark, director.monsters.size(), stats.rooms, stats.far])
	print("MONSTER SOAK: PASS")
	get_tree().quit(0)
