extends Node
## Plays the escape run by itself, in the real game window (run debug/autoplay.tscn, not headless), to
## try to beat it: it walks the maze with the real input actions, picks up keys and items, relights its
## candle with matches or a spare, holds its flame up at monsters, freezes for a Lurker (or, on purpose,
## sometimes doesn't), uses the lamp, the string and the chalk, and stands in a gate with its keys.
## It steers by what the maze grid says (it does not "see"), so it tests the mechanics, not the eyes.
## Everything it does and everything that happens to it is written to user://autoplay_log.txt.

@export var seconds_limit := 1500.0
@export var speed := 2.0
## The prisoner freezes for a Lurker this often (otherwise it carries on, to see the rush).
@export_range(0.0, 1.0, 0.1) var obey_lurker := 0.5

var _game: LocalGame
var _escape: EscapeRun
var _manager: MazeManager
var _director: MonsterDirector
var _shrines: WaxShrines
var _player: Player
var _rig: CameraRig
var _log: FileAccess
var _clock := 0.0
var _rng := RandomNumberGenerator.new()

var _goal := Vector2i(-9999, -9999)
var _goal_until := 0.0
var _visited: Dictionary = {}
var _stuck := 0.0
var _seen_keys_lost := 0
var _seen_gates_lost := 0
var _last_fall := -999.0
var _web_until := 0.0
var _web_target: Node3D
var _unstick_until := 0.0
var _unstick_side: StringName = &"move_left"
var _last_position := Vector3.ZERO
var _held_actions: Dictionary = {}
var _taps: Array[Dictionary] = []
var _frozen_until := 0.0
var _flame_until := 0.0
var _seen_monsters: Dictionary = {}
var _stats := {"hits": 0, "snuffs": 0, "relights": 0, "falls": 0, "keys": 0, "items": 0, "stuck": 0, "frozen": 0, "rushed": 0, "flames": 0}
var _next_report := 30.0
var _next_item_try := 25.0
var _string_tied_at := -1.0
var _done := false
var _dark_since := -1.0
var _match_hold := 0.0


func _ready() -> void:
	_rng.randomize()
	_log = FileAccess.open("user://autoplay_log.txt", FileAccess.WRITE)
	GameSettings.monsters = true
	GameSettings.game_mode = GameSettings.GameMode.ESCAPE
	GameSettings.player_count = 1
	# A short candle, so every run has to find a wax shrine or a spare candle.
	GameSettings.candle_minutes = 4
	GameInput.configure(1)
	_game = (load("res://game/game.tscn") as PackedScene).instantiate() as LocalGame
	add_child(_game)
	await get_tree().create_timer(1.0).timeout
	_escape = _game.escape
	_manager = _game.get_node("MazeManager")
	_director = _game.get_node("MonsterDirector")
	_shrines = _game.get_node("WaxShrines")
	_player = _game.players[0]
	_rig = _game.rigs[0]
	_last_position = _player.global_position
	_player.snuffed.connect(func() -> void:
		_stats.snuffs += 1
		_dark_since = _clock
		_say("SNUFFED (candle out)"))
	_player.relit.connect(func() -> void:
		_stats.relights += 1
		_say("RELIT after %.0f s in the dark" % (_clock - _dark_since))
		_dark_since = -1.0)
	_player.fell.connect(func() -> void:
		_stats.falls += 1
		_last_fall = _clock
		_say("FELL through the floor from %s" % _cell_of(_player.global_position)))
	_director.player_hit.connect(func(monster: Monster, _p: Player) -> void:
		_stats.hits += 1
		_say("HIT by %s" % _kind(monster)))
	_escape.key_taken.connect(func(_slot: int) -> void:
		_stats.keys += 1
		_say("TOOK A KEY (%d of %d)" % [_escape.keys_held[0], _escape.keys_per_prisoner]))
	_player.burned_out.connect(func() -> void: _say("the candle BURNED DOWN"))
	_shrines.shrine_used.connect(func(cell: Vector2i, _who: Array) -> void: _say("filled the candle at the shrine in %s" % cell))
	_escape.run_won.connect(func(_escaped: Array) -> void: _finish("WON the run"))
	_escape.run_lost.connect(func(reason: String) -> void: _finish("LOST the run: " + reason))
	Engine.time_scale = speed
	_say("start: maze %d, keys needed %d, gates %d, candle %d min" % [GameSettings.maze_size, _escape.keys_required(), _escape.gates_total, GameSettings.candle_minutes])


func _say(text: String) -> void:
	var line := "[%6.1f s | %3.0f fps] %s" % [_clock, Engine.get_frames_per_second(), text]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


func _kind(monster: Monster) -> String:
	return str(monster.get_script().get_global_name())


func _finish(text: String) -> void:
	if _done:
		return
	_done = true
	_say(text)
	_say("totals: %s" % str(_stats))
	_release_all()
	var shot := get_viewport().get_texture().get_image()
	shot.save_png("user://autoplay_end.png")


func _physics_process(delta: float) -> void:
	if _escape == null or _done:
		return
	_clock += delta
	if _clock > seconds_limit:
		_finish("TIMED OUT after %.0f s" % _clock)
		return
	_run_taps(delta)
	if _escape.keys_lost != _seen_keys_lost or _escape.gates_lost != _seen_gates_lost:
		_say("LOSS: keys lost %d (was %d), gates lost %d (was %d); player in %s, candle %s, last fall %.0f s ago, key held %d, rooms %d" % [
				_escape.keys_lost, _seen_keys_lost, _escape.gates_lost, _seen_gates_lost, _cell_of(_player.global_position),
				"lit" if _player.is_candle_lit() else "OUT", _clock - _last_fall, _escape.keys_held[0], _manager.view.room_count()])
		_seen_keys_lost = _escape.keys_lost
		_seen_gates_lost = _escape.gates_lost
	_watch_monsters()
	_handle_dark(delta)
	_maybe_use_items()
	_report()
	var cell := _cell_of(_player.global_position)
	_visited[cell] = _clock
	_check_stuck(delta)
	if _clock < _frozen_until:
		_release(&"move_forward")
		_release(&"sprint")
		return
	_steer(cell, delta)


# --- Looking after itself ---------------------------------------------------------------

func _cell_of(position: Vector3) -> Vector2i:
	return _director.cell_at(position)


func _press(action_name: StringName, strength := 1.0) -> void:
	var action := GameInput.action(0, action_name)
	if not _held_actions.has(action):
		Input.action_press(action, strength)
		_held_actions[action] = true


func _release(action_name: StringName) -> void:
	var action := GameInput.action(0, action_name)
	if _held_actions.has(action):
		Input.action_release(action)
		_held_actions.erase(action)


func _release_all() -> void:
	for action in _held_actions.keys():
		Input.action_release(action)
	_held_actions.clear()


## Presses a button for a moment (so it counts as one press).
func _tap(action_name: StringName, seconds := 0.12) -> void:
	_press(action_name)
	_taps.append({"action": action_name, "left": seconds})


func _run_taps(delta: float) -> void:
	for tap in _taps.duplicate():
		tap.left -= delta
		if tap.left <= 0.0:
			_release(tap.action)
			_taps.erase(tap)


func _report() -> void:
	if _clock < _next_report:
		return
	_next_report += 30.0
	var kinds := {}
	for monster in _director.monsters:
		kinds[_kind(monster)] = kinds.get(_kind(monster), 0) + 1
	_say("status: cell %s, rooms %d, keys held %d/%d collected %d of %d placed, tension %.2f, monsters %s, items %s, %s" % [
			_cell_of(_player.global_position), _manager.view.room_count(), _escape.keys_held[0], _escape.keys_per_prisoner,
			_escape.keys_collected, _escape.keys_placed, _director.tension, str(kinds), str(_escape.bag.summary(0)),
			"candle lit" if _player.is_candle_lit() else "CANDLE OUT"])


# --- Monsters ---------------------------------------------------------------------------

func _watch_monsters() -> void:
	var worst: Monster = null
	for monster in _director.monsters:
		if monster.is_going():
			continue
		if not _seen_monsters.has(monster):
			_seen_monsters[monster] = true
			_say("monster appeared: %s in %s, %.1f m away, lit for us: %s" % [_kind(monster), monster.cell,
					_director.offset(_player.global_position, monster.global_position).length(), _director.is_lit(_player, monster.cell)])
			monster.tree_exiting.connect(func() -> void: _say("monster gone: %s" % _kind(monster)))
		if not _director.is_lit(_player, monster.cell):
			continue
		var distance := _director.offset(_player.global_position, monster.global_position).length()
		if monster is Lurker:
			if _clock >= _frozen_until and not monster.get_meta(&"decided", false):
				monster.set_meta(&"decided", true)
				if _rng.randf() < obey_lurker:
					_frozen_until = _clock + 7.0
					_stats.frozen += 1
					_say("a lurker is in the light: FREEZING (no move, no camera) for 7 s")
				else:
					_stats.rushed += 1
					_say("a lurker is in the light: ignoring it, to see the rush")
		elif distance < 5.0 and (worst == null or distance < _director.offset(_player.global_position, worst.global_position).length()):
			worst = monster
	if worst != null and _clock >= _flame_until:
		_flame_until = _clock + 2.5
		_stats.flames += 1
		_say("holding the flame up at a %s" % _kind(worst))
	if worst != null and _clock < _flame_until:
		_face(_director.offset(_player.global_position, worst.global_position))
		_press(&"hold_flame")
	elif _clock >= _flame_until and _clock >= _web_until:
		_release(&"hold_flame")


# --- The dark -----------------------------------------------------------------------------

func _handle_dark(delta: float) -> void:
	# At a shrine with the candle low, hold the button at the altar.
	if _shrines.has_shrine(_cell_of(_player.global_position)) and _player.wax.fraction() < 0.7:
		_press(&"interact")
		return
	var burnt := _player.is_burnt_out()
	if not _player.is_snuffed() and not burnt:
		_match_hold = 0.0
		if _escape.equipped[0] != 0 and _escape.held_item(0).kind in [&"matches", &"spare_candle"]:
			_escape.equipped[0] = 0
		_release(&"interact")
		return
	var list := _escape.hand_items(0)
	for i in list.size():
		if list[i].kind == &"spare_candle" or (list[i].kind == &"matches" and not burnt):
			_escape.equipped[0] = i
			if list[i].kind == &"matches":
				_press(&"interact")
			elif _match_hold <= 0.0:
				_tap(&"interact")
				_match_hold = 1.0
			_match_hold = maxf(_match_hold - delta, 0.0) if list[i].kind == &"spare_candle" else _match_hold
			return
	_release(&"interact")


# --- Items --------------------------------------------------------------------------------

func _maybe_use_items() -> void:
	# A string tied earlier is tied off after a while.
	if _string_tied_at > 0.0 and _clock - _string_tied_at > 15.0:
		_string_tied_at = -1.0
		_say("tying the string off")
		_tap(&"use_item")
	if _clock < _next_item_try or _player.is_snuffed() or _escape.free_slots(0) < 0:
		return
	_next_item_try = _clock + 20.0
	var list := _escape.hand_items(0)
	for i in list.size():
		var kind: StringName = list[i].kind
		if list[i].type != &"item" or not kind in [&"lamp", &"string", &"chalk"]:
			continue
		_escape.equipped[0] = i
		_say("using %s (%d in the pack)" % [kind, list[i].count])
		_stats.items += 1
		_tap(&"use_item")
		if kind == &"string":
			_string_tied_at = _clock
		elif kind == &"chalk":
			get_tree().create_timer(0.5).timeout.connect(func() -> void:
				_say("the message list opened for the chalk: confirming the first message")
				_tap(&"interact"))
		return


# --- Walking ------------------------------------------------------------------------------

func _check_stuck(delta: float) -> void:
	if _player.global_position.distance_to(_last_position) > 0.25:
		_last_position = _player.global_position
		_stuck = 0.0
		return
	if _clock < _frozen_until or _player.controls_locked:
		return
	_stuck += delta
	if _stuck > 0.8 and _web_until < _clock:
		for web in _director._webs.values():
			if is_instance_valid(web) and _director.offset(_player.global_position, (web as Node3D).global_position).length() < 3.0:
				_web_until = _clock + 4.0
				_web_target = web
				_say("a web is in the way: holding the flame up to burn it")
				break
	if _stuck > 1.2 and _unstick_until < _clock and _web_until < _clock:
		# Sidestep round whatever is in the way (a prop, a pillar), backing off a little first.
		_unstick_until = _clock + 0.9
		_unstick_side = &"move_left" if _rng.randf() < 0.5 else &"move_right"
	if _stuck > 3.5:
		_stuck = 0.0
		_stats.stuck += 1
		var here := _cell_of(_player.global_position)
		var open := []
		for side in RoomDefs.SIDE_COUNT:
			open.append(_manager.grid.is_open(here, side))
		_say("stuck at %s: at %s (room middle %s), walking to %s, open sides %s, goal %s: choosing a new goal" % [here,
				str(_player.global_position.snapped(Vector3.ONE * 0.01)), str(RoomDefs.cell_to_world(here)), str(_target(here)), str(open), str(_goal)])
		_goal = Vector2i(-9999, -9999)
		_visited[_cell_of(_player.global_position)] = _clock + 30.0


func _steer(cell: Vector2i, _delta: float) -> void:
	var target: Variant = _target(cell)
	if target == null:
		_release(&"move_forward")
		return
	var point: Vector3 = target
	if _clock < _web_until and is_instance_valid(_web_target):
		# Hold the flame up to the web, standing a step from it, until it burns away.
		_face(_director.offset(_player.global_position, _web_target.global_position))
		_press(&"hold_flame")
		_release(&"move_forward")
		return
	var to := _director.offset(_player.global_position, point)
	if to.length() < 0.1:
		return
	_face(to)
	if _clock < _unstick_until:
		_release(&"move_left")
		_release(&"move_right")
		_press(_unstick_side)
		_press(&"move_forward")
		return
	_release(&"move_left")
	_release(&"move_right")
	_press(&"move_forward")
	if _stuck < 1.0 and not _player.is_snuffed():
		_press(&"sprint")
	else:
		_release(&"sprint")


func _face(direction: Vector3) -> void:
	if direction.length() > 0.01:
		_rig.yaw = lerp_angle(_rig.yaw, atan2(-direction.x, -direction.z), 0.5)


## Where to walk now: a pickup if there is one to be had, the gate with enough keys, otherwise onward.
func _target(cell: Vector2i) -> Variant:
	# 1. A key (or an item) to pick up.
	var best: Node3D = null
	var best_distance := INF
	for pickup in _manager.view.find_children("*", "KeyPickup", true, false):
		if _escape.can_take_key(0) and _escape.keys_held[0] < _escape.keys_per_prisoner:
			var d := _director.offset(_player.global_position, (pickup as Node3D).global_position).length()
			if d < best_distance and (pickup as Node3D).is_visible_in_tree():
				best_distance = d
				best = pickup
	if best == null:
		for pickup in _manager.view.find_children("*", "ItemPickup", true, false):
			var d2 := _director.offset(_player.global_position, (pickup as Node3D).global_position).length()
			if d2 < best_distance and d2 < 14.0 and _escape.bag.has_room(0, (pickup as ItemPickup).kind, 1):
				best_distance = d2
				best = pickup
	if best != null:
		return _toward(cell, _cell_of(best.global_position), best.global_position)
	# 2. A gate, once we hold all the keys we need.
	if _escape.keys_held[0] >= _escape.keys_per_prisoner:
		for anchor in _escape.gate_anchors():
			if _escape.gate_status(0) != "":
				return null
			return _toward(cell, anchor, RoomDefs.cell_to_world(anchor))
	# 3. Onward: a far room we have not been in lately.
	return _explore(cell)


func _toward(from: Vector2i, goal: Vector2i, point: Vector3) -> Variant:
	if from == goal:
		return point
	var step: Variant = _director.next_step(from, goal, 40, false)
	if step == null:
		step = _director.next_step(from, goal, 40, true)
	if step == null:
		return _explore(from)
	return _through_door(from, step)


## The point to walk to to go from room `from` into the next room `step`: a doorway is in the middle of a
## wall, so first line up with the middle of the room, then go through.
func _through_door(from: Vector2i, step: Vector2i) -> Vector3:
	var middle := RoomDefs.cell_to_world(from)
	var way := _director.offset(middle, RoomDefs.cell_to_world(step)).normalized()
	var rel := _director.offset(middle, _player.global_position)
	var along := rel.dot(way)
	var lateral := rel - way * along
	if lateral.length() > 0.3 and along < 1.2:
		return middle + way * minf(along, 0.0)
	return RoomDefs.cell_to_world(step)


func _explore(cell: Vector2i) -> Variant:
	# A candle running low: make for a shrine that can be reached, and stay at the altar until the candle is full.
	var shrine: Variant = _shrine_to_seek(cell)
	if shrine != null:
		if cell == shrine:
			return RoomDefs.cell_to_world(cell)
		if _goal != shrine:
			_say("candle low (%.0f%%): heading for the shrine in %s" % [_player.wax.fraction() * 100.0, shrine])
		_goal = shrine
		_goal_until = _clock + 20.0
	if _goal == Vector2i(-9999, -9999) or _clock > _goal_until or cell == _goal or not _manager.grid.has_cell(_goal):
		var found := _director.reachable(cell, 12)
		var best := cell
		var best_score := -INF
		for candidate in found:
			var score: float = found[candidate].steps * 1.0 + _rng.randf() * 3.0
			if _visited.has(candidate):
				score -= 6.0 if _clock - _visited[candidate] < 120.0 else 0.0
			if score > best_score:
				best_score = score
				best = candidate
		_goal = best
		_goal_until = _clock + 20.0
	if _goal == cell:
		return RoomDefs.cell_to_world(cell)
	var step: Variant = _director.next_step(cell, _goal, 14, false)
	if step == null:
		_goal = Vector2i(-9999, -9999)
		return RoomDefs.cell_to_world(cell)
	return _through_door(cell, step)


## The nearest unused shrine within reach when the candle is under 45% (or burnt out), or null.
func _shrine_to_seek(cell: Vector2i) -> Variant:
	if _player.wax.is_endless() or _player.wax.fraction() >= 0.45:
		return null
	var found := _director.reachable(cell, 14)
	var best: Variant = null
	var best_steps := 999
	for shrine in _shrines._shrines:
		if _shrines.has_shrine(shrine) and found.has(shrine) and found[shrine].steps < best_steps:
			best = shrine
			best_steps = found[shrine].steps
	return best
