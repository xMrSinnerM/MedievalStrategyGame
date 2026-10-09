extends SceneTree
## Plans roads between settlements over the terrain and writes data/roads.json.
##
## Run from the project folder (after place_settlements.gd or after moving
## settlements by hand):
##   godot --headless --path . --script res://scripts/tools/generate_roads.gd
##
## This overwrites data/roads.json. The result is plain point lists, so roads
## can be hand-tweaked afterwards.
##
## Network: towns and castles are joined by a minimum spanning tree plus a few
## shortcuts ("main" roads); every village gets a "track" to its lord's seat.
## Each road prefers flat, open ground, avoids water and steep slopes, crosses
## rivers as few times as it can, and reuses roads already built.

const ROADS_PATH := "res://data/roads.json"
const CELL := 4.0               ## pathfinding grid spacing in map units
const SHORTCUT_MAX := 520.0     ## extra main roads between hubs up to this far apart
const REUSE_COST := 0.3         ## cost multiplier on cells an earlier road already uses

var terrain: TerrainData
var astar := AStarGrid2D.new()
var size := 0


func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain_config.json"))
	terrain = TerrainData.new()
	if terrain.load_from_config(config) != OK:
		quit(1)
		return
	var settlements: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/settlements.json")).settlements
	var by_id := {}
	for s in settlements:
		by_id[s.id] = s

	_build_grid()
	var links := _plan_links(settlements, by_id)
	print("Routing %d roads" % links.size())
	var roads: Array = []
	for link in links:
		var a: Dictionary = by_id[link.from]
		var b: Dictionary = by_id[link.to]
		var points := _route(_pos(a), _pos(b))
		if points.is_empty():
			push_warning("No route from %s to %s" % [a.name, b.name])
			continue
		roads.append({"from": a.id, "to": b.id, "kind": link.kind, "points": points})

	var f := FileAccess.open(ROADS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"roads": roads}, "\t") + "\n")
	f.close()
	print("Wrote %d roads to %s" % [roads.size(), ROADS_PATH])
	quit()


static func _pos(s: Dictionary) -> Vector2:
	return Vector2(s.position[0], s.position[1])


func _build_grid() -> void:
	size = int(terrain.world_size / CELL) + 1
	astar.region = Rect2i(0, 0, size, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	var river_cells := {}
	for river in terrain.rivers:
		var pts: Array = river.points
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var steps := int(ceil(a.distance_to(b) / (CELL * 0.5))) + 1
			for s in steps:
				var p := a.lerp(b, float(s) / steps)
				river_cells[Vector2i(int(round(p.x / CELL)), int(round(p.y / CELL)))] = true

	for j in size:
		for i in size:
			var x := i * CELL
			var z := j * CELL
			var cell := Vector2i(i, j)
			if terrain.get_height(x, z) < terrain.sea_level + 0.5:
				astar.set_point_solid(cell, true)
				continue
			var slope := terrain.get_slope(x, z)
			if slope > 0.42:
				astar.set_point_solid(cell, true)
				continue
			var biome := terrain.get_biome(x, z)
			var cost := 1.0 + slope * slope * 60.0 + biome.g * 0.6 + biome.b * 0.4
			if river_cells.has(cell):
				cost += 12.0   # bridges are expensive: cross rivers rarely
			astar.set_point_weight_scale(cell, cost)


func _plan_links(settlements: Array, by_id: Dictionary) -> Array[Dictionary]:
	var hubs := settlements.filter(func(s): return s.type != "village")
	var links: Array[Dictionary] = []
	var linked := {}

	# Minimum spanning tree over the hubs (Prim's algorithm).
	var in_tree := {hubs[0].id: true}
	while in_tree.size() < hubs.size():
		var best_d := INF
		var best_pair := []
		for a in hubs:
			if not in_tree.has(a.id):
				continue
			for b in hubs:
				if in_tree.has(b.id):
					continue
				var d := _pos(a).distance_to(_pos(b))
				if d < best_d:
					best_d = d
					best_pair = [a, b]
		in_tree[best_pair[1].id] = true
		_add_link(links, linked, best_pair[0].id, best_pair[1].id, "main")

	# A few shortcuts so the network has loops: each hub to its nearest neighbours.
	for a in hubs:
		var near := hubs.filter(func(b): return b.id != a.id and _pos(a).distance_to(_pos(b)) < SHORTCUT_MAX)
		near.sort_custom(func(p, q): return _pos(a).distance_to(_pos(p)) < _pos(a).distance_to(_pos(q)))
		for b in near.slice(0, 2):
			_add_link(links, linked, a.id, b.id, "main")

	# Shorter roads first, so longer ones can reuse them.
	links.sort_custom(func(p, q): return _link_length(p, by_id) < _link_length(q, by_id))

	for v in settlements:
		if v.type == "village" and v.bound_to != null and by_id.has(v.bound_to):
			_add_link(links, linked, v.bound_to, v.id, "track")
	return links


func _link_length(link: Dictionary, by_id: Dictionary) -> float:
	return _pos(by_id[link.from]).distance_to(_pos(by_id[link.to]))


static func _add_link(links: Array[Dictionary], linked: Dictionary, a: String, b: String, kind: String) -> void:
	var key := a + "|" + b if a < b else b + "|" + a
	if linked.has(key):
		return
	linked[key] = true
	links.append({"from": a, "to": b, "kind": kind})


func _route(from: Vector2, to: Vector2) -> Array:
	var start := _free_cell_near(from)
	var goal := _free_cell_near(to)
	if start.x < 0 or goal.x < 0:
		return []
	var cells := astar.get_id_path(start, goal)
	if cells.is_empty():
		return []
	for c in cells:
		astar.set_point_weight_scale(c, minf(astar.get_point_weight_scale(c), 1.0) * REUSE_COST + 0.05)

	var raw: Array[Vector2] = [from]
	for c in cells:
		raw.append(Vector2(c) * CELL)
	raw.append(to)
	var smooth := _chaikin(_simplify(raw, 2.5), 2)
	var out: Array = []
	for p in smooth:
		out.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	return out


func _free_cell_near(p: Vector2) -> Vector2i:
	var c := Vector2i(int(round(p.x / CELL)), int(round(p.y / CELL)))
	for r in 6:
		for oy in range(-r, r + 1):
			for ox in range(-r, r + 1):
				var q := c + Vector2i(ox, oy)
				if astar.is_in_boundsv(q) and not astar.is_point_solid(q):
					return q
	return Vector2i(-1, -1)


static func _simplify(points: Array[Vector2], tolerance: float) -> Array[Vector2]:
	## Ramer-Douglas-Peucker: drop points that stay within `tolerance` of the line.
	if points.size() < 3:
		return points
	var first := points[0]
	var last := points[points.size() - 1]
	var max_d := 0.0
	var index := 0
	for k in range(1, points.size() - 1):
		var d := points[k].distance_to(Geometry2D.get_closest_point_to_segment(points[k], first, last))
		if d > max_d:
			max_d = d
			index = k
	if max_d <= tolerance:
		return [first, last]
	var left := _simplify(points.slice(0, index + 1), tolerance)
	var right := _simplify(points.slice(index), tolerance)
	left.pop_back()
	left.append_array(right)
	return left


static func _chaikin(points: Array[Vector2], iterations: int) -> Array[Vector2]:
	## Corner cutting, keeping the end points where they are.
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
