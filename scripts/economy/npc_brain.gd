class_name NpcBrain
extends RefCounted
## Runs an NPC lord's castle: whenever a builder is free it picks something
## sensible to build or upgrade. It plays by exactly the same rules as the
## player (same costs, times, builders and storage); it only has no hands on
## the mouse.
##
## Priorities, in order:
##   1. the keep, once nothing else can grow without it
##   2. a storehouse, when the keep's next level costs more than storage holds
##   3. the producer of whatever resource comes in slowest
##   4. the wall, kept no lower than the keep
##   5. the keep anyway
## The first of these the castle can afford right now is started.

## Seconds between decisions while catching up on time the game was closed
## (with a builder free but nothing affordable yet).
const STEP := 900.0
## Longest stretch simulated decision by decision; older time only produces.
const MAX_CATCH_UP := 7.0 * 86400.0
## Which building produces each resource.
const PRODUCER := {"wood": "woodcutter", "stone": "quarry", "food": "farm", "gold": "house"}
## How much each resource matters when deciding what is "slowest".
const WEIGHT := {"wood": 1.0, "stone": 1.0, "food": 0.8, "gold": 0.6}


static func catch_up(castle: CastleState, now: float) -> void:
	## Brings the castle to `now`, deciding every STEP seconds along the way.
	if now - castle.last_update > MAX_CATCH_UP:
		castle.advance_to(now - MAX_CATCH_UP)
	var t := castle.last_update
	while t < now:
		# With every builder busy nothing can change until one finishes, so jump
		# straight there; otherwise look again in STEP seconds.
		var next := t + STEP
		if castle.free_builders() <= 0:
			next = INF
			for b in castle.constructions():
				next = minf(next, b.finish)
			next = maxf(next, t + 1.0)
		t = minf(next, now)
		castle.advance_to(t)
		think(castle, t)


static func think(castle: CastleState, now: float) -> int:
	## Starts as many jobs as there are free builders. Returns how many started.
	var started := 0
	while castle.free_builders() > 0:
		var order := choose(castle)
		if order.is_empty():
			break
		var ok: bool
		if order.has("id"):
			ok = castle.upgrade(order.id, now)
		else:
			ok = castle.place(order.type, order.cell, now) > 0
		if not ok:
			break
		started += 1
	return started


static func choose(castle: CastleState) -> Dictionary:
	## The next order: {"id": building} to upgrade, {"type", "cell"} to build,
	## or {} if nothing worthwhile is affordable now.
	for option in _options(castle):
		if option.has("id"):
			if castle.check_upgrade(option.id) == "":
				return option
		elif castle.check_build(option.type) == "":
			var cell := free_cell(castle, option.type)
			if cell.x >= 0:
				return {"type": option.type, "cell": cell}
	return {}


static func free_cell(castle: CastleState, type: String) -> Vector2i:
	## The free spot closest to the middle of the grid, leaving a one-cell lane
	## around buildings where possible so the castle doesn't become a solid block.
	var rules := castle.rules
	var n := rules.grid_size
	var s := rules.size(type)
	# Two occupancy maps: cells under a building, and those cells grown by one.
	var taken := PackedByteArray()
	var near := PackedByteArray()
	taken.resize(n * n)
	near.resize(n * n)
	for b in castle.buildings:
		if b.cell.x < 0:
			continue
		var r := Rect2i(b.cell, rules.size(b.type))
		for y in range(r.position.y - 1, r.end.y + 1):
			for x in range(r.position.x - 1, r.end.x + 1):
				if x < 0 or y < 0 or x >= n or y >= n:
					continue
				near[y * n + x] = 1
				if r.has_point(Vector2i(x, y)):
					taken[y * n + x] = 1
	var centre := Vector2(n, n) * 0.5
	var best := Vector2i(-1, -1)
	var best_tight := Vector2i(-1, -1)
	var best_d := INF
	var best_tight_d := INF
	for y in n - s.y + 1:
		for x in n - s.x + 1:
			var d := (Vector2(x, y) + Vector2(s) * 0.5).distance_squared_to(centre)
			if d >= best_tight_d and d >= best_d:
				continue
			var free := true
			var lane := true
			for dy in s.y:
				for dx in s.x:
					var i := (y + dy) * n + x + dx
					if taken[i]:
						free = false
					if near[i]:
						lane = false
			if not free:
				continue
			if d < best_tight_d:
				best_tight_d = d
				best_tight = Vector2i(x, y)
			if lane and d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best if best.x >= 0 else best_tight


static func _options(castle: CastleState) -> Array[Dictionary]:
	var rules := castle.rules
	var out: Array[Dictionary] = []
	var keep := _first(castle, "keep")
	var keep_level := castle.keep_level()
	var keep_maxed: bool = keep.is_empty() or keep.level >= int(rules.types.keep.get("max_level", 5))

	# Producers, slowest resource first.
	var rates := castle.production_per_hour()
	var resources: Array = PRODUCER.keys()
	resources.sort_custom(func(a: String, b: String) -> bool:
		return rates.get(a, 0.0) / WEIGHT[a] < rates.get(b, 0.0) / WEIGHT[b])
	var producers: Array[Dictionary] = []
	var producers_capped := true
	for r: String in resources:
		var type: String = PRODUCER[r]
		if castle.count(type) < rules.max_count(type, keep_level):
			producers.append({"type": type})
			producers_capped = false
		var lowest := _lowest(castle, type)
		if not lowest.is_empty() and lowest.level < rules.max_level(type, keep_level):
			producers.append({"id": lowest.id})
			producers_capped = false

	if not keep_maxed and producers_capped:
		out.append({"id": keep.id})
	if not keep_maxed:
		var keep_cost := rules.cost("keep", keep.level + 1)
		var needs_room := false
		for r: String in keep_cost:
			if keep_cost[r] > castle.storage_capacity():
				needs_room = true
		if needs_room:
			if castle.count("storehouse") < rules.max_count("storehouse", keep_level):
				out.append({"type": "storehouse"})
			var store := _lowest(castle, "storehouse")
			if not store.is_empty():
				out.append({"id": store.id})
	out.append_array(producers)
	var wall := _first(castle, "wall")
	if not wall.is_empty() and wall.level < keep_level:
		out.append({"id": wall.id})
	if not keep_maxed:
		out.append({"id": keep.id})
	return out


static func _first(castle: CastleState, type: String) -> Dictionary:
	for b in castle.buildings:
		if b.type == type:
			return b
	return {}


static func _lowest(castle: CastleState, type: String) -> Dictionary:
	## The lowest-level building of this type that isn't already being worked on.
	var best := {}
	for b in castle.buildings:
		if b.type == type and b.target == 0 and (best.is_empty() or b.level < best.level):
			best = b
	return best
