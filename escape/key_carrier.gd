class_name KeyCarrier
extends Node3D
## The key a prisoner has taken out, drawn in their hand (the others stay in the pack, unseen), and
## while the hold-out button is down (F, or the left trigger / bumper: the same button that raises
## the flame) held out in front for a teammate to take. A child of the Player; EscapeRun tells it how
## many keys there are and whether one is in hand.

## Where the key in hand is, and where it is held out, relative to the body facing north.
@export var in_hand_at := Vector3(0.38, 0.2, -0.35)
@export var offered_at := Vector3(-0.32, 0.38, -0.55)
## How fast a key moves between the hand and out in front, in whole moves a second.
@export var move_speed := 8.0

## True while a key in hand is held out.
var offering := false

var _player: Player
var _models: Array[Node3D] = []
var _in_hand := false
var _out := 0.0


func _ready() -> void:
	_player = get_parent() as Player
	top_level = true


## How many keys are carried (one model for each), and whether one of them is in the hand.
func set_state(count: int, in_hand: bool) -> void:
	while _models.size() < count:
		var model := KeyPickup.build_model()
		model.scale = Vector3.ONE * 0.9
		add_child(model)
		_models.append(model)
	while _models.size() > count:
		_models.pop_back().queue_free()
	_in_hand = in_hand and count > 0


func _physics_process(delta: float) -> void:
	var action := GameInput.action(_player.slot, &"hold_flame")
	offering = _in_hand and InputMap.has_action(action) and Input.is_action_pressed(action)
	_out = move_toward(_out, 1.0 if offering else 0.0, delta * move_speed)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var yaw := (_player.get_node("Visual") as Node3D).rotation.y
	global_transform = Transform3D(Basis(Vector3.UP, yaw), _player.get_global_transform_interpolated().origin)
	# Only the item in hand is shown: the first model. The others are in the pack, out of sight.
	for i in _models.size():
		_models[i].visible = _in_hand and i == 0
	if _in_hand:
		_models[0].position = in_hand_at.lerp(offered_at, _out)
