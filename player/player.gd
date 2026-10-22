class_name Player
extends CharacterBody3D
## The test prisoner: moves on the floor plane, carries the candle that lights the maze, and
## falls when the floor disappears under it (see hazards/cracked_floor.gd).
## Speeds follow the design doc (walk 2.5 m/s, sprint 4.5 m/s).
## Movement is relative to the camera (see CameraRig): in top view up is north, in the
## 3D views forward is wherever the camera looks.
##
## Scene layout (player/player.tscn): Visual (the body mesh), CollisionShape3D, Candle,
## CandleCollision, GroundProbe (a RayCast3D pointing down), FloorStamp (hold-to-stamp).

## The body has dropped out of sight through a pit.
signal fell

@export_group("Movement")
@export var walk_speed := 2.5
@export var sprint_speed := 4.5
## How quickly the body turns to face the way it walks (third person).
@export var turn_speed := 12.0

@export_group("Candle and maze")
## How far the candle's light reaches along open corridors, in cells.
@export var candle_reach := 1.0
## Extra cells the maze keeps alive beyond the candle's light. Rooms appear, get blocked and
## disappear in this unlit ring, so the player never sees the maze change. 0 builds rooms
## right at the edge of the light, where the changes can be seen.
@export_range(0, 3) var dark_margin := 1
## Where the candle is held, relative to the body when it faces north: out to the right and
## a little ahead. It swings round with the body, and has its own collision box (CandleCollision)
## so the body is stopped before the candle can go into a wall.
@export var candle_hold := Vector3(0.38, 0.1, -0.35)
## Where the middle of the candle's collision box sits below the wick.
@export var candle_box_drop := 0.07

@export_group("Falling")
## Downward acceleration once the floor is gone, in m/s².
@export var fall_gravity := 20.0
## The fastest the body falls, in m/s.
@export var terminal_speed := 30.0
## How far below the floor the body falls before it counts as lost, in metres.
@export var fall_depth := 12.0
## A fall that lasts longer than this, in seconds, counts as lost too, so a body can never be
## left falling forever.
@export var fall_timeout := 4.0
## How many physics ticks in a row nothing may be holding the body up before it starts to
## fall, so one unlucky tick can't drop it.
@export var fall_after_ticks := 3
## How far below the feet something still counts as holding the body up, in metres.
@export var support_reach := 0.15
## Wake the body in a new room far from where it fell after a fall (the maze builds one). A
## placeholder until falling has real consequences (design doc: steer to a landing spot).
## With this off the body is simply frozen once it has fallen.
@export var respawn_after_fall := true
## Seconds after spawning during which the floor is trusted to be there, so a floor that
## was only just built can't be mistaken for a pit.
@export var spawn_grace := 0.3

## Read by the maze: how many cells around the player exist (reach + margin).
var light_radius := 2
## Read by the maze: rooms further than this from the player (metres) are too dim to see,
## so that is when they get replaced. The candle's visible distance plus the half metre it
## is held out from the body.
var change_distance := 6.0

var _start_position: Vector3
var _stand_height := 0.8
var _rig: CameraRig
var _falling := false
var _fall_speed := 0.0
var _fall_time := 0.0
var _unsupported_ticks := 0
var _grace_left := 0.0

@onready var _visual: Node3D = $Visual
@onready var _candle: Candle = $Candle
@onready var _candle_box: CollisionShape3D = $CandleCollision
@onready var _ground_probe: RayCast3D = $GroundProbe


func _ready() -> void:
	GameInput.ensure_actions()
	add_to_group("players")
	add_to_group("light_sources")
	motion_mode = MOTION_MODE_FLOATING
	_start_position = global_position
	_grace_left = spawn_grace
	# Standing height: the body's feet rest on the floor.
	var body := $CollisionShape3D.shape as CapsuleShape3D
	_stand_height = body.height * 0.5
	light_radius = ceili(candle_reach) + dark_margin
	_candle.reach_cells = candle_reach
	change_distance = _candle.visible_distance() + 0.5
	# Changes happen about `light_radius` cells away; the light (plus the candle being held
	# half a metre out) must stop short of that or the changes become visible.
	if _candle.light_range() + 0.5 > light_radius * RoomDefs.CELL_SIZE:
		push_warning("Player: the candle's light reaches rooms that can still change; raise dark_margin")


func _physics_process(delta: float) -> void:
	if _rig == null:
		_rig = get_tree().get_first_node_in_group("camera_rig") as CameraRig
	_hold_candle()
	if _falling:
		_fall(delta)
	else:
		_walk(delta)


## Back to the start, standing.
func reset_position() -> void:
	global_position = _start_position
	velocity = Vector3.ZERO
	_falling = false
	_fall_speed = 0.0
	_fall_time = 0.0
	_unsupported_ticks = 0
	_grace_left = spawn_grace
	reset_physics_interpolation()


# --- Walking ---------------------------------------------------------------------------

func _walk(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var speed := sprint_speed if Input.is_action_pressed("sprint") else walk_speed
	var facing := _rig.movement_basis if _rig else Basis.IDENTITY
	var direction := facing * Vector3(input.x, 0.0, input.y)
	velocity = direction * speed
	move_and_slide()
	if _grace_left > 0.0:
		_grace_left -= delta
	elif _is_supported():
		_unsupported_ticks = 0
	else:
		_unsupported_ticks += 1
		if _unsupported_ticks >= fall_after_ticks:
			_start_falling()
	if not _falling:
		# The prisoner walks on the floor; keep the body at standing height so nothing can
		# push it up or down.
		global_position.y = _stand_height
	_update_visual(direction, delta)


## Is something holding the body up? Either the ray from the middle of the body finds floor,
## or the body itself rests on something just below it. The second check matters: the floor is
## made of separate slabs, and a ray down the exact seam between two can miss both; and a body
## standing on the edge of a pit, with its middle over the hole, is still held up.
func _is_supported() -> bool:
	_ground_probe.force_raycast_update()
	if _ground_probe.is_colliding():
		return true
	return test_move(global_transform, Vector3(0.0, -support_reach, 0.0))


## Turns the body to face where it is going (or where the camera looks, in first person).
func _update_visual(direction: Vector3, delta: float) -> void:
	var first_person := _rig != null and _rig.is_first_person()
	_visual.visible = not first_person
	if first_person:
		_visual.rotation.y = _rig.yaw
	elif direction.length_squared() > 0.01:
		var goal := atan2(-direction.x, -direction.z)
		_visual.rotation.y = lerp_angle(_visual.rotation.y, goal, 1.0 - exp(-turn_speed * delta))


# --- Falling ---------------------------------------------------------------------------

func _start_falling() -> void:
	_falling = true
	_fall_speed = 0.0
	_fall_time = 0.0


## No control while falling: the body keeps what sideways speed it had and drops. It ends in
## one of three ways: it lands on something (control returns), it falls out of sight, or it
## has been falling too long (both of those count as lost).
func _fall(delta: float) -> void:
	_fall_time += delta
	_fall_speed = minf(_fall_speed + fall_gravity * delta, terminal_speed)
	velocity.y = -_fall_speed
	move_and_slide()
	_update_visual(Vector3.ZERO, delta)
	if _is_supported():
		_land()
	elif global_position.y < -fall_depth or _fall_time > fall_timeout:
		_land_in_the_void()


## The body has come to rest on something: stand up and take control again.
func _land() -> void:
	_falling = false
	_fall_speed = 0.0
	_unsupported_ticks = 0
	velocity = Vector3.ZERO
	global_position.y = _stand_height


## Wakes the body in a new room far from where it fell (the maze builds one), or back at the
## start if there is no maze to ask.
func _land_somewhere_new() -> void:
	var manager := get_tree().get_first_node_in_group("maze_manager") as MazeManager
	if manager == null:
		reset_position()
		return
	var spot := manager.landing_point(global_position)
	reset_position()
	global_position = Vector3(spot.x, _stand_height, spot.z)
	reset_physics_interpolation()


func _land_in_the_void() -> void:
	_falling = false
	fell.emit()
	if respawn_after_fall:
		_land_somewhere_new()
	else:
		set_physics_process(false)


# --- The candle ------------------------------------------------------------------------

## Puts the candle, and the collision box around it, where the body is holding it.
func _hold_candle() -> void:
	var held := Basis(Vector3.UP, _visual.rotation.y) * candle_hold
	_candle.position = held
	_candle_box.position = held - Vector3(0.0, candle_box_drop, 0.0)
	_candle_box.rotation.y = _visual.rotation.y
