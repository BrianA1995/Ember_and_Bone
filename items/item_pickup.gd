class_name ItemPickup
extends Area3D
## An item lying on a room's floor (see ItemDealer). Whoever walks over it and has room for it takes it
## (`taken`) and it goes; a prisoner whose pack is full leaves it for later. Its look is a placeholder
## built by ItemDefs.build_model.

signal taken(player: Player)

@export var kind: StringName = &"matches"
@export var spin_speed := 1.2
@export var pickup_radius := 0.8

## Called as accepts.call(player) -> bool; false leaves it where it lies.
var accepts := Callable()

var _model: Node3D
var _done := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = pickup_radius
	shape.shape = sphere
	add_child(shape)
	_model = ItemDefs.build_model(kind)
	add_child(_model)


func _process(delta: float) -> void:
	_model.rotation.y += spin_speed * delta


func _physics_process(_delta: float) -> void:
	if _done:
		return
	for body in get_overlapping_bodies():
		if body is Player and body.global_position.distance_to(global_position) <= pickup_radius + 0.6 \
				and (not accepts.is_valid() or accepts.call(body)):
			_done = true
			taken.emit(body)
			queue_free()
			return
