class_name CastleModels
extends RefCounted
## Models for the castle screen, built from KayKit pieces (KitModels). Each
## model sits on its footprint with the origin at the footprint's centre, and
## grows a little with level. Roofs and flags take the owner's colour.

const CELL := 2.0          ## world units per castle grid cell
const WALL_MARGIN := 2.0   ## gap between the grid's edge and the wall


static func build(type: String, level: int, size: Vector2i, constructing: bool, team: Color) -> ArrayMesh:
	## The model for one building. Level 0 while constructing is a building site.
	var kit := KitModels.new()
	var w := size.x * CELL
	var d := size.y * CELL
	if level <= 0:
		_put(kit, "building_stage_A" if w <= 4.0 else "building_stage_B", Vector3.ZERO, w / 2.0)
		return kit.commit(team)
	match type:
		"keep":
			_put(kit, "building_castle_blue", Vector3.ZERO, 3.3 + 0.12 * level)
			if level >= 2:
				_put(kit, "building_tower_A_blue", Vector3(-3.0, 0, 2.8), 1.5 + 0.1 * level)
				_put(kit, "building_tower_A_blue", Vector3(3.0, 0, 2.8), 1.5 + 0.1 * level)
			if level >= 4:
				_put(kit, "building_tower_B_blue", Vector3(-3.0, 0, -2.8), 1.6)
				_put(kit, "building_tower_B_blue", Vector3(3.0, 0, -2.8), 1.6)
		"woodcutter":
			_put(kit, "building_lumbermill_blue", Vector3(-0.3, 0, -0.3), 2.7 + 0.05 * level)
			_put(kit, "resource_lumber", Vector3(1.3, 0, 1.3), 1.4)
			_put(kit, "tree_single_A_cut", Vector3(-1.4, 0, 1.4), 1.6)
		"quarry":
			_put(kit, "building_mine_blue", Vector3(0, 0, -0.2), 2.4 + 0.05 * level)
			_put(kit, "resource_stone", Vector3(1.4, 0, 1.4), 1.3)
			_put(kit, "rock_single_B", Vector3(-1.5, 0, 1.5), 1.4)
		"farm":
			_put(kit, "building_grain", Vector3(0.6, 0, 0.6), 2.8)
			_put(kit, "building_windmill_blue", Vector3(-1.9, 0, -1.9), 2.2 + 0.08 * level)
			_put(kit, "sack", Vector3(-2.2, 0, 0.6), 1.6)
		"house":
			_put(kit, "building_home_B_blue" if level >= 4 else "building_home_A_blue", Vector3.ZERO, 3.9 + 0.12 * mini(level, 6))
		"storehouse":
			_put(kit, "building_market_blue", Vector3(0, 0, -0.3), 3.2)
			_put(kit, "crate_A_big", Vector3(-2.0, 0, 2.0), 1.5)
			_put(kit, "barrel", Vector3(-1.2, 0, 2.3), 1.5)
			_put(kit, "crate_long_A", Vector3(1.6, 0, 2.1), 1.5)
		"barracks":
			_put(kit, "building_barracks_blue", Vector3(0, 0, -0.6), 3.7 + 0.05 * level)
			_put(kit, "weaponrack", Vector3(2.2, 0, 2.0), 1.6)
			_put(kit, "target", Vector3(-2.0, 0, 2.2), 1.6)
		"workshop":
			_put(kit, "building_blacksmith_blue", Vector3(0, 0, -0.5), 3.9 + 0.05 * level)
			_put(kit, "wheelbarrow", Vector3(-2.0, 0, 2.0), 1.6)
			_put(kit, "ladder", Vector3(2.2, 0, 1.8), 1.6)
		_:
			_put(kit, "crate_A_big", Vector3.ZERO, 2.0)
	if constructing:
		_put(kit, "building_scaffolding", Vector3(w * 0.3, 0, d * 0.3), 0.9)
	return kit.commit(team)


static func wall(level: int, grid_size: int, team: Color) -> ArrayMesh:
	## The curtain wall around the whole grid: corner towers, a south gate, more
	## towers as it levels up, and stores and ladders along its inside.
	var kit := KitModels.new()
	var lo := -WALL_MARGIN
	var hi := grid_size * CELL + WALL_MARGIN
	var side := hi - lo
	var n := 9
	var s := side / n / 2.0
	var hs := Vector3(s, s * (0.9 + 0.08 * level), s)
	for k in n:
		var t := lo + (k + 0.5) * side / n
		_put_s(kit, "wall_straight", Vector3(t, 0, lo), 0.0, hs)
		_put_s(kit, "wall_straight", Vector3(lo, 0, t), PI * 0.5, hs)
		_put_s(kit, "wall_straight", Vector3(hi, 0, t), PI * 0.5, hs)
		_put_s(kit, "wall_straight_gate" if k == n / 2 else "wall_straight", Vector3(t, 0, hi), PI if k == n / 2 else 0.0, hs)
	var tower := 1.8 + 0.12 * level
	var mid := (lo + hi) * 0.5
	var towers: Array[Vector3] = [Vector3(lo, 0, lo), Vector3(hi, 0, lo), Vector3(lo, 0, hi), Vector3(hi, 0, hi)]
	for c in towers:
		_put(kit, "building_tower_A_blue", c, tower)
		_flag(kit, c + Vector3(0, 2.19 * tower, 0), tower)
	if level >= 2:
		# Towers halfway along the walls; catapult towers from level 4.
		for c in [Vector3(mid, 0, lo), Vector3(lo, 0, mid), Vector3(hi, 0, mid)]:
			_put(kit, "building_tower_catapult_blue" if level >= 4 else "building_tower_B_blue", c, tower * 0.9)
			if level < 4:
				_flag(kit, c + Vector3(0, 2.48 * tower * 0.9, 0), tower)
	if level >= 3:
		var gate := side / n * 0.5 + 0.5
		for x in [mid - gate, mid + gate]:
			_put(kit, "building_tower_base_blue", Vector3(x, 0, hi), tower)
			_flag(kit, Vector3(x, 1.5 * tower, hi), tower)
	# Life along the inside of the wall: stores, arrows, ladders up to the wall walk.
	var props := ["barrel", "crate_A_big", "crate_B_small", "bucket_arrows", "weaponrack", "sack", "crate_long_B", "barrel"]
	var inside := lo + 1.6
	var far := hi - 1.6
	var spots := [
		[Vector3(lo + 5.0, 0, inside), 0.0], [Vector3(hi - 6.0, 0, inside), 0.0], [Vector3(mid + 6.0, 0, inside), 0.0],
		[Vector3(inside, 0, lo + 9.0), PI * 0.5], [Vector3(inside, 0, hi - 9.0), PI * 0.5], [Vector3(far, 0, lo + 7.0), -PI * 0.5],
		[Vector3(far, 0, hi - 7.0), -PI * 0.5], [Vector3(mid - 9.0, 0, far), PI], [Vector3(mid + 9.0, 0, far), PI],
	]
	for i in spots.size():
		var at: Vector3 = spots[i][0]
		var yaw: float = spots[i][1]
		_put(kit, props[i % props.size()], at, 2.4, yaw)
		_put(kit, props[(i + 3) % props.size()], at + Basis(Vector3.UP, yaw) * Vector3(1.4, 0, 0.3), 2.1, yaw + 0.4)
		if i % 3 == 0:
			_put(kit, "ladder", at + Basis(Vector3.UP, yaw) * Vector3(-2.2, 0, -0.7), 3.0, yaw)
	return kit.commit(team)


static func wall_bounds(grid_size: int) -> Rect2:
	## The wall's outline in world xz, for picking it with the mouse.
	var lo := -WALL_MARGIN - 1.0
	var size := grid_size * CELL + (WALL_MARGIN + 1.0) * 2.0
	return Rect2(lo, lo, size, size)


static func _flag(kit: KitModels, top: Vector3, scale: float) -> void:
	## A pennant in the owner's colour on top of a tower.
	_put(kit, "flag_blue", top - Vector3(0, 0.1, 0), scale * 2.0)


static func _put(kit: KitModels, piece: String, at: Vector3, scale: float, yaw := 0.0) -> void:
	kit.add(piece, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * scale), at))


static func _put_s(kit: KitModels, piece: String, at: Vector3, yaw: float, scale: Vector3) -> void:
	kit.add(piece, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale), at))
