class_name CameraRig
extends Node3D
## Three ways to look at the maze: top view, third person, first person.
## V cycles through them, 1 / 2 / 3 pick one directly. Top view hides ceilings; the two
## 3D views show them. In the 3D views the mouse is captured for looking (Esc releases it,
## a click captures it again) and the player moves relative to where the camera faces.
##
## Needs a Camera3D child named "Camera3D". Follows `target`, or the first node in
## `target_group` if none is set.
##
## With several local players each has a rig (player/camera_rig.tscn); `slot` picks the input
## actions it listens to (see GameInput). Only one rig (`uses_mouse`, the player on the
## keyboard) uses the mouse; the others look with a gamepad stick.

signal mode_changed(new_mode: Mode)

enum Mode { TOP, THIRD, FIRST }

@export var mode := Mode.TOP:
	set = set_mode
@export var target_group := &"players"
## Which local player this rig belongs to (0-3).
@export var slot := 0
## Whether this rig turns with the mouse (and captures it in the 3D views).
@export var uses_mouse := true
@export_group("Top view")
@export var top_height := 20.0
@export var top_size := 22.0
@export var top_min_size := 8.0
@export var top_max_size := 60.0
@export var top_follow_speed := 8.0
## A jump of the target further than this, in metres, moves the top view there at once instead
## of sliding across the maze.
@export var snap_distance := 30.0
@export_group("Looking")
@export var mouse_sensitivity := 0.0025
@export var fov := 75.0
## Radians per second at full stick, for gamepad looking.
@export var stick_look_speed := 2.8
@export_group("Third person")
@export var third_distance := 3.2
@export var third_min_distance := 1.5
@export var third_max_distance := 7.0
@export var third_pivot_height := 0.5
## Degrees the camera looks down when third person is chosen (negative = down).
@export var third_start_pitch := -18.0
## How far the camera stays off a wall it is pushed against.
@export var wall_margin := 0.25
@export_group("First person")
@export var eye_height := 0.65

## The body this rig follows (set by whoever builds the rig).
var target: Node3D

## Where the camera faces, in radians. 0 faces north (-Z).
var yaw := 0.0
var pitch := 0.0

## Rotate WASD input by this to get a world direction.
var movement_basis: Basis:
	get:
		return Basis.IDENTITY if mode == Mode.TOP else Basis(Vector3.UP, yaw)

var _camera: Camera3D
var _top_position := Vector3.ZERO


func _ready() -> void:
	add_to_group("camera_rig")
	GameInput.ensure_actions()
	# The rig is positioned every frame from the target's interpolated position.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera = $Camera3D
	# The camera is moved into a split-screen view, out from under this node, so it needs the
	# setting itself. Interpolated, it would glide from the old place to the new one when a player
	# is carried across the maze's edge: a flash of the maze vanishing around the player.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.current = true
	var followed := _find_target()
	if followed:
		var origin := _origin_of(followed)
		_top_position = Vector3(origin.x, top_height, origin.z)
	_apply_mode()


func _process(delta: float) -> void:
	var followed := _find_target()
	if followed == null:
		return
	_look_with_stick(delta)
	var origin := _origin_of(followed)
	match mode:
		Mode.TOP:
			var goal := Vector3(origin.x, top_height, origin.z)
			if _top_position.distance_to(goal) > snap_distance:
				_top_position = goal
			_top_position = _top_position.lerp(goal, 1.0 - exp(-top_follow_speed * delta))
			_camera.global_transform = Transform3D(Basis.from_euler(Vector3(-PI / 2.0, 0.0, 0.0)), _top_position)
		Mode.FIRST:
			_camera.global_transform = Transform3D(_look_basis(), origin + Vector3(0.0, eye_height, 0.0))
		Mode.THIRD:
			_camera.global_transform = Transform3D(_look_basis(), _third_person_position(followed, origin))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(GameInput.action(slot, &"camera_cycle")):
		set_mode(((mode as int) + 1) % Mode.size() as Mode)
	elif event.is_action_pressed(GameInput.action(slot, &"camera_top")):
		set_mode(Mode.TOP)
	elif event.is_action_pressed(GameInput.action(slot, &"camera_third")):
		set_mode(Mode.THIRD)
	elif event.is_action_pressed(GameInput.action(slot, &"camera_first")):
		set_mode(Mode.FIRST)
	elif not uses_mouse:
		return
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch = clampf(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		_on_mouse_button(event)


func set_mode(value: Mode) -> void:
	mode = value
	if is_node_ready():
		_apply_mode()


## Changes the field of view (degrees) of the 3D views, at once.
func set_fov(degrees: float) -> void:
	fov = degrees
	if _camera and mode != Mode.TOP:
		_camera.fov = fov


## The camera, for whoever shows this rig's view (it can be moved into another viewport).
func get_camera() -> Camera3D:
	return _camera


func mode_name() -> String:
	return ["Top view", "Third person", "First person"][mode]


func is_first_person() -> bool:
	return mode == Mode.FIRST


func _apply_mode() -> void:
	if mode == Mode.TOP:
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.size = top_size
		if uses_mouse and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.fov = fov
		_camera.near = 0.05
		pitch = deg_to_rad(third_start_pitch) if mode == Mode.THIRD else 0.0
		if uses_mouse and not get_tree().paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_ceilings()
	mode_changed.emit(mode)


## Ceilings are hidden while any player looks from above (the maze has one set of ceilings).
func _update_ceilings() -> void:
	var from_above := false
	for node in get_tree().get_nodes_in_group("camera_rig"):
		from_above = from_above or (node as CameraRig).mode == Mode.TOP
	get_tree().call_group("maze_view", "set_hide_ceilings", from_above)


## Turns the view with the gamepad's look stick.
func _look_with_stick(delta: float) -> void:
	if mode == Mode.TOP:
		return
	var stick := Input.get_vector(GameInput.action(slot, &"look_left"), GameInput.action(slot, &"look_right"),
			GameInput.action(slot, &"look_up"), GameInput.action(slot, &"look_down"))
	yaw -= stick.x * stick_look_speed * delta
	pitch = clampf(pitch - stick.y * stick_look_speed * delta, deg_to_rad(-85.0), deg_to_rad(85.0))


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		if mode != Mode.TOP and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	var zoom_in := event.button_index == MOUSE_BUTTON_WHEEL_UP
	var zoom_out := event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	if not (zoom_in or zoom_out):
		return
	var factor := 0.9 if zoom_in else 1.1
	if mode == Mode.TOP:
		top_size = clampf(top_size * factor, top_min_size, top_max_size)
		_camera.size = top_size
	elif mode == Mode.THIRD:
		third_distance = clampf(third_distance * factor, third_min_distance, third_max_distance)


func _look_basis() -> Basis:
	return Basis.from_euler(Vector3(pitch, yaw, 0.0))


## Behind the player along the look direction, pulled in if a wall is in the way.
func _third_person_position(target: Node3D, origin: Vector3) -> Vector3:
	var pivot := origin + Vector3(0.0, third_pivot_height, 0.0)
	var desired := pivot + _look_basis() * Vector3(0.0, 0.0, third_distance)
	var query := PhysicsRayQueryParameters3D.create(pivot, desired)
	if target is CollisionObject3D:
		var skip: Array[RID] = [(target as CollisionObject3D).get_rid()]
		query.exclude = skip
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return desired
	var hit_position: Vector3 = hit.position
	return hit_position + (pivot - hit_position).normalized() * wall_margin


func _find_target() -> Node3D:
	if is_instance_valid(target):
		return target
	return get_tree().get_first_node_in_group(target_group) as Node3D


## The target's smoothed position, so the camera doesn't stutter between physics ticks.
func _origin_of(target: Node3D) -> Vector3:
	return target.get_global_transform_interpolated().origin
