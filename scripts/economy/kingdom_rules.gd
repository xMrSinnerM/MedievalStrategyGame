class_name KingdomRules
extends RefCounted
## The other kingdoms: lands across the sea, each with its own map, robber
## barons and a good found nowhere else (iron in Frostmark, glass in
## Sunreach). The numbers are in data/kingdoms.json; server/rules/kingdoms.ts
## is the same rules for the online game.
##
## Your castle in a kingdom is a CastleState with id castle_id(kingdom),
## "limits" on what it may build and "yields" for the good its keep gathers.
## A player's kingdoms are {kingdom id -> {"ships", "next_ship"}}; a ship is
## {id, good, amount, depart, arrive} carrying the good to your main castle.

const PATH := "res://data/kingdoms.json"
const CASTLE_PREFIX := "kingdom_"

var goods := {}                ## good -> {name, description}
var types: Array = []
var keep_cap := 1
var kingdoms := {}             ## kingdom id -> its definition


static func load_default() -> KingdomRules:
	var rules := KingdomRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


func load_from(data: Dictionary) -> void:
	goods = data.get("goods", {})
	types = data.get("types", [])
	keep_cap = int(data.get("keep_cap", 1))
	kingdoms = data.get("kingdoms", {})


static func castle_id(kingdom: String) -> String:
	return CASTLE_PREFIX + kingdom


static func kingdom_of(id: String) -> String:
	## The kingdom a castle id belongs to ("" for other castles).
	return id.substr(CASTLE_PREFIX.length()) if id.begins_with(CASTLE_PREFIX) else ""


func ids() -> Array:
	return kingdoms.keys()


func has(kingdom: Variant) -> bool:
	return kingdom is String and kingdoms.has(kingdom)


func good_name(good: String) -> String:
	return String(goods.get(good, {}).get("name", good.capitalize()))


func is_good(r: String) -> bool:
	return goods.has(r)


func check_found(main: CastleState, founded: Dictionary, kingdom: Variant) -> String:
	## Why a castle can't be founded in this kingdom now ("" if it can).
	## `founded` is the player's kingdoms.
	if not has(kingdom):
		return "No such kingdom."
	var k: Dictionary = kingdoms[kingdom]
	if founded.has(kingdom):
		return "You already have a castle in %s." % k.name
	if main.keep_level() < int(k.keep_needed):
		return "Your keep must reach level %d first." % int(k.keep_needed)
	if not main.can_afford(k.cost):
		return "Not enough resources to found a castle in %s." % k.name
	return ""


func found(main: CastleState, kingdom: String, now: float) -> CastleState:
	## Pays for a castle in the kingdom from the main castle and returns it.
	var k: Dictionary = kingdoms[kingdom]
	for r: String in k.cost:
		main.resources[r] = float(main.resources[r]) - float(k.cost[r])
		main.stats.spent += float(k.cost[r])
	var castle := CastleState.create_new(main.rules, castle_id(kingdom), String(k.castle_name), "player", now)
	castle.limits = {"types": types.duplicate(), "keep": keep_cap}
	castle.yields = {String(k.good): {"rate": float(k.yield.rate), "store": float(k.yield.store)}}
	return castle


func camps(kingdom: String) -> Array:
	## The kingdom's robber baron camps as a new player finds them:
	## [{"id", "name", "position": [x, y], "level", "kingdom"}].
	var out: Array = []
	for c: Dictionary in kingdoms[kingdom].get("camps", []):
		out.append({"id": c.id, "name": c.name, "position": [float(c.position[0]), float(c.position[1])],
				"level": int(c.level), "kingdom": kingdom})
	return out


func voyage(kingdom: String) -> float:
	return float(kingdoms[kingdom].get("voyage", 0.0))


func waiting(castle: CastleState, kingdom: String) -> int:
	## Whole units of the kingdom's good waiting at your castle there.
	return int(floor(float(castle.goods.get(String(kingdoms[kingdom].good), 0.0)) + 0.0001))


func check_ship(castle: CastleState, kingdom: Variant) -> String:
	## Why no ship can sail home from this kingdom now ("" if one can).
	if not has(kingdom) or castle == null:
		return "You have no castle there."
	if waiting(castle, kingdom) < 1:
		return "There is no %s to ship yet." % good_name(String(kingdoms[kingdom].good)).to_lower()
	return ""


func ship(castle: CastleState, state: Dictionary, kingdom: String, now: float) -> Dictionary:
	## Loads everything waiting onto a ship for home and returns the ship.
	var good := String(kingdoms[kingdom].good)
	var amount := waiting(castle, kingdom)
	castle.goods[good] = float(castle.goods.get(good, 0.0)) - amount
	var id := int(state.get("next_ship", 1))
	var boat := {"id": id, "good": good, "amount": amount, "depart": now, "arrive": now + voyage(kingdom)}
	var ships: Array = state.get("ships", [])
	ships.append(boat)
	state["ships"] = ships
	state["next_ship"] = id + 1
	return boat


static func deliver(home: CastleState, state: Dictionary, t: float) -> int:
	## Unloads the ships that are in by `t` at your main castle. Returns how many landed.
	var landed := 0
	var left: Array = []
	for boat: Dictionary in state.get("ships", []):
		if float(boat.arrive) <= t:
			home.goods[boat.good] = float(home.goods.get(boat.good, 0.0)) + float(boat.amount)
			landed += 1
		else:
			left.append(boat)
	state["ships"] = left
	return landed
