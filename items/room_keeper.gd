class_name RoomKeeper
extends Node3D
## A light that keeps the room it stands in alive, without lighting anything else: a lamp, or a point
## on a line of string. The maze reads it like a player standing in the dark (a light source with no
## radius), but it never makes rooms around a dark player appear at once (see MazeManager).

## Read by the maze.
var light_radius := 0
var change_distance := 0.5
var keep_only := true


func _ready() -> void:
	add_to_group("light_sources")
