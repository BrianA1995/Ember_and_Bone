class_name StringLine
extends Node3D
## A ball of string tied where a prisoner stood. It pays out behind them as they walk, and every room
## it passes through is kept alive (a RoomKeeper in each), so the way back stays. It comes away from the
## prisoner when they tie it off, when it has run through `max_rooms` rooms, or when they fall or are
## carried off (a fall breaks it). Once loose it fades away, and its rooms are let go oldest first as
## it does, so they fade out with it.

signal ran_out
signal tied_off
signal broken

## Rooms the string can pass through before it comes away (change to taste).
@export var max_rooms := 10
@export var step_metres := 0.8
@export var height := 0.08
## Seconds a loose string takes to fade, its rooms going with it.
@export_range(0.5, 60.0, 0.5, "suffix:s") var fade_seconds := 8.0
## A prisoner who moves farther than this (metres) in one tick was carried off, and the string breaks.
@export var jump_metres := 4.0

var owner_player: Player
## True while it is still tied to the prisoner.
var active := true

var _last: Vector3
var _cells: Dictionary = {}
var _material := StandardMaterial3D.new()
var _fading := false
var _fade_age := 0.0
var _released := 0


func start(player: Player) -> void:
	owner_player = player
	_material.albedo_color = ItemDefs.ITEMS[&"string"].color
	_material.emission_enabled = true
	_material.emission = _material.albedo_color
	_material.emission_energy_multiplier = 0.4
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_last = _floor_point(player.global_position)
	_keep(RoomDefs.world_to_cell(_last))
	player.fell.connect(_on_fell)


func tie_off() -> void:
	_let_go(tied_off)


func rooms() -> int:
	return _cells.size()


func _physics_process(delta: float) -> void:
	if _fading:
		_fade(delta)
		return
	if not active or not is_instance_valid(owner_player):
		return
	var here := _floor_point(owner_player.global_position)
	if here.distance_to(_last) > jump_metres:
		_let_go(broken)
		return
	if here.distance_to(_last) < step_metres:
		return
	var cell := RoomDefs.world_to_cell(here)
	if not _cells.has(cell):
		if _cells.size() >= max_rooms:
			_let_go(ran_out)
			return
		_keep(cell)
	_segment(_last, here)
	_last = here


func _on_fell() -> void:
	_let_go(broken)


## The string comes away from the prisoner and starts to fade.
func _let_go(reason: Signal) -> void:
	if not active:
		return
	active = false
	_fading = true
	if is_instance_valid(owner_player) and owner_player.fell.is_connected(_on_fell):
		owner_player.fell.disconnect(_on_fell)
	reason.emit()


func _fade(delta: float) -> void:
	_fade_age += delta
	var done := clampf(_fade_age / fade_seconds, 0.0, 1.0)
	var color := _material.albedo_color
	color.a = 1.0 - done
	_material.albedo_color = color
	# Rooms are let go from the oldest, one after another, as the string fades.
	var keepers := _cells.values()
	var due := int(floor(done * keepers.size()))
	while _released < due:
		if is_instance_valid(keepers[_released]):
			keepers[_released].queue_free()
		_released += 1
	if done >= 1.0:
		queue_free()


func _keep(cell: Vector2i) -> void:
	if _cells.has(cell):
		return
	var keeper := RoomKeeper.new()
	add_child(keeper)
	keeper.global_position = RoomDefs.cell_to_world(cell)
	_cells[cell] = keeper


func _segment(from: Vector3, to: Vector3) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.025, 0.025, from.distance_to(to))
	mesh.mesh = box
	mesh.material_override = _material
	add_child(mesh)
	mesh.global_position = (from + to) * 0.5
	mesh.look_at(to, Vector3.UP)


func _floor_point(at: Vector3) -> Vector3:
	return Vector3(at.x, height, at.z)
