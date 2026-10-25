class_name MazeView
extends Node3D
## Draws a MazeGrid: one room scene per cell. It only listens, it never changes the grid.
## Rooms appear and vanish at once (with `animate` on they rise out of the floor and sink away, and a
## blocked doorway gets a wall that rises across it); cracking rooms tint.

## Hides ceilings so a top-down camera can see in. Collision is unaffected.
@export var hide_ceilings := true:
	set = set_hide_ceilings
## Off: rooms and walls just appear and vanish. On: they rise and sink over the times below.
@export var animate := false
@export var rise_time := 0.4
@export var fall_time := 0.3
@export var rise_depth := 3.5
## In a wrapping maze, how many cells deep from each edge are also drawn past the opposite edge.
@export var seam_depth := 2
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

## Name prefix of a room's look-only copies past the seam.
const SEAM_COPY := "SeamCopy"

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


## While true, rooms appear and disappear at once instead of rising and sinking. The manager sets
## it for a moment while a player stands in the dark, so they never see a room move.
var instant := false


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
	_add_seam_copies(room, data)
	_apply_ceiling(room)
	style_room(room)
	if data.cracked:
		crack_floor(room)
	if animate and rise_time > 0.0 and not instant:
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
	if instant or not animate:
		room.queue_free()
		return
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
	# The room's seam copies (see _add_seam_copies) get the same wall.
	var copies: Array[Node3D] = [room]
	copies.append_array(_seam_copies(room))
	for copy in copies:
		for i in spots.size():
			var wall: Node3D = wall_scene.instantiate()
			wall.name = "Wall_Seal_%d_%d_%d_%d" % [local_cell.x, local_cell.y, local_side, i + 1]
			wall.position = cell_origin + spots[i].pos
			wall.rotation_degrees.y = spots[i].rot
			copy.add_child(wall)
			if copy != room:
				_look_only(wall)
			_paint(wall, _wall_paint())
			if animate and seal_time > 0.0:
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


## Swaps each of a room's plain floors (nodes named Floor*; a big room has one per cell) for a
## CrackedFloor tile in the same place. Returns the tiles.
func crack_floor(room: Node3D) -> Array[Node3D]:
	var tiles: Array[Node3D] = []
	for plain in room.get_children():
		if not str(plain.name).begins_with("Floor") or plain is CrackedFloor:
			continue
		var tile: Node3D = _scene_at(RoomDefs.CRACKED_FLOOR_SCENE).instantiate()
		tile.name = plain.name
		tile.transform = (plain as Node3D).transform
		room.remove_child(plain)
		plain.free()
		room.add_child(tile)
		tiles.append(tile)
	return tiles


## Applies the test colouring to a room: walls (nodes named Wall*) and furnishings
## (nodes named Prop*). Public so other scenes, like the room gallery, can use it.
func style_room(room: Node3D) -> void:
	for child in room.get_children():
		var node_name := str(child.name)
		if node_name.begins_with(SEAM_COPY):
			style_room(child)
		elif node_name.begins_with("Wall"):
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
	for copy in _seam_copies(room):
		_apply_ceiling(copy)


## In a wrapping maze, a room near an edge is also drawn just beyond the opposite edge, so a
## doorway on that edge looks into the next room instead of into darkness. A copy is look only
## (no collision, a plain floor); the real room is on the other side and is the one you walk into.
## Copies are children of the room, so they rise, sink and turn with it.
func _add_seam_copies(room: Node3D, data: Dictionary) -> void:
	if not _grid.wrap_edges:
		return
	var bounds := _grid.bounds
	var cells := _grid.room_cells(data.anchor)
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if (dx == 0 and dy == 0) or not _near_seam(cells, Vector2i(dx, dy)):
				continue
			var copy: Node3D = _scene_for(data.piece).instantiate()
			copy.name = "%s_%d_%d" % [SEAM_COPY, dx, dy]
			copy.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			var offset := Vector3(dx * bounds.size.x, 0.0, dy * bounds.size.y) * RoomDefs.CELL_SIZE
			# The room is turned, so the offset is measured in its own frame.
			copy.position = offset.rotated(Vector3.UP, -room.rotation.y)
			room.add_child(copy)
			_look_only(copy)


## Turns off everything a node's bodies collide with and are collided by.
func _look_only(node: Node) -> void:
	var bodies := node.find_children("*", "CollisionObject3D", true, false)
	if node is CollisionObject3D:
		bodies.append(node)
	for body in bodies:
		body.collision_layer = 0
		body.collision_mask = 0


## Whether any of `cells` is within `seam_depth` cells of the edge a copy shifted by `shift`
## (-1, 0 or 1 on each axis) would sit beyond: a shift of +1 on x is a copy past the east edge,
## made from a room near the west edge.
func _near_seam(cells: Array, shift: Vector2i) -> bool:
	var bounds := _grid.bounds
	for cell in cells:
		var from_low: Vector2i = cell - bounds.position
		var from_high: Vector2i = bounds.end - Vector2i.ONE - cell
		var x_ok := shift.x == 0 or (from_low.x if shift.x > 0 else from_high.x) < seam_depth
		var y_ok := shift.y == 0 or (from_low.y if shift.y > 0 else from_high.y) < seam_depth
		if x_ok and y_ok:
			return true
	return false


func _seam_copies(room: Node3D) -> Array[Node3D]:
	var copies: Array[Node3D] = []
	for child in room.get_children():
		if str(child.name).begins_with(SEAM_COPY):
			copies.append(child)
	return copies


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
