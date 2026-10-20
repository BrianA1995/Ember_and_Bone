class_name Candle
extends Node3D
## A handheld candle built entirely in code: a wax stick, a flame and a flickering warm
## light. The node's origin is the wick. The light reaches `reach_cells` cells along open
## corridors; walls cast shadows, so it never shines around corners or through walls.
##
## Later: shielding or raising the flame (design doc) is a change to `reach_cells` and
## `energy` on this node.

## How far the light carries, in cells (1 = the next room along each corridor).
@export var reach_cells := 1.0:
	set = set_reach_cells
@export var flame_color := Color(1.0, 0.62, 0.28)
@export var energy := 3.0
@export var flicker_amount := 0.18
@export var flicker_speed := 9.0
@export var shadows := true

var _light: OmniLight3D
var _flame: MeshInstance3D
var _noise := FastNoiseLite.new()
var _time := randf() * 100.0


func _ready() -> void:
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_build_stick()
	_build_flame()
	_build_light()


func _process(delta: float) -> void:
	_time += delta * flicker_speed
	var flicker := _noise.get_noise_1d(_time * 10.0)
	_light.light_energy = energy * (1.0 + flicker * flicker_amount * 2.0)
	_light.position.x = flicker * 0.012
	_flame.scale = Vector3(1.0 - flicker * 0.08, 1.0 + flicker * 0.3, 1.0 - flicker * 0.08)


func set_reach_cells(value: float) -> void:
	reach_cells = value
	if _light:
		_light.omni_range = _range()


## How far the light carries, in metres.
func light_range() -> float:
	return _range()


## The distance beyond which the light is too dim to make anything out, in metres.
func visible_distance(min_brightness := 0.08) -> float:
	var distance := 0.0
	while distance < _range() and brightness_at(distance) >= min_brightness:
		distance += 0.05
	return distance


## Roughly how bright the light is `distance` metres away, in light-energy units
## (0 beyond the range). It fades smoothly, so the last stretch of the range is nearly dark.
func brightness_at(distance: float) -> float:
	if _light == null:
		return 0.0
	return energy * pow(clampf(1.0 - distance / _range(), 0.0, 1.0), _light.omni_attenuation)


## Far enough to light the walls of the next room, then fading to nothing. Kept under the
## distance at which the maze changes (see Player.dark_margin) so changes happen unseen.
func _range() -> float:
	return RoomDefs.CELL_SIZE * (reach_cells + 0.5)


func _build_stick() -> void:
	var wax := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.032
	mesh.bottom_radius = 0.038
	mesh.height = 0.26
	wax.mesh = mesh
	wax.position.y = -0.13
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.86, 0.72)
	material.roughness = 0.9
	wax.material_override = material
	add_child(wax)


func _build_flame() -> void:
	_flame = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.035
	mesh.height = 0.11
	_flame.mesh = mesh
	_flame.position.y = 0.05
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.85, 0.5)
	material.emission_enabled = true
	material.emission = flame_color
	material.emission_energy_multiplier = 3.0
	_flame.material_override = material
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.light_color = flame_color
	_light.light_energy = energy
	_light.omni_range = _range()
	_light.omni_attenuation = 1.4
	_light.shadow_enabled = shadows
	_light.shadow_bias = 0.03
	_light.position.y = 0.08
	add_child(_light)
