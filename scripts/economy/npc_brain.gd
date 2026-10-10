class_name NpcBrain
extends RefCounted
## Runs an NPC lord's castle: whenever a builder is free it picks something
## sensible to build or upgrade, and it trains soldiers from what it has to
## spare. It plays by exactly the same rules as the player (same costs, times,
## builders, storage and food upkeep); it only has no hands on the mouse.
##
## Building priorities, in order:
##   1. the keep, once nothing else can grow without it
##   2. a storehouse, when the keep's next level costs more than storage holds
##   3. a barracks, from keep level 2
##   4. the producer of whatever resource comes in slowest
##   5. the wall, kept no lower than the keep
##   6. the barracks, kept no lower than the keep
##   7. the keep anyway
## The first of these the castle can afford right now is started.
##
## Recruiting: the strongest unlocked unit, paid only from stock above half the
## storage, never so many that soldiers eat more than 70% of the food, and up
## to 60 soldiers per keep level.

## Seconds between decisions while catching up on time the game was closed
## (with a builder free but nothing affordable yet).
const STEP := 900.0
## Longest stretch simulated decision by decision; older time only produces.
const MAX_CATCH_UP := 7.0 * 86400.0
## Which building produces each resource.
const PRODUCER := {"wood": "woodcutter", "stone": "quarry", "food": "farm", "gold": "house"}
## How much each resource matters when deciding what is "slowest".
const WEIGHT := {"wood": 1.0, "stone": 1.0, "food": 0.8, "gold": 0.6}
## Recruiting limits: stock kept back (share of storage), share of food
## production soldiers may eat, soldiers per batch and batches queued.
const KEEP_BACK := 0.5
const FOOD_FOR_TROOPS := 0.7
const BATCH := 20
const QUEUE := 2
## NPC garrisons stop growing at this many soldiers per keep level.
const GARRISON_PER_KEEP := 60
## A lord visiting their home castle fills their warband up to this size
## (plus WARBAND_PER_KEEP per keep level), leaving at least half the garrison.
const WARBAND_BASE := 40
const WARBAND_PER_KEEP := 20


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
	recruit(castle, now)
	return started


static func recruit(castle: CastleState, now: float) -> int:
	## Queues soldiers from spare stock. Returns how many were queued.
	var rules := castle.rules
	if castle.barracks_level() <= 0 or castle.training.size() >= QUEUE:
		return 0
	var cap := castle.storage_capacity()
	var food_left: float = castle.production_per_hour().get("food", 0.0) * FOOD_FOR_TROOPS - castle.upkeep_per_hour()
	var room := GARRISON_PER_KEEP * castle.keep_level() - castle.troop_count()
	for t in castle.training:
		food_left -= t.remaining * rules.unit_upkeep(t.unit)
		room -= t.remaining
	var units: Array = rules.units.keys()
	units.sort_custom(func(a: String, b: String) -> bool:
		return rules.unit_barracks_level(a) > rules.unit_barracks_level(b))
	for unit: String in units:
		if rules.unit_barracks_level(unit) > castle.barracks_level():
			continue
		var n := mini(mini(BATCH, room), int(food_left / rules.unit_upkeep(unit)))
		var cost := rules.unit_cost(unit)
		for r: String in cost:
			if cost[r] > 0.0:
				n = mini(n, int((castle.resources.get(r, 0.0) - cap * KEEP_BACK) / cost[r]))
		if n >= 1 and castle.recruit(unit, n, now):
			return n
	return 0


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
	if keep_level >= 2 and castle.count("barracks") == 0:
		out.append({"type": "barracks"})
	out.append_array(producers)
	var wall := _first(castle, "wall")
	if not wall.is_empty() and wall.level < keep_level:
		out.append({"id": wall.id})
	var barracks := _lowest(castle, "barracks")
	if not barracks.is_empty() and barracks.level < keep_level:
		out.append({"id": barracks.id})
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


static func resupply(castle: CastleState) -> int:
	## Moves soldiers from the garrison into the lord's warband, strongest
	## units first. Returns how many joined.
	var rules := castle.rules
	var want := WARBAND_BASE + WARBAND_PER_KEEP * castle.keep_level() - castle.field_count()
	var spare := castle.troop_count() / 2
	var n := mini(want, spare)
	if n <= 0:
		return 0
	var units: Array = castle.troops.keys()
	units.sort_custom(func(a: String, b: String) -> bool:
		return rules.unit_stat(a, "attack") + rules.unit_stat(a, "defense") > rules.unit_stat(b, "attack") + rules.unit_stat(b, "defense"))
	var moved := 0
	for unit: String in units:
		moved += castle.send_to_field(unit, n - moved)
		if moved >= n:
			break
	return moved
