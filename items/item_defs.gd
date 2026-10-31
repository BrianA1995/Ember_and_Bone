class_name ItemDefs
extends RefCounted
## What each item is called, how many a pickup gives (`gives`), how many fit in one inventory slot
## (`per_slot`), how many a prisoner can carry in all (`cap`), and its placeholder colour. Every item
## takes inventory slots, keys included; the pouch is the one thing that does not (`no_slot`): it is
## worn, and gives a prisoner one more slot. Add an item by adding a line here, a model in
## build_model(), and the rule for using it (see ItemUse).

const ITEMS := {
	&"matches": {"label": "Matches", "gives": 3, "per_slot": 3, "cap": 6, "color": Color(0.85, 0.25, 0.15)},
	&"spare_candle": {"label": "Spare candle", "gives": 1, "per_slot": 1, "cap": 2, "color": Color(0.92, 0.9, 0.8)},
	&"lamp": {"label": "Lamp", "gives": 1, "per_slot": 1, "cap": 2, "color": Color(1.0, 0.8, 0.35)},
	&"string": {"label": "String", "gives": 1, "per_slot": 1, "cap": 2, "color": Color(0.8, 0.7, 0.5)},
	&"chalk": {"label": "Chalk", "gives": 6, "per_slot": 6, "cap": 12, "color": Color(0.95, 0.95, 0.95)},
	&"walkie": {"label": "Walkie-talkie", "gives": 1, "per_slot": 1, "cap": 1, "color": Color(0.45, 0.5, 0.45)},
	&"pouch": {"label": "Pouch", "gives": 1, "per_slot": 1, "cap": 2, "color": Color(0.5, 0.33, 0.2), "no_slot": true},
}


static func label(kind: StringName) -> String:
	return ITEMS[kind].label


## Does this item take a slot (everything but the pouch)?
static func uses_slot(kind: StringName) -> bool:
	return not ITEMS[kind].get("no_slot", false)


static func per_slot(kind: StringName) -> int:
	return ITEMS[kind].per_slot


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
	match kind:
		&"spare_candle":
			var stick := CylinderMesh.new()
			stick.top_radius = 0.03
			stick.bottom_radius = 0.035
			stick.height = 0.22
			body.mesh = stick
			model.add_child(_flame(Vector3(0.0, 0.14, 0.0)))
		&"lamp":
			var glass := CylinderMesh.new()
			glass.top_radius = 0.07
			glass.bottom_radius = 0.09
			glass.height = 0.2
			body.mesh = glass
			model.add_child(_flame(Vector3(0.0, 0.0, 0.0)))
		&"string":
			var coil := TorusMesh.new()
			coil.inner_radius = 0.05
			coil.outer_radius = 0.11
			body.mesh = coil
		&"chalk":
			var stick := BoxMesh.new()
			stick.size = Vector3(0.03, 0.03, 0.18)
			body.mesh = stick
		&"walkie":
			var box := BoxMesh.new()
			box.size = Vector3(0.09, 0.17, 0.04)
			body.mesh = box
			var antenna := MeshInstance3D.new()
			var rod := CylinderMesh.new()
			rod.top_radius = 0.008
			rod.bottom_radius = 0.008
			rod.height = 0.12
			antenna.mesh = rod
			antenna.position = Vector3(0.03, 0.14, 0.0)
			antenna.material_override = material
			model.add_child(antenna)
		&"pouch":
			var bag := SphereMesh.new()
			bag.radius = 0.1
			bag.height = 0.17
			body.mesh = bag
		_:
			var box := BoxMesh.new()
			box.size = Vector3(0.2, 0.06, 0.12)
			body.mesh = box
	body.material_override = material
	model.add_child(body)
	return model


static func _flame(at: Vector3) -> MeshInstance3D:
	var flame := MeshInstance3D.new()
	var drop := SphereMesh.new()
	drop.radius = 0.035
	drop.height = 0.09
	flame.mesh = drop
	flame.position = at
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.7, 0.3)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.6, 0.2)
	fire.emission_energy_multiplier = 2.0
	flame.material_override = fire
	return flame
