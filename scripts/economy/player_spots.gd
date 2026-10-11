class_name PlayerSpots
extends RefCounted
## Where players' castles can stand in the online world: your castle's spot
## first, then spots spread over the map from a fixed seed, on open, gentle
## ground away from settlements, robber baron camps and each other. The
## server gives each new player a free one (server/world/world.json).

const SEED := 777
const COUNT := 200
const GAP := 65.0
## Clear ground between a castle and a settlement's edge.
const SETTLEMENT_GAP := 40.0
## How far each kind of settlement reaches (as SettlementModels.RADIUS).
const SETTLEMENT_RADIUS := {"town": 50.0, "castle": 22.0, "village": 20.0}
const CAMP_GAP := 40.0
const EDGE_MARGIN := 90.0
const RADIUS := 14.0
const MAX_SLOPE := 0.08


static func place(terrain: TerrainData, passable: Callable, settlements: Array, camps: Array, home: Vector2) -> Array:
	## Returns [[x, z], ...] with home first.
	var spots: Array = [[home.x, home.y]]
	var taken: Array[Vector2] = [home]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var size := terrain.world_size
	var tries := 0
	while spots.size() < COUNT and tries < COUNT * 300:
		tries += 1
		var p := Vector2(rng.randf_range(EDGE_MARGIN, size - EDGE_MARGIN), rng.randf_range(EDGE_MARGIN, size - EDGE_MARGIN))
		if not _good_ground(terrain, passable, p):
			continue
		if taken.any(func(q: Vector2) -> bool: return p.distance_to(q) < GAP):
			continue
		if settlements.any(func(s: Dictionary) -> bool:
				var reach: float = SETTLEMENT_RADIUS.get(s.get("type", "village"), 20.0) + SETTLEMENT_GAP + RADIUS
				return p.distance_to(Vector2(s.position[0], s.position[1])) < reach):
			continue
		if camps.any(func(c: Dictionary) -> bool:
				return p.distance_to(Vector2(c.position[0], c.position[1])) < CAMP_GAP):
			continue
		taken.append(p)
		spots.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1)])
	return spots


static func _good_ground(terrain: TerrainData, passable: Callable, p: Vector2) -> bool:
	if not passable.call(p.x, p.y) or terrain.get_slope(p.x, p.y) > MAX_SLOPE:
		return false
	for k in 8:
		var q := p + Vector2.from_angle(k * TAU / 8.0) * RADIUS
		if not passable.call(q.x, q.y) or terrain.is_water(q.x, q.y) or terrain.get_slope(q.x, q.y) > MAX_SLOPE:
			return false
	return true
