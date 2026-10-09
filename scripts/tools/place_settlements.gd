extends SceneTree
## Places towns, castles and villages for every faction on the current terrain
## and writes data/settlements.json.
##
## Run from the project folder:
##   godot --headless --path . --script res://scripts/tools/place_settlements.gd
##
## This overwrites data/settlements.json. Run it after generating a new
## continent, then run generate_roads.gd. Positions are only a starting point:
## edit the JSON by hand to move, rename or add settlements.

const SETTLEMENTS_PATH := "res://data/settlements.json"
const GRID := 12.0             ## candidate spacing in map units

## Names per faction, in placement order. The first town is the capital and
## must match "capital" in factions.json.
const NAMES := {
	"aldmere": {
		"town": ["Highford", "Wexmoor"],
		"castle": ["Ravenhold", "Brackenwall"],
		"village": ["Millbrook", "Ashby", "Thornley", "Elmstead", "Oakhurst"],
	},
	"varnholt": {
		"town": ["Frostgard", "Kaldvik"],
		"castle": ["Ulfhall", "Isenvarde"],
		"village": ["Snjorby", "Hrimstad", "Birkeli", "Varmdal"],
	},
	"ashkar": {
		"town": ["Qasr Umbar", "Zahirah"],
		"castle": ["Dar Sennek", "Qalat Yaruq"],
		"village": ["Bir Assam", "Wadi Tarfa", "Nakhla", "Sabrin"],
	},
	"thornwald": {
		"town": ["Elderholm", "Briarwick"],
		"castle": ["Hollowmere", "Greywood"],
		"village": ["Fernhollow", "Mossgate", "Larchford", "Bramblecote", "Wrenfield"],
	},
	"corvane": {
		"town": ["Saltmere", "Port Calder"],
		"castle": ["Gullcrest", "Seawatch"],
		"village": ["Tidewell", "Corran", "Shellbay", "Driftholm"],
	},
}

## Minimum distances: town to town, castle to town or castle, and anything to a village.
const SPACING := {"town": 300.0, "castle": 210.0, "village": 95.0}

var terrain: TerrainData
var factions: Array = []
var placed: Array[Dictionary] = []
var near_river := {}          ## Vector2i grid cell -> true
var region_noise := FastNoiseLite.new()
var mainland := {}            ## Vector2i grid cell -> true, reachable on foot from the centre


func _initialize() -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/terrain_config.json"))
	terrain = TerrainData.new()
	if terrain.load_from_config(config) != OK:
		quit(1)
		return
	factions = JSON.parse_string(FileAccess.get_file_as_string("res://data/factions.json")).factions
	region_noise.seed = 91
	region_noise.frequency = 0.004
	region_noise.fractal_octaves = 3
	_mark_rivers()

	_flood_mainland()
	var candidates := _candidates()
	print("%d candidate spots" % candidates.size())
	for kind in ["town", "castle", "village"]:
		for faction in factions:
			_place_kind(faction, kind, candidates)

	_bind_villages()
	var out: Array = []
	for s in placed:
		out.append({
			"id": s.id, "name": s.name, "type": s.type, "faction": s.faction,
			"position": [snappedf(s.pos.x, 0.1), snappedf(s.pos.y, 0.1)],
			"rotation_deg": s.rotation_deg, "bound_to": s.bound_to,
		})
	var f := FileAccess.open(SETTLEMENTS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"settlements": out}, "\t") + "\n")
	f.close()
	print("Wrote %d settlements to %s" % [out.size(), SETTLEMENTS_PATH])
	quit()


func _mark_rivers() -> void:
	for river in terrain.rivers:
		for p in river.points:
			var c := Vector2i(int(p[0] / 40.0), int(p[1] / 40.0))
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					near_river[c + Vector2i(ox, oy)] = true


func _passable(cell: Vector2i) -> bool:
	var x := cell.x * GRID
	var z := cell.y * GRID
	if not terrain.contains(x, z):
		return false
	return terrain.get_height(x, z) >= terrain.sea_level + 0.5 and terrain.get_slope(x, z) <= 0.4


func _flood_mainland() -> void:
	## Settlements only go where parties can walk to from the heart of the map
	## (no islands, no valleys sealed off by mountains).
	var start := Vector2i(int(terrain.world_size * 0.5 / GRID), int(terrain.world_size * 0.48 / GRID))
	var queue: Array[Vector2i] = [start]
	mainland[start] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + o
			if not mainland.has(n) and _passable(n):
				mainland[n] = true
				queue.append(n)


func _region(pos: Vector2) -> String:
	var warped := pos + Vector2(region_noise.get_noise_2d(pos.x, pos.y), region_noise.get_noise_2d(pos.y + 500.0, pos.x)) * 160.0
	var best := ""
	var best_d := INF
	for faction in factions:
		var c: Array = faction.region_center
		var d := warped.distance_squared_to(Vector2(c[0], c[1]))
		if d < best_d:
			best_d = d
			best = faction.id
	return best


func _candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var steps := int(terrain.world_size / GRID)
	for j in range(4, steps - 4):
		for i in range(4, steps - 4):
			var pos := Vector2(i * GRID, j * GRID)
			var h := terrain.get_height(pos.x, pos.y)
			if h < terrain.sea_level + 3.0 or h > 165.0 or not mainland.has(Vector2i(i, j)):
				continue
			# Needs a reasonably flat footprint, judged on a ring around the spot.
			var worst := 0.0
			var water_nearby := false
			for a in 8:
				var off := Vector2.from_angle(a * TAU / 8.0) * 22.0
				var q := pos + off
				worst = maxf(worst, absf(terrain.get_height(q.x, q.y) - h))
				if terrain.get_height(q.x, q.y) < terrain.sea_level + 1.0:
					water_nearby = true
			if worst > 7.0 or water_nearby:
				continue
			var coast := false
			for a in 8:
				var q := pos + Vector2.from_angle(a * TAU / 8.0) * 70.0
				if terrain.get_height(q.x, q.y) < terrain.sea_level:
					coast = true
					break
			result.append({
				"pos": pos,
				"height": h,
				"flat": 1.0 - worst / 7.0,
				"river": near_river.has(Vector2i(int(pos.x / 40.0), int(pos.y / 40.0))),
				"coast": coast,
				"region": _region(pos),
			})
	return result


func _place_kind(faction: Dictionary, kind: String, candidates: Array[Dictionary]) -> void:
	var names: Array = NAMES[faction.id][kind]
	var centre := Vector2(faction.region_center[0], faction.region_center[1])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(faction.id + kind)
	for name in names:
		var best: Dictionary = {}
		var best_score := -INF
		for c in candidates:
			if c.region != faction.id or not _spacing_ok(c.pos, kind):
				continue
			var score := _score(c, kind, faction, centre)
			if score > best_score:
				best_score = score
				best = c
		if best.is_empty():
			push_warning("No room for %s %s of %s" % [kind, name, faction.id])
			continue
		placed.append({
			"id": "%s_%s_%s" % [faction.id, kind, String(name).to_lower().replace(" ", "_")],
			"name": name,
			"type": kind,
			"faction": faction.id,
			"pos": best.pos,
			"rotation_deg": rng.randi_range(0, 35) * 10,
			"bound_to": null,
		})


func _spacing_ok(pos: Vector2, kind: String) -> bool:
	for s in placed:
		var need: float = SPACING.castle
		if kind == "village" or s.type == "village":
			need = SPACING.village
		elif kind == "town" and s.type == "town":
			need = SPACING.town
		if pos.distance_to(s.pos) < need:
			return false
	return true


func _score(c: Dictionary, kind: String, faction: Dictionary, centre: Vector2) -> float:
	var d_centre: float = c.pos.distance_to(centre)
	var score: float = c.flat * 2.0
	match kind:
		"town":
			# Capitals near the heart of the realm; towns like rivers and, on the east coast, harbours.
			score -= d_centre / 250.0 if _count(faction.id, "town") == 0 else -d_centre / 900.0
			score += 1.2 if c.river else 0.0
			score += 1.0 if c.coast and faction.id == "corvane" else 0.0
		"castle":
			# Castles guard the realm's edges and like higher ground.
			score += d_centre / 350.0
			score += clampf((c.height - terrain.sea_level) / 80.0, 0.0, 1.5)
		"village":
			# Villages cluster around their lord's town or castle, near water.
			var nearest := _nearest_hub_distance(c.pos, faction.id)
			score -= absf(nearest - 140.0) / 60.0
			score += 0.8 if c.river else 0.0
	return score


func _count(faction_id: String, kind: String) -> int:
	return placed.filter(func(s): return s.faction == faction_id and s.type == kind).size()


func _nearest_hub_distance(pos: Vector2, faction_id: String) -> float:
	var best := INF
	for s in placed:
		if s.faction == faction_id and s.type != "village":
			best = minf(best, pos.distance_to(s.pos))
	return best


func _bind_villages() -> void:
	for v in placed:
		if v.type != "village":
			continue
		var best_d := INF
		for s in placed:
			if s.faction == v.faction and s.type != "village":
				var d: float = v.pos.distance_to(s.pos)
				if d < best_d:
					best_d = d
					v.bound_to = s.id
