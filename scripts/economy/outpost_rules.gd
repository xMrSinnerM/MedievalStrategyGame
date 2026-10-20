class_name OutpostRules
extends RefCounted
## Outposts: a second castle with its own buildings, storage and production,
## working a region that boosts one resource, and carts that carry resources
## between it and your home. The numbers are in data/outposts.json;
## server/rules/outposts.ts is the same rules for the online game.
##
## An outpost is a CastleState with id OUTPOST_ID, a "boost" for its region
## and "limits" on what it may build. Carts are {id, to ("home" or
## "outpost"), resources, depart, arrive}.

const PATH := "res://data/outposts.json"
const OUTPOST_ID := "outpost"

var keep_needed := 99
var cost := {}
var keep_cap := 1
var types: Array = []
var cart_share := 0.0
var cart_min := 0
var regions := {}              ## resource -> {name, bonus, description}


static func load_default() -> OutpostRules:
	var rules := OutpostRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


func load_from(data: Dictionary) -> void:
	keep_needed = int(data.get("keep_needed", 99))
	cost = data.get("cost", {})
	keep_cap = int(data.get("keep_cap", 1))
	types = data.get("types", [])
	cart_share = float(data.get("cart_share", 0.0))
	cart_min = int(data.get("cart_min", 0))
	regions = data.get("regions", {})


func check_found(main: CastleState, has: bool, region: Variant, spot: Variant) -> String:
	## Why an outpost can't be founded now ("" if it can). `spot` is where it would stand, or null.
	if has:
		return "You already have an outpost."
	if main.keep_level() < keep_needed:
		return "Your keep must reach level %d first." % keep_needed
	if not region is String or not regions.has(region):
		return "Choose a region for your outpost."
	if spot == null:
		return "There's no free land for an outpost."
	if not main.can_afford(cost):
		return "Not enough resources to found an outpost."
	return ""


func found(main: CastleState, region: String, now: float) -> CastleState:
	## Pays for an outpost from the main castle and returns its new castle.
	for r: String in cost:
		main.resources[r] = float(main.resources[r]) - float(cost[r])
		main.stats.spent = float(main.stats.spent) + float(cost[r])
	var outpost := CastleState.create_new(main.rules, OUTPOST_ID, String(regions[region].name), "player", now)
	outpost.boost = {region: float(regions[region].bonus)}
	outpost.limits = {"types": types.duplicate(), "keep": keep_cap}
	return outpost


func cart_capacity(from: CastleState) -> int:
	## How much one trip of carts from this castle can carry.
	return maxi(cart_min, floori(from.storage_capacity() * cart_share))


func check_carts(from: CastleState, resources: Variant) -> String:
	## Why these resources can't leave `from` by cart ("" if they can).
	if not resources is Dictionary:
		return "Bad resources."
	var total := 0
	for r: Variant in resources:
		if not from.rules.resources.has(r):
			return "Bad resources."
		var n: Variant = resources[r]
		if not (n is int or n is float) or n != floorf(n) or n < 0:
			return "Bad resources."
		if int(n) > floori(float(from.resources.get(r, 0.0))):
			return "Not enough resources."
		total += int(n)
	if total <= 0:
		return "Load something onto the carts."
	var cap := cart_capacity(from)
	if total > cap:
		return "Carts carry at most %d per trip." % cap
	return ""


static func unload(to: CastleState, resources: Dictionary) -> void:
	## Unloads carts into a castle, up to its storage (what doesn't fit is lost).
	var cap := to.storage_capacity()
	for r: String in resources:
		if not to.resources.has(r):
			continue
		var have := float(to.resources[r])
		to.resources[r] = maxf(have, minf(cap, have + float(resources[r])))


static func deliver_carts(home: CastleState, outpost: CastleState, carts: Array, t: float) -> Array:
	## Delivers the carts due by `t`, in order, running each castle up to the
	## moment they arrive. Returns the carts still on the road.
	var due := carts.filter(func(c: Dictionary) -> bool: return float(c.arrive) <= t)
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.arrive) < float(b.arrive) or (float(a.arrive) == float(b.arrive) and int(a.id) < int(b.id)))
	for c: Dictionary in due:
		var to := home if c.to == "home" else outpost
		to.advance_to(float(c.arrive))
		unload(to, c.resources)
	return carts.filter(func(c: Dictionary) -> bool: return float(c.arrive) > t)


static func nearest_spot(spots: Array, home: Vector2, taken: Array) -> Variant:
	## The free castle spot nearest `home` (not home itself) as [x, y], or null.
	var best: Variant = null
	var best_d := INF
	for s: Array in spots:
		var p := Vector2(float(s[0]), float(s[1]))
		if p == home or taken.any(func(q: Vector2) -> bool: return q == p):
			continue
		var d := p.distance_to(home)
		if d < best_d:
			best_d = d
			best = [float(s[0]), float(s[1])]
	return best
