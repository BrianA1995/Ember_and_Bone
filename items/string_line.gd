class_name StringLine
extends Node3D
## A ball of string tied where a prisoner stood. It pays out behind them as they walk, up to `max_rooms`
## rooms, and every room it passes through is kept alive (a RoomKeeper in each), so the way back
## stays. Using the string again ties it off; the line stays until the maze is rebuilt.

signal ran_out
signal tied_off

@export var max_rooms := 12
@export var step_metres := 0.8
@export var height := 0.08

var owner_player: Player
var active := true

var _last: Vector3
var _cells: Dictionary = {}
var _material := StandardMaterial3D.new()


func start(player: Player) -> void:
	owner_player = player
	_material.albedo_color = ItemDefs.ITEMS[&"string"].color
	_material.emission_enabled = true
	_material.emission = _material.albedo_color
	_material.emission_energy_multiplier = 0.4
	_last = _floor_point(player.global_position)
	_keep(RoomDefs.world_to_cell(_last))


func tie_off() -> void:
	if active:
		active = false
		tied_off.emit()


func rooms() -> int:
	return _cells.size()


func _physics_process(_delta: float) -> void:
	if not active or not is_instance_valid(owner_player):
		return
	var here := _floor_point(owner_player.global_position)
	if here.distance_to(_last) < step_metres:
		return
	var cell := RoomDefs.world_to_cell(here)
	if not _cells.has(cell) and _cells.size() >= max_rooms:
		active = false
		ran_out.emit()
		return
	_keep(cell)
	_segment(_last, here)
	_last = here


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
