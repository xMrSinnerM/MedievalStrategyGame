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
## Where the garrison stands when the castle is stormed: percent on the left,
## front and right walls and in the courtyard (Battle.siege()).
var layout := Battle.DEFAULT_LAYOUT.duplicate()
## Lifetime counts the quests check (QuestBook): soldiers trained, resources
## spent (less what cancelling gave back), robber barons beaten, loot brought home.
var stats := new_stats()
## Where the castle stands with its quests: the story quest being worked on,
## today's daily tasks and the coffer (QuestBook).
var quests := new_quest_log()
## Siege tools in store (tool -> count), the workshop's queue (batches
## {tool, remaining, unit_time, next}, like training) and the defence tools
## posted on each wall (wall -> {tool: count}, Battle.siege()).
var tools := {}
var crafting: Array[Dictionary] = []
var defence_tools := {}
## Commanders, the castellan's gear and the bag of gear not worn (GearRules).
var armoury := GearRules.new_armoury()

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


static func new_stats() -> Dictionary:
	return {"trained": 0, "spent": 0.0, "barons": 0, "looted": 0.0}


static func new_quest_log() -> Dictionary:
	return {"story": 0, "day": -1, "keep": 1, "picks": [], "base": {}, "claimed": [], "chest": false,
		"streak": 0, "chest_day": -1}


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


func workshop_level() -> int:
	for b in buildings:
		if b.type == "workshop":
			return b.level
	return 0


func wall_level() -> int:
	for b in buildings:
		if b.type == "wall":
			return b.level
	return 0


func check_craft(tool: String, amount: int) -> String:
	## Why `amount` of this siege tool can't be queued, or "" if they can.
	if not rules.has_tool(tool):
		return "Unknown siege tool"
	if workshop_level() <= 0:
		return "Build a siege workshop first"
	if workshop_level() < rules.tool_workshop_level(tool):
		return "Needs workshop level %d" % rules.tool_workshop_level(tool)
	if amount < 1 or amount > rules.max_batch:
		return "Build between 1 and %d at a time" % rules.max_batch
	if crafting.size() >= rules.queue_size:
		return "The workshop queue is full"
	if not can_afford(rules.tool_cost(tool, amount)):
		return "Not enough resources"
	return ""


func affordable_tools(tool: String) -> int:
	## How many of this tool the castle could pay for right now (capped at a batch).
	var cost := rules.tool_cost(tool)
	var n := rules.max_batch
	for r: String in cost:
		if cost[r] > 0.0:
			n = mini(n, int(floor((resources.get(r, 0.0) + 0.0001) / cost[r])))
	return maxi(n, 0)


func check_defence_tools(group: Variant) -> String:
	## Why these defence tools can't stand on the walls ("" if they can).
	return Battle.check_tools(rules, group, "defence", rules.tool_slots(wall_level()), tools)


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
	_refund(rules.cost(b.type, b.target))
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
	_refund(rules.unit_cost(batch.unit, batch.remaining))
	training.remove_at(index)
	if index == 0 and not training.is_empty():
		training[0].next = now + training[0].unit_time
	return true


func craft(tool: String, amount: int, now: float) -> bool:
	## Pays for `amount` siege tools and queues them in the workshop.
	advance_to(now)
	if check_craft(tool, amount) != "":
		return false
	_pay(rules.tool_cost(tool, amount))
	var unit_time := rules.tool_time(tool, workshop_level())
	crafting.append({"tool": tool, "remaining": amount, "unit_time": unit_time,
		"next": now + unit_time if crafting.is_empty() else 0.0})
	return true


func cancel_crafting(index: int, now: float) -> bool:
	## Drops a queued batch of tools and refunds part of what the unbuilt ones cost.
	advance_to(now)
	if index < 0 or index >= crafting.size():
		return false
	var batch: Dictionary = crafting[index]
	_refund(rules.tool_cost(batch.tool, batch.remaining))
	crafting.remove_at(index)
	if index == 0 and not crafting.is_empty():
		crafting[0].next = now + crafting[0].unit_time
	return true


func set_defence_tools(group: Variant) -> String:
	## Posts defence tools on the walls; "" or why not.
	var why := check_defence_tools(group)
	if why != "":
		return why
	defence_tools = Battle.clean_tools(group if group is Dictionary else {})
	return ""


func use_tools(group: Dictionary) -> void:
	## Takes tools out of the store (attack tools sent with an army, or tools lost).
	for w: String in Battle.WALLS:
		var at: Dictionary = group.get(w, {})
		for tool: String in at:
			tools[tool] = maxi(0, int(tools.get(tool, 0)) - int(at[tool]))
			if tools[tool] == 0:
				tools.erase(tool)


func lose_defence_tools(lost: Dictionary) -> void:
	## Defence tools lost when their walls fell: off the walls and out of the store.
	for w: String in Battle.WALLS:
		if not defence_tools.has(w):
			continue
		var posted: Dictionary = defence_tools[w]
		var gone: Dictionary = lost.get(w, {})
		for tool: String in gone:
			posted[tool] = maxi(0, int(posted.get(tool, 0)) - int(gone[tool]))
			if posted[tool] == 0:
				posted.erase(tool)
		if posted.is_empty():
			defence_tools.erase(w)
	use_tools(lost)


func crafting_left(now: float) -> float:
	## Seconds until the workshop's whole queue is built.
	if crafting.is_empty():
		return 0.0
	var total: float = maxf(crafting[0].next - now, 0.0) + crafting[0].unit_time * (crafting[0].remaining - 1)
	for i in range(1, crafting.size()):
		total += crafting[i].unit_time * crafting[i].remaining
	return total


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
	_finish_crafts(now)


func _finish_crafts(now: float) -> void:
	## Tools don't eat or produce, so the workshop just catches up.
	while not crafting.is_empty() and crafting[0].next <= now:
		var batch: Dictionary = crafting[0]
		tools[batch.tool] = int(tools.get(batch.tool, 0)) + 1
		batch.remaining -= 1
		var done_at: float = batch.next
		if batch.remaining > 0:
			batch.next = done_at + batch.unit_time
			continue
		crafting.pop_front()
		if not crafting.is_empty():
			crafting[0].next = done_at + crafting[0].unit_time


func _finish_soldier() -> void:
	var batch: Dictionary = training[0]
	troops[batch.unit] = troops.get(batch.unit, 0) + 1
	stats.trained += 1
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
	layout = other.layout
	stats = other.stats
	quests = other.quests
	tools = other.tools
	crafting = other.crafting
	defence_tools = other.defence_tools
	armoury = other.armoury
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
		"field": field.duplicate(), "field_ready": field_ready, "layout": layout.duplicate(),
		"stats": stats.duplicate(), "quests": quests.duplicate(true),
		"tools": tools.duplicate(), "crafting": crafting.duplicate(true), "defence_tools": defence_tools.duplicate(true),
		"armoury": armoury.duplicate(true),
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
	var saved: Variant = data.get("layout")
	if Battle.check_layout(saved) == "":
		for key: String in Battle.DEFAULT_LAYOUT:
			castle.layout[key] = int(saved[key])
	# Castles saved before quests have no stats or quest log yet.
	var st: Dictionary = data.get("stats", {})
	castle.stats = {"trained": int(st.get("trained", 0)), "spent": float(st.get("spent", 0.0)),
		"barons": int(st.get("barons", 0)), "looted": float(st.get("looted", 0.0))}
	var q: Dictionary = data.get("quests", {})
	var base := {}
	for k: String in q.get("base", {}):
		base[k] = float(q.base[k])
	var picks: Array = []
	for k in q.get("picks", []):
		picks.append(String(k))
	var claimed: Array = []
	for i in q.get("claimed", []):
		claimed.append(int(i))
	castle.quests = {"story": int(q.get("story", 0)), "day": int(q.get("day", -1)), "keep": int(q.get("keep", 1)),
		"picks": picks, "base": base, "claimed": claimed, "chest": bool(q.get("chest", false)),
		"streak": int(q.get("streak", 0)), "chest_day": int(q.get("chest_day", -1))}
	var stock: Dictionary = data.get("tools", {})
	for tool: String in stock:
		if p_rules.has_tool(tool) and int(stock[tool]) > 0:
			castle.tools[tool] = int(stock[tool])
	for c in data.get("crafting", []):
		if p_rules.has_tool(c.get("tool", "")):
			castle.crafting.append({"tool": String(c.tool), "remaining": int(c.remaining),
				"unit_time": float(c.unit_time), "next": float(c.get("next", 0.0))})
	if not castle.crafting.is_empty() and castle.crafting[0].next <= 0.0:
		castle.crafting[0].next = castle.last_update + castle.crafting[0].unit_time
	var posted: Dictionary = data.get("defence_tools", {})
	for w: String in Battle.WALLS:
		var group := {}
		var at: Dictionary = posted.get(w, {})
		for tool: String in at:
			if p_rules.has_tool(tool) and int(at[tool]) > 0:
				group[tool] = int(at[tool])
		if not group.is_empty():
			castle.defence_tools[w] = group
	castle.armoury = GearRules.read_armoury(data.get("armoury"))
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
		stats.spent += cost[r]


func _refund(cost: Dictionary) -> void:
	## Gives back part of a cost (CANCEL_REFUND), up to the storage cap.
	var cap := storage_capacity()
	for r: String in cost:
		resources[r] = maxf(resources.get(r, 0.0), minf(resources.get(r, 0.0) + cost[r] * CANCEL_REFUND, cap))
		stats.spent -= cost[r] * CANCEL_REFUND


func _add_building(type: String, level: int, cell: Vector2i) -> Dictionary:
	var b := {"id": _next_id, "type": type, "level": level, "cell": cell, "target": 0, "finish": 0.0}
	_next_id += 1
	buildings.append(b)
	return b
