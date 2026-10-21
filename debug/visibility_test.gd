extends Node
## Plays the real game scene and checks, with real ray casts, whether the player could ever
## SEE the maze change. The player is moved from cell to cell (standing just past each cell
## boundary, which is the instant the maze updates) and, for every room created, doorway
## blocked or room removed, rays are cast from the candle to points on the changed geometry.
## A change counts as seen if a ray gets there unobstructed within the candle's reach.
## Run debug/visibility_test.tscn and read the output for "VISIBILITY TEST".

const NO_EXIT := Vector2i(-9999, -9999)

@export var seeds := 3
@export var steps_per_seed := 100
@export var settle_seconds := 0.4
@export var time_scale := 6.0
## Light on a surface dimmer than this (candle energy is 3.0, so this is under 3% of full
## brightness) is treated as black: the player can't make anything out in it.
@export var min_brightness := 0.08

var _manager: MazeManager
var _player: Player
var _candle: Candle
var _view: MazeView
var _rng := RandomNumberGenerator.new()
var _events: Array[Dictionary] = []
var _checked := {"created": 0, "removed": 0, "blocked": 0}
var _seen: Array[String] = []
var _falls := 0


func _ready() -> void:
	Engine.time_scale = time_scale
	var game: Node = (load("res://main.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().physics_frame
	_manager = game.get_node("MazeManager")
	_player = game.get_node("Player")
	_candle = _player.get_node("Candle")
	_view = _manager.view
	# This test is about the maze changing. A cracked floor would drop the player mid-test (the
	# key alcove always has one, and the test revisits rooms), and has its own test
	# (debug/cracked_floor_test.tscn). Cracked floors only react to bodies in the "players"
	# group, so take the test player out of it; it stays a light source.
	_manager.crack_chance = 0.0
	# Likewise the start room's floor collapsing would drop the player (it has its own test).
	_manager.start_collapse_delay = 0.0
	_player.remove_from_group("players")
	_player.fell.connect(func() -> void: _falls += 1)
	# Rooms must be at their final position when checked, not still rising.
	_view.rise_time = 0.0
	_view.seal_time = 0.0
	_rng.seed = 7
	for run in seeds:
		await _run(2000 + run)
	var total: int = _checked.created + _checked.removed + _checked.blocked
	print("VISIBILITY TEST: %s - %d changes checked (%d rooms created, %d doorways blocked, %d rooms removed), %d seen by the player" % [
		"PASS" if _seen.is_empty() else "FAIL", total, _checked.created, _checked.blocked,
		_checked.removed, _seen.size()])
	print("  candle reach %.1f m (visible out to about %.1f m), dark margin %d cell(s), player falls %d" % [
		_candle.light_range(), _visible_distance(), _player.dark_margin, _falls])
	if _falls > 0:
		print("  WARNING: the player fell %d time(s); respawning rebuilds the maze and spoils the results" % _falls)
	for line in _seen.slice(0, 8):
		print("  SEEN: " + line)
	get_tree().quit(0 if _seen.is_empty() else 1)


func _run(map_seed: int) -> void:
	_manager.build(map_seed)
	_player.reset_position()
	var grid := _manager.grid
	grid.cell_added.connect(func(cell: Vector2i) -> void: _events.append({"kind": "created", "cell": cell}))
	grid.cell_removed.connect(func(cell: Vector2i) -> void: _events.append({"kind": "removed", "cell": cell}))
	grid.side_sealed.connect(func(cell: Vector2i, side: int) -> void:
		_events.append({"kind": "blocked", "cell": cell, "side": side}))
	# Let the starting area appear; it isn't an update the player watches happen.
	for i in 30:
		await get_tree().physics_frame
	_events.clear()
	# Each room is crossed in two stops: just inside it (the instant the maze updates for a
	# new cell), then near its far edge, where the rooms behind have gone dark and get replaced.
	var cell := Vector2i.ZERO
	var target := _pick_exit(grid, cell)
	for step in steps_per_seed:
		if target == NO_EXIT:
			break
		var from := RoomDefs.cell_to_world(cell)
		var to := RoomDefs.cell_to_world(target)
		_stand_at((from + to) * 0.5 + (to - from).normalized() * 0.05)
		await _dwell()
		var further := _pick_exit(grid, target)
		if further == NO_EXIT:
			break
		_stand_at(to + (RoomDefs.cell_to_world(further) - to) * 0.475)
		await _dwell()
		cell = target
		target = further


## A random cell you can walk to from `cell`, or NO_EXIT.
func _pick_exit(grid: MazeGrid, cell: Vector2i) -> Vector2i:
	var exits: Array[Vector2i] = []
	for side in RoomDefs.SIDE_COUNT:
		var next := grid.neighbor(cell, side)
		if grid.is_open(cell, side) and grid.has_cell(next):
			exits.append(next)
	if exits.is_empty():
		return NO_EXIT
	return exits[_rng.randi() % exits.size()]


func _stand_at(world: Vector3) -> void:
	_player.global_position = Vector3(world.x, 0.9, world.z)
	_player.velocity = Vector3.ZERO
	_player.reset_physics_interpolation()
	# The candle is held out to one side of the body; try every way round.
	_player.get_node("Visual").rotation.y = deg_to_rad(90.0 * _rng.randi_range(0, 3))


## Let the maze update, checking what changed on every physics tick.
func _dwell() -> void:
	var ticks := ceili(settle_seconds * Engine.physics_ticks_per_second)
	for tick in ticks:
		await get_tree().physics_frame
		_check_events()


func _check_events() -> void:
	for event in _events:
		_evaluate(event)
	_events.clear()


func _evaluate(event: Dictionary) -> void:
	_checked[event.kind] += 1
	var cell: Vector2i = event.cell
	var owners: Array[Node] = []
	var points: Array[Vector3] = []
	match event.kind:
		"created":
			var room := _view.room_at(cell)
			if room == null:
				return
			owners.append(room)
			points = _cell_points(cell)
		"removed":
			points = _cell_points(cell)
		"blocked":
			var room := _view.room_at(cell)
			if room == null:
				return
			for child in room.get_children():
				if str(child.name).begins_with("Wall_Seal"):
					owners.append(child)
					var wall := child as Node3D
					for y in [0.5, 1.5, 2.5]:
						for along in [-0.4, 0.0, 0.4]:
							points.append(wall.global_transform * Vector3(along, y, 0.0))
	for point in points:
		if _sees(point, owners):
			var distance := (_candle.global_position - point).length()
			_seen.append("%s of cell %s, %.1f m from the candle, player at %s" % [
				event.kind, cell, distance, _player.global_position.snapped(Vector3(0.1, 0.1, 0.1))])
			return


## The distance at which the candle's light drops below `min_brightness`.
func _visible_distance() -> float:
	var distance := 0.0
	while distance < _candle.light_range() and _candle.brightness_at(distance) >= min_brightness:
		distance += 0.05
	return distance


## Could the player see `point`? Only if it is within the candle's light, and a ray from the
## candle gets there unobstructed, or first strikes surface belonging to `owners`.
func _sees(point: Vector3, owners: Array[Node]) -> bool:
	var origin := _candle.global_position + Vector3(0.0, 0.08, 0.0)
	if _candle.brightness_at(origin.distance_to(point)) < min_brightness:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin, point)
	var skip: Array[RID] = [_player.get_rid()]
	query.exclude = skip
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.collider as Node
	for owner in owners:
		if collider == owner or owner.is_ancestor_of(collider):
			return true
	return false


## Points on the floor and walls of a cell to try seeing.
func _cell_points(cell: Vector2i) -> Array[Vector3]:
	var centre := RoomDefs.cell_to_world(cell)
	var points: Array[Vector3] = []
	for x in [-1.5, 0.0, 1.5]:
		for z in [-1.5, 0.0, 1.5]:
			for y in [0.1, 1.5]:
				points.append(centre + Vector3(x, y, z))
	for edge in [-1.9, 1.9]:
		points.append(centre + Vector3(edge, 1.5, 0.0))
		points.append(centre + Vector3(0.0, 1.5, edge))
	return points
