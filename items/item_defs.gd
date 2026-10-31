class_name ItemDefs
extends RefCounted
## What each item is called, how many a pickup gives, how many a prisoner can carry, and what colour
## its placeholder model is. Add an item by adding a line here (and, if it can be used, a rule where it
## is used: see Relighting for matches and the spare candle).

const ITEMS := {
	&"matches": {"label": "Matches", "gives": 3, "cap": 6, "color": Color(0.85, 0.25, 0.15)},
	&"spare_candle": {"label": "Spare candle", "gives": 1, "cap": 2, "color": Color(0.92, 0.9, 0.8)},
}


static func label(kind: StringName) -> String:
	return ITEMS[kind].label


## The placeholder model of an item lying on the floor, about 0.3 m across; replace it with a real one.
static func build_model(kind: StringName) -> Node3D:
	var model := Node3D.new()
	var color: Color = ITEMS[kind].color
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.6
	var body := MeshInstance3D.new()
	if kind == &"spare_candle":
		var stick := CylinderMesh.new()
		stick.top_radius = 0.03
		stick.bottom_radius = 0.035
		stick.height = 0.22
		body.mesh = stick
		var flame := MeshInstance3D.new()
		var drop := SphereMesh.new()
		drop.radius = 0.035
		drop.height = 0.09
		flame.mesh = drop
		flame.position.y = 0.14
		var fire := StandardMaterial3D.new()
		fire.albedo_color = Color(1.0, 0.7, 0.3)
		fire.emission_enabled = true
		fire.emission = Color(1.0, 0.6, 0.2)
		fire.emission_energy_multiplier = 2.0
		flame.material_override = fire
		model.add_child(flame)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.2, 0.06, 0.12)
		body.mesh = box
	body.material_override = material
	model.add_child(body)
	return model
