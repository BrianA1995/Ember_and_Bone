class_name Weaver
extends Monster
## Creeps toward the nearest prisoner, slowly, and spins a web across the doorway behind it each
## time it moves from one room to the next. A web stops prisoners and the other monsters (never the
## Weaver); holding a flame up to it burns it away (see Web). Touching the Weaver snuffs a candle.
##
## Tell: webs across the doorways. Survive: burn a way through, or go round.

@export_group("Weaver")
## How far, in rooms, it can sense a prisoner.
@export_range(1, 10) var sense_cells := 4
## The chance it spins a web in the doorway behind it when it enters a new room.
@export_range(0.0, 1.0, 0.05) var web_chance := 0.7

var _last_cell := Vector2i(-9999, -9999)


func _init() -> void:
	move_speed = 1.1
	crosses_webs = true


func build_model() -> Node3D:
	var body := Node3D.new()
	var grey := Color(0.5, 0.5, 0.46)
	var shape := part(ball(0.35), grey, Vector3(0.0, 0.4, 0.0))
	shape.scale = Vector3(1.0, 0.7, 1.2)
	body.add_child(shape)
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		var leg := part(box(Vector3(0.9, 0.05, 0.05)), grey, Vector3(side * 0.55, 0.35, (i / 2 - 1) * 0.3))
		leg.rotation.z = side * 0.5
		body.add_child(leg)
	body.add_child(part(ball(0.04), Color(0.9, 0.9, 0.2), Vector3(-0.1, 0.5, -0.38), 3.0))
	body.add_child(part(ball(0.04), Color(0.9, 0.9, 0.2), Vector3(0.1, 0.5, -0.38), 3.0))
	return body


func _act(delta: float) -> void:
	_spin_behind()
	var found := director.reachable(cell, sense_cells, true)
	var target: Player = null
	var best := INF
	for player in director.players:
		var there := director.cell_at(player.global_position)
		if found.has(there) and found[there].steps < best:
			best = found[there].steps
			target = player
	if target:
		go_to(director.cell_at(target.global_position), target.global_position, move_speed, delta)
	else:
		wander(move_speed * 0.6, delta)


## Left a room for the next one: maybe close the doorway it came through.
func _spin_behind() -> void:
	if cell == _last_cell:
		return
	var came_from := _last_cell
	_last_cell = cell
	if director.rng.randf() > web_chance:
		return
	for side in RoomDefs.SIDE_COUNT:
		if director.grid.neighbor(cell, side) == came_from:
			director.place_web(cell, side)
