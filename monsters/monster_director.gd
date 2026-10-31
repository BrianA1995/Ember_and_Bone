class_name MonsterDirector
extends Node
## Puts monsters in the maze and gives them what they need to live in it: the map of rooms they may
## walk, what the players are doing, and a way to hurt them. A monster (monsters/monster.gd) is a
## Node3D that asks this node about the world; this node knows nothing about how any one monster
## behaves. It sits on top of the maze like the other layers (MazeManager and its scripts know nothing
## about it) and, for the few things only the escape run knows (keys, gates), asks the EscapeRun.
##
## Every monster snuffs the candle of the prisoner it hits (Player.snuff) and then does its own thing
## (Monster.on_hit). Nothing here kills anyone. Monsters live only in rooms that exist: when the room
## under one goes dark it falls, and the Director sends another a little later.
##
## Pressure: after `grace_seconds` one monster is added every `spawn_interval` until the limit is
## reached; the limit grows with the players and with the keys the team has taken. Monsters are
## placed in the dark ring, where the player cannot see a room being built.

signal player_hit(monster: Monster, player: Player)

@export var enabled := true
@export_group("Pressure")
## Seconds after the run starts before the first monster.
@export_range(0.0, 120.0, 1.0, "suffix:s") var grace_seconds := 20.0
## Seconds between one monster being added and the next.
@export_range(1.0, 60.0, 0.5, "suffix:s") var spawn_interval := 8.0
## How many monsters at once, by number of players ({up_to, max}); every two keys taken add one.
@export var limits: Array[Dictionary] = [{"up_to": 1, "max": 3}, {"up_to": 4, "max": 5}, {"up_to": 8, "max": 9}]
## How close, in cells, a new monster may be placed to a prisoner. Rooms nearer than 2 are in the light.
@export_range(1, 6) var spawn_min_cells := 2
@export_range(2, 10) var spawn_max_cells := 4
## How likely each kind is to be picked (a kind missing from here is never spawned at random). The
## Warden is not picked: it comes to a gate (see _spawn_wardens).
@export var weights := {&"lurker": 4.0, &"thief": 2.0, &"weaver": 2.0, &"crawler": 3.0, &"moth": 3.0}
@export_group("Hits")
## Seconds after a hit during which the same prisoner cannot be hit again, so a pile of monsters is not one long snuff.
@export_range(0.0, 20.0, 0.5, "suffix:s") var hit_immunity := 4.0
@export_group("Wardens")
## Keys the team must have taken before a Warden stands at a gate.
@export_range(0, 10) var warden_after_keys := 2

var players: Array[Player] = []
var monsters: Array[Monster] = []
var grid: MazeGrid
var manager: MazeManager
## The escape run, for what only it knows (keys and gates); null in a game without one.
var run: EscapeRun
## Seconds since the maze was built.
var elapsed := 0.0

## For anything a monster decides by chance, so a maze's monsters repeat for the same seed.
var rng := RandomNumberGenerator.new()
var _spawn_timer := 0.0
var _immune: Dictionary = {}
## Doorways closed by a web: canonical key (see _web_key) -> Web.
var _webs: Dictionary = {}
## Sounds the players and the world made lately: {position, loudness, left}.
var _noises: Array[Dictionary] = []


## Starts watching `p_manager`'s maze for `p_players`. `p_run` is optional.
func setup(p_players: Array[Player], p_manager: MazeManager, p_run: EscapeRun = null) -> void:
	players = p_players
	manager = p_manager
	run = p_run
	manager.maze_rebuilt.connect(_on_maze_rebuilt)
	_on_maze_rebuilt()


func _on_maze_rebuilt() -> void:
	for monster in monsters:
		monster.queue_free()
	monsters.clear()
	_webs.clear()
	_noises.clear()
	_immune.clear()
	for player in players:
		player.relight()
	grid = manager.grid
	grid.cell_removed.connect(_on_cell_removed)
	rng.seed = grid.seed_value + 77
	elapsed = 0.0
	_spawn_timer = grace_seconds


func _physics_process(delta: float) -> void:
	if grid == null:
		return
	elapsed += delta
	for player in _immune.keys():
		_immune[player] -= delta
		if _immune[player] <= 0.0:
			_immune.erase(player)
	for noise in _noises:
		noise.left -= delta
	_noises = _noises.filter(func(noise: Dictionary) -> bool: return noise.left > 0.0)
	if not enabled:
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = spawn_interval
	_spawn_wardens()
	if monsters.size() < limit():
		_spawn_random()


## How many monsters there may be at once now.
func limit() -> int:
	var base: int = limits[-1].max
	for entry in limits:
		if players.size() <= entry.up_to:
			base = entry.max
			break
	return base + (run.keys_collected / 2 if run else 0)


# --- Spawning --------------------------------------------------------------------------

## Every kind of monster, by name.
static func kinds() -> Dictionary:
	return {
		&"lurker": Lurker,
		&"thief": Thief,
		&"weaver": Weaver,
		&"crawler": Crawler,
		&"moth": Moth,
		&"warden": Warden,
	}


## Puts a monster of `kind` in `cell`, whether or not it suits the place. Returns it.
func spawn(kind: StringName, cell: Vector2i) -> Monster:
	var monster: Monster = kinds()[kind].new()
	monster.director = self
	monster.position = RoomDefs.cell_to_world(cell)
	add_child(monster)
	monsters.append(monster)
	monster.tree_exited.connect(func() -> void: monsters.erase(monster))
	return monster


func _spawn_random() -> void:
	var kinds: Array = weights.keys()
	var cells := _spawn_cells()
	if kinds.is_empty() or cells.is_empty():
		return
	for attempt in 8:
		var kind: StringName = _pick_kind(kinds)
		var cell: Vector2i = cells[rng.randi() % cells.size()]
		var monster := spawn(kind, cell)
		if monster.suits(cell):
			return
		monsters.erase(monster)
		monster.queue_free()


func _pick_kind(kinds: Array) -> StringName:
	var total := 0.0
	for kind in kinds:
		total += weights[kind]
	var roll := rng.randf() * total
	for kind in kinds:
		roll -= weights[kind]
		if roll <= 0.0:
			return kind
	return kinds[-1]


## Ordinary rooms in the dark ring around the prisoners, with nobody else's monster in them.
func _spawn_cells() -> Array[Vector2i]:
	var taken := {}
	for monster in monsters:
		taken[monster.cell] = true
	var cells: Array[Vector2i] = []
	for cell in grid.cells():
		var data := grid.get_cell(cell)
		if taken.has(cell) or RoomDefs.is_special(data.piece):
			continue
		var nearest := _cells_to_nearest_player(cell)
		if nearest >= spawn_min_cells and nearest <= spawn_max_cells:
			cells.append(cell)
	return cells


## A Warden stands at every gate once the team has taken enough keys.
func _spawn_wardens() -> void:
	if run == null or run.keys_collected < warden_after_keys:
		return
	for anchor in run.gate_anchors():
		var guarded := false
		for monster in monsters:
			if monster is Warden and monster.home == anchor:
				guarded = true
		if not guarded:
			(spawn(&"warden", anchor) as Warden).home = anchor


func _cells_to_nearest_player(cell: Vector2i) -> int:
	var best := 1000
	for player in players:
		var apart := _cell_delta(cell_at(player.global_position), cell)
		best = mini(best, maxi(absi(apart.x), absi(apart.y)))
	return best


func _on_cell_removed(cell: Vector2i) -> void:
	for monster in monsters.duplicate():
		if monster.cell == cell:
			monster.fall()


# --- The world, as monsters see it -----------------------------------------------------

## The cell a point is in (the maze wraps).
func cell_at(position: Vector3) -> Vector2i:
	return grid.wrap_cell(RoomDefs.world_to_cell(position))


## The way from `from` to `to` on the floor plane, the short way round the loop of the maze.
func offset(from: Vector3, to: Vector3) -> Vector3:
	var span := Vector2(grid.bounds.size) * RoomDefs.CELL_SIZE
	return Vector3(_short(to.x - from.x, span.x), 0.0, _short(to.z - from.z, span.y))


## `position` brought back inside the maze when it has walked over the seam.
func wrap_world(position: Vector3) -> Vector3:
	if not grid.wrap_edges:
		return position
	var span := Vector2(grid.bounds.size) * RoomDefs.CELL_SIZE
	var low := Vector2(grid.bounds.position) * RoomDefs.CELL_SIZE - Vector2.ONE * RoomDefs.CELL_SIZE * 0.5
	return Vector3(low.x + fposmod(position.x - low.x, span.x), position.y, low.y + fposmod(position.z - low.y, span.y))


## Can you walk from `cell` out through `side`? Both rooms must exist and be open to each other;
## a web across the doorway stops you unless `through_webs`.
func can_pass(cell: Vector2i, side: int, through_webs := false) -> bool:
	if not grid.is_open(cell, side):
		return false
	if not grid.is_open(grid.neighbor(cell, side), RoomDefs.opposite(side)):
		return false
	return through_webs or not has_web(cell, side)


## The rooms reachable from `from` in at most `depth` steps: {cell: {"first": the room to step into
## first, "steps": how many steps}}. `from` itself is there with 0 steps.
func reachable(from: Vector2i, depth: int, through_webs := false) -> Dictionary:
	var found := {from: {"first": from, "steps": 0}}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var here: Vector2i = queue[head]
		head += 1
		var info: Dictionary = found[here]
		if info.steps >= depth:
			continue
		for side in RoomDefs.SIDE_COUNT:
			if not can_pass(here, side, through_webs):
				continue
			var next := grid.neighbor(here, side)
			if found.has(next):
				continue
			found[next] = {"first": next if info.steps == 0 else info.first, "steps": info.steps + 1}
			queue.append(next)
	return found


## The room to step into to get from `from` toward `to`, or null when `to` can't be reached in `depth` steps.
func next_step(from: Vector2i, to: Vector2i, depth := 14, through_webs := false) -> Variant:
	if from == to:
		return from
	var found := reachable(from, depth, through_webs)
	return found[to].first if found.has(to) else null


## The room to step into to get from `from` away from the points in `threats`: the reachable room
## (within `depth` steps) farthest from the nearest of them. Null if there is nowhere to go.
func step_away(from: Vector2i, threats: Array[Vector2i], depth := 8, through_webs := false) -> Variant:
	var found := reachable(from, depth, through_webs)
	var best: Variant = null
	var best_distance := -1.0
	for cell in found:
		var distance := 1000.0
		for threat in threats:
			distance = minf(distance, _cell_delta(threat, cell).length())
		if distance > best_distance and found[cell].steps > 0:
			best_distance = distance
			best = found[cell].first
	return best


## The rooms in a straight line from `cell` out through `side` that can be walked along with no wall
## in the way, up to `longest` of them (not counting `cell`). Open space between rooms counts for nothing.
func lane(cell: Vector2i, side: int, longest: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var here := cell
	while cells.size() < longest and can_pass(here, side):
		here = grid.neighbor(here, side)
		cells.append(here)
	return cells


## Is there nothing solid between two points (walls and webs stop the sight)?
func line_clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var skip: Array[RID] = []
	for player in players:
		skip.append(player.get_rid())
	query.exclude = skip
	return get_viewport().world_3d.direct_space_state.intersect_ray(query).is_empty()


# --- Hits ------------------------------------------------------------------------------

## Can `player` be hit now (they were not hit a moment ago)?
func can_hit(player: Player) -> bool:
	return not _immune.has(player)


## `monster` hits `player`: the candle goes out. Returns false (and does nothing) if they were hit lately.
func hit(monster: Monster, player: Player) -> bool:
	if not can_hit(player):
		return false
	_immune[player] = hit_immunity
	player.snuff()
	player_hit.emit(monster, player)
	monster.on_hit(player)
	return true


## Moves a prisoner to a new room far away; the maze grows around them there.
func teleport(player: Player) -> void:
	var spot := manager.landing_point(player.global_position)
	player.warp_to(Vector3(spot.x, player.global_position.y, spot.z))


# --- Webs ------------------------------------------------------------------------------

func has_web(cell: Vector2i, side: int) -> bool:
	return _webs.has(_web_key(cell, side))


## Closes the doorway of `cell` on `side` with a web. Does nothing if there is one or no room.
func place_web(cell: Vector2i, side: int) -> void:
	var key := _web_key(cell, side)
	var room := manager.view.room_at(cell)
	if room == null or _webs.has(key) or not can_pass(cell, side, true):
		return
	var web := Web.new()
	web.players = players
	room.add_child(web)
	web.global_position = RoomDefs.cell_to_world(cell) + Vector3(RoomDefs.DIRS[side].x, 0.0, RoomDefs.DIRS[side].y) * RoomDefs.CELL_SIZE * 0.5
	web.global_rotation.y = 0.0 if side % 2 == 0 else PI * 0.5
	_webs[key] = web
	web.tree_exited.connect(func() -> void: _webs.erase(key))


## A doorway has two names, one from each room; this is one name for both (always a north or east side).
func _web_key(cell: Vector2i, side: int) -> Vector3i:
	if side >= 2:
		return _web_key(grid.neighbor(cell, side), RoomDefs.opposite(side))
	return Vector3i(cell.x, cell.y, side)


# --- Sound -----------------------------------------------------------------------------

## Something made a noise `loudness` (0-1) at `position`; monsters that listen can hear it for `seconds`.
func make_noise(position: Vector3, loudness: float, seconds := 2.5) -> void:
	_noises.append({"position": position, "loudness": loudness, "left": seconds})


## Everything that can be heard now: the prisoners (running is loud, walking quiet, standing still
## silent) and the noises made lately. Each is {position, loudness}.
func sounds() -> Array[Dictionary]:
	var heard: Array[Dictionary] = []
	for player in players:
		var speed := player.floor_speed()
		if speed > 0.5:
			heard.append({"position": player.global_position, "loudness": clampf(speed / player.sprint_speed, 0.0, 1.0)})
	heard.append_array(_noises)
	return heard


# --- Keys (the escape run owns them) ---------------------------------------------------

## Does this prisoner carry anything a thief would want?
func carries_something(player: Player) -> bool:
	return run != null and run.keys_held[player.slot] > 0


## Takes a key from `player`. False if they have none (or there is no run).
func steal_key(player: Player) -> bool:
	return run != null and run.take_key_from(player)


## A key lying loose where a monster let it fall, in `cell`'s room.
func drop_key(position: Vector3, cell: Vector2i) -> void:
	if run:
		run.drop_key(position, cell)


## A stolen key that is gone from the maze: it will be found again somewhere new.
func return_key() -> void:
	if run:
		run.key_returned()


# --- Maths -----------------------------------------------------------------------------

## `to` relative to `from` in cells, the short way round the loop.
func _cell_delta(from: Vector2i, to: Vector2i) -> Vector2:
	var size := grid.bounds.size
	if not grid.wrap_edges:
		return Vector2(to - from)
	return Vector2(_short(to.x - from.x, size.x), _short(to.y - from.y, size.y))


## A distance along one axis that is a loop of `span`, as the shortest signed way round.
func _short(delta: float, span: float) -> float:
	if not grid.wrap_edges:
		return delta
	var d := fposmod(delta, span)
	return d - span if d * 2.0 > span else d
