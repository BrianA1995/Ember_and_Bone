class_name Thief
extends Monster
## Hunts a prisoner who carries something: a key, matches, a spare candle. A touch snuffs their candle
## and takes one thing, chosen at random from what they carry; it runs off with it. A flame held up at
## it makes it drop the thing where it stands (and it bolts); if it gets away with it, or fades out with
## its room, the thing goes back into the maze and turns up again later. With nobody carrying anything
## it only wanders.
##
## Tell: what it carries is on its back. Survive: keep out of reach, or stun it.

@export_group("Thief")
## Seconds it runs with its loot before it is gone with it.
@export_range(5.0, 120.0, 1.0, "suffix:s") var flee_seconds := 25.0
@export var run_speed := 2.2
## Seconds it bolts for after being made to drop its loot, before it is gone.
@export_range(1.0, 30.0, 0.5, "suffix:s") var scared_seconds := 5.0

enum State { HUNT, FLEE, SCARED }

var _state := State.HUNT
## What it carries: &"key", the kind of an item, or &"" for nothing.
var _loot: StringName = &""
var _timer := 0.0
var _carried: Node3D
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
	return body


func is_carrying() -> bool:
	return _loot != &""


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
				fade_out()
				return
			_run_away(delta)


func on_hit(player: Player) -> void:
	var loot := director.steal_from(player)
	if loot == &"":
		return
	_loot = loot
	_show_loot(loot)
	_state = State.FLEE
	_timer = flee_seconds


func on_stunned() -> void:
	if is_carrying():
		director.drop_loot(_loot, global_position, cell)
		_loot = &""
		_show_loot(&"")
		_state = State.SCARED
		_timer = scared_seconds


func on_fall() -> void:
	if is_carrying():
		var loot := _loot
		_loot = &""
		director.return_loot(loot)


## The loot on its back: a key, or the item's own model.
func _show_loot(loot: StringName) -> void:
	if _carried:
		_carried.queue_free()
		_carried = null
	if loot == &"":
		return
	_carried = KeyPickup.build_model() if loot == &"key" else ItemDefs.build_model(loot)
	_carried.position = Vector3(0.0, 0.6, 0.3)
	model.add_child(_carried)


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
