class_name MazeView
extends Node3D
## Draws a MazeGrid: one room scene per cell. It only listens, it never changes the grid.
## New rooms rise out of the floor, a blocked doorway gets a wall that rises across it,
## cracking rooms tint, removed rooms sink away.

## Hides ceilings so a top-down camera can see in. Collision is unaffected.
@export var hide_ceilings := true:
	set = set_hide_ceilings
@export var rise_time := 0.4
@export var fall_time := 0.3
@export var rise_depth := 3.5
## How long the blocking wall takes to rise across a doorway.
@export var seal_time := 0.35
## Material laid over a cracking room. Left empty, a warm red is used.
@export var cracking_material: Material
## Test aid: the room pieces have no materials yet, so walls are coloured in code
## to stand out from the floor. Turn off once the pieces are properly textured.
@export var color_walls := true
@export var wall_color := Color(0.22, 0.24, 0.3)
## The colour of a special room's furnishings (altars, plinths, bones), also a test aid.
@export var prop_color := Color(0.6, 0.55, 0.45)

var _grid: MazeGrid
var _rooms: Dictionary = {}
var _scenes: Dictionary = {}
var _wall_material: StandardMaterial3D
var _prop_material: StandardMaterial3D


func _ready() -> void:
	add_to_group("maze_view")


## Start showing `grid`. Clears anything shown before.
func bind(grid: MazeGrid, reveal: RevealCollapse) -> void:
	clear()
	_grid = grid
	grid.cell_added.connect(_on_cell_added)
	grid.cell_removed.connect(_on_cell_removed)
	grid.side_sealed.connect(_on_side_sealed)
	reveal.cell_cracking.connect(_on_cell_cracking)
	reveal.cell_restored.connect(_on_cell_restored)


func clear() -> void:
	for room in _rooms.values():
		room.queue_free()
	_rooms.clear()


func set_hide_ceilings(value: bool) -> void:
	hide_ceilings = value
	for room in _rooms.values():
		_apply_ceiling(room)


func room_count() -> int:
	var rooms := {}
	for room in _rooms.values():
		rooms[room] = true
	return rooms.size()


## The room node drawn for `cell` (a room bigger than a cell is the same node for each cell it
## covers), or null.
func room_at(cell: Vector2i) -> Node3D:
	return _rooms.get(cell)


func _on_cell_added(cell: Vector2i) -> void:
	# A room bigger than a cell is announced once per cell but built once.
	if _rooms.has(cell):
		return
	var data := _grid.get_cell(cell)
	var room: Node3D = _scene_for(data.piece).instantiate()
	room.name = "Cell_%d_%d" % [data.anchor.x, data.anchor.y]
	room.position = RoomDefs.cell_to_world(data.anchor)
	room.rotation_degrees.y = 90.0 * data.rotation
	# Rooms are moved by tweens, not physics ticks, so they must not be interpolated.
	room.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(room)
	for member in _grid.room_cells(cell):
		_rooms[member] = room
	_apply_ceiling(room)
	style_room(room)
	if data.cracked:
		crack_floor(room)
	if rise_time > 0.0:
		room.position.y = -rise_depth
		room.create_tween().tween_property(room, "position:y", 0.0, rise_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_cell_removed(cell: Vector2i) -> void:
	var room: Node3D = _rooms.get(cell)
	if room == null:
		return
	_rooms.erase(cell)
	# A room bigger than a cell is told to go once per cell; it only sinks once.
	if room.has_meta(&"sinking"):
		return
	room.set_meta(&"sinking", true)
	for body in room.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0
	var tween := room.create_tween()
	tween.tween_property(room, "position:y", -rise_depth, fall_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(room.queue_free)


## A doorway was blocked: raise two wall pieces across it. They are children of the
## room, so they turn and sink with it.
func _on_side_sealed(cell: Vector2i, side: int) -> void:
	var room: Node3D = _rooms.get(cell)
	if room == null:
		return
	var data := _grid.get_cell(cell)
	var rotation_steps: int = data.rotation
	var local_side := (side + rotation_steps) % RoomDefs.SIDE_COUNT
	# Where this cell sits inside its room, before the room is turned.
	var local_cell := RoomDefs.rotate_offset(cell - data.anchor, (RoomDefs.SIDE_COUNT - rotation_steps) % RoomDefs.SIDE_COUNT)
	var cell_origin := Vector3(local_cell.x, 0.0, local_cell.y) * RoomDefs.CELL_SIZE
	var wall_scene := _scene_at(RoomDefs.WALL_SCENE)
	var spots := RoomDefs.seal_spots(local_side)
	for i in spots.size():
		var wall: Node3D = wall_scene.instantiate()
		wall.name = "Wall_Seal_%d_%d_%d_%d" % [local_cell.x, local_cell.y, local_side, i + 1]
		wall.position = cell_origin + spots[i].pos
		wall.rotation_degrees.y = spots[i].rot
		room.add_child(wall)
		_paint(wall, _wall_paint())
		if seal_time > 0.0:
			wall.position.y = -rise_depth
			wall.create_tween().tween_property(wall, "position:y", 0.0, seal_time) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_cell_cracking(cell: Vector2i) -> void:
	var room: Node3D = _rooms.get(cell)
	if room:
		for mesh in room.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = _cracking_material()


func _on_cell_restored(cell: Vector2i) -> void:
	var room: Node3D = _rooms.get(cell)
	if room:
		for mesh in room.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = null
		style_room(room)


## Swaps a room's plain floor for a CrackedFloor tile in the same place.
func crack_floor(room: Node3D) -> void:
	var plain := room.get_node_or_null("Floor") as Node3D
	if plain == null:
		return
	var tile: Node3D = _scene_at(RoomDefs.CRACKED_FLOOR_SCENE).instantiate()
	tile.name = "Floor"
	tile.transform = plain.transform
	room.remove_child(plain)
	plain.free()
	room.add_child(tile)


## Applies the test colouring to a room: walls (nodes named Wall*) and furnishings
## (nodes named Prop*). Public so other scenes, like the room gallery, can use it.
func style_room(room: Node3D) -> void:
	for child in room.get_children():
		var node_name := str(child.name)
		if node_name.begins_with("Wall"):
			_paint(child, _wall_paint())
		elif node_name.begins_with("Prop"):
			_paint(child, _prop_paint())


func _paint(node: Node, material: Material) -> void:
	if not color_walls:
		return
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = material
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material


func _wall_paint() -> StandardMaterial3D:
	if _wall_material == null:
		_wall_material = StandardMaterial3D.new()
		_wall_material.albedo_color = wall_color
	return _wall_material


func _prop_paint() -> StandardMaterial3D:
	if _prop_material == null:
		_prop_material = StandardMaterial3D.new()
		_prop_material.albedo_color = prop_color
	return _prop_material


func _apply_ceiling(room: Node3D) -> void:
	var ceiling := room.get_node_or_null("Ceiling") as Node3D
	if ceiling:
		ceiling.visible = not hide_ceilings


func _scene_for(piece: StringName) -> PackedScene:
	return _scene_at(RoomDefs.PIECES[piece].scene)


func _scene_at(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


func _cracking_material() -> Material:
	if cracking_material == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color(0.85, 0.35, 0.25)
		cracking_material = fallback
	return cracking_material
