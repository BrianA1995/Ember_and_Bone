class_name TagMode
extends Node
## The rules of tag, on top of a LocalGame. One player is "it". When the player who is it
## touches another player, the tag passes to them. Every second you are it costs a point.
##
## With `eliminate` on (Tag): a player who runs out of points is out. They are sent to a sealed
## room (HoldingRoom) and stay there until the round ends, and the tag goes to a random player who
## is still in. The last player left wins.
## With it off (Endless tag): nobody is ever out. Points stop at zero and the game goes on until
## the players quit.
##
## Only the player who is it is told so (TagHud). Everyone sees their own points, nobody else's,
## until the round is over. A short head start lets everyone spread out first, and a newly tagged
## player can't tag straight back.

signal tag_passed(from_slot: int, to_slot: int)
signal player_out(slot: int)
signal round_over(standings: Array)

## How close two bodies must be, in metres, to count as touching.
@export var touch_distance := 1.0
## Seconds at the start before tagging and the point loss begin.
@export var head_start := 5.0
## Seconds after a tag during which it can't be passed again.
@export var cooldown := 1.5
## Players who run out of points are out of the round (see above).
@export var eliminate := true

var start_points := 100
## Points left, per slot.
var points: Array[float] = []
## Who is still in the round, per slot.
var alive: Array[bool] = []
## Who is it (a slot), or -1 before the round starts.
var it_slot := -1
var finished := false
## Where the people who are out wait.
var holding_room: HoldingRoom
## Leads the player who is it toward the others (see Pursuit). Optional: without it, nobody is helped.
var pursuit: Pursuit

var _players: Array[Player] = []
var _huds: Array[TagHud] = []
var _out_order: Array[int] = []
var _head_start_left := 0.0
var _cooldown_left := 0.0


## Starts a round for `players`, with a readout in each one's pane of `split`.
func setup(players: Array[Player], split: SplitScreen, p_start_points: int) -> void:
	_players = players
	start_points = p_start_points
	holding_room = HoldingRoom.new()
	add_child(holding_room)
	for i in players.size():
		var hud := TagHud.new()
		split.pane_at(i).add_child(hud)
		_huds.append(hud)
	reset()


## Everyone back in, with full points; a new player is it and the head start begins again.
func reset() -> void:
	points.clear()
	alive.clear()
	_out_order.clear()
	for player in _players:
		points.append(float(start_points))
		alive.append(true)
		# Anyone who was sent away lights the maze again (the caller moves them back to the start).
		player.add_to_group("light_sources")
	it_slot = randi() % _players.size()
	finished = false
	_head_start_left = head_start
	_cooldown_left = 0.0
	_refresh()


func players_in() -> int:
	return alive.count(true)


func _physics_process(delta: float) -> void:
	if finished or _players.size() < 2:
		return
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _head_start_left > 0.0:
		_head_start_left = maxf(_head_start_left - delta, 0.0)
	else:
		points[it_slot] = maxf(points[it_slot] - delta, 0.0)
		_check_touch()
		if points[it_slot] <= 0.0 and eliminate:
			_send_out(it_slot)
	_refresh()


## The standings: [{slot, points, out}], the winner first, then the others by how long they lasted.
## In endless tag (no one is out) it is simply who has the most points.
func standings() -> Array:
	var list: Array = []
	for slot in points.size():
		list.append({"slot": slot, "points": points[slot], "out": not alive[slot]})
	if not eliminate:
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.points > b.points)
		return list
	# Still in first, then those who went out, the last one out coming first.
	var ranked: Array = []
	for entry in list:
		if not entry.out:
			ranked.append(entry)
	for i in range(_out_order.size() - 1, -1, -1):
		ranked.append(list[_out_order[i]])
	return ranked


## The player who is it passes the tag to the first other player in the round they touch.
func _check_touch() -> void:
	if _cooldown_left > 0.0:
		return
	var tagger := _players[it_slot].global_position
	for slot in _players.size():
		if slot == it_slot or not alive[slot]:
			continue
		var other := _players[slot].global_position
		if Vector2(tagger.x - other.x, tagger.z - other.z).length() <= touch_distance and absf(tagger.y - other.y) < 1.0:
			pass_tag(slot)
			return


func pass_tag(to_slot: int) -> void:
	var from := it_slot
	it_slot = to_slot
	_cooldown_left = cooldown
	tag_passed.emit(from, to_slot)


## Sends a player who has run out of points to the sealed room, and gives the tag to somebody still
## in. If one player is left, the round is over.
func _send_out(slot: int) -> void:
	alive[slot] = false
	_out_order.append(slot)
	var player := _players[slot]
	player.remove_from_group("light_sources")
	player.warp_to(holding_room.spot(_out_order.size() - 1) + Vector3(0.0, player.global_position.y, 0.0))
	player_out.emit(slot)
	if players_in() <= 1:
		finished = true
		_refresh()
		round_over.emit(standings())
		return
	var still_in: Array[int] = []
	for other in _players.size():
		if alive[other]:
			still_in.append(other)
	it_slot = still_in[randi() % still_in.size()]
	_cooldown_left = cooldown


func _refresh() -> void:
	for slot in _huds.size():
		_huds[slot].show_state(points[slot], slot == it_slot and alive[slot] and not finished,
				_head_start_left, not alive[slot])
	_update_pursuit()


## Whoever is it hunts everyone else still in. The hunter's clock starts when the head start ends.
func _update_pursuit() -> void:
	if pursuit == null:
		return
	if finished or it_slot < 0:
		pursuit.stop()
		return
	var prey: Array[Node3D] = []
	for slot in _players.size():
		if slot != it_slot and alive[slot]:
			prey.append(_players[slot])
	pursuit.set_chase(_players[it_slot], prey, _head_start_left <= 0.0)
