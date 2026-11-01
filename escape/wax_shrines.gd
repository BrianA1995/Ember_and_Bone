class_name WaxShrines
extends Node
## Wax shrines (design doc: refill candles once, then go dark). A shrine is a small room with an altar and two
## burning candles. A prisoner who stands in it and holds the interact button for a moment lights every candle
## in the room from the altar: each prisoner there gets their candle back at full (a candle that had burned
## down or been put out is lit again). Then the shrine's candles go out for good.
##
## The shrines are dealt like the key alcoves: after `first_after` rooms have been built one is due, the next
## room that can be a shrine is one, and the next comes `rooms_between` rooms later. How far apart that is
## follows from how long a candle burns (setup), so a short candle gets shrines closer together. A candle that
## never burns down needs none. Nothing here knows about keys or gates; it only asks the maze for rooms.

signal shrine_used(cell: Vector2i, prisoners: Array)

## Rooms built before the first shrine is due, and between one shrine and the next.
var first_after := 40
var rooms_between := 80
## How long the button is held, in seconds. A little less than a match takes to strike (Relighting), so a
## prisoner with matches is lit by the altar first.
@export_range(0.2, 5.0, 0.1, "suffix:s") var hold_seconds := 0.8
## How much of a full candle the altar gives.
@export_range(0.1, 1.0, 0.05) var refill := 1.0
## How many rooms a player builds in a second, about: turns a candle's burning time into a distance between shrines.
@export_range(0.1, 3.0, 0.05) var rooms_per_second := 0.8
## The share of a candle's life that passes between shrines, so there is always one to find before it is gone.
@export_range(0.1, 1.5, 0.05) var life_share := 0.6

var players: Array[Player] = []

const DUE_WEIGHT := 1000.0
const FLAME_COLOR := Color(1.0, 0.62, 0.28)

var _manager: MazeManager
var _grid: MazeGrid
## cell -> {room: Node3D, flames: Array[Node3D], used: bool}
var _shrines: Dictionary = {}
var _held: Dictionary = {}
var _builds := 0
var _next_at := 0
var _rng := RandomNumberGenerator.new()


func setup(p_players: Array[Player], p_manager: MazeManager) -> void:
	players = p_players
	_manager = p_manager
	_manager.maze_rebuilt.connect(restart)
	restart()


## A new maze: no shrines yet, the first one a while off.
func restart() -> void:
	_shrines.clear()
	_held.clear()
	_builds = 0
	_grid = _manager.grid
	_rng.seed = _grid.seed_value + 1
	var life := GameSettings.candle_minutes * 60.0
	rooms_between = maxi(roundi(life * rooms_per_second * life_share), 20)
	first_after = roundi(rooms_between * 0.5)
	_next_at = first_after
	if not _grid.cell_added.is_connected(_on_cell_added):
		_grid.cell_added.connect(_on_cell_added)
		_grid.cell_removed.connect(_on_cell_removed)
	_update_weights()


func _physics_process(delta: float) -> void:
	for player in players:
		var shrine: Dictionary = _shrine_of(player)
		if shrine.is_empty() or shrine.used:
			_held.erase(player)
			continue
		if Input.is_action_pressed(GameInput.action(player.slot, &"interact")):
			_held[player] = _held.get(player, 0.0) + delta
			if _held[player] >= hold_seconds:
				_light_from(_cell_of(player))
		else:
			_held[player] = 0.0


## What the prisoner can do at the altar they stand at, with the button named {interact} ("" if nothing).
func hint(player: Player) -> String:
	var shrine: Dictionary = _shrine_of(player)
	if shrine.is_empty():
		return ""
	if shrine.used:
		return "The shrine has gone dark"
	return "Hold {interact}: light your candle at the altar (everyone here)"


## Is there a shrine that has not been used standing at `cell`?
func has_shrine(cell: Vector2i) -> bool:
	return _shrines.has(cell) and not _shrines[cell].used


## Lights the candle of everyone in the shrine at `cell` from the altar, then puts the altar out.
func use(cell: Vector2i) -> void:
	_light_from(cell)


func _light_from(cell: Vector2i) -> void:
	var shrine: Dictionary = _shrines.get(cell, {})
	if shrine.is_empty() or shrine.used:
		return
	shrine.used = true
	var lit: Array[Player] = []
	for player in players:
		if _cell_of(player) == cell:
			player.refill(refill)
			lit.append(player)
			_held.erase(player)
	for flame in shrine.flames:
		if is_instance_valid(flame):
			flame.queue_free()
	shrine.flames.clear()
	shrine_used.emit(cell, lit)


func _shrine_of(player: Player) -> Dictionary:
	return _shrines.get(_cell_of(player), {})


func _cell_of(player: Player) -> Vector2i:
	return _grid.cell_at(player.global_position)


## The next room is a shrine when one is due and there will be candles to light; never otherwise.
func _update_weights() -> void:
	var wanted := GameSettings.candle_minutes > 0 and _builds >= _next_at
	_grid.weights[&"wax_shrine"] = DUE_WEIGHT if wanted else 0.0


func _on_cell_added(cell: Vector2i) -> void:
	var data := _grid.get_cell(cell)
	if data.is_empty() or data.anchor != cell:
		return
	if data.piece == &"wax_shrine":
		_place(cell)
		_next_at = _builds + rooms_between + _rng.randi_range(-roundi(rooms_between * 0.2), roundi(rooms_between * 0.2))
	elif not RoomDefs.is_special(data.piece):
		_builds += 1
	_update_weights()


func _on_cell_removed(cell: Vector2i) -> void:
	_shrines.erase(cell)


## Lights the two candles on the altar.
func _place(cell: Vector2i) -> void:
	var room := _manager.view.room_at(cell)
	if room == null:
		return
	var flames: Array[Node3D] = []
	for holder in [&"PropHolderLeft", &"PropHolderRight"]:
		var at := room.get_node_or_null(NodePath(holder)) as Node3D
		if at != null:
			flames.append(_flame(room, at.position + Vector3(0.0, 0.2, 0.0)))
	_shrines[cell] = {"room": room, "flames": flames, "used": false}


## A burning flame and its small light, as children of the room.
func _flame(room: Node3D, at: Vector3) -> Node3D:
	var flame := Node3D.new()
	flame.name = "AltarFlame"
	flame.position = at
	var mesh := MeshInstance3D.new()
	var drop := SphereMesh.new()
	drop.radius = 0.025
	drop.height = 0.08
	mesh.mesh = drop
	var fire := StandardMaterial3D.new()
	fire.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire.albedo_color = Color(1.0, 0.7, 0.35)
	fire.emission_enabled = true
	fire.emission = FLAME_COLOR
	fire.emission_energy_multiplier = 2.0
	mesh.material_override = fire
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.add_child(mesh)
	var light := OmniLight3D.new()
	light.light_color = FLAME_COLOR
	light.light_energy = 1.4
	light.omni_range = 3.5
	light.shadow_enabled = false
	flame.add_child(light)
	room.add_child(flame)
	return flame
