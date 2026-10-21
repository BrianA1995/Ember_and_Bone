extends Node3D
## Lays out every room in RoomDefs.PIECES side by side, each labelled, under flat light and
## viewed from above, for checking how the rooms look. Nothing here is game logic.
## Run debug/room_gallery.tscn.

## Rooms per row.
@export var columns := 5
## Metres of empty floor between rooms.
@export var gap := 1.5


func _ready() -> void:
	_build_lighting()
	# The maze's view already knows how to colour rooms for testing; borrow it.
	var painter := MazeView.new()
	var index := 0
	var cursor := Vector2.ZERO
	var row_depth := 0.0
	var extent := Vector2.ZERO
	for piece in RoomDefs.PIECES:
		var cells: Dictionary = RoomDefs.PIECES[piece].get("cells", {Vector2i.ZERO: 0})
		var size := _footprint_size(cells)
		if index % columns == 0 and index > 0:
			cursor = Vector2(0.0, cursor.y + row_depth + gap)
			row_depth = 0.0
		var room := (load(RoomDefs.PIECES[piece].scene) as PackedScene).instantiate() as Node3D
		# The room's origin cell is the top-left cell of its footprint unless it has cells above or left of it.
		var low := _footprint_low(cells)
		room.position = Vector3(cursor.x + RoomDefs.CELL_SIZE * 0.5 - low.x * RoomDefs.CELL_SIZE, 0.0,
				cursor.y + RoomDefs.CELL_SIZE * 0.5 - low.y * RoomDefs.CELL_SIZE)
		add_child(room)
		painter.style_room(room)
		if RoomDefs.always_cracked(piece):
			painter.crack_floor(room)
		var ceiling := room.get_node_or_null("Ceiling") as Node3D
		if ceiling:
			ceiling.visible = false
		_add_label(Vector3(cursor.x + size.x * 0.5, 0.2, cursor.y + size.y + 0.3), str(piece))
		extent = Vector2(maxf(extent.x, cursor.x + size.x), maxf(extent.y, cursor.y + size.y + 0.8))
		cursor.x += size.x + gap
		row_depth = maxf(row_depth, size.y + 0.8)
		index += 1
	painter.free()
	_build_camera(extent)


## Width and depth, in metres, of the cells a room covers.
func _footprint_size(cells: Dictionary) -> Vector2:
	var low := _footprint_low(cells)
	var high := Vector2i(-1000, -1000)
	for offset in cells:
		high = Vector2i(maxi(high.x, offset.x), maxi(high.y, offset.y))
	return Vector2(high - low + Vector2i.ONE) * RoomDefs.CELL_SIZE


func _footprint_low(cells: Dictionary) -> Vector2i:
	var low := Vector2i(1000, 1000)
	for offset in cells:
		low = Vector2i(mini(low.x, offset.x), mini(low.y, offset.y))
	return low


func _add_label(at: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text.replace("_", " ")
	label.font_size = 56
	label.pixel_size = 0.01
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = at
	label.no_depth_test = true
	add_child(label)


func _build_lighting() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.05, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.7
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70.0, 20.0, 0.0)
	add_child(sun)


func _build_camera(extent: Vector2) -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(extent.y, extent.x * 9.0 / 16.0) + 2.0
	camera.position = Vector3(extent.x * 0.5, 10.0, extent.y * 0.5)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(camera)
