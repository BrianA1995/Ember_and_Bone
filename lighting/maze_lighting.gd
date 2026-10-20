class_name MazeLighting
extends Node
## All world lighting, set up in code: a black void with a trace of cold ambient light,
## a faint dark fog so distance swallows the edges, and bloom so flames glow.
## There is no sun: the only real light in the maze is the candle (see Candle).
##
## `debug_bright` swaps in flat bright light so the whole maze can be seen while testing.

@export var debug_bright := false:
	set = set_debug_bright
@export_group("The void")
@export var ambient_color := Color(0.05, 0.06, 0.09)
@export_range(0.0, 1.0, 0.01) var ambient_energy := 0.15
@export var fog_color := Color(0.01, 0.01, 0.015)
@export_range(0.0, 0.2, 0.005) var fog_density := 0.03
@export_group("Look")
@export_range(0.5, 2.0, 0.05) var exposure := 1.0
@export_range(0.0, 2.0, 0.05) var glow_strength := 0.9

var _world := WorldEnvironment.new()
var _environment := Environment.new()


func _ready() -> void:
	add_to_group("maze_lighting")
	_world.environment = _environment
	add_child(_world)
	_apply()


func set_debug_bright(value: bool) -> void:
	debug_bright = value
	if is_node_ready():
		_apply()


func _apply() -> void:
	var env := _environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = exposure
	env.glow_enabled = not debug_bright
	env.glow_intensity = glow_strength
	env.glow_bloom = 0.12
	if debug_bright:
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 0.9
		env.fog_enabled = false
	else:
		env.ambient_light_color = ambient_color
		env.ambient_light_energy = ambient_energy
		env.fog_enabled = true
		env.fog_light_color = fog_color
		env.fog_density = fog_density
