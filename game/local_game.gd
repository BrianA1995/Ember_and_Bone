class_name LocalGame
extends Node3D
## A game for 1-4 local players on one screen. It sits on top of the maze: the maze scripts
## (MazeManager, MazeView, Lighting) know nothing about players or screens, they just light
## the world around every node in the "light_sources" group.
##
## Builds, for each player: a body (player/player.tscn), a camera rig (player/camera_rig.tscn)
## and a view of the world in the split screen. Then keeps view settings in step with
## GameSettings. Children from game/game.tscn: MazeManager, Lighting, Pursuit (its sliders are in
## the inspector), Players, SplitScreen.

const PLAYER_SCENE := preload("res://player/player.tscn")
const RIG_SCENE := preload("res://player/camera_rig.tscn")
const DEBUG_SCRIPT := preload("res://debug/debug_overlay.gd")
## Height the bodies start at, and how far apart they stand in the start room.
const SPAWN_HEIGHT := 0.9
const SPAWN_SPREAD := 0.8

## The tag rules, in a tag game (null in freeplay).
var tag: TagMode
## The escape rules, in an escape game (null otherwise).
var escape: EscapeRun
var players: Array[Player] = []
var rigs: Array[CameraRig] = []

var _debug_layer: CanvasLayer
var _map_layer: CanvasLayer
var _devices: Array = []
var _base_sensitivity := 0.0025

@onready var _players_root: Node3D = $Players
@onready var _split: SplitScreen = $Views/SplitScreen


## The maze takes its size from the settings, and wraps, before it builds itself (its _ready).
func _enter_tree() -> void:
	var manager := $MazeManager as MazeManager
	manager.grid_size = Vector2i(GameSettings.maze_size, GameSettings.maze_size)
	manager.wrap_edges = true


func _ready() -> void:
	GameInput.ensure_actions()
	_base_sensitivity = (RIG_SCENE.instantiate() as CameraRig).mouse_sensitivity
	for slot in GameSettings.player_count:
		_add_player(slot, GameSettings.player_count)
	_add_debug_overlay()
	_add_map()
	if GameSettings.is_tag_mode():
		_add_tag()
	elif GameSettings.game_mode == GameSettings.GameMode.ESCAPE:
		_add_escape()
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()


func _exit_tree() -> void:
	if GameSettings.changed.is_connected(_apply_settings):
		GameSettings.changed.disconnect(_apply_settings)


## Where player `slot` of `count` stands in the start room, so nobody starts inside another.
static func spawn_offset(slot: int, count: int) -> Vector3:
	if count == 1:
		return Vector3.ZERO
	if count == 2:
		return Vector3((slot * 2 - 1) * SPAWN_SPREAD, 0.0, 0.0)
	return Vector3((slot % 2 * 2 - 1) * SPAWN_SPREAD, 0.0, (slot / 2 * 2 - 1) * SPAWN_SPREAD)


func _add_player(slot: int, count: int) -> void:
	var player := PLAYER_SCENE.instantiate() as Player
	player.slot = slot
	player.name = "Player%d" % (slot + 1)
	player.position = Vector3(0.0, SPAWN_HEIGHT, 0.0) + spawn_offset(slot, count)
	_players_root.add_child(player)
	var rig := RIG_SCENE.instantiate() as CameraRig
	rig.slot = slot
	rig.mode = GameSettings.start_view
	rig.target = player
	rig.uses_mouse = GameSettings.controllers[slot] == GameInput.DEVICE_KEYBOARD
	rig.name = "CameraRig%d" % (slot + 1)
	add_child(rig)
	_split.add_view(rig.get_camera(), slot, Player.SLOT_COLORS[slot])
	players.append(player)
	rigs.append(rig)


## The test readout, shown if the settings ask for it. Built here so it finds the players.
func _add_debug_overlay() -> void:
	_debug_layer = CanvasLayer.new()
	_debug_layer.set_script(DEBUG_SCRIPT)
	var label := Label.new()
	label.name = "Label"
	label.position = Vector2(12, 8)
	_debug_layer.add_child(label)
	add_child(_debug_layer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(GameInput.TOGGLE_MAP):
		GameSettings.show_map = not GameSettings.show_map
		GameSettings.commit()


## Tag: rules, a readout in every pane, and a results screen when one player is left.
## A new maze (from the pause menu) starts a new round.
func _add_tag() -> void:
	tag = TagMode.new()
	tag.eliminate = GameSettings.game_mode == GameSettings.GameMode.TAG
	tag.pursuit = $Pursuit
	add_child(tag)
	tag.setup(players, _split, GameSettings.tag_points)
	tag.round_over.connect(func(standings: Array) -> void:
		var results := TagResults.new()
		add_child(results)
		results.show_results(standings))
	($MazeManager as MazeManager).maze_rebuilt.connect(tag.reset)


## Escape: keys and gates (its numbers are on the EscapeRun node), a readout in every pane, and a
## results screen when the run is won or lost. A new maze starts a new run.
func _add_escape() -> void:
	escape = $EscapeRun
	escape.setup(players, _split)
	escape.run_won.connect(func(escaped: Array) -> void:
		var names: Array[String] = []
		for slot in escaped:
			names.append("Player %d" % (slot + 1))
		_show_run_results("You escaped", ", ".join(names) + " got out.", escape))
	escape.run_lost.connect(func(reason: String) -> void:
		_show_run_results("The Cage keeps you", reason, escape))
	if GameSettings.monsters:
		_add_monsters()


## The monsters, and the ways to get a snuffed candle lit again.
func _add_monsters() -> void:
	var director := MonsterDirector.new()
	director.name = "MonsterDirector"
	add_child(director)
	director.setup(players, $MazeManager as MazeManager, escape)
	var relighting := Relighting.new()
	relighting.name = "Relighting"
	add_child(relighting)
	relighting.setup(players)


func _show_run_results(title: String, reason: String, run: EscapeRun) -> void:
	var seconds := int(run.elapsed)
	var facts: Array[String] = [
		"Keys found: %d of %d (%d lost to the dark)" % [run.keys_collected, run.keys_total, run.keys_lost],
		"Time: %d:%02d" % [seconds / 60, seconds % 60],
		"Maze seed: %d" % ($MazeManager as MazeManager).grid.seed_value,
	]
	var results := RunResults.new()
	add_child(results)
	results.show_results(title, reason, facts)


## The debug map of the maze, shown if the settings ask for it.
func _add_map() -> void:
	_map_layer = CanvasLayer.new()
	_map_layer.layer = 5
	_map_layer.add_child(MazeMap.new())
	add_child(_map_layer)


func _apply_settings() -> void:
	# Controllers can be changed from the pause menu.
	if _devices != GameSettings.controllers:
		_devices = GameSettings.controllers.duplicate()
		GameInput.configure(players.size(), _devices)
		for i in rigs.size():
			rigs[i].uses_mouse = _devices[i] == GameInput.DEVICE_KEYBOARD
	_map_layer.visible = GameSettings.show_map
	for rig in rigs:
		rig.mouse_sensitivity = _base_sensitivity * GameSettings.mouse_sensitivity
		rig.set_fov(GameSettings.field_of_view)
	_split.apply_settings()
	_debug_layer.visible = GameSettings.show_debug
