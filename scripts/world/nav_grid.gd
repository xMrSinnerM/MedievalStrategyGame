class_name NavGrid
extends RefCounted
## Travel costs over the whole map and A* pathfinding for parties.
##
## Each grid cell has a cost per unit of distance: lower is faster. A party's
## speed is its base speed divided by the cost of the ground it is on, so the
## same numbers decide both the route and how fast it is walked.

const CELL := 4.0               ## grid spacing in map units

## Cost per unit of distance (1.0 = open plains).
const ROAD := 0.6
const PLAINS := 1.0
const DESERT := 1.4
const SNOW := 1.4
const FOREST := 1.8
const HILLS := 0.8              ## added on steep-ish ground, scaled by slope
const FORD := 3.0               ## wading across a river where there is no bridge
const MAX_SLOPE := 0.42         ## steeper than this is impassable (mountains, cliffs)

var size := 0
var astar := AStarGrid2D.new()
var costs := PackedFloat32Array()    ## per cell, 0 = impassable
var kinds := PackedByteArray()       ## per cell, index into KIND_NAMES

enum Kind { BLOCKED, ROAD, PLAINS, FOREST, DESERT, SNOW, HILLS, FORD }
const KIND_NAMES := ["Impassable", "Road", "Plains", "Forest", "Desert", "Snow", "Hills", "River ford"]

var _terrain: TerrainData


func build(terrain: TerrainData, roads: RoadNetwork) -> void:
	_terrain = terrain
	size = int(terrain.world_size / CELL) + 1
	astar.region = Rect2i(0, 0, size, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	costs.resize(size * size)
	kinds.resize(size * size)

	var river_cells := _river_cells(terrain)
	var bridge_cells := _bridge_cells(roads)
	for j in size:
		for i in size:
			var x := i * CELL
			var z := j * CELL
			var k := j * size + i
			var cost := 0.0
			var kind := Kind.BLOCKED
			var on_road := roads.is_on_road(x, z) or bridge_cells.has(Vector2i(i, j))
			var slope := terrain.get_slope(x, z)
			if on_road:
				cost = ROAD
				kind = Kind.ROAD
			elif terrain.get_height(x, z) >= terrain.sea_level + 0.3 and slope <= MAX_SLOPE:
				var biome := terrain.get_biome(x, z)
				cost = PLAINS + biome.g * (FOREST - PLAINS) + biome.r * (DESERT - PLAINS) + biome.b * (SNOW - PLAINS)
				var hills := smoothstep(0.15, MAX_SLOPE, slope) * HILLS
				cost += hills
				kind = Kind.PLAINS
				if biome.g > 0.5:
					kind = Kind.FOREST
				elif biome.r > 0.5:
					kind = Kind.DESERT
				elif biome.b > 0.5:
					kind = Kind.SNOW
				elif hills > 0.3:
					kind = Kind.HILLS
				if river_cells.has(Vector2i(i, j)):
					cost = maxf(cost, FORD)
					kind = Kind.FORD
			costs[k] = cost
			kinds[k] = kind
			if cost <= 0.0:
				astar.set_point_solid(Vector2i(i, j), true)
			else:
				# Scaled so roads weigh 1: the distance estimate then never
				# overshoots, and A* finds the truly fastest route.
				astar.set_point_weight_scale(Vector2i(i, j), cost / ROAD)


func cost_at(x: float, z: float) -> float:
	## Travel cost of the ground here (0 where impassable).
	return costs[_index(_cell(Vector2(x, z)))]


func kind_name(x: float, z: float) -> String:
	return KIND_NAMES[kinds[_index(_cell(Vector2(x, z)))]]


func is_passable(x: float, z: float) -> bool:
	return cost_at(x, z) > 0.0


func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	## A smoothed route in map units from `from` towards `to`. If `to` can't be
	## reached (an island, a mountain top), the route ends as close as it gets.
	var start := _free_cell_near(_cell(from))
	var goal := _free_cell_near(_cell(to))
	if start.x < 0 or goal.x < 0:
		return PackedVector2Array()
	var cells := astar.get_id_path(start, goal, true)
	if cells.is_empty():
		return PackedVector2Array()
	var reached_goal := cells[cells.size() - 1] == goal
	var pts: Array[Vector2] = [from]
	for idx in _pull_string(cells):
		pts.append(Vector2(cells[idx]) * CELL)
	if reached_goal and _cell(to) == goal:
		pts.append(to)
	var out := PackedVector2Array()
	for p in _chaikin(pts, 2):
		out.append(p)
	return out


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(round(p.x / CELL)), 0, size - 1), clampi(int(round(p.y / CELL)), 0, size - 1))


func _index(c: Vector2i) -> int:
	return c.y * size + c.x


func _free_cell_near(c: Vector2i) -> Vector2i:
	for r in 12:
		var best := Vector2i(-1, -1)
		var best_d := INF
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				var q := c + Vector2i(ox, oy)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					var d := Vector2(ox, oy).length_squared()
					if d < best_d:
						best_d = d
						best = q
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _pull_string(cells: Array[Vector2i]) -> PackedInt32Array:
	## Keeps only the corners of a cell path: from each corner, skip ahead to the
	## furthest cell reachable in a straight line over ground no more costly than
	## the path itself used, so shortcuts never leave a road or cut through forest.
	var keep := PackedInt32Array()
	var anchor := 0
	while anchor < cells.size() - 1:
		var worst := costs[_index(cells[anchor])]
		var best := anchor + 1
		var j := anchor + 1
		while j < cells.size():
			worst = maxf(worst, costs[_index(cells[j])])
			if _line_ok(cells[anchor], cells[j], worst + 0.01):
				best = j
			elif j - best > 8:
				break
			j += 1
		keep.append(best)
		anchor = best
	return keep


func _line_ok(a: Vector2i, b: Vector2i, max_cost: float) -> bool:
	var steps := int(ceil(Vector2(a).distance_to(Vector2(b)) * 2.0))
	for s in range(1, steps):
		var p := Vector2(a).lerp(Vector2(b), float(s) / steps)
		var c := costs[_index(Vector2i(int(round(p.x)), int(round(p.y))))]
		if c <= 0.0 or c > max_cost:
			return false
	return true


static func _chaikin(points: Array[Vector2], iterations: int) -> Array[Vector2]:
	## Corner cutting for gentle curves, keeping the end points.
	var pts := points
	for it in iterations:
		if pts.size() < 3:
			return pts
		var next: Array[Vector2] = [pts[0]]
		for k in pts.size() - 1:
			next.append(pts[k].lerp(pts[k + 1], 0.25))
			next.append(pts[k].lerp(pts[k + 1], 0.75))
		next.append(pts[pts.size() - 1])
		pts = next
	return pts


func _bridge_cells(roads: RoadNetwork) -> Dictionary:
	var cells := {}
	for b in roads.bridges:
		var reach := int(ceil(b.half_length / CELL)) + 1
		var centre := _cell(b.at)
		for oy in range(-reach, reach + 1):
			for ox in range(-reach, reach + 1):
				var c := centre + Vector2i(ox, oy)
				if roads.bridge_deck_at(c.x * CELL, c.y * CELL) > -INF:
					cells[c] = true
	return cells


func _river_cells(terrain: TerrainData) -> Dictionary:
	var cells := {}
	for river in terrain.rivers:
		var pts: Array = river.points
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var r: float = pts[k][3] * 0.5 + 1.0
			var steps := int(ceil(a.distance_to(b) / (CELL * 0.5))) + 1
			for s in steps + 1:
				var p := a.lerp(b, float(s) / steps)
				var reach := int(ceil(r / CELL))
				for oy in range(-reach, reach + 1):
					for ox in range(-reach, reach + 1):
						var c := Vector2i(int(round(p.x / CELL)) + ox, int(round(p.y / CELL)) + oy)
						if (Vector2(c) * CELL).distance_to(p) <= r:
							cells[c] = true
	return cells
