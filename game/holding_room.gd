class_name HoldingRoom
extends Node3D
## A sealed room far outside the maze, where eliminated players wait for the round to end.
## It is the maze's own closed-off dead-end room (rooms/dead_end.tscn: floor, ceiling and walls on
## every side, no doorway) made bigger, so there is no way out and no way in. Nothing in the maze
## knows it exists.

const ROOM_SCENE := preload("res://rooms/dead_end.tscn")
## Where it stands: well past any maze (the biggest is 100 cells, 400 m, across).
const LOCATION := Vector3(1000.0, 0.0, 1000.0)
## How much bigger than a normal room it is.
const ROOM_SCALE := 2.0


func _ready() -> void:
	position = LOCATION
	var room := ROOM_SCENE.instantiate() as Node3D
	room.scale = Vector3.ONE * ROOM_SCALE
	add_child(room)


## Where the `index`th person kept here stands (spread out so nobody starts inside another).
func spot(index: int) -> Vector3:
	var spread := RoomDefs.CELL_SIZE * ROOM_SCALE * 0.2
	var column := index % 3 - 1
	var row := index / 3 - 0
	return LOCATION + Vector3(column * spread, 0.0, row * spread - spread * 0.5)
