class_name Relighting
extends Node
## How a snuffed candle is lit again. A snuffed prisoner holds the interact button (E, or A) beside a
## teammate whose candle burns, and takes a light from theirs.
##
## Matches and hearth rooms will be the other ways; until they exist `fallback_seconds` lights a
## candle by itself after a while, so a prisoner alone is never stuck in the dark. Set it to 0 to turn
## the fallback off.

## How near, in metres, the lit candle has to be.
@export var relight_distance := 1.8
## Seconds the button is held.
@export_range(0.2, 10.0, 0.1, "suffix:s") var hold_seconds := 1.5
## A stand-in for matches and hearths: seconds after which a snuffed candle lights itself. 0 is never.
@export_range(0.0, 120.0, 1.0, "suffix:s") var fallback_seconds := 12.0

var players: Array[Player] = []

var _held: Dictionary = {}
var _dark: Dictionary = {}


func setup(p_players: Array[Player]) -> void:
	players = p_players


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
		if _asking(player) and _light_near(player):
			_held[player] = _held.get(player, 0.0) + delta
			if _held[player] >= hold_seconds:
				player.relight()
		else:
			_held[player] = 0.0


func _asking(player: Player) -> bool:
	return Input.is_action_pressed(GameInput.action(player.slot, &"interact"))


## Is a teammate with a burning candle within reach?
func _light_near(player: Player) -> bool:
	for other in players:
		if other != player and other.is_candle_lit():
			var apart := other.global_position - player.global_position
			if Vector2(apart.x, apart.z).length() <= relight_distance:
				return true
	return false
