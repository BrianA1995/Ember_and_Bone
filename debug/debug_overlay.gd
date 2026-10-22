extends CanvasLayer
## Test-time readout and shortcuts. Safe to delete from the game scene later.
##   R  new maze      C  collapse on/off      H  ceilings on/off      L  debug light
##   E (hold)  stamp a cracked floor next to you

## How long the "you fell" message stays up, in seconds.
const FELL_MESSAGE_TIME := 2.5

@onready var _label: Label = $Label

var _manager: MazeManager
var _refresh := 0.0
var _fell_message_left := 0.0


func _ready() -> void:
	_manager = get_tree().get_first_node_in_group("maze_manager") as MazeManager
	var player := get_tree().get_first_node_in_group("players") as Player
	if player:
		player.fell.connect(func() -> void: _fell_message_left = FELL_MESSAGE_TIME)


func _process(delta: float) -> void:
	_fell_message_left = maxf(_fell_message_left - delta, 0.0)
	_refresh -= delta
	if _refresh > 0.0 or _manager == null or _manager.grid == null:
		return
	_refresh = 0.2
	_label.text = "\n".join(_lines())


func _unhandled_input(event: InputEvent) -> void:
	if _manager == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_R:
			_manager.restart()
		KEY_C:
			_manager.collapse_enabled = not _manager.collapse_enabled
		KEY_H:
			_manager.view.hide_ceilings = not _manager.view.hide_ceilings
		KEY_L:
			var lighting := get_tree().get_first_node_in_group("maze_lighting") as MazeLighting
			if lighting:
				lighting.debug_bright = not lighting.debug_bright


func _lines() -> Array[String]:
	var grid := _manager.grid
	var report := grid.validate()
	var rig := get_tree().get_first_node_in_group("camera_rig") as CameraRig
	var lighting := get_tree().get_first_node_in_group("maze_lighting") as MazeLighting
	var player := get_tree().get_first_node_in_group("players") as Node3D
	var player_cell := RoomDefs.world_to_cell(player.global_position) if player else Vector2i.ZERO
	var lines: Array[String] = [
		"Seed %d    FPS %d" % [grid.seed_value, Engine.get_frames_per_second()],
		"Player cell %s (%s)    Cells alive %d (lit %d)" % [
			player_cell, grid.get_cell(player_cell).get("piece", "-"), grid.cell_count(), _manager.reveal.lit.size()],
		"Illegal connections: %d    Open doorways awaiting light: %d    Blocked doorways: %d" % [
			report.problems.size(), report.pending, grid.sealed_count()],
		"View: %s    Light: %s    Collapse: %s    Ceilings: %s" % [
			rig.mode_name() if rig else "-",
			"DEBUG bright" if lighting and lighting.debug_bright else "candle",
			"ON" if _manager.collapse_enabled else "off",
			"hidden" if _manager.view.hide_ceilings else "shown"],
		"WASD move   Shift sprint   Mouse look   Wheel zoom   Esc free mouse",
		"V / 1 2 3 view   R new maze   C collapse   H ceilings   L debug light   E (hold) stamp a cracked floor",
	]
	var start := _manager.start_collapse
	if start and start.phase == StartCollapse.Phase.SPREADING:
		lines.append("Start chamber floor breaks in %.0f s" % start.seconds_left())
	var floor_line := _floor_line(player)
	if not floor_line.is_empty():
		lines.append(floor_line)
	if _fell_message_left > 0.0:
		lines.append("YOU FELL: the floor gave way. You wake somewhere else.")
	if not report.problems.is_empty():
		lines.append("PROBLEM: " + report.problems[0])
	return lines


## What the cracked floor under the player is doing, or "" if they aren't on one.
func _floor_line(player: Node3D) -> String:
	if player == null:
		return ""
	for node in get_tree().get_nodes_in_group("cracked_floors"):
		var tile := node as CrackedFloor
		if tile and tile.is_intact() and tile.is_occupied_by(player):
			return "Cracked floor: collapses in %.1f s" % maxf(tile.seconds_left(), 0.0)
	return ""
