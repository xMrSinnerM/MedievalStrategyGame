class_name CastleModels
extends RefCounted
## Placeholder models for the castle screen, built from boxes, cylinders and
## roofs like the world map's settlements. Each model sits on its footprint
## with the origin at the footprint's centre, and grows a little with level.
## Swap these for real models later; the castle view only needs the mesh.

const CELL := 2.0          ## world units per castle grid cell
const WALL_MARGIN := 2.0   ## gap between the grid's edge and the wall

const STONE := Color(0.64, 0.61, 0.56)
const STONE_DARK := Color(0.49, 0.47, 0.44)
const ROOF := Color(0.58, 0.24, 0.17)
const THATCH := Color(0.73, 0.6, 0.34)
const WOOD := Color(0.43, 0.3, 0.19)
const WOOD_LIGHT := Color(0.62, 0.47, 0.3)
const PLASTER := Color(0.86, 0.81, 0.69)
const SOIL := Color(0.41, 0.31, 0.21)
const CROP := Color(0.8, 0.7, 0.3)
const CROP_GREEN := Color(0.46, 0.6, 0.26)
const ROCK := Color(0.56, 0.55, 0.53)
const BANNER := Color(0.75, 0.62, 0.2)


static func build(type: String, level: int, size: Vector2i, constructing: bool) -> ArrayMesh:
	## The model for one building. Level 0 while constructing is a building site.
	var kit := MeshKit.new()
	var w := size.x * CELL
	var d := size.y * CELL
	if level <= 0:
		_site(kit, w, d)
	else:
		match type:
			"keep":
				_keep(kit, level)
			"woodcutter":
				_woodcutter(kit, level)
			"quarry":
				_quarry(kit, level)
			"farm":
				_farm(kit, level, w)
			"house":
				_house(kit, level)
			"storehouse":
				_storehouse(kit, level)
			"barracks":
				_barracks(kit, level)
			_:
				kit.box(STONE, Transform3D(), Vector3(w * 0.8, 2.0, d * 0.8))
		if constructing:
			_scaffold(kit, w, d, 2.6 + level * 0.3)
	return kit.commit(true)


static func wall(level: int, grid_size: int) -> ArrayMesh:
	## The curtain wall around the whole grid, with corner towers and a south gate.
	var kit := MeshKit.new()
	var lo := -WALL_MARGIN
	var hi := grid_size * CELL + WALL_MARGIN
	var h := 2.4 + 0.6 * level
	var thick := 1.2
	var mid := (lo + hi) * 0.5
	var gate_half := 3.0
	_wall_run(kit, Vector3(lo, 0, lo), Vector3(hi, 0, lo), h, thick)
	_wall_run(kit, Vector3(lo, 0, lo), Vector3(lo, 0, hi), h, thick)
	_wall_run(kit, Vector3(hi, 0, lo), Vector3(hi, 0, hi), h, thick)
	_wall_run(kit, Vector3(lo, 0, hi), Vector3(mid - gate_half, 0, hi), h, thick)
	_wall_run(kit, Vector3(mid + gate_half, 0, hi), Vector3(hi, 0, hi), h, thick)
	for corner in [Vector3(lo, 0, lo), Vector3(hi, 0, lo), Vector3(lo, 0, hi), Vector3(hi, 0, hi)]:
		_round_tower(kit, Transform3D(Basis(), corner), 1.6, h + 1.6)
	# Gatehouse: two towers and a passage over the gate.
	for side in [-1.0, 1.0]:
		var at := Vector3(mid + side * (gate_half + 0.4), 0, hi)
		kit.box(STONE_DARK, Transform3D(Basis(), at), Vector3(2.2, h + 1.8, 2.2))
		_crenels(kit, at + Vector3(-1.1, h + 1.8, 0), at + Vector3(1.1, h + 1.8, 0), 0.0)
	kit.box(STONE_DARK, Transform3D(Basis(), Vector3(mid, h * 0.65, hi)), Vector3(gate_half * 2.0, h * 0.35 + 1.0, 1.8))
	kit.box(WOOD, Transform3D(Basis(), Vector3(mid, 0, hi + 0.2)), Vector3(gate_half * 2.0 - 0.6, h * 0.65, 0.3))
	return kit.commit(true)


static func wall_bounds(grid_size: int) -> Rect2:
	## The wall's outline in world xz, for picking it with the mouse.
	var lo := -WALL_MARGIN - 1.0
	var size := grid_size * CELL + (WALL_MARGIN + 1.0) * 2.0
	return Rect2(lo, lo, size, size)


# --- Buildings ----------------------------------------------------------------

static func _keep(kit: MeshKit, level: int) -> void:
	var h := 4.5 + 1.3 * level
	kit.box(STONE_DARK, Transform3D(), Vector3(7.4, 0.5, 7.4))
	kit.box(STONE, Transform3D(Basis(), Vector3(0, 0.5, 0)), Vector3(4.6, h, 4.6))
	_crenels(kit, Vector3(-2.3, h + 0.5, -2.3), Vector3(2.3, h + 0.5, -2.3), 0.0)
	_crenels(kit, Vector3(-2.3, h + 0.5, 2.3), Vector3(2.3, h + 0.5, 2.3), 0.0)
	_crenels(kit, Vector3(-2.3, h + 0.5, -2.3), Vector3(-2.3, h + 0.5, 2.3), 0.0)
	_crenels(kit, Vector3(2.3, h + 0.5, -2.3), Vector3(2.3, h + 0.5, 2.3), 0.0)
	var turrets := 2 if level < 3 else 4
	var corners := [Vector3(-2.4, 0.5, 2.4), Vector3(2.4, 0.5, 2.4), Vector3(-2.4, 0.5, -2.4), Vector3(2.4, 0.5, -2.4)]
	for i in turrets:
		var t := Transform3D(Basis(), corners[i])
		kit.cylinder(STONE, t, 0.85, h + 1.2, 8)
		kit.cone(ROOF, t.translated(Vector3(0, h + 1.2, 0)), 1.1, 2.0, 8)
	if level >= 2:
		# A great hall against the north side.
		var hall := Transform3D(Basis(), Vector3(0, 0.5, -3.2))
		kit.box(PLASTER, hall, Vector3(5.0, 2.2, 1.4))
		kit.gable_roof(ROOF, hall.translated(Vector3(0, 2.2, 0)), 5.0, 1.4, 1.0)
	# Banner pole on the roof.
	kit.cylinder(WOOD, Transform3D(Basis(), Vector3(0, h + 0.5, 0)), 0.08, 3.0, 5)
	kit.box(BANNER, Transform3D(Basis(), Vector3(0.6, h + 2.6, 0)), Vector3(1.1, 0.8, 0.06))
	# Door facing the gate.
	kit.box(WOOD, Transform3D(Basis(), Vector3(0, 0.5, 2.31)), Vector3(1.0, 1.6, 0.05))


static func _woodcutter(kit: MeshKit, level: int) -> void:
	var hut := Transform3D(Basis(), Vector3(-0.5, 0, -0.5))
	var hh := 1.4 + 0.12 * level
	kit.box(WOOD_LIGHT, hut, Vector3(2.0, hh, 1.6))
	kit.gable_roof(WOOD, hut.translated(Vector3(0, hh, 0)), 2.0, 1.6, 0.9)
	var piles := 1 + int(level >= 3) + int(level >= 6)
	# Log piles; logs lie along x (a cylinder rotated about z grows towards -x).
	var log_basis := Basis(Vector3.BACK, PI * 0.5)
	for p in piles:
		var centre := Vector3(1.3, 0, -1.1 + 1.0 * p)
		for at in [Vector3(0, 0.17, -0.18), Vector3(0, 0.17, 0.18), Vector3(0, 0.46, 0)]:
			kit.cylinder(WOOD, Transform3D(log_basis, centre + at + Vector3(0.5, 0, 0)), 0.17, 1.0, 6)
	kit.cylinder(WOOD, Transform3D(Basis(), Vector3(-1.3, 0, 1.2)), 0.25, 0.35, 6)
	kit.box(WOOD_LIGHT, Transform3D(Basis(), Vector3(-1.3, 0.35, 1.2)), Vector3(0.05, 0.4, 0.05))


static func _quarry(kit: MeshKit, level: int) -> void:
	kit.box(STONE_DARK.darkened(0.15), Transform3D(), Vector3(3.6, 0.08, 3.6))
	var rocks := [Vector3(-0.9, 0, -0.8), Vector3(0.6, 0, -1.0), Vector3(-1.1, 0, 0.6), Vector3(0.9, 0, 0.9), Vector3(0.0, 0, 0.1)]
	for i in rocks.size():
		var s := 0.7 + 0.15 * float((i * 7) % 3)
		kit.box(ROCK, Transform3D(Basis(Vector3.UP, i * 0.7), rocks[i]), Vector3(s, s * 0.8, s * 0.9))
	# Cut blocks stacked by the edge; the stack grows with level.
	var blocks := mini(2 + level, 8)
	for i in blocks:
		kit.box(STONE, Transform3D(Basis(), Vector3(1.3 - 0.5 * (i % 2), 0.08 + 0.4 * (i / 2), -0.1)), Vector3(0.45, 0.38, 0.6))
	# A simple wooden crane.
	kit.cylinder(WOOD, Transform3D(Basis(), Vector3(-1.4, 0, -1.4)), 0.1, 2.6, 5)
	kit.box(WOOD, Transform3D(Basis(Vector3.UP, -PI * 0.25), Vector3(-0.9, 2.5, -0.9)), Vector3(0.12, 0.12, 1.8))


static func _farm(kit: MeshKit, level: int, w: float) -> void:
	var field := w - 0.6
	kit.box(SOIL, Transform3D(), Vector3(field, 0.08, field))
	var rows := 6
	for i in rows:
		var x := -field * 0.5 + field * (i + 0.5) / rows
		var crop := CROP if (i + level) % 3 != 0 else CROP_GREEN
		kit.box(crop, Transform3D(Basis(), Vector3(x, 0.08, 0.6)), Vector3(field / rows * 0.6, 0.22, field - 1.6))
	# Barn in a corner.
	var barn := Transform3D(Basis(), Vector3(-field * 0.5 + 1.1, 0, -field * 0.5 + 0.8))
	var bh := 1.3 + 0.1 * level
	kit.box(WOOD_LIGHT, barn, Vector3(2.0, bh, 1.4))
	kit.gable_roof(THATCH, barn.translated(Vector3(0, bh, 0)), 2.0, 1.4, 0.8)
	if level >= 4:
		kit.cylinder(THATCH, Transform3D(Basis(), Vector3(field * 0.5 - 0.8, 0, -field * 0.5 + 0.8)), 0.55, 1.0, 8)
		kit.cone(THATCH.darkened(0.1), Transform3D(Basis(), Vector3(field * 0.5 - 0.8, 1.0, -field * 0.5 + 0.8)), 0.6, 0.6, 8)


static func _house(kit: MeshKit, level: int) -> void:
	var t := Transform3D()
	var h := 1.6 + 0.25 * mini(level, 6)
	kit.box(PLASTER, t, Vector3(2.4, h, 2.0))
	kit.box(WOOD, t.translated(Vector3(0, h * 0.5, 0)), Vector3(2.45, 0.1, 2.05))
	kit.gable_roof(ROOF, t.translated(Vector3(0, h, 0)), 2.4, 2.0, 1.1)
	kit.box(STONE_DARK, Transform3D(Basis(), Vector3(0.7, h, -0.5)), Vector3(0.35, 1.2, 0.35))
	kit.box(WOOD, Transform3D(Basis(), Vector3(0, 0, 1.01)), Vector3(0.5, 0.9, 0.05))
	if level >= 5:
		var annex := Transform3D(Basis(), Vector3(-1.3, 0, 1.2))
		kit.box(PLASTER, annex, Vector3(1.1, 1.2, 1.0))
		kit.gable_roof(ROOF, annex.translated(Vector3(0, 1.2, 0)), 1.1, 1.0, 0.6)


static func _storehouse(kit: MeshKit, level: int) -> void:
	var t := Transform3D(Basis(), Vector3(0, 0, -0.4))
	var h := 2.0 + 0.15 * level
	kit.box(STONE_DARK, t, Vector3(4.8, 0.4, 3.4))
	kit.box(WOOD_LIGHT, t.translated(Vector3(0, 0.4, 0)), Vector3(4.6, h, 3.2))
	kit.gable_roof(ROOF, t.translated(Vector3(0, h + 0.4, 0)), 4.6, 3.2, 1.4)
	kit.box(WOOD, Transform3D(Basis(), Vector3(0, 0.4, 1.21)), Vector3(1.4, 1.5, 0.05))
	# Crates and barrels in front, more of them at higher levels.
	var crates := mini(2 + level / 2, 6)
	for i in crates:
		var at := Vector3(-2.0 + 0.7 * i, 0, 2.2)
		if i % 2 == 0:
			kit.box(WOOD, Transform3D(Basis(Vector3.UP, 0.3 * i), at), Vector3(0.5, 0.5, 0.5))
		else:
			kit.cylinder(WOOD_LIGHT, Transform3D(Basis(), at), 0.25, 0.6, 7)


static func _barracks(kit: MeshKit, level: int) -> void:
	# A long hall along the north side and a training yard in front of it.
	var hall := Transform3D(Basis(), Vector3(0, 0, -1.6))
	var h := 1.8 + 0.15 * level
	kit.box(STONE_DARK, hall, Vector3(5.2, 0.4, 2.2))
	kit.box(PLASTER, hall.translated(Vector3(0, 0.4, 0)), Vector3(5.0, h, 2.0))
	kit.box(WOOD, hall.translated(Vector3(0, 0.4 + h * 0.5, 0)), Vector3(5.05, 0.12, 2.05))
	kit.gable_roof(ROOF, hall.translated(Vector3(0, h + 0.4, 0)), 5.0, 2.0, 1.1)
	kit.box(WOOD, Transform3D(Basis(), Vector3(0, 0.4, -0.59)), Vector3(0.9, 1.3, 0.05))
	kit.box(SOIL.lightened(0.15), Transform3D(Basis(), Vector3(0, 0, 1.2)), Vector3(5.4, 0.05, 3.0))
	# Training dummies: a post with a crossbar and a straw sack.
	var dummies := mini(2 + level / 3, 4)
	for i in dummies:
		var at := Vector3(-1.8 + 1.2 * i, 0.05, 1.5)
		kit.box(WOOD, Transform3D(Basis(), at), Vector3(0.12, 1.5, 0.12))
		kit.box(WOOD, Transform3D(Basis(), at + Vector3(0, 1.1, 0)), Vector3(0.7, 0.1, 0.1))
		kit.cylinder(THATCH, Transform3D(Basis(), at + Vector3(0, 0.75, 0)), 0.22, 0.45, 6)
	# A rack of spears.
	var rack := Vector3(2.3, 0.05, 1.0)
	kit.box(WOOD, Transform3D(Basis(), rack), Vector3(0.12, 0.9, 1.4))
	for i in 4:
		kit.box(WOOD_LIGHT, Transform3D(Basis(Vector3.RIGHT, 0.15), rack + Vector3(0.1, 0, -0.5 + 0.33 * i)), Vector3(0.05, 1.8, 0.05))
	kit.cylinder(WOOD, Transform3D(Basis(), Vector3(-2.5, 0.05, 2.5)), 0.06, 3.0, 5)
	kit.box(BANNER, Transform3D(Basis(), Vector3(-2.1, 2.3, 2.5)), Vector3(0.8, 0.6, 0.05))


# --- Construction ---------------------------------------------------------------

static func _site(kit: MeshKit, w: float, d: float) -> void:
	## A new building's site: a plank floor, a frame and a stack of timber.
	kit.box(SOIL, Transform3D(), Vector3(w - 0.4, 0.06, d - 0.4))
	kit.box(WOOD_LIGHT, Transform3D(Basis(), Vector3(0, 0.06, 0)), Vector3(w * 0.6, 0.12, d * 0.6))
	_scaffold(kit, w * 0.6, d * 0.6, 1.8)
	for i in 3:
		kit.box(WOOD_LIGHT, Transform3D(Basis(), Vector3(w * 0.5 - 0.6, 0.12 * i, -d * 0.5 + 0.5)), Vector3(0.6, 0.11, 1.2))


static func _scaffold(kit: MeshKit, w: float, d: float, h: float) -> void:
	## Poles at the corners and edge midpoints, tied together at the top.
	var hw := w * 0.5
	var hd := d * 0.5
	var pts := [Vector3(-hw, 0, -hd), Vector3(0, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, 0),
		Vector3(hw, 0, hd), Vector3(0, 0, hd), Vector3(-hw, 0, hd), Vector3(-hw, 0, 0)]
	for p: Vector3 in pts:
		kit.box(WOOD, Transform3D(Basis(), p), Vector3(0.1, h, 0.1))
	for y in [h * 0.5, h]:
		kit.box(WOOD, Transform3D(Basis(), Vector3(0, y, -hd)), Vector3(w, 0.08, 0.08))
		kit.box(WOOD, Transform3D(Basis(), Vector3(0, y, hd)), Vector3(w, 0.08, 0.08))
		kit.box(WOOD, Transform3D(Basis(), Vector3(-hw, y, 0)), Vector3(0.08, 0.08, d))
		kit.box(WOOD, Transform3D(Basis(), Vector3(hw, y, 0)), Vector3(0.08, 0.08, d))


# --- Wall parts -------------------------------------------------------------------

static func _wall_run(kit: MeshKit, a: Vector3, b: Vector3, h: float, thick: float) -> void:
	var dir := b - a
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	kit.box(STONE, Transform3D(basis, (a + b) * 0.5), Vector3(dir.length(), h, thick))
	_crenels(kit, a + Vector3(0, h, 0), b + Vector3(0, h, 0), thick * 0.5 - 0.15)


static func _crenels(kit: MeshKit, a: Vector3, b: Vector3, outward: float) -> void:
	## Merlons along the top of a wall from a to b.
	var dir := b - a
	var length := dir.length()
	var basis := Basis(Vector3.UP, atan2(-dir.z, dir.x))
	var side := basis * Vector3(0, 0, outward)
	var n := maxi(int(length / 1.1), 2)
	for i in n:
		var at := a.lerp(b, (i + 0.5) / n) + side
		kit.box(STONE, Transform3D(basis, at), Vector3(0.5, 0.45, 0.3))


static func _round_tower(kit: MeshKit, xform: Transform3D, r: float, h: float) -> void:
	kit.cylinder(STONE, xform, r, h, 10)
	kit.cylinder(STONE_DARK, xform.translated(Vector3(0, h, 0)), r + 0.25, 0.5, 10)
	kit.cone(ROOF, xform.translated(Vector3(0, h + 0.5, 0)), r + 0.3, 2.2, 10)
