class_name Moth
extends Monster
## Flutters toward the brightest flame it can sense (a raised flame counts three times as bright as one
## held low) and flies straight into it: the candle goes out and the moth burns up. A suicide run, so
## it only ever hits once. The flame bends toward it as it nears.
##
## Tell: fluttering, a flame leaning toward it. Survive: put the candle away, or shield it.

@export_group("Moth")
## How far, in rooms, it can sense a flame.
@export_range(1, 12) var sense_cells := 5
## How far (degrees) a flame leans toward it, and from how many metres away.
@export_range(0.0, 60.0, 1.0) var lean_degrees := 30.0
@export var lean_range := 8.0
## How close, in metres, it must come to the flame itself (not the body) to fly into it.
@export var flame_reach := 0.7

var _wings: Array[MeshInstance3D] = []
var _time := randf() * TAU
var _leaning: Player


func _init() -> void:
	move_speed = 2.2


func _process(delta: float) -> void:
	if model == null:
		return
	_time += delta * 24.0
	for i in _wings.size():
		_wings[i].rotation.z = (1.0 if i == 0 else -1.0) * sin(_time) * 0.7
	if not _falling:
		model.position.y = 1.2 + sin(_time * 0.12) * 0.15


func _exit_tree() -> void:
	_calm_flame()


func build_model() -> Node3D:
	var body := Node3D.new()
	var dust := Color(0.72, 0.66, 0.55)
	body.add_child(part(CapsuleMesh.new(), dust, Vector3(0.0, 0.0, 0.0)))
	(body.get_child(0) as MeshInstance3D).scale = Vector3(0.15, 0.2, 0.15)
	for side in [-1.0, 1.0]:
		var wing := part(box(Vector3(0.45, 0.02, 0.35)), dust, Vector3(side * 0.22, 0.05, 0.0), 0.3)
		body.add_child(wing)
		_wings.append(wing)
	return body


func on_fall() -> void:
	_calm_flame()


func _act(delta: float) -> void:
	var target := _brightest()
	_lean_flame_of(target)
	if target == null:
		wander(move_speed * 0.5, delta)
		return
	go_to(director.cell_at(target.global_position), target.global_position, move_speed, delta)


## It flies into a flame, not into the body: the candle goes out and the moth is gone.
func _touch() -> void:
	for player in director.players:
		if not player.is_candle_lit():
			continue
		var to := director.offset(player.candle_position(), global_position)
		if Vector2(to.x, to.z).length() <= flame_reach:
			director.hit(self, player)
			burn_up()
			return


## The lit prisoner whose flame draws it most: bright and near.
func _brightest() -> Player:
	var best: Player = null
	var best_score := 0.0
	for player in director.players:
		if not player.is_candle_lit():
			continue
		var distance := director.offset(global_position, player.global_position).length()
		if distance > sense_cells * RoomDefs.CELL_SIZE:
			continue
		var score := (3.0 if player.flame_raised() else 1.0) / (1.0 + distance)
		if score > best_score:
			best_score = score
			best = player
	return best


func _lean_flame_of(target: Player) -> void:
	if target != _leaning:
		_calm_flame()
	_leaning = target
	if target == null:
		return
	var to := director.offset(target.global_position, global_position)
	target.lean_flame(to if to.length() < lean_range else Vector3.ZERO, lean_degrees)


func _calm_flame() -> void:
	if is_instance_valid(_leaning):
		_leaning.lean_flame(Vector3.ZERO)
	_leaning = null
