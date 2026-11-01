class_name Sandbox
extends Node3D
## The smallest game there is: one maze, one body, one camera rig, no rules and no screens (main.tscn). It
## wires them the way LocalGame does, by hand: the body lights the maze, the rig follows the body, the body
## knows its rig and its maze. Used by the tests that need a world without a whole game around it.

@onready var maze: MazeManager = $MazeManager
@onready var player: Player = $Player
@onready var rig: CameraRig = $CameraRig


func _ready() -> void:
	rig.target = player
	player.rig = rig
	player.maze = maze
	maze.add_light(player)
