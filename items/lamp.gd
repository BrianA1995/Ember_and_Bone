class_name Lamp
extends RoomKeeper
## A lamp set down in a room: it keeps that room alive and lit warmly for `life_seconds`, and the flame of
## any lit candle within `lean_metres` leans toward it, so a prisoner can find their way back to it.
## Its look is a placeholder (ItemDefs.build_model).

@export var life_seconds := 60.0
@export var lean_metres := 10.0

var _age := 0.0
var _light: OmniLight3D
var _leaning: Array[Player] = []


func _ready() -> void:
	super()
	add_child(ItemDefs.build_model(&"lamp"))
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.75, 0.4)
	_light.light_energy = 1.6
	_light.omni_range = 7.0
	_light.position = Vector3(0.0, 0.5, 0.0)
	add_child(_light)
	position.y += 0.1


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= life_seconds:
		_release()
		queue_free()
		return
	# It gutters in its last few seconds.
	_light.light_energy = 1.6 * clampf((life_seconds - _age) / 5.0, 0.0, 1.0)
	for node in get_tree().get_nodes_in_group("players"):
		var player := node as Player
		var apart := global_position - player.global_position
		var near := player.is_candle_lit() and Vector2(apart.x, apart.z).length() <= lean_metres
		if near:
			player.lean_flame(apart)
			if not _leaning.has(player):
				_leaning.append(player)
		elif _leaning.has(player):
			_leaning.erase(player)
			player.lean_flame(Vector3.ZERO)


func _exit_tree() -> void:
	_release()


func _release() -> void:
	for player in _leaning:
		if is_instance_valid(player):
			player.lean_flame(Vector3.ZERO)
	_leaning.clear()
