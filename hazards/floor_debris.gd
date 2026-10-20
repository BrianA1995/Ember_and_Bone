class_name FloorDebris
extends RefCounted
## The chunks that fall away when a floor tile collapses. Purely visual: they have no
## collision and just tumble out of sight, then free themselves.


## Breaks `tile` into falling chunks. They become children of `tile`, so they go with the
## room if it is removed.
static func burst(tile: Node3D, count := 10) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.5, 0.47, 0.42)
	material.roughness = 0.95
	for i in count:
		var chunk := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(randf_range(0.3, 0.8), 0.18, randf_range(0.3, 0.8))
		chunk.mesh = mesh
		chunk.material_override = material
		chunk.position = Vector3(randf_range(-1.6, 1.6), -0.1, randf_range(-1.6, 1.6))
		chunk.rotation.y = randf() * TAU
		tile.add_child(chunk)
		var fall_time := randf_range(0.7, 1.3)
		var tumble := chunk.rotation + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5))
		var tween := chunk.create_tween().set_parallel(true)
		tween.tween_property(chunk, "position:y", -9.0, fall_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.tween_property(chunk, "rotation", tumble, fall_time)
		tween.chain().tween_callback(chunk.queue_free)
