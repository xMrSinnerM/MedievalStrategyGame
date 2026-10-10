class_name BaronPlacer
extends RefCounted
## Spreads robber baron camps over the map from a fixed seed, so every game
## (and later the server) gets the same camps: on open, passable ground, away
## from settlements and from each other. Camps near your castle start at
## level 1; further out they start higher.


static func place(rules: BaronRules, passable: Callable, settlements: Array, home: Vector2, map_size: float) -> Array:
	## Returns [{"id", "name", "position": [x, z], "level"}]. passable(x, z)
	## says whether an army can stand there.
	var cfg := rules.camps
	var count := int(cfg.get("count", 30))
	var gap := float(cfg.get("min_gap", 70.0))
	var settlement_gap := float(cfg.get("settlement_gap", 45.0))
	var margin := float(cfg.get("edge_margin", 80.0))
	var per_level := float(cfg.get("level_per_distance", 170.0))
	var level_max := int(cfg.get("start_level_max", 12))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cfg.get("seed", 4242))
	var first: Array = rules.names.get("first", ["Robber"])
	var second: Array = rules.names.get("second", ["Camp"])
	var used_names := {}
	var out: Array = []
	var tries := 0
	while out.size() < count and tries < count * 400:
		tries += 1
		var p := Vector2(rng.randf_range(margin, map_size - margin), rng.randf_range(margin, map_size - margin))
		if not passable.call(p.x, p.y) or p.distance_to(home) < settlement_gap * 2.0:
			continue
		if settlements.any(func(s: Dictionary) -> bool:
				return p.distance_to(Vector2(s.position[0], s.position[1])) < settlement_gap):
			continue
		if out.any(func(c: Dictionary) -> bool: return p.distance_to(Vector2(c.position[0], c.position[1])) < gap):
			continue
		var camp_name := ""
		for attempt in 20:
			camp_name = "%s %s" % [first[rng.randi() % first.size()], second[rng.randi() % second.size()]]
			if not used_names.has(camp_name):
				break
		used_names[camp_name] = true
		var level := clampi(1 + floori(p.distance_to(home) / per_level), 1, level_max)
		out.append({"id": "baron_%d" % out.size(), "name": camp_name,
				"position": [snappedf(p.x, 0.1), snappedf(p.y, 0.1)], "level": level})
	return out
