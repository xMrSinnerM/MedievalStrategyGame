class_name VillagePlacer
extends RefCounted
## Spreads the resource villages over the map from a fixed seed: on open,
## gentle ground, clear of settlements, robber baron camps, players' castle
## spots and each other. Villages near the middle of the map are the richest
## (and best guarded), so the centre is worth fighting over. Only
## scripts/tools/export_server_world.gd runs this; the game and the server
## both read the result from server/world/world.json.

const SETTLEMENT_GAP := 25.0
const AVOID_GAP := 35.0
## Invader camps (Baron Invasions) only stand somewhere for a while: a smaller gap will do.
const PASSING_GAP := 22.0


static func place(rules: VillageRules, open: Callable, settlements: Array, avoid: Array[Vector2], passing: Array[Vector2],
		map_size: float) -> Array:
	## Returns [{"id", "name", "position": [x, z], "level", "resource"}].
	## open(p) says whether a village can stand at map position p; `avoid`
	## lists other places to keep clear of (camps, castle spots), `passing`
	## the places invader camps can stand.
	var cfg := rules.placement
	var count := int(cfg.get("count", 36))
	var gap := float(cfg.get("min_gap", 60.0))
	var margin := float(cfg.get("edge_margin", 90.0))
	var rings: Array = cfg.get("level_rings", [])
	var resources: Array = rules.yields.keys()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 5150))
	var first: Array = rules.names.get("first", ["Mill"])
	var second: Array = rules.names.get("second", ["ton"])
	var centre := Vector2(map_size, map_size) * 0.5
	var used_names := {}
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < count * 400:
		tries += 1
		var p := Vector2(rng.randf_range(margin, map_size - margin), rng.randf_range(margin, map_size - margin))
		if not open.call(p):
			continue
		if avoid.any(func(q: Vector2) -> bool: return p.distance_to(q) < AVOID_GAP):
			continue
		if passing.any(func(q: Vector2) -> bool: return p.distance_to(q) < PASSING_GAP):
			continue
		if settlements.any(func(s: Dictionary) -> bool:
				var reach: float = PlayerSpots.SETTLEMENT_RADIUS.get(s.get("type", "village"), 20.0) + SETTLEMENT_GAP
				return p.distance_to(Vector2(s.position[0], s.position[1])) < reach):
			continue
		if out.any(func(v: Dictionary) -> bool: return p.distance_to(Vector2(v.position[0], v.position[1])) < gap):
			continue
		var village_name := ""
		for attempt in 20:
			village_name = "%s%s" % [first[rng.randi() % first.size()], second[rng.randi() % second.size()]]
			if not used_names.has(village_name):
				break
		used_names[village_name] = true
		# Level 5 inside the first ring, 4 inside the second, and so on; 1 outside them all.
		var level := 1
		var d := p.distance_to(centre)
		for i in rings.size():
			if d < float(rings[i]):
				level = rules.max_level - i
				break
		out.append({"id": "village_%d" % out.size(), "name": village_name,
				"position": [snappedf(p.x, 0.1), snappedf(p.y, 0.1)], "level": level,
				"resource": resources[out.size() % resources.size()]})
	return out
