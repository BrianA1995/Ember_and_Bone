class_name Warden
extends Monster
## Stands guard at a gate once the team has taken enough keys (see MonsterDirector.warden_after_keys).
## It patrols the rooms around the gate, and goes after any prisoner who comes into them. A touch
## snuffs the candle, makes the prisoner drop a key they carry on the spot (anyone can pick it up) and
## sends them off to a room far away. It leaves with its gate: when the gate goes, so does the Warden.
##
## Tell: heavy footsteps, chains. Survive: lure it away from the gate, then slip round it.

@export_group("Warden")
## How many rooms from the gate it patrols and chases.
@export_range(1, 8) var zone_cells := 3
@export var chase_speed := 2.0

## The gate's anchor room (the Director sets it).
var home := Vector2i.ZERO

var _zone: Dictionary = {}
var _zone_timer := 0.0


func _init() -> void:
	move_speed = 1.2
	reach = 1.3
	after_hit_pause = 4.0


func build_model() -> Node3D:
	var body := Node3D.new()
	var iron := Color(0.2, 0.2, 0.24)
	body.add_child(part(box(Vector3(0.9, 1.5, 0.6)), iron, Vector3(0.0, 1.0, 0.0)))
	body.add_child(part(box(Vector3(0.45, 0.45, 0.45)), Color(0.55, 0.52, 0.48), Vector3(0.0, 2.0, 0.0)))
	body.add_child(part(box(Vector3(0.3, 0.05, 0.05)), Color(0.9, 0.35, 0.1), Vector3(0.0, 2.02, -0.23), 3.0))
	body.add_child(part(box(Vector3(0.2, 1.2, 0.25)), iron, Vector3(-0.6, 1.0, 0.0)))
	body.add_child(part(box(Vector3(0.2, 1.2, 0.25)), iron, Vector3(0.6, 1.0, 0.0)))
	body.add_child(part(box(Vector3(0.25, 0.5, 0.3)), iron, Vector3(-0.25, 0.25, 0.0)))
	body.add_child(part(box(Vector3(0.25, 0.5, 0.3)), iron, Vector3(0.25, 0.25, 0.0)))
	return body


func _act(delta: float) -> void:
	if director.run == null or not director.run.gate_anchors().has(home):
		fade_out()
		return
	_zone_timer -= delta
	if _zone_timer <= 0.0:
		_zone_timer = 0.5
		_zone = director.reachable(home, zone_cells, crosses_webs)
	var target: Player = null
	var best := INF
	for player in director.players:
		var there := director.cell_at(player.global_position)
		if _zone.has(there) and _zone[there].steps < best:
			best = _zone[there].steps
			target = player
	if target:
		go_to(director.cell_at(target.global_position), target.global_position, chase_speed, delta)
	else:
		wander(move_speed, delta, home, zone_cells)


func on_hit(player: Player) -> void:
	if director.steal_key(player):
		director.drop_key(player.global_position, director.cell_at(player.global_position))
	director.teleport(player)
