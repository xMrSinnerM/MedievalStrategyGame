class_name SettlementModels
extends RefCounted
## Models for towns (capitals), castles and villages on the world map, built
## from KayKit pieces (KitModels) with roofs and flags in the owner's colour.
## The rest of the game only needs the returned mesh, its height and radius.
##
## Sizes in map units: town ~95 across, castle ~32, village ~30.

const DIRT := Color(0.47, 0.39, 0.29)

## Height of the tallest part per type, used to place the label.
const TOP := {"town": 44.0, "castle": 32.0, "village": 10.0}
## Footprint radius per type, used to clear trees and paint the ground.
const RADIUS := {"town": 50.0, "castle": 22.0, "village": 20.0}


static func foundation(type: String, depth: float) -> ArrayMesh:
	## A low earth plinth that hides the gap between the model and sloping ground.
	var kit := MeshKit.new()
	var r: float = RADIUS[type] * (0.95 if type == "town" else 0.8)
	kit.cylinder(DIRT, Transform3D(Basis(), Vector3(0, -depth, 0)), r, depth + 0.25, 14, r * 0.97)
	return kit.commit()


static func build(type: String, team: Color, seed_value: int) -> ArrayMesh:
	var kit := KitModels.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	match type:
		"town":
			_town(kit, rng)
		"castle":
			_castle(kit, rng)
		_:
			_village(kit, rng)
	return kit.commit(team, true)


static func _put(kit: KitModels, piece: String, at: Vector3, scale: float, yaw := 0.0) -> void:
	kit.add(piece, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), at))


static func _wall(kit: KitModels, a: Vector3, b: Vector3, height: float, gate := false) -> void:
	## Wall pieces from a to b; a gate piece in the middle when asked.
	var dir := b - a
	var n := maxi(int(round(dir.length() / 9.0)), 1)
	var s := dir.length() / n / 2.0
	var yaw := atan2(-dir.z, dir.x)
	for k in n:
		var at := a.lerp(b, (k + 0.5) / n)
		var piece := "wall_straight_gate" if gate and k == n / 2 else "wall_straight"
		kit.add(piece, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, height, s)), at))


static func _town(kit: KitModels, rng: RandomNumberGenerator) -> void:
	var radius := 44.0
	var segments := 10
	for k in segments:
		var a := Vector3(cos(TAU * k / segments), 0, sin(TAU * k / segments)) * radius
		var b := Vector3(cos(TAU * (k + 1) / segments), 0, sin(TAU * (k + 1) / segments)) * radius
		_wall(kit, a, b, 6.5, k == 7)
		_put(kit, "building_tower_A_blue", a, 6.5, rng.randf() * TAU)
		if k % 2 == 0:
			_flag(kit, a + Vector3(0, 2.19 * 6.5, 0), 6.5)
	# The citadel in the middle with a church and market around a square.
	_put(kit, "building_castle_blue", Vector3(0, 0, -6), 11.0, PI)
	_put(kit, "building_church_blue", Vector3(19, 0, -17), 10.0, -0.6)
	_put(kit, "building_market_blue", Vector3(-8, 0, 19), 9.0, PI * 0.5)
	_put(kit, "building_well_blue", Vector3(8, 0, 13), 6.0)
	_put(kit, "building_tavern_blue", Vector3(-22, 0, -12), 9.0, 0.9)
	_put(kit, "building_blacksmith_blue", Vector3(23, 0, 9), 9.0, -1.4)
	var placed: Array[Vector2] = [Vector2(0, -6), Vector2(19, -17), Vector2(-8, 19), Vector2(8, 13), Vector2(-22, -12), Vector2(23, 9)]
	var tries := 0
	while placed.size() < 34 and tries < 600:
		tries += 1
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(14.0, radius - 7.0)
		var p := Vector2(cos(angle), sin(angle)) * dist
		var clear := true
		for q in placed:
			if p.distance_to(q) < (15.0 if q == placed[0] else 9.5):
				clear = false
				break
		if not clear:
			continue
		placed.append(p)
		var piece := "building_home_A_blue" if rng.randf() < 0.6 else "building_home_B_blue"
		_put(kit, piece, Vector3(p.x, 0, p.y), rng.randf_range(8.0, 9.5), -angle + PI * 0.5 + rng.randf_range(-0.3, 0.3))
	# Fields and a windmill outside the walls.
	_put(kit, "building_windmill_blue", Vector3(58, 0, 18), 9.0, 2.0)
	_put(kit, "building_grain", Vector3(62, 0, 0), 8.0)
	_put(kit, "building_grain", Vector3(54, 0, 36), 8.0, 1.0)


static func _castle(kit: KitModels, rng: RandomNumberGenerator) -> void:
	var half := 14.0
	var corners := [Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half), Vector3(-half, 0, half)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		_wall(kit, a, b, 5.0, k == 2)
		_put(kit, "building_tower_A_blue", a, 5.0, rng.randf() * TAU)
		_flag(kit, a + Vector3(0, 2.19 * 5.0, 0), 5.0)
	_put(kit, "building_castle_blue", Vector3(-1, 0, -2), 8.0, PI)
	_put(kit, "building_barracks_blue", Vector3(7, 0, 7), 5.5, -PI * 0.5)
	_put(kit, "building_home_A_blue", Vector3(-8, 0, 7), 6.0, PI * 0.5)


static func _village(kit: KitModels, rng: RandomNumberGenerator) -> void:
	## Cottages in a ring; the middle is left for the village's resource building
	## (VillagesLayer adds it).
	var count := rng.randi_range(5, 7)
	for k in count:
		var angle := TAU * k / count + rng.randf_range(-0.3, 0.3)
		var dist := rng.randf_range(10.5, 14.0)
		var piece := "building_home_A_blue" if rng.randf() < 0.7 else "building_home_B_blue"
		_put(kit, piece, Vector3(cos(angle) * dist, 0, sin(angle) * dist), rng.randf_range(7.0, 8.5), -angle + PI * 0.5 + rng.randf_range(-0.3, 0.3))
	for k in 3:
		var angle := rng.randf() * TAU
		_put(kit, "fence_wood_straight", Vector3(cos(angle), 0, sin(angle)) * 18.0, 5.0, -angle)


static func _flag(kit: KitModels, top: Vector3, scale: float) -> void:
	## A pennant in the owner's colour on top of a tower.
	_put(kit, "flag_blue", top - Vector3(0, 0.1 * scale, 0), scale * 3.5)
