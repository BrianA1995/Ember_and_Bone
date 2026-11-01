class_name SightMap
extends Node
## Which rooms each prisoner can see: the rooms their candle lights (their own room and those joined to it
## by open doorways, as far as the light reaches), or only their own room without a candle.
##
## Several systems ask this (what to show, where a monster may chase, which alcoves were seen). It is worked
## out here, once per prisoner, and kept until the prisoner changes room, lights or snuffs their candle, or
## the maze changes shape, so a bigger group of prisoners costs a flood fill only when somebody moves on.

var players: Array[Player] = []

var _manager: MazeManager
var _grid: MazeGrid
## Bumped whenever the maze changes shape, which makes every kept answer stale.
var _revision := 0
## Player -> {cell, radius, revision, cells}: the last answer for that prisoner.
var _kept: Dictionary = {}


func setup(p_players: Array[Player], p_manager: MazeManager) -> void:
	players = p_players
	_manager = p_manager
	_manager.maze_rebuilt.connect(_bind)
	_bind()


## The rooms `player` sees now, as a set (Dictionary of cell -> true). Do not change it.
func cells_for(player: Player) -> Dictionary:
	if _grid == null:
		return {}
	var cell := _grid.wrap_cell(RoomDefs.world_to_cell(player.global_position))
	var radius := player.view_radius()
	var kept: Dictionary = _kept.get(player, {})
	if kept.get("cell") != cell or kept.get("radius") != radius or kept.get("revision") != _revision:
		kept = {
			"cell": cell,
			"radius": radius,
			"revision": _revision,
			"cells": LightField.compute(_grid, [{"cell": cell, "radius": radius}], false),
		}
		_kept[player] = kept
	return kept.cells


## Can `player` see the room `cell`?
func sees(player: Player, cell: Vector2i) -> bool:
	return cells_for(player).has(cell)


## Can any prisoner see the room `cell`?
func anyone_sees(cell: Vector2i) -> bool:
	for player in players:
		if sees(player, cell):
			return true
	return false


func _bind() -> void:
	_grid = _manager.grid
	_kept.clear()
	_revision += 1
	_grid.cell_added.connect(_on_maze_changed)
	_grid.cell_removed.connect(_on_maze_changed)
	_grid.side_sealed.connect(_on_side_sealed)


func _on_maze_changed(_cell: Vector2i) -> void:
	_revision += 1


func _on_side_sealed(_cell: Vector2i, _side: int) -> void:
	_revision += 1
