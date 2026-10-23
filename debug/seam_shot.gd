extends Node
## Walks a real player out of an east-edge doorway and records the brightness of every frame
## around the crossing (and saves those frames), to find a flash. Needs a real window (not
## --headless) and the SHOT_DIR environment variable. Run debug/seam_shot.tscn.

const SIZE := 20
const VIEW_MODE := CameraRig.Mode.FIRST


func _ready() -> void:
	if OS.get_environment("NOINTERP_TREE") != "":
		get_tree().set_physics_interpolation_enabled(false)
	GameSettings.player_count = 1
	GameSettings.maze_size = SIZE
	GameSettings.start_view = VIEW_MODE
	GameInput.configure(1)
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	if OS.get_environment("SEAM_DEPTH") != "":
		game.get_node("MazeManager/MazeView").seam_depth = int(OS.get_environment("SEAM_DEPTH"))
	add_child(game)
	await _frames(20)
	var manager: MazeManager = game.get_node("MazeManager")
	manager.start_collapse_delay = 0.0
	var player: Player = game.players[0]
	var east_x := SIZE / 2 - 1
	var found := false
	for z in range(-SIZE / 2 + 2, SIZE / 2 - 2):
		player.warp_to(Vector3((east_x - 1) * 4.0, 0.8, z * 4.0))
		await _frames(40)
		if manager.grid.is_open(Vector2i(east_x, z), 1) and manager.grid.is_open(Vector2i(east_x - 1, z), 1):
			found = true
			break
	print("doorway found: ", found)
	var rig: CameraRig = game.rigs[0]
	rig.yaw = 0.0
	Input.action_press(&"move_right")
	var previous := 0.0
	if OS.get_environment("NOINTERP") != "":
		player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if OS.get_environment("NOSHADOW") != "":
		(player.find_children("*", "OmniLight3D", true, false)[0] as OmniLight3D).shadow_enabled = false
	var events := []
	manager.grid.cell_added.connect(func(c: Vector2i) -> void: events.append("+%s" % c))
	manager.grid.cell_removed.connect(func(c: Vector2i) -> void: events.append("-%s" % c))
	var light := player.find_children("*", "OmniLight3D", true, false)[0] as OmniLight3D
	var dir := OS.get_environment("SHOT_DIR")
	for frame in 240:
		await get_tree().process_frame
		if OS.get_environment("WARPTEST") != "" and frame == 10:
			player.warp_to(player.global_position)
		var image := get_viewport().get_texture().get_image()
		var small := image.duplicate() as Image
		small.resize(16, 8, Image.INTERPOLATE_LANCZOS)
		var brightness := 0.0
		for py in 8:
			for px in 16:
				brightness += small.get_pixel(px, py).get_luminance() / 128.0
		var x := player.global_position.x
		var note := "   <-- JUMP" if absf(brightness - previous) > 0.02 and frame > 0 else ""
		print("frame %3d  x %7.2f  brightness %.4f%s  cam %s light %s vis %s energy %.2f  %s" % [frame, x, brightness, note, rig.get_camera().global_position.snappedf(0.1), light.global_position.snappedf(0.1), light.is_visible_in_tree(), light.light_energy, events])
		events.clear()
		if note != "" or absf(x) > 36.0 and absf(x) < 44.0 and dir != "":
			image.save_png("%s/seam_%03d.png" % [dir, frame])
		previous = brightness
	Input.action_release(&"move_right")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
