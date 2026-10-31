class_name RoomFade
extends RefCounted
## Fades a room in from nothing without the see-through look of plain alpha blending. Each mesh gets
## its own copy of its materials set to "alpha with depth pre-pass", so the nearest surface hides
## whatever is behind it (pillars, walls) even while it is faint; when the fade is over the original
## materials are put back and the room is solid again.

## Fades `room` in over `seconds`. The tween belongs to the room, so it stops if the room is freed.
static func fade_in(room: Node3D, seconds: float) -> void:
	var faded: Array[Dictionary] = []
	for node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		var entry := {"mesh": mesh, "override": mesh.material_override, "surfaces": [], "copies": []}
		if mesh.material_override != null:
			var copy := _fadeable(mesh.material_override)
			mesh.material_override = copy
			entry.copies.append(copy)
		else:
			for surface in mesh.mesh.get_surface_count():
				var original := mesh.get_active_material(surface)
				entry.surfaces.append(mesh.get_surface_override_material(surface))
				var copy := _fadeable(original)
				mesh.set_surface_override_material(surface, copy)
				entry.copies.append(copy)
		faded.append(entry)
	var tween := room.create_tween()
	tween.tween_method(func(amount: float) -> void: _set_alpha(faded, amount), 0.0, 1.0, seconds)
	tween.tween_callback(func() -> void: _restore(faded))


static func _fadeable(original: Material) -> Material:
	if not original is StandardMaterial3D:
		return original
	var copy := original.duplicate() as StandardMaterial3D
	copy.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	return copy


static func _set_alpha(faded: Array[Dictionary], amount: float) -> void:
	for entry in faded:
		if not is_instance_valid(entry.mesh):
			continue
		for copy in entry.copies:
			if copy is StandardMaterial3D:
				var color: Color = copy.albedo_color
				color.a = amount
				copy.albedo_color = color


static func _restore(faded: Array[Dictionary]) -> void:
	for entry in faded:
		var mesh := entry.mesh as MeshInstance3D
		if not is_instance_valid(mesh):
			continue
		mesh.material_override = entry.override
		for surface in entry.surfaces.size():
			mesh.set_surface_override_material(surface, entry.surfaces[surface])
