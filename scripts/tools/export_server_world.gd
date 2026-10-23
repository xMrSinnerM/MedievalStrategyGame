extends SceneTree
## Writes server/world/world.json: the robber baron camps, placed exactly as
## the game places them (BaronPlacer), how their starting level grows with
## distance, the spots where players' castles can stand (PlayerSpots), and
## for each spot the places around it where invader camps can stand during a
## Baron Invasion, the resource villages (VillagePlacer, with the old villages
## of data/settlements.json among them) and the capitals
## (the towns of data/settlements.json, see capitals()) and the fortresses
## (its other castles, see fortresses()). The server
## can't read the terrain, so it uses these lists; the game reads the
## villages from here too.
##
## Run from the project folder after changing the terrain, settlements,
## player.json, factions.json, the "camps" section of barons.json or the
## "placement" section of villages.json:
##   godot --headless --path . --script res://scripts/tools/export_server_world.gd

const OUT := "res://server/world/world.json"
const MAIN_CASTLE := "player_castle"


func _initialize() -> void:
	var game_data = load("res://scripts/core/game_data.gd").new()
	if not game_data.ensure_loaded():
		push_error("Could not load the world")
		quit(1)
		return
	var own: Dictionary = game_data.settlements_by_id.get(MAIN_CASTLE, {})
	var home := Vector2(own.position[0], own.position[1])
	var baron_rules := BaronRules.load_default()
	var camps := BaronPlacer.place(baron_rules, game_data.nav.is_passable, game_data.settlements,
			home, game_data.terrain.world_size)
	var spots := PlayerSpots.place(game_data.terrain, game_data.nav.is_passable, game_data.settlements, camps, home)
	var invaders := invasion_spots(game_data, spots, camps)
	var avoid: Array[Vector2] = []
	for c: Dictionary in camps:
		avoid.append(Vector2(c.position[0], c.position[1]))
	for s: Array in spots:
		avoid.append(Vector2(s[0], s[1]))
	var passing: Array[Vector2] = []
	for row: Array in invaders:
		for s: Array in row:
			passing.append(Vector2(s[0], s[1]))
	var village_rules := VillageRules.load_default()
	var villages := VillagePlacer.place(village_rules,
			func(p: Vector2) -> bool: return _open(game_data, p, VILLAGE_RADIUS, VILLAGE_MAX_SLOPE),
			game_data.settlements, avoid, passing, game_data.terrain.world_size)
	# The old villages after the placed ones, so those keep their ids.
	villages += VillagePlacer.from_settlements(village_rules, game_data.settlements, game_data.terrain.world_size)
	var out := {
		"home": [home.x, home.y],
		"camp_levels": {"per_distance": float(baron_rules.camps.get("level_per_distance", 170.0)),
				"max": int(baron_rules.camps.get("start_level_max", 12))},
		"camps": camps,
		"spots": spots,
		"invasion_spots": invaders,
		"villages": villages,
		"capitals": capitals(game_data),
		"fortresses": fortresses(game_data),
	}
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t", false))
	file.close()
	print("wrote %s with %d camps, %d spots, %d villages, %d capitals and %d fortresses" % [OUT, camps.size(), spots.size(),
			villages.size(), out.capitals.size(), out.fortresses.size()])
	game_data.free()
	quit()


## Invader camps stand this far from the castle, on open ground clear of
## other castles' spots, camps, settlements and each other.
const INVADER_RINGS := [65.0, 85.0, 105.0, 125.0, 145.0]
const INVADER_PER_SPOT := 4
const INVADER_GAP := 35.0
const INVADER_MAX_SLOPE := 0.15
## A village needs a little more room than an invader camp.
const VILLAGE_RADIUS := 11.0
const VILLAGE_MAX_SLOPE := 0.15


static func capitals(game_data) -> Array:
	## Every town as a capital: a faction's capital town is level 2, the others level 1.
	var seats := {}
	for f: Dictionary in game_data.factions:
		seats[String(f.get("capital", ""))] = true
	var out := []
	for s: Dictionary in game_data.settlements:
		if s.get("type", "") != "town":
			continue
		out.append({"id": s.id, "name": s.name, "position": [s.position[0], s.position[1]], "level": 2 if seats.has(s.id) else 1,
				"resource": "gold", "capital": true, "faction": s.faction})
	return out


static func fortresses(game_data) -> Array:
	## Every castle but yours, as a fortress (data/fortresses.json).
	var out := []
	for s: Dictionary in game_data.settlements:
		if s.get("type", "") == "castle" and s.id != MAIN_CASTLE:
			out.append({"id": s.id, "name": s.name, "position": [s.position[0], s.position[1]]})
	return out


static func invasion_spots(game_data, spots: Array, camps: Array) -> Array:
	var others: Array[Vector2] = []
	for s: Array in spots:
		others.append(Vector2(s[0], s[1]))
	for c: Dictionary in camps:
		others.append(Vector2(c.position[0], c.position[1]))
	var out := []
	for i in spots.size():
		var home := Vector2(spots[i][0], spots[i][1])
		var found: Array[Vector2] = []
		var turn := float(i % 7) * 0.4
		for radius: float in INVADER_RINGS:
			for k in 16:
				if found.size() >= INVADER_PER_SPOT:
					break
				var p := home + Vector2.from_angle(turn + k * TAU / 16.0) * radius
				if not _open_ground(game_data, p):
					continue
				if others.any(func(q: Vector2) -> bool: return q != home and p.distance_to(q) < INVADER_GAP):
					continue
				if found.any(func(q: Vector2) -> bool: return p.distance_to(q) < INVADER_GAP * 1.5):
					continue
				if game_data.settlements.any(func(st: Dictionary) -> bool:
						var reach: float = PlayerSpots.SETTLEMENT_RADIUS.get(st.get("type", "village"), 20.0) + 35.0
						return p.distance_to(Vector2(st.position[0], st.position[1])) < reach):
					continue
				found.append(p)
		var row := []
		for p in found:
			row.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
		out.append(row)
	return out


static func _open_ground(game_data, p: Vector2) -> bool:
	return _open(game_data, p, 9.0, INVADER_MAX_SLOPE)


static func _open(game_data, p: Vector2, radius: float, max_slope: float) -> bool:
	## Whether p and a ring of points `radius` around it are passable, dry and
	## no steeper than max_slope.
	var terrain: TerrainData = game_data.terrain
	var size := terrain.world_size
	if p.x < 40.0 or p.y < 40.0 or p.x > size - 40.0 or p.y > size - 40.0:
		return false
	for k in 9:
		var q := p if k == 8 else p + Vector2.from_angle(k * TAU / 8.0) * radius
		if not game_data.nav.is_passable(q.x, q.y) or terrain.is_water(q.x, q.y) \
				or terrain.get_slope(q.x, q.y) > max_slope:
			return false
	return true
