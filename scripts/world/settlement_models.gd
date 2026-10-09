class_name SettlementModels
extends RefCounted
## Placeholder 3D models for towns, castles and villages, built from boxes,
## cylinders and roofs in the owning faction's colours (factions.json "style").
## Swap these for real models later; the rest of the game only needs the
## returned mesh and its height.
##
## Sizes in map units: town ~95 across, castle ~32, village ~30.

const DIRT := Color(0.47, 0.39, 0.29)
const WOOD := Color(0.42, 0.31, 0.21)

## Height of the tallest part per type, used to place the banner and label.
const TOP := {"town": 30.0, "castle": 22.0, "village": 8.0}
## Footprint radius per type, used to clear trees and paint the ground.
const RADIUS := {"town": 50.0, "castle": 22.0, "village": 20.0}


static func build(type: String, style: Dictionary, seed_value: int) -> ArrayMesh:
	var kit := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wall := Color.html(style.get("wall", "#b0a690"))
	var roof := Color.html(style.get("roof", "#9a4632"))
	var flat: bool = style.get("flat_roofs", false)
	match type:
		"town":
			_town(kit, rng, wall, roof, flat)
		"castle":
			_castle(kit, rng, wall, roof, flat)
		_:
			_village(kit, rng, wall, roof, flat)
	return kit.commit()


static func foundation(type: String, depth: float) -> ArrayMesh:
	## A low earth plinth that hides the gap between the model and sloping ground.
	var kit := MeshKit.new()
	var r: float = RADIUS[type] * (0.95 if type == "town" else 0.8)
	kit.cylinder(DIRT, Transform3D(Basis(), Vector3(0, -depth, 0)), r, depth + 0.25, 14, r * 0.97)
	return kit.commit()


static func _at(x: float, z: float, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, 0, z))


static func _house(kit: MeshKit, xform: Transform3D, w: float, d: float, h: float, wall: Color, roof: Color, flat: bool) -> void:
	kit.box(wall, xform, Vector3(w, h, d))
	if flat:
		kit.box(roof, xform.translated_local(Vector3(0, h, 0)), Vector3(w + 0.4, 0.5, d + 0.4))
	else:
		kit.gable_roof(roof, xform.translated_local(Vector3(0, h, 0)), w, d, h * 0.8)


static func _tower(kit: MeshKit, xform: Transform3D, r: float, h: float, wall: Color, roof: Color, flat: bool) -> void:
	kit.cylinder(wall, xform, r, h, 8)
	if flat:
		kit.cylinder(wall.darkened(0.1), xform.translated_local(Vector3(0, h, 0)), r + 0.4, 1.0, 8)
	else:
		kit.cone(roof, xform.translated_local(Vector3(0, h, 0)), r + 0.5, r * 1.8, 8)


static func _wall_between(kit: MeshKit, a: Vector3, b: Vector3, h: float, thick: float, color: Color) -> void:
	var mid := (a + b) * 0.5
	var dir := b - a
	var yaw := atan2(-dir.z, dir.x)
	kit.box(color, Transform3D(Basis(Vector3.UP, yaw), mid), Vector3(dir.length(), h, thick))
	# Simple crenellations along the top.
	var count := int(dir.length() / 2.2)
	for k in count:
		if k % 2 == 0:
			var p := a.lerp(b, (k + 0.5) / count)
			kit.box(color, Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, h, 0)), Vector3(1.1, 0.9, thick))


static func _village(kit: MeshKit, rng: RandomNumberGenerator, wall: Color, roof: Color, flat: bool) -> void:
	var count := rng.randi_range(5, 7)
	var house_wall := wall.lerp(Color(0.62, 0.53, 0.4), 0.4)
	for k in count:
		var angle := TAU * k / count + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(5.0, 13.0)
		var xform := _at(cos(angle) * dist, sin(angle) * dist, -angle + rng.randf_range(-0.3, 0.3))
		_house(kit, xform, rng.randf_range(4.0, 6.0), rng.randf_range(3.2, 4.2), rng.randf_range(2.4, 3.2), house_wall, roof, flat)
	# A well or shrine in the middle.
	kit.cylinder(wall.darkened(0.2), _at(0, 0), 1.0, 1.2, 8)


static func _castle(kit: MeshKit, rng: RandomNumberGenerator, wall: Color, roof: Color, flat: bool) -> void:
	var half := 14.0
	var h := 8.0
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		if k == 2:
			# Front wall with a gate gap and a gatehouse.
			var gap := 2.8
			var mid := (a + b) * 0.5
			_wall_between(kit, a, mid + (a - b).normalized() * gap, h, 2.0, wall)
			_wall_between(kit, mid + (b - a).normalized() * gap, b, h, 2.0, wall)
			kit.box(wall.darkened(0.08), _at(mid.x, mid.z), Vector3(9.0, h + 3.0, 4.0))
			kit.box(WOOD, _at(mid.x, mid.z + 2.05), Vector3(4.2, 5.0, 0.2))
		else:
			_wall_between(kit, a, b, h, 2.0, wall)
		_tower(kit, _at(a.x, a.z), 3.0, h + 4.0, wall, roof, flat)
	# The keep.
	kit.box(wall.darkened(0.05), _at(-2.0, -2.0), Vector3(11.0, 15.0, 11.0))
	if flat:
		kit.box(wall.darkened(0.15), _at(-2.0, -2.0).translated_local(Vector3(0, 15.0, 0)), Vector3(11.6, 1.0, 11.6))
		kit.dome(roof, _at(-2.0, -2.0).translated_local(Vector3(0, 16.0, 0)), 3.5)
	else:
		kit.gable_roof(roof, _at(-2.0, -2.0).translated_local(Vector3(0, 15.0, 0)), 11.0, 11.0, 6.0)
	_tower(kit, _at(4.5, -6.5), 2.2, 18.0, wall, roof, flat)


static func _town(kit: MeshKit, rng: RandomNumberGenerator, wall: Color, roof: Color, flat: bool) -> void:
	var radius := 44.0
	var segments := 10
	var h := 9.0
	var gate := 7   # segment index facing +z (south-ish before rotation)
	for k in segments:
		var a := Vector3(cos(TAU * k / segments), 0, sin(TAU * k / segments)) * radius
		var b := Vector3(cos(TAU * (k + 1) / segments), 0, sin(TAU * (k + 1) / segments)) * radius
		if k == gate:
			var mid := (a + b) * 0.5
			var along := (b - a).normalized()
			_wall_between(kit, a, mid - along * 4.0, h, 2.5, wall)
			_wall_between(kit, mid + along * 4.0, b, h, 2.5, wall)
			var yaw := atan2(-along.z, along.x)
			kit.box(wall.darkened(0.08), Transform3D(Basis(Vector3.UP, yaw), mid), Vector3(12.0, h + 4.0, 6.0))
		else:
			_wall_between(kit, a, b, h, 2.5, wall)
		_tower(kit, _at(a.x, a.z), 3.6, h + 5.0, wall, roof, flat)

	# Houses in rings around the centre, leaving room for the keep and a square.
	var house_wall := wall.lerp(Color(0.64, 0.56, 0.43), 0.35)
	var placed: Array[Vector2] = []
	var tries := 0
	while placed.size() < 34 and tries < 400:
		tries += 1
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(17.0, radius - 7.0)
		var p := Vector2(cos(angle), sin(angle)) * dist
		var clear := true
		for q in placed:
			if p.distance_to(q) < 7.5:
				clear = false
				break
		if not clear:
			continue
		placed.append(p)
		var tint := rng.randf_range(-0.06, 0.06)
		var w := rng.randf_range(5.0, 7.5)
		_house(kit, _at(p.x, p.y, -angle + PI * 0.5 + rng.randf_range(-0.2, 0.2)), w, rng.randf_range(4.0, 5.5),
			rng.randf_range(3.2, 5.0), house_wall.lightened(tint) if tint > 0.0 else house_wall.darkened(-tint),
			roof.lightened(tint * 0.5) if tint > 0.0 else roof.darkened(-tint), flat)

	# Keep or great hall, with a tall tower.
	kit.box(wall.darkened(0.04), _at(0, -4.0), Vector3(16.0, 16.0, 11.0))
	if flat:
		kit.dome(roof, _at(0, -4.0).translated_local(Vector3(0, 16.0, 0)), 5.0)
		kit.cylinder(wall, _at(9.0, 5.0), 1.6, 26.0, 8)
		kit.dome(roof, _at(9.0, 5.0).translated_local(Vector3(0, 26.0, 0)), 2.0)
	else:
		kit.gable_roof(roof, _at(0, -4.0).translated_local(Vector3(0, 16.0, 0)), 16.0, 11.0, 7.0)
		_tower(kit, _at(9.0, 5.0), 3.0, 24.0, wall, roof, false)
