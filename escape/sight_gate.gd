class_name SightGate
extends Node
## Shows what lies in a room only while a prisoner can see that room: the rooms their candle lights, or
## only their own room without it. The maze keeps its rooms whether anyone can see them or not, so a
## key, an item or a monster in a room out of sight is hidden (not populated, as far as the player is
## concerned) and appears when the room comes into view. Anything in the group `sight_gated` is
## handled; it needs a world position, and is shown when its room is in any prisoner's view.

const GROUP := &"sight_gated"

var players: Array[Player] = []

var _manager: MazeManager


func setup(p_players: Array[Player], p_manager: MazeManager) -> void:
	players = p_players
	_manager = p_manager


func _physics_process(_delta: float) -> void:
	var grid := _manager.grid
	var seen := {}
	for player in players:
		var radius := ceili(player.candle_reach) if player.is_candle_lit() else 0
		var here := grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
		seen.merge(LightField.compute(grid, [{"cell": here, "radius": radius}], false))
	for node in get_tree().get_nodes_in_group(GROUP):
		var thing := node as Node3D
		thing.visible = seen.has(grid.wrap_cell(RoomDefs.world_to_cell(thing.global_position)))
