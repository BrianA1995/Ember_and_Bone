class_name LocalGame
extends Node3D
## A game for 1-4 local players on one screen. It sits on top of the maze: the maze scripts
## (MazeManager, MazeView, Lighting) know nothing about players or screens, they just light
## the world around every node in the "light_sources" group.
##
## Builds, for each player: a body (player/player.tscn), a camera rig (player/camera_rig.tscn)
## and a view of the world in the split screen. Then keeps view settings in step with
## GameSettings. Children from game/game.tscn: MazeManager, Lighting, Players, SplitScreen.

const PLAYER_SCENE := preload("res://player/player.tscn")
const RIG_SCENE := preload("res://player/camera_rig.tscn")
const DEBUG_SCRIPT := preload("res://debug/debug_overlay.gd")
## Height the bodies start at, and how far apart they stand in the start room.
const SPAWN_HEIGHT := 0.9
const SPAWN_SPREAD := 0.8

var players: Array[Player] = []
var rigs: Array[CameraRig] = []

var _debug_layer: CanvasLayer
var _base_sensitivity := 0.0025

@onready var _players_root: Node3D = $Players
@onready var _split: SplitScreen = $Views/SplitScreen


func _ready() -> void:
	GameInput.ensure_actions()
	_base_sensitivity = (RIG_SCENE.instantiate() as CameraRig).mouse_sensitivity
	for slot in GameSettings.player_count:
		_add_player(slot, GameSettings.player_count)
	_add_debug_overlay()
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
	rig.target = player
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


func _apply_settings() -> void:
	for rig in rigs:
		rig.mouse_sensitivity = _base_sensitivity * GameSettings.mouse_sensitivity
		rig.set_fov(GameSettings.field_of_view)
	_split.apply_settings()
	_debug_layer.visible = GameSettings.show_debug
