class_name Mimic
extends Monster
## Looks like a teammate standing at the edge of the light, in the wrong flame tint and without a name
## tag, and leads the prisoner to a Thief. It keeps about `lead_distance` ahead of the nearest prisoner,
## walks on when they come closer and waits when they fall behind. Its course is planned the way the
## tag mode plans a hunter's: RouteFinder finds the way between the Mimic and the Thief, and Pursuit is
## told to chase the Thief with the Mimic as hunter, so rooms built along the course open toward it.
## At the Thief it stops and, after a while, fades. Touching it snuffs the candle and it fades at once.
##
## Tell: no name tag, a flame of the wrong colour. Survive: do not follow it.

@export_group("Mimic")
@export var lead_speed := 2.3
## It stays about this many metres ahead of the nearest prisoner.
@export var lead_distance := 5.5
## It waits for a prisoner farther behind than this.
@export var wait_distance := 12.0
## Seconds it stands by the Thief before it fades.
@export_range(1.0, 60.0, 1.0, "suffix:s") var linger_seconds := 12.0
## Seconds without any Thief to lead to before it gives up and fades.
@export_range(1.0, 60.0, 1.0, "suffix:s") var patience_seconds := 8.0

enum State { LEAD, AT_THIEF }

var _state := State.LEAD
var _thief: Thief
var _route: Array[Vector2i] = []
var _route_timer := 0.0
var _linger := 0.0
var _idle := 0.0


func _init() -> void:
	move_speed = 2.3


func build_model() -> Node3D:
	var body := Node3D.new()
	# A teammate's colour, as a prisoner would see one.
	var slot := 0
	if not director.players.is_empty():
		slot = (director.players[0].slot + 1) % Player.SLOT_COLORS.size()
	var color: Color = Player.SLOT_COLORS[slot]
	body.add_child(part(CapsuleMesh.new(), color, Vector3(0.0, 0.8, 0.0)))
	# A candle with the wrong flame.
	body.add_child(part(box(Vector3(0.04, 0.12, 0.04)), Color(0.9, 0.88, 0.8), Vector3(0.38, 0.65, -0.35)))
	body.add_child(part(ball(0.05), Color(0.4, 1.0, 0.5), Vector3(0.38, 0.77, -0.35), 3.0))
	return body


func _exit_tree() -> void:
	_stop_pursuit()


func on_fall() -> void:
	_stop_pursuit()


func on_hit(_player: Player) -> void:
	fade_out(0.3)


func _act(delta: float) -> void:
	if not is_instance_valid(_thief) or _thief.is_queued_for_deletion() or _thief._falling:
		_thief = _find_thief()
		if _thief == null:
			_idle += delta
			if _idle >= patience_seconds:
				fade_out()
			return
	_idle = 0.0
	if director.pursuit and director.pursuit.hunter != self:
		director.pursuit.set_chase(self, [_thief])
	match _state:
		State.LEAD:
			_lead(delta)
		State.AT_THIEF:
			_linger += delta
			if _linger >= linger_seconds:
				fade_out()


func _lead(delta: float) -> void:
	if cell == _thief.cell or director.offset(global_position, _thief.global_position).length() < 2.0:
		_state = State.AT_THIEF
		return
	var prisoner := nearest_player()
	var to_prisoner := director.offset(global_position, prisoner.global_position)
	if to_prisoner.length() > lead_distance and to_prisoner.length() <= wait_distance:
		face(to_prisoner.normalized(), delta)
		return
	if to_prisoner.length() > wait_distance:
		return
	var next: Variant = _next_room()
	if next != null:
		go_to(next, RoomDefs.cell_to_world(next), lead_speed, delta)


## The room to walk into next along the course to the Thief, or null when the way is not built yet.
func _next_room() -> Variant:
	_route_timer -= get_physics_process_delta_time()
	var here := _route.find(cell)
	if _route_timer <= 0.0 or here < 0:
		_route_timer = 1.0
		_route = RouteFinder.find(director.grid, cell, _thief.cell)
		here = _route.find(cell)
	if here < 0 or here + 1 >= _route.size():
		return null
	var next := _route[here + 1]
	for side in RoomDefs.SIDE_COUNT:
		if director.grid.neighbor(cell, side) == next and director.can_pass(cell, side):
			return next
	return null


func _find_thief() -> Thief:
	for monster in director.monsters:
		if monster is Thief and not monster._falling:
			return monster
	return null


func _stop_pursuit() -> void:
	if director != null and director.pursuit != null and director.pursuit.hunter == self:
		director.pursuit.stop()
