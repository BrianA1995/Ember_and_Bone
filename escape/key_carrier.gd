class_name KeyCarrier
extends Node3D
## The keys a prisoner carries, drawn on them: hanging at the chest on a cord, or, while the
## hold-out button is down (F, or the left trigger / bumper: the same button that raises the flame),
## held out in front for a teammate to take. A child of the Player; EscapeRun tells it how many.

## Where the keys hang, and where they are held out, relative to the body facing north.
@export var carried_at := Vector3(0.0, 0.3, -0.22)
@export var offered_at := Vector3(-0.32, 0.38, -0.55)
## How fast a key moves between the two, in whole moves a second.
@export var move_speed := 8.0

## True while the keys are held out (and there is at least one).
var offering := false

var _player: Player
var _models: Array[Node3D] = []
var _out := 0.0


func _ready() -> void:
	_player = get_parent() as Player
	top_level = true


## How many keys are carried: one model for each, side by side.
func set_count(count: int) -> void:
	while _models.size() < count:
		var model := KeyPickup.build_model()
		model.scale = Vector3.ONE * 0.9
		add_child(model)
		_models.append(model)
	while _models.size() > count:
		_models.pop_back().queue_free()


func _physics_process(delta: float) -> void:
	var action := GameInput.action(_player.slot, &"hold_flame")
	offering = not _models.is_empty() and InputMap.has_action(action) and Input.is_action_pressed(action)
	_out = move_toward(_out, 1.0 if offering else 0.0, delta * move_speed)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var yaw := (_player.get_node("Visual") as Node3D).rotation.y
	var facing := Basis(Vector3.UP, yaw)
	global_transform = Transform3D(facing, _player.get_global_transform_interpolated().origin + facing * carried_at.lerp(offered_at, _out))
	for i in _models.size():
		_models[i].position = Vector3(i * 0.09 - (_models.size() - 1) * 0.045, 0.0, 0.0)
