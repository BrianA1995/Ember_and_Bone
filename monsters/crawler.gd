class_name Crawler
extends Monster
## Slowly follows the loudest sound it can hear: a running prisoner is loud, a walking one quiet, one
## standing still silent (see MonsterDirector.sounds; a thrown pebble will be another sound). A touch
## snuffs the candle and drags the prisoner off to a room far away in the maze, so the team is split.
##
## Tell: dragging, scraping. Survive: keep quiet, or lead it somewhere with a noise.

@export_group("Crawler")
## How far, in rooms, a full-volume sound carries; quieter ones carry less.
@export_range(1, 12) var hear_cells := 6


func _init() -> void:
	move_speed = 1.4


func build_model() -> Node3D:
	var body := Node3D.new()
	var pale := Color(0.62, 0.58, 0.5)
	var torso := part(CapsuleMesh.new(), pale, Vector3(0.0, 0.3, 0.0))
	torso.scale = Vector3(0.7, 0.55, 0.7)
	torso.rotation.x = PI * 0.5
	body.add_child(torso)
	body.add_child(part(ball(0.2), pale, Vector3(0.0, 0.32, -0.75)))
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var limb := part(box(Vector3(0.7, 0.06, 0.06)), pale, Vector3(side * 0.5, 0.2, -0.3 + (i / 2) * 0.55))
		limb.rotation.y = side * 0.4
		body.add_child(limb)
	return body


func _act(delta: float) -> void:
	var heard := _loudest()
	if heard.is_empty():
		wander(move_speed * 0.5, delta)
		return
	var there: Vector3 = heard.position
	go_to(director.cell_at(there), there, move_speed, delta)


func on_hit(player: Player) -> void:
	director.teleport(player)


## The sound that reaches it best, or {}.
func _loudest() -> Dictionary:
	var best := {}
	var best_score := 0.0
	for sound in director.sounds():
		var distance := director.offset(global_position, sound.position).length()
		if distance > hear_cells * RoomDefs.CELL_SIZE * sound.loudness:
			continue
		var score: float = sound.loudness / (1.0 + distance)
		if score > best_score:
			best_score = score
			best = sound
	return best
