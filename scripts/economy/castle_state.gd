class_name CastleState
extends RefCounted
## One castle's economy: its stock of resources, its buildings on the castle
## grid, the constructions under way, its garrison of soldiers, the
## barracks' training queue and the warband its lord leads in the field
## (which the castle still has to feed). The same class runs the player's castle and NPC
## castles; only who gives the orders differs.
##
## Time is passed in explicitly (Unix seconds) so the castle can catch up on
## hours spent offline in one call, and so tests can fast-forward.

## Share of the cost given back when a construction is cancelled.
const CANCEL_REFUND := 0.75

var id := ""
var castle_name := ""
var owner := "player"          ## "player", or the faction id running an NPC castle
var rules: BuildingRules
var resources := {}            ## resource -> float amount
var buildings: Array[Dictionary] = []   ## {id, type, level, cell: Vector2i, target: int, finish: float}
var last_update := 0.0
var troops := {}               ## unit -> soldiers in the garrison
var training: Array[Dictionary] = []    ## batches {unit, remaining: int, unit_time: float, next: float}
var hunger := 0.0              ## food owed to soldiers while the stores are empty
var field := {}                ## unit -> soldiers away in the lord's warband
var field_ready := false       ## the warband has been given its starting army

var _next_id := 1


func _init(p_rules: BuildingRules = null) -> void:
	rules = p_rules


static func create_new(p_rules: BuildingRules, p_id: String, p_name: String, p_owner: String, now: float) -> CastleState:
	## A fresh castle as described by "start" in buildings.json.
	var castle := CastleState.new(p_rules)
	castle.id = p_id
	castle.castle_name = p_name
	castle.owner = p_owner
	castle.last_update = now
	for r in p_rules.resources:
		castle.resources[r] = float(p_rules.start.get("resources", {}).get(r, 0))
	for b in p_rules.start.get("buildings", []):
		var cell := Vector2i(-1, -1)
		if b.has("cell"):
			cell = Vector2i(int(b.cell[0]), int(b.cell[1]))
		castle._add_building(b.type, int(b.level), cell)
	return castle


func is_npc() -> bool:
	return owner != "player"


# --- Queries -----------------------------------------------------------------

func keep_level() -> int:
	for b in buildings:
		if b.type == "keep":
			return b.level
	return 0


func get_building(building_id: int) -> Dictionary:
	for b in buildings:
		if b.id == building_id:
			return b
	return {}


func count(type: String) -> int:
	var n := 0
	for b in buildings:
		if b.type == type:
			n += 1
	return n


func constructions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in buildings:
		if b.target > 0:
			out.append(b)
	return out


func free_builders() -> int:
	return rules.builders(keep_level()) - constructions().size()


func production_per_hour() -> Dictionary:
	var out := {}
	for r in rules.resources:
		out[r] = 0.0
	for b in buildings:
		var p := rules.production(b.type, b.level)
		for r: String in p:
			out[r] = out.get(r, 0.0) + p[r]
	return out


func upkeep_per_hour() -> float:
	## Food the garrison eats per hour.
	var total := 0.0
	for unit: String in troops:
		total += troops[unit] * rules.unit_upkeep(unit)
	for unit: String in field:
		total += field[unit] * rules.unit_upkeep(unit)
	return total


func net_per_hour() -> Dictionary:
	## Production minus what the soldiers eat; food can go below zero.
	var out := production_per_hour()
	out["food"] = out.get("food", 0.0) - upkeep_per_hour()
	return out


func troop_count() -> int:
	var n := 0
	for unit: String in troops:
		n += troops[unit]
	return n


func field_count() -> int:
	var n := 0
	for unit: String in field:
		n += field[unit]
	return n


func send_to_field(unit: String, amount: int) -> int:
	## Moves up to `amount` soldiers from the garrison into the warband.
	## Returns how many moved.
	var n := mini(amount, troops.get(unit, 0))
	if n <= 0:
		return 0
	troops[unit] -= n
	field[unit] = field.get(unit, 0) + n
	return n


func return_from_field(unit: String, amount: int) -> int:
	## Moves up to `amount` soldiers from the warband back into the garrison.
	var n := mini(amount, field.get(unit, 0))
	if n <= 0:
		return 0
	field[unit] -= n
	troops[unit] = troops.get(unit, 0) + n
	return n


func barracks_level() -> int:
	for b in buildings:
		if b.type == "barracks":
			return b.level
	return 0


func check_recruit(unit: String, amount: int) -> String:
	## Why `amount` soldiers of this unit can't be queued, or "" if they can.
	if not rules.has_unit(unit):
		return "Unknown unit"
	if barracks_level() <= 0:
		return "Build a barracks first"
	if barracks_level() < rules.unit_barracks_level(unit):
		return "Needs barracks level %d" % rules.unit_barracks_level(unit)
	if amount < 1 or amount > rules.max_batch:
		return "Train between 1 and %d at a time" % rules.max_batch
	if training.size() >= rules.queue_size:
		return "The training queue is full"
	if not can_afford(rules.unit_cost(unit, amount)):
		return "Not enough resources"
	return ""


func affordable(unit: String) -> int:
	## How many of this unit the castle could pay for right now (capped at a batch).
	var cost := rules.unit_cost(unit)
	var n := rules.max_batch
	for r: String in cost:
		if cost[r] > 0.0:
			n = mini(n, int(floor((resources.get(r, 0.0) + 0.0001) / cost[r])))
	return maxi(n, 0)


func storage_capacity() -> float:
	## The same cap applies to every resource.
	var total := 0.0
	for b in buildings:
		total += rules.storage(b.type, b.level)
	return total


func defense() -> float:
	var total := 0.0
	for b in buildings:
		total += rules.defense(b.type, b.level)
	return total


func can_afford(cost: Dictionary) -> bool:
	for r: String in cost:
		if resources.get(r, 0.0) + 0.0001 < cost[r]:
			return false
	return true


func check_build(type: String) -> String:
	## Why a new building of this type can't be started anywhere, or "" if it can.
	if not rules.has_type(type):
		return "Unknown building"
	if rules.is_perimeter(type):
		return "This is built around the castle, not placed"
	if count(type) >= rules.max_count(type, keep_level()):
		return "The castle already has one" if rules.is_unique(type) else "Upgrade the keep to build more of these"
	return _check_start_work(rules.cost(type, 1))


func check_place(type: String, cell: Vector2i) -> String:
	## Why a new building can't go here, or "" if it can.
	var reason := check_build(type)
	if reason != "":
		return reason
	if not fits(type, cell):
		return "There's no room there"
	return ""


func check_upgrade(building_id: int) -> String:
	## Why this building can't be upgraded now, or "" if it can.
	var b := get_building(building_id)
	if b.is_empty():
		return "No such building"
	if b.target > 0:
		return "Already under construction"
	if b.level >= rules.max_level(b.type, keep_level()):
		if b.type != "keep" and b.level < int(rules.types[b.type].get("max_level", 10)):
			return "Upgrade the keep first"
		return "Fully upgraded"
	return _check_start_work(rules.cost(b.type, b.level + 1))


func fits(type: String, cell: Vector2i, ignore_id := -1) -> bool:
	## True if the footprint lies on the grid and overlaps no other building.
	var s := rules.size(type)
	var rect := Rect2i(cell, s)
	if rect.position.x < 0 or rect.position.y < 0 or rect.end.x > rules.grid_size or rect.end.y > rules.grid_size:
		return false
	for b in buildings:
		if b.id == ignore_id or b.cell.x < 0:
			continue
		if rect.intersects(Rect2i(b.cell, rules.size(b.type))):
			return false
	return true


func time_left(building_id: int, now: float) -> float:
	var b := get_building(building_id)
	return maxf(b.finish - now, 0.0) if not b.is_empty() and b.target > 0 else 0.0


# --- Orders ------------------------------------------------------------------

func place(type: String, cell: Vector2i, now: float) -> int:
	## Starts building something new. Returns its id, or -1 if not allowed.
	advance_to(now)
	if check_place(type, cell) != "":
		return -1
	_pay(rules.cost(type, 1))
	var b := _add_building(type, 0, cell)
	b.target = 1
	b.finish = now + rules.build_time(type, 1)
	return b.id


func upgrade(building_id: int, now: float) -> bool:
	advance_to(now)
	if check_upgrade(building_id) != "":
		return false
	var b := get_building(building_id)
	_pay(rules.cost(b.type, b.level + 1))
	b.target = b.level + 1
	b.finish = now + rules.build_time(b.type, b.target)
	return true


func cancel(building_id: int, now: float) -> bool:
	## Stops a construction and refunds part of its cost. A building that was
	## being built from scratch is removed.
	advance_to(now)
	var b := get_building(building_id)
	if b.is_empty() or b.target <= 0:
		return false
	var cost := rules.cost(b.type, b.target)
	var cap := storage_capacity()
	for r: String in cost:
		resources[r] = maxf(resources.get(r, 0.0), minf(resources.get(r, 0.0) + cost[r] * CANCEL_REFUND, cap))
	b.target = 0
	b.finish = 0.0
	if b.level == 0:
		buildings.erase(b)
	return true


func recruit(unit: String, amount: int, now: float) -> bool:
	## Pays for `amount` soldiers and queues them; they train one after another.
	advance_to(now)
	if check_recruit(unit, amount) != "":
		return false
	_pay(rules.unit_cost(unit, amount))
	var unit_time := rules.unit_time(unit, barracks_level())
	training.append({"unit": unit, "remaining": amount, "unit_time": unit_time,
		"next": now + unit_time if training.is_empty() else 0.0})
	return true


func cancel_training(index: int, now: float) -> bool:
	## Drops a queued batch and refunds part of what its untrained soldiers cost.
	advance_to(now)
	if index < 0 or index >= training.size():
		return false
	var batch: Dictionary = training[index]
	var cost := rules.unit_cost(batch.unit, batch.remaining)
	var cap := storage_capacity()
	for r: String in cost:
		resources[r] = maxf(resources.get(r, 0.0), minf(resources.get(r, 0.0) + cost[r] * CANCEL_REFUND, cap))
	training.remove_at(index)
	if index == 0 and not training.is_empty():
		training[0].next = now + training[0].unit_time
	return true


func training_left(now: float) -> float:
	## Seconds until the whole queue is trained.
	if training.is_empty():
		return 0.0
	var total: float = maxf(training[0].next - now, 0.0) + training[0].unit_time * (training[0].remaining - 1)
	for i in range(1, training.size()):
		total += training[i].unit_time * training[i].remaining
	return total


func move(building_id: int, cell: Vector2i) -> bool:
	## Moves a building to another free spot, at no cost.
	var b := get_building(building_id)
	if b.is_empty() or b.cell.x < 0 or not fits(b.type, cell, building_id):
		return false
	b.cell = cell
	return true


# --- Time --------------------------------------------------------------------

func advance_to(now: float) -> void:
	## Runs the economy forward to `now`: produces resources up to the storage
	## cap, finishes constructions and trains soldiers in the order they
	## complete, so a finished upgrade produces (and a new soldier eats) from
	## the moment it is done.
	while true:
		var next: Dictionary = {}
		for b in buildings:
			if b.target > 0 and b.finish <= now and (next.is_empty() or b.finish < next.finish):
				next = b
		var soldier_due: bool = not training.is_empty() and training[0].next <= now \
			and (next.is_empty() or training[0].next < next.finish)
		var until: float = now
		if soldier_due:
			until = training[0].next
		elif not next.is_empty():
			until = next.finish
		_produce(until - last_update)
		last_update = maxf(last_update, until)
		if soldier_due:
			_finish_soldier()
		elif not next.is_empty():
			next.level = next.target
			next.target = 0
			next.finish = 0.0
		else:
			break


func _finish_soldier() -> void:
	var batch: Dictionary = training[0]
	troops[batch.unit] = troops.get(batch.unit, 0) + 1
	batch.remaining -= 1
	var done_at: float = batch.next
	if batch.remaining > 0:
		batch.next = done_at + batch.unit_time
		return
	training.pop_front()
	if not training.is_empty():
		training[0].next = done_at + training[0].unit_time


func _produce(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var rates := net_per_hour()
	var cap := storage_capacity()
	for r: String in rates:
		var have: float = resources.get(r, 0.0)
		var after: float = have + rates[r] * seconds / 3600.0
		if rates[r] >= 0.0:
			# Production stops at the cap but never takes away what is already above it.
			resources[r] = maxf(have, minf(after, cap))
		elif after >= 0.0:
			resources[r] = after
		else:
			# The soldiers ate everything: what they couldn't eat becomes hunger.
			resources[r] = 0.0
			hunger += -after
	if resources.get("food", 0.0) > 0.0:
		hunger = 0.0
	_desert()


func _desert() -> void:
	## Each hour of food a soldier goes without makes one soldier leave. The
	## hungriest group (most upkeep in total, in the garrison or the warband)
	## deserts first.
	while hunger > 0.0:
		var worst := ""
		var pool := {}
		var most := 0.0
		for group: Dictionary in [troops, field]:
			for unit: String in group:
				var eats: float = group[unit] * rules.unit_upkeep(unit)
				if group[unit] > 0 and eats > most:
					most = eats
					worst = unit
					pool = group
		if worst == "":
			hunger = 0.0
			return
		var upkeep := rules.unit_upkeep(worst)
		var leaving := mini(int(hunger / upkeep), pool[worst])
		if leaving <= 0:
			return
		pool[worst] -= leaving
		hunger -= leaving * upkeep


func copy_from(other: CastleState) -> void:
	## Takes over another castle's whole state (used when the server sends
	## yours), keeping this object so everything that shows it stays linked.
	id = other.id
	castle_name = other.castle_name
	owner = other.owner
	resources = other.resources
	buildings = other.buildings
	last_update = other.last_update
	troops = other.troops
	training = other.training
	hunger = other.hunger
	field = other.field
	field_ready = other.field_ready
	_next_id = other._next_id


# --- Saving ------------------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	for b in buildings:
		list.append({
			"id": b.id, "type": b.type, "level": b.level,
			"cell": [b.cell.x, b.cell.y], "target": b.target, "finish": b.finish,
		})
	return {
		"id": id, "name": castle_name, "owner": owner,
		"resources": resources.duplicate(), "buildings": list,
		"last_update": last_update, "next_id": _next_id,
		"troops": troops.duplicate(), "training": training.duplicate(true), "hunger": hunger,
		"field": field.duplicate(), "field_ready": field_ready,
	}


static func from_dict(p_rules: BuildingRules, data: Dictionary) -> CastleState:
	var castle := CastleState.new(p_rules)
	castle.id = data.get("id", "")
	castle.castle_name = data.get("name", "")
	castle.owner = data.get("owner", "player")
	castle.last_update = float(data.get("last_update", 0.0))
	castle._next_id = int(data.get("next_id", 1))
	for r in p_rules.resources:
		castle.resources[r] = float(data.get("resources", {}).get(r, 0.0))
	for b in data.get("buildings", []):
		if not p_rules.has_type(b.get("type", "")):
			continue   # a building type removed from the data since this save
		castle.buildings.append({
			"id": int(b.id), "type": String(b.type), "level": int(b.level),
			"cell": Vector2i(int(b.cell[0]), int(b.cell[1])),
			"target": int(b.get("target", 0)), "finish": float(b.get("finish", 0.0)),
		})
	# Saves from before recruitment have no troops; units removed from the data are dropped.
	for unit: String in data.get("troops", {}):
		if p_rules.has_unit(unit):
			castle.troops[unit] = int(data.troops[unit])
	for t in data.get("training", []):
		if p_rules.has_unit(t.get("unit", "")):
			castle.training.append({"unit": String(t.unit), "remaining": int(t.remaining),
				"unit_time": float(t.unit_time), "next": float(t.get("next", 0.0))})
	if not castle.training.is_empty() and castle.training[0].next <= 0.0:
		castle.training[0].next = castle.last_update + castle.training[0].unit_time
	castle.hunger = float(data.get("hunger", 0.0))
	for unit: String in data.get("field", {}):
		if p_rules.has_unit(unit):
			castle.field[unit] = int(data.field[unit])
	castle.field_ready = bool(data.get("field_ready", false))
	return castle


# --- Internals ---------------------------------------------------------------

func _check_start_work(cost: Dictionary) -> String:
	if free_builders() <= 0:
		return "All builders are busy"
	if not can_afford(cost):
		return "Not enough resources"
	return ""


func _pay(cost: Dictionary) -> void:
	for r: String in cost:
		resources[r] = resources.get(r, 0.0) - cost[r]


func _add_building(type: String, level: int, cell: Vector2i) -> Dictionary:
	var b := {"id": _next_id, "type": type, "level": level, "cell": cell, "target": 0, "finish": 0.0}
	_next_id += 1
	buildings.append(b)
	return b
