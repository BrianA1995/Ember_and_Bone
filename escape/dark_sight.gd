class_name DarkSight
extends Node
## What a prisoner's view looks like without their candle: almost grayscale. A screen effect on
## each player's pane, faded in while their own candle is away, and faded out again while another
## prisoner's burning candle, or a lamp set down, reaches them (that light has its colour, and wins over the grey).
##
## The dim grey light and the vanishing rooms belong to the Player (see Player.set_candle_lit);
## this node only does the colour. Placeholder look: the shader is below.

## How grey the view gets at most (1 is fully grey), and how fast it changes, in whole changes a second.
@export_range(0.0, 1.0, 0.05) var greyness := 0.92
@export var fade_speed := 3.0
## Within this fraction of a candle's reach, its light wins completely; it fades out to the edge.
@export_range(0.1, 1.0, 0.05) var full_colour_within := 0.6

const SHADER := """
shader_type canvas_item;
uniform float grey : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	// A touch of cold blue so the grey is not flat.
	vec3 tinted = vec3(luma) * vec3(0.94, 0.98, 1.06);
	COLOR = vec4(mix(c.rgb, tinted, grey), c.a);
}
"""

var players: Array[Player] = []
## How grey each player's view is now, by position in `players`.
var amount: Array[float] = []

var _materials: Array[ShaderMaterial] = []
## The maze, to find the lamps standing in it.
var _maze: MazeManager


func setup(p_players: Array[Player], split: SplitScreen, p_maze: MazeManager) -> void:
	players = p_players
	_maze = p_maze
	var shader := Shader.new()
	shader.code = SHADER
	for i in players.size():
		var material := ShaderMaterial.new()
		material.shader = shader
		split.picture_at(i).material = material
		_materials.append(material)
		amount.append(0.0)


func _process(delta: float) -> void:
	for i in players.size():
		amount[i] = move_toward(amount[i], target(players[i]), delta * fade_speed)
		_materials[i].set_shader_parameter("grey", amount[i])


## How grey `player`'s view should be: not at all with their own candle burning, fully without it,
## less the closer another burning candle's light is that actually reaches them.
func target(player: Player) -> float:
	if player.is_candle_lit():
		return 0.0
	var grey := greyness
	for other in players:
		if other != player and other.is_candle_lit():
			grey = minf(grey, greyness * (1.0 - _lit_by(other.candle_position(), other.candle_range(), player, [other.get_rid()])))
	if _maze != null:
		for light in _maze.lights():
			var lamp := light as Lamp
			if lamp != null and lamp.light_range() > 0.0:
				grey = minf(grey, greyness * (1.0 - _lit_by(lamp.light_position(), lamp.light_range(), player, [])))
	return grey


## 0-1: how much of a light at `from` that carries `reach` metres reaches `player` (nothing through a wall).
func _lit_by(from: Vector3, reach: float, player: Player, exclude: Array[RID]) -> float:
	var to := player.global_position + Vector3(0.0, 0.4, 0.0)
	var distance := from.distance_to(to)
	if distance >= reach:
		return 0.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = exclude.duplicate()
	skip.append(player.get_rid())
	query.exclude = skip
	if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		return 0.0
	return clampf((reach - distance) / (reach * (1.0 - full_colour_within)), 0.0, 1.0)
