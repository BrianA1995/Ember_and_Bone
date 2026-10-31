class_name Web
extends StaticBody3D
## A web across a doorway, spun by a Weaver. Solid to prisoners (it has a collision box); the
## MonsterDirector also counts it as a closed door when monsters plan a walk. A prisoner who holds the
## flame up close to it, facing it, burns it away in `burn_seconds`; left alone it rots after `lifetime`.
## Its look is a placeholder built in code: a loose net of pale threads.

@export var lifetime := 45.0
@export_range(0.2, 10.0, 0.1, "suffix:s") var burn_seconds := 1.5
## How near, in metres, the flame has to be.
@export var burn_distance := 1.8
@export var width := 3.2
@export var height := 2.4

var players: Array[Player] = []

var _burn := 0.0
var _threads: Array[MeshInstance3D] = []


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height, 0.15)
	shape.shape = box
	shape.position.y = height * 0.5
	add_child(shape)
	_build_threads()


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	if _flame_at_me():
		_burn += delta
		if _burn >= burn_seconds:
			queue_free()
			return
	else:
		_burn = maxf(_burn - delta * 0.5, 0.0)
	var fraction := 1.0 - _burn / burn_seconds
	for thread in _threads:
		thread.scale = Vector3.ONE * (0.4 + 0.6 * fraction)
		(thread.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.7 + 0.3 * fraction, 0.4 + 0.5 * fraction, 0.55)


func _flame_at_me() -> bool:
	for player in players:
		if not player.flame_raised():
			continue
		var to := global_position + Vector3.UP * height * 0.5 - player.candle_position()
		if to.length() <= burn_distance and player.facing().angle_to(Vector3(to.x, 0.0, to.z)) < deg_to_rad(60.0):
			return true
	return false


func _build_threads() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 1.0, 0.9, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 4:
		_add_thread(Vector3(width, 0.03, 0.03), Vector3(0.0, height * (0.2 + 0.2 * i), 0.0), 0.0, material)
	for i in 5:
		_add_thread(Vector3(0.03, height, 0.03), Vector3(width * (-0.4 + 0.2 * i), height * 0.5, 0.0), 0.0, material)
	_add_thread(Vector3(width * 1.2, 0.03, 0.03), Vector3(0.0, height * 0.5, 0.0), atan2(height, width), material)
	_add_thread(Vector3(width * 1.2, 0.03, 0.03), Vector3(0.0, height * 0.5, 0.0), -atan2(height, width), material)


func _add_thread(size: Vector3, at: Vector3, tilt: float, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var thread := MeshInstance3D.new()
	thread.mesh = mesh
	thread.position = at
	thread.rotation.z = tilt
	thread.material_override = material.duplicate()
	add_child(thread)
	_threads.append(thread)
