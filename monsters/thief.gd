class_name Thief
extends Monster
## Hunts a prisoner who carries a key. A touch snuffs their candle and takes the key; it runs off with
## it. A flame held up at it makes it drop the key where it stands (and it bolts); if it gets away
## with it, or falls, the key is lost from this place and turns up again somewhere new later. With
## nobody carrying a key it only wanders.
##
## Tell: a gold key on its back once it has one. Survive: keep your key out of reach, or stun it.

@export_group("Thief")
## Seconds it runs with a key before it is gone with it.
@export_range(5.0, 120.0, 1.0, "suffix:s") var flee_seconds := 25.0
@export var run_speed := 2.2
## Seconds it bolts for after being made to drop the key, before it is gone.
@export_range(1.0, 30.0, 0.5, "suffix:s") var scared_seconds := 5.0

enum State { HUNT, FLEE, SCARED }

var _state := State.HUNT
var _carrying := false
var _timer := 0.0
var _key: Node3D
var _away: Variant = null
var _away_timer := 0.0


func _init() -> void:
	move_speed = 2.0


func build_model() -> Node3D:
	var body := Node3D.new()
	var brown := Color(0.22, 0.15, 0.1)
	body.add_child(part(ball(0.32), brown, Vector3(0.0, 0.45, 0.0)))
	body.add_child(part(ball(0.17), Color(0.7, 0.62, 0.55), Vector3(0.0, 0.85, -0.12)))
	body.add_child(part(ball(0.03), Color(1.0, 0.85, 0.2), Vector3(-0.06, 0.88, -0.27), 3.0))
	body.add_child(part(ball(0.03), Color(1.0, 0.85, 0.2), Vector3(0.06, 0.88, -0.27), 3.0))
	body.add_child(part(box(Vector3(0.08, 0.08, 0.7)), brown, Vector3(-0.3, 0.4, -0.25)))
	body.add_child(part(box(Vector3(0.08, 0.08, 0.7)), brown, Vector3(0.3, 0.4, -0.25)))
	_key = KeyPickup.build_model()
	_key.position = Vector3(0.0, 0.6, 0.3)
	_key.visible = false
	body.add_child(_key)
	return body


func _act(delta: float) -> void:
	match _state:
		State.HUNT:
			var target := nearest_player(director.carries_something)
			if target == null:
				wander(move_speed * 0.5, delta)
			else:
				go_to(director.cell_at(target.global_position), target.global_position, move_speed, delta)
		State.FLEE, State.SCARED:
			_timer -= delta
			if _timer <= 0.0:
				fall()
				return
			_run_away(delta)


func on_hit(player: Player) -> void:
	if director.steal_key(player):
		_carrying = true
		_key.visible = true
		_state = State.FLEE
		_timer = flee_seconds


func on_stunned() -> void:
	if _carrying:
		director.drop_key(global_position, cell)
		_carrying = false
		_key.visible = false
		_state = State.SCARED
		_timer = scared_seconds


func on_fall() -> void:
	if _carrying:
		_carrying = false
		director.return_key()


func _run_away(delta: float) -> void:
	_away_timer -= delta
	if _away_timer <= 0.0:
		_away_timer = 0.4
		var threats: Array[Vector2i] = []
		for player in director.players:
			threats.append(director.cell_at(player.global_position))
		_away = director.step_away(cell, threats)
	if _away != null:
		go_to(_away, RoomDefs.cell_to_world(_away), run_speed, delta)
