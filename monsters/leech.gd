class_name Leech
extends Monster
## Crawls after the nearest prisoner. A touch snuffs the candle and the leech clings to them: they
## walk at `slow_factor` of their speed and cannot sprint until `slow_seconds` are up, then it drops off
## and fades away. The timer is a stand-in: how a leech is shaken off may change later. It cannot be
## stunned while it clings.
##
## Tell: wet crawling. Survive: stay away from it; once it is on you, wait it out.

@export_group("Leech")
## How fast a clinging leech lets the prisoner walk, compared with normal (0.45 is less than half).
@export_range(0.1, 1.0, 0.05) var slow_factor := 0.45
## Seconds it clings.
@export_range(1.0, 120.0, 1.0, "suffix:s") var slow_seconds := 12.0
## How far, in rooms, it can sense a prisoner.
@export_range(1, 12) var sense_cells := 5
## Where it sits on a prisoner, in metres from their middle.
@export var cling_at := Vector3(0.32, 0.55, 0.05)

var _host: Player
var _timer := 0.0


func _init() -> void:
	move_speed = 1.7
	after_hit_pause = 0.0


func build_model() -> Node3D:
	var body := Node3D.new()
	var slime := Color(0.28, 0.06, 0.08)
	var shape := part(ball(0.2), slime, Vector3(0.0, 0.14, 0.0))
	shape.scale = Vector3(0.8, 0.55, 1.7)
	body.add_child(shape)
	body.add_child(part(ball(0.06), Color(0.85, 0.75, 0.6), Vector3(0.0, 0.14, -0.34), 0.6))
	return body


func is_clinging() -> bool:
	return _host != null


func _act(delta: float) -> void:
	if _host != null:
		_cling(delta)
		return
	var target := nearest_player(func(player: Player) -> bool:
		return director.offset(global_position, player.global_position).length() <= sense_cells * RoomDefs.CELL_SIZE)
	if target == null:
		wander(move_speed * 0.5, delta)
	else:
		go_to(director.cell_at(target.global_position), target.global_position, move_speed, delta)


func on_hit(player: Player) -> void:
	_host = player
	_timer = slow_seconds
	player.slow(slow_factor, slow_seconds)


## A leech on a prisoner is out of reach of a flame.
func _flame_held_at_me() -> bool:
	return _host == null and super()


func _cling(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0 or not is_instance_valid(_host):
		_host = null
		fade_out()
		return
	global_position = _host.global_position + cling_at - Vector3(0.0, _host.global_position.y, 0.0)
