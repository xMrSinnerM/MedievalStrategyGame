class_name CastleState
extends RefCounted
## One castle's economy: its stock of resources, its buildings on the castle
## grid, the constructions under way, its garrison of soldiers, the
## barracks' training queue, the warband its lord leads in the field
## (which the castle still has to feed) and what its academy has researched.
## The same class runs the player's castle and NPC
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
## Lifetime counts the quests and achievements check (QuestBook, Achievements):
## soldiers trained, resources spent (less what cancelling gave back), robber
## barons beaten, loot brought home and, online, battles won against players'
## castles and attacks on this one held off.
var stats := new_stats()
## Where the castle stands with its quests: the story quest being worked on,
## today's daily tasks and the coffer (QuestBook).
var quests := new_quest_log()
## Achievements: tiers earned and claimed by achievement, and the title shown
## ("id:tier", or "" for none) (Achievements).
var achievements := new_achievement_log()
## The Royal Gift for coming back each day: the last day it was taken
## (days since 1970, UTC), days in a row and days in all (LoginRewards).
var login := new_login_log()
## Seasons (SeasonRules): the month it counts renown for, the stats it counts
## from, track rewards claimed, last season's renown ({key, points, claimed})
## and the season titles won.
var season := new_season_log()
## Treasure chests to open (kind -> count) and how many were opened in all,
## which picks each spin of the Wheel of Fortune (ChestRules).
var chests := new_chest_log()
## Siege tools in store (tool -> count), the workshop's queue (batches
## {tool, remaining, unit_time, next}, like training) and the defence tools
## posted on each wall (wall -> {tool: count}, Battle.siege()).
var tools := {}
var crafting: Array[Dictionary] = []
var defence_tools := {}
## Commanders, the castellan's gear and the bag of gear not worn (GearRules).
var armoury := GearRules.new_armoury()
## Extra production by resource (0.5 for half as much again): an outpost's region.
var boost := {}
## An outpost's building limits ({"types": [allowed types], "keep": highest
## keep level}); empty for a normal castle (OutpostRules).
var limits := {}
## Studies researched in the academy (study -> level) and the one under way
## ({study, target, finish}, or empty), see "research" in buildings.json.
var research := {}
var studying := {}

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
	return {"trained": 0, "spent": 0.0, "barons": 0, "looted": 0.0, "pvp_won": 0, "pvp_held": 0}


static func new_achievement_log() -> Dictionary:
	return {"tiers": {}, "claimed": {}, "title": ""}


static func new_login_log() -> Dictionary:
	return {"last": -1, "streak": 0, "total": 0}


static func new_season_log() -> Dictionary:
	return {"key": -1, "base": {}, "track": 0, "last": {}, "honours": []}


static func new_chest_log() -> Dictionary:
	return {"have": {}, "opened": 0}


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
	for r: String in boost:
		if out.has(r):
			out[r] *= 1.0 + float(boost[r])
	for r: String in out:
		var more := research_bonus(r)
		if more != 0.0:
			out[r] *= 1.0 + more
	var mood := order_bonus()
	if mood != 0.0:
		for r: String in out:
			out[r] *= 1.0 + mood
	return out


func public_order() -> float:
	## The keep and decorations raise it; every other finished building crowds
	## the castle and lowers it (see "public_order" in buildings.json).
	var total := 0.0
	for b in buildings:
		total += rules.order(b.type, b.level)
	return total


func order_bonus() -> float:
	## How much more (or, below zero, less) the castle produces because of its public order.
	return rules.order_bonus(public_order())


func upkeep_per_hour() -> float:
	## Food the garrison eats per hour.
	var total := 0.0
	for unit: String in troops:
		total += troops[unit] * unit_upkeep(unit)
	for unit: String in field:
		total += field[unit] * unit_upkeep(unit)
	return total


func unit_upkeep(unit: String) -> float:
	## Food one soldier eats per hour here, after Field Rations.
	return rules.unit_upkeep(unit) * (1.0 + research_bonus("upkeep"))


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
	return Battle.check_tools(rules, group, "defence", defence_slots(), tools)


func defence_slots() -> int:
	## Defence tools that fit on each wall: by wall level, plus Murder Holes.
	var n := rules.tool_slots(wall_level())
	return n + int(research_bonus("defence_slots")) if n > 0 else 0


func storage_capacity() -> float:
	## The same cap applies to every resource.
	var total := 0.0
	for b in buildings:
		total += rules.storage(b.type, b.level)
	return total * (1.0 + research_bonus("storage"))


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
	if not limits.is_empty() and not limits.types.has(type):
		return "An outpost can't have one of these"
	if count(type) >= rules.max_count(type, keep_level()):
		return "The castle already has one" if rules.is_unique(type) else "Upgrade the keep to build more of these"
	if keep_level() < rules.required_keep(type):
		return "Needs keep level %d" % rules.required_keep(type)
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
	if not limits.is_empty() and b.type == "keep" and b.level >= int(limits.keep):
		return "An outpost's keep can't go higher"
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


func unit_time(unit: String) -> float:
	## Seconds to train one soldier here: by barracks level, then Drill Yards.
	return _shorter(rules.unit_time(unit, barracks_level()), research_bonus("recruit_time"))


func tool_time(tool: String) -> float:
	## Seconds to build one siege tool here: by workshop level, then Siegecraft.
	return _shorter(rules.tool_time(tool, workshop_level()), research_bonus("craft_time"))


# --- Research ------------------------------------------------------------------

func academy_level() -> int:
	for b in buildings:
		if b.type == "academy":
			return b.level
	return 0


func study_level(study: String) -> int:
	return int(research.get(study, 0))


func research_bonus(effect: String) -> float:
	## What every study researched adds up to for one effect (see "research"
	## in buildings.json): 0.12 for 12% more, -0.1 for 10% less.
	if research.is_empty():
		return 0.0
	var total := 0.0
	for study: String in research:
		var per: Variant = rules.study_effects(study).get(effect)
		if per != null:
			total += float(per) * int(research[study])
	return total


func research_effects(side: String) -> Dictionary:
	## The battle effects research gives (stat -> share, like GearRules.effects()):
	## "attack" for your armies, "defence" for your castle.
	var out := {}
	for stat: String in (["wall_attack", "yard_attack"] if side == "attack" else ["wall_defence", "yard_defence", "wall_bonus"]):
		var n := research_bonus(stat)
		if n > 0.0:
			out[stat] = n
	return out


func march_factor() -> float:
	## Multiplier on how long your armies march (Forced March).
	return maxf(1.0 + research_bonus("march_time"), 0.1)


func hidden() -> float:
	## How much of each resource Hidden Cellars keep safe from plunder.
	return storage_capacity() * research_bonus("hidden")


func heal(before: Dictionary) -> Dictionary:
	## After a battle at the castle: the Infirmary sends back a share of the
	## garrison that fell (`before` is the garrison before it). Returns unit -> healed.
	var share := research_bonus("heal")
	var out := {}
	if share <= 0.0:
		return out
	for unit: String in before:
		var n := int(floor((int(before[unit]) - int(troops.get(unit, 0))) * share))
		if n > 0:
			troops[unit] = int(troops.get(unit, 0)) + n
			out[unit] = n
	return out


func check_research(study: String) -> String:
	## Why the academy can't start on this study's next level, or "" if it can.
	if not rules.has_study(study):
		return "Unknown study"
	if academy_level() <= 0:
		return "Build an academy first"
	var level := study_level(study)
	if level >= rules.study_max_level(study):
		return "Fully researched"
	if academy_level() < rules.study_academy_level(study):
		return "Needs academy level %d" % rules.study_academy_level(study)
	var needs := rules.study_requires(study)
	for other: String in needs:
		if study_level(other) < int(needs[other]):
			return "Needs %s level %d" % [rules.study_name(other), int(needs[other])]
	if not studying.is_empty():
		return "The academy is already researching"
	if not can_afford(rules.study_cost(study, level + 1)):
		return "Not enough resources"
	return ""


func research_time(study: String) -> float:
	## Seconds the next level of this study takes in this academy.
	return rules.study_time(study, study_level(study) + 1, academy_level())


func research_left(now: float) -> float:
	return maxf(float(studying.finish) - now, 0.0) if not studying.is_empty() else 0.0


func start_research(study: String, now: float) -> bool:
	## Pays for the next level of a study and starts it.
	advance_to(now)
	if check_research(study) != "":
		return false
	var target := study_level(study) + 1
	_pay(rules.study_cost(study, target))
	studying = {"study": study, "target": target, "finish": now + research_time(study)}
	return true


func cancel_research(now: float) -> bool:
	## Stops the study under way and refunds part of its cost.
	advance_to(now)
	if studying.is_empty():
		return false
	_refund(rules.study_cost(studying.study, int(studying.target)))
	studying = {}
	return true


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
	var each := unit_time(unit)
	training.append({"unit": unit, "remaining": amount, "unit_time": each,
		"next": now + each if training.is_empty() else 0.0})
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
	var each := tool_time(tool)
	crafting.append({"tool": tool, "remaining": amount, "unit_time": each,
		"next": now + each if crafting.is_empty() else 0.0})
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
		# A study finishes first if it is done before the soldier or building.
		var study_due: bool = not studying.is_empty() and float(studying.finish) <= now \
			and (float(studying.finish) < training[0].next if soldier_due else (next.is_empty() or float(studying.finish) < next.finish))
		var until: float = now
		if study_due:
			until = float(studying.finish)
		elif soldier_due:
			until = training[0].next
		elif not next.is_empty():
			until = next.finish
		_produce(until - last_update)
		last_update = maxf(last_update, until)
		if study_due:
			research[studying.study] = int(studying.target)
			studying = {}
		elif soldier_due:
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
				var eats: float = group[unit] * unit_upkeep(unit)
				if group[unit] > 0 and eats > most:
					most = eats
					worst = unit
					pool = group
		if worst == "":
			hunger = 0.0
			return
		var upkeep := unit_upkeep(worst)
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
	achievements = other.achievements
	login = other.login
	season = other.season
	chests = other.chests
	tools = other.tools
	crafting = other.crafting
	defence_tools = other.defence_tools
	armoury = other.armoury
	boost = other.boost
	limits = other.limits
	research = other.research
	studying = other.studying
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
		"stats": stats.duplicate(), "quests": quests.duplicate(true), "achievements": achievements.duplicate(true),
		"login": login.duplicate(), "season": season.duplicate(true),
		"chests": chests.duplicate(true),
		"tools": tools.duplicate(), "crafting": crafting.duplicate(true), "defence_tools": defence_tools.duplicate(true),
		"armoury": armoury.duplicate(true),
		"boost": boost.duplicate(), "limits": limits.duplicate(true) if not limits.is_empty() else null,
		"research": research.duplicate(), "studying": studying.duplicate() if not studying.is_empty() else null,
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
		"barons": int(st.get("barons", 0)), "looted": float(st.get("looted", 0.0)),
		"pvp_won": int(st.get("pvp_won", 0)), "pvp_held": int(st.get("pvp_held", 0))}
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
	# Castles saved before achievements have earned none yet.
	var ach: Variant = data.get("achievements", {})
	if ach is Dictionary:
		for k: String in ach.get("tiers", {}):
			castle.achievements.tiers[k] = int(ach.tiers[k])
		for k: String in ach.get("claimed", {}):
			castle.achievements.claimed[k] = int(ach.claimed[k])
		var shown: Variant = ach.get("title", "")
		castle.achievements.title = shown if shown is String else ""
	# Castles saved before the Royal Gift have never taken one.
	var gift: Variant = data.get("login", {})
	if gift is Dictionary:
		castle.login = {"last": int(gift.get("last", -1)), "streak": int(gift.get("streak", 0)), "total": int(gift.get("total", 0))}
	# Castles saved before seasons start counting in the season they're next played in.
	var sea: Variant = data.get("season", {})
	if sea is Dictionary:
		var sbase := {}
		for k: String in sea.get("base", {}):
			sbase[k] = float(sea.base[k])
		var last := {}
		var l: Variant = sea.get("last", {})
		if l is Dictionary and l.has("key"):
			last = {"key": int(l.key), "points": int(l.get("points", 0)), "claimed": bool(l.get("claimed", false))}
		var honours: Array = []
		for h: Variant in sea.get("honours", []):
			if h is String:
				honours.append(h)
		castle.season = {"key": int(sea.get("key", -1)), "base": sbase, "track": int(sea.get("track", 0)),
			"last": last, "honours": honours}
	# Castles saved before treasure chests have none.
	var box: Variant = data.get("chests", {})
	if box is Dictionary:
		for kind: String in box.get("have", {}):
			if int(box.have[kind]) > 0:
				castle.chests.have[kind] = int(box.have[kind])
		castle.chests.opened = int(box.get("opened", 0))
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
	var boosts: Variant = data.get("boost", {})
	if boosts is Dictionary:
		for r: String in boosts:
			if p_rules.resources.has(r):
				castle.boost[r] = float(boosts[r])
	var lim: Variant = data.get("limits")
	if lim is Dictionary:
		var types: Array = []
		for t in lim.get("types", []):
			types.append(String(t))
		castle.limits = {"types": types, "keep": int(lim.get("keep", 1))}
	# Castles saved before the academy have researched nothing.
	var known: Variant = data.get("research", {})
	if known is Dictionary:
		for study: String in known:
			if p_rules.has_study(study) and int(known[study]) > 0:
				castle.research[study] = mini(int(known[study]), p_rules.study_max_level(study))
	var st_now: Variant = data.get("studying")
	if st_now is Dictionary and p_rules.has_study(String(st_now.get("study", ""))):
		castle.studying = {"study": String(st_now.study), "target": int(st_now.get("target", 1)),
			"finish": float(st_now.get("finish", 0.0))}
	return castle


# --- Internals ---------------------------------------------------------------

func _shorter(time: float, change: float) -> float:
	## A time after research (change -0.1 for 10% faster), whole seconds, at least one.
	return time if change == 0.0 else maxf(roundf(time * (1.0 + change)), 1.0)


func _check_start_work(cost: Dictionary) -> String:
	if free_builders() <= 0:
		return "All builders are busy"
	if not can_afford(cost):
		return "Not enough resources"
	return ""


func pay(cost: Dictionary) -> void:
	## Takes what something outside the castle costs (a capital's town building).
	_pay(cost)


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
