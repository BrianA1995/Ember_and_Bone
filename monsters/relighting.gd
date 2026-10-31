class_name Relighting
extends Node
## How a snuffed candle is lit again, with the interact button (E, or A on a pad):
##  - beside a teammate whose candle burns: hold it and take a light from theirs (free);
##  - otherwise with matches: hold it while a match is struck (uses one up);
##  - otherwise with a spare candle: press it and the spare is lit in place of yours (uses it up).
## Hearth rooms will be another way. `fallback_seconds` is a last resort for testing: 0 turns it off.

## How near, in metres, a lit candle has to be.
@export var relight_distance := 1.8
## Seconds the button is held to take a light from a teammate.
@export_range(0.2, 10.0, 0.1, "suffix:s") var hold_seconds := 1.5
## Seconds the button is held to strike a match.
@export_range(0.2, 10.0, 0.1, "suffix:s") var match_seconds := 1.0
## Seconds after which a snuffed candle lights itself whatever happens. 0 is never.
@export_range(0.0, 300.0, 1.0, "suffix:s") var fallback_seconds := 0.0

var players: Array[Player] = []
## What the prisoners carry; without it only teammates (and the fallback) can relight.
var bag: ItemBag

var _held: Dictionary = {}
var _dark: Dictionary = {}


func setup(p_players: Array[Player], p_bag: ItemBag = null) -> void:
	players = p_players
	bag = p_bag


func _physics_process(delta: float) -> void:
	for player in players:
		if not player.is_snuffed():
			_held.erase(player)
			_dark.erase(player)
			continue
		_dark[player] = _dark.get(player, 0.0) + delta
		if fallback_seconds > 0.0 and _dark[player] >= fallback_seconds:
			player.relight()
			continue
		_ask(player, delta)


## What the prisoner can do now to get a light, with the button named {interact}.
func hint(player: Player) -> String:
	if _light_near(player):
		return "Hold {interact}: take a light from your teammate"
	if bag and bag.count(player.slot, &"matches") > 0:
		return "Hold {interact}: strike a match (%d left)" % bag.count(player.slot, &"matches")
	if bag and bag.count(player.slot, &"spare_candle") > 0:
		return "{interact}: light your spare candle"
	return "Your candle is out: find a teammate's light, matches or a spare candle"


func _ask(player: Player, delta: float) -> void:
	var button := GameInput.action(player.slot, &"interact")
	var needed := INF
	var spend: StringName = &""
	if _light_near(player):
		needed = hold_seconds
	elif bag and bag.count(player.slot, &"matches") > 0:
		needed = match_seconds
		spend = &"matches"
	elif bag and bag.count(player.slot, &"spare_candle") > 0:
		if Input.is_action_just_pressed(button) and bag.take(player.slot, &"spare_candle"):
			player.relight()
		return
	if needed == INF or not Input.is_action_pressed(button):
		_held[player] = 0.0
		return
	_held[player] = _held.get(player, 0.0) + delta
	if _held[player] >= needed and (spend == &"" or bag.take(player.slot, spend)):
		_held[player] = 0.0
		player.relight()


## Is a teammate with a burning candle within reach?
func _light_near(player: Player) -> bool:
	for other in players:
		if other != player and other.is_candle_lit():
			var apart := other.global_position - player.global_position
			if Vector2(apart.x, apart.z).length() <= relight_distance:
				return true
	return false
