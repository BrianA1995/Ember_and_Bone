class_name SightGate
extends Node
## Shows what lies in a room only while a prisoner can see that room (see SightMap). The maze keeps its
## rooms whether anyone can see them or not, so a key, an item or a monster in a room out of sight is
## hidden (not populated, as far as the player is concerned) and appears when the room comes into view.
## Anything in the group `sight_gated` is handled; it needs a world position, and is shown when its room is
## in any prisoner's view.

const GROUP := &"sight_gated"

var _sight: SightMap
var _manager: MazeManager


func setup(p_sight: SightMap, p_manager: MazeManager) -> void:
	_sight = p_sight
	_manager = p_manager


func _physics_process(_delta: float) -> void:
	var grid := _manager.grid
	for node in get_tree().get_nodes_in_group(GROUP):
		var thing := node as Node3D
		thing.visible = _sight.anyone_sees(grid.cell_at(thing.global_position))
