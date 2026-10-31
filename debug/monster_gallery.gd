extends Node
## Shows every kind of monster in turn, standing in front of the prisoner in the start room, so how each
## one looks can be checked in the real game window (run it, don't use --headless). The Weaver is shown
## on the floor, a wall and the ceiling. Nothing here moves or attacks: the Director is off.
## Run debug/monster_gallery.tscn.

const KINDS: Array[StringName] = [&"lurker", &"thief", &"weaver", &"crawler", &"moth", &"leech", &"warden", &"mimic"]
## Seconds each is shown for.
@export var seconds := 5.0

var _game: LocalGame
var _director: MonsterDirector
var _shown: Monster
var _label := Label.new()


func _ready() -> void:
	GameSettings.monsters = true
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	GameInput.configure(1)
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	(_game.get_node("MazeManager") as MazeManager).start_collapse_delay = 0.0
	add_child(_game)
	var layer := CanvasLayer.new()
	layer.layer = 50
	_label.add_theme_font_size_override("font_size", 28)
	_label.position = Vector2(20.0, 80.0)
	layer.add_child(_label)
	add_child(layer)
	await get_tree().create_timer(0.8).timeout
	_director = _game.get_node("MonsterDirector")
	_director.enabled = false
	_cycle()


func _cycle() -> void:
	var player := _game.players[0]
	var rig := _game.get_node("CameraRig1") as CameraRig
	while true:
		for kind in KINDS:
			for pose in (3 if kind == &"weaver" else 1):
				if is_instance_valid(_shown):
					_shown.queue_free()
				# The prisoner stands at the middle of the start room, facing the monster 1.6 m ahead.
				rig.yaw = 0.0
				var here := _director.cell_at(player.global_position)
				var middle := RoomDefs.cell_to_world(here)
				player.global_position = Vector3(middle.x, player.global_position.y, middle.z + 1.4)
				_shown = _director.spawn(kind, here)
				# The Weaver stands in the middle so that the wall it climbs is the far one.
				_shown.global_position = Vector3(middle.x, 0.0, middle.z - (0.0 if kind == &"weaver" else 0.9))
				# Monsters face -Z; turn it to face the prisoner.
				_shown.rotation.y = PI
				_shown.set_physics_process(false)
				_label.text = "%s%s" % [kind, " (pose %d)" % pose if kind == &"weaver" else ""]
				if kind == &"weaver":
					(_shown as Weaver)._climb_to(Vector3(0.0, 0.0, -1.0), [0.0, 2.5, 5.0][pose], 1.9)
					(_shown as Weaver)._climb = [0.0, 2.5, 5.0][pose]
				await get_tree().create_timer(seconds).timeout
