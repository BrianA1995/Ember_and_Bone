extends Node3D
## Shows one cracked floor tile at several stages of spreading, side by side under flat light,
## for tuning how the cracks look (hazards/cracked_floor.gdshader). Nothing here is game logic.
## Run debug/cracked_floor_preview.tscn.

const TILE_SCENE := preload("res://hazards/cracked_floor.tscn")

## How far the cracks have spread on each tile, left to right (0 to 1).
@export var stages: Array[float] = [0.0, 0.35, 0.7, 1.0]
## Metres from the middle of one tile to the next.
@export var spacing := 4.6
## The crack pattern all the tiles share, so the stages can be compared.
@export var pattern := 12.0
## How tall a view the camera has, in metres. Smaller zooms in.
@export var view_height := 10.4


func _ready() -> void:
	_build_lighting()
	for i in stages.size():
		var tile := TILE_SCENE.instantiate() as CrackedFloor
		tile.pattern_seed = pattern
		tile.position = Vector3(i * spacing, 0.0, 0.0)
		add_child(tile)
		# Spread from the middle, as if someone stood there.
		tile.spread_cracks(tile.global_position, stages[i])
	_build_camera()


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


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = view_height
	camera.position = Vector3((stages.size() - 1) * spacing * 0.5, 10.0, 0.0)
	camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	add_child(camera)
