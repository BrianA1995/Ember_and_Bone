class_name KeyPickup
extends Area3D
## A key lying where the maze put it (a key alcove's plinth). Its look is a placeholder built in
## code, like the candle: a gold ring, a shaft and two teeth, turning and bobbing slowly so it is
## easy to spot at the edge of the light. Whoever walks into it picks it up (`taken`) and it goes.
##
## Replace the model later by changing build_model(); nothing else depends on it.

signal taken(player: Player)

## How fast it turns, in radians a second, and how far and fast it bobs.
@export var spin_speed := 1.6
@export var bob_height := 0.05
@export var bob_speed := 2.2
## How close a body has to come to pick it up, in metres.
@export var pickup_radius := 0.8

var _model: Node3D
var _time := randf() * TAU
var _picked := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = pickup_radius
	shape.shape = sphere
	add_child(shape)
	_model = build_model()
	add_child(_model)
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	_model.rotation.y += spin_speed * delta
	_model.position.y = sin(_time * bob_speed) * bob_height


## The placeholder key, about 0.3 m long, standing upright with its ring at the top.
static func build_model(color := Color(1.0, 0.78, 0.3)) -> Node3D:
	var model := Node3D.new()
	model.name = "KeyModel"
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.8
	material.roughness = 0.35
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.5
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.035
	torus.outer_radius = 0.07
	ring.mesh = torus
	ring.rotation.x = PI / 2.0
	ring.position.y = 0.1
	ring.material_override = material
	model.add_child(ring)
	var shaft := MeshInstance3D.new()
	var rod := CylinderMesh.new()
	rod.top_radius = 0.014
	rod.bottom_radius = 0.014
	rod.height = 0.22
	shaft.mesh = rod
	shaft.position.y = -0.03
	shaft.material_override = material
	model.add_child(shaft)
	for i in 2:
		var tooth := MeshInstance3D.new()
		var block := BoxMesh.new()
		block.size = Vector3(0.05, 0.025, 0.014)
		tooth.mesh = block
		tooth.position = Vector3(0.03, -0.1 + i * 0.045, 0.0)
		tooth.material_override = material
		model.add_child(tooth)
	return model


func _on_body_entered(body: Node3D) -> void:
	if _picked or not body is Player:
		return
	_picked = true
	taken.emit(body)
	queue_free()
