extends Node3D
## Lays out every room in RoomDefs.PIECES side by side, each labelled, under flat light and
## viewed from above, for checking how the rooms look. Nothing here is game logic.
## Run debug/room_gallery.tscn.

## Rooms per row.
@export var columns := 5
## Metres from the middle of one room to the next.
@export var spacing := 5.0
## How tall a view the camera has, in metres. Smaller zooms in.
@export var view_height := 15.5


func _ready() -> void:
	_build_lighting()
	# The maze's view already knows how to colour rooms for testing; borrow it.
	var painter := MazeView.new()
	var index := 0
	for piece in RoomDefs.PIECES:
		var room := (load(RoomDefs.PIECES[piece].scene) as PackedScene).instantiate() as Node3D
		room.position = Vector3((index % columns) * spacing, 0.0, floori(float(index) / columns) * spacing)
		add_child(room)
		painter.style_room(room)
		if RoomDefs.always_cracked(piece):
			painter.crack_floor(room)
		var ceiling := room.get_node_or_null("Ceiling") as Node3D
		if ceiling:
			ceiling.visible = false
		_add_label(room.position, str(piece))
		index += 1
	painter.free()
	_build_camera(index)


func _add_label(room_position: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text.replace("_", " ")
	label.font_size = 56
	label.pixel_size = 0.01
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	label.position = room_position + Vector3(0.0, 0.2, 2.45)
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


func _build_camera(room_count: int) -> void:
	var rows := ceili(float(room_count) / columns)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = view_height
	camera.position = Vector3((mini(room_count, columns) - 1) * spacing * 0.5, 10.0, (rows - 1) * spacing * 0.5)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(camera)
