class_name EncounterRules
extends RefCounted
## Random map encounters: bandit camps, merchant caravans and treasure sites
## that come and go along the roads. Which ones are on the map, where and
## for how long is worked out from the time alone (each of `count` slots
## picks a new one every `window_hours`, staggered), so the game and the
## server see the same ones without keeping a list. Each castle can win each
## encounter once (castle.encounters.done). The numbers are in
## data/encounters.json; server/rules/encounters.ts is the same rules.

const PATH := "res://data/encounters.json"
const ROADS_PATH := "res://data/roads.json"
const SETTLEMENTS_PATH := "res://data/settlements.json"
const CLEAR := {"town": 115.0, "castle": 65.0, "village": 45.0}   ## room kept round settlements
const KINDS := ["bandits", "caravan", "treasure"]
const SHARES := {"quarter": 0.25, "half": 0.5, "all": 1.0}

var window := 21600.0         ## seconds an encounter stays
var count := 0
var scale: Array = [1]
var weights := {}             ## kind -> weight
var bandits := {}
var caravan := {}
var treasure := {}
var roads: Array = []         ## [[[x, z], ...], ...]
var places: Array = []        ## [[Vector2, room], ...] settlements a camp keeps clear of (drawing only)
var _spots := {}              ## "road:at" -> Vector2


static func load_default() -> EncounterRules:
	var rules := EncounterRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	var road_data = JSON.parse_string(FileAccess.get_file_as_string(ROADS_PATH))
	if not data is Dictionary or not road_data is Dictionary:
		push_error("Could not read %s or %s" % [PATH, ROADS_PATH])
		data = {}
		road_data = {}
	rules.load_from(data, road_data.get("roads", []))
	var places_data = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENTS_PATH))
	if places_data is Dictionary:
		for s: Dictionary in places_data.get("settlements", []):
			rules.places.append([Vector2(s.position[0], s.position[1]), float(CLEAR.get(String(s.type), 40.0))])
	return rules


func load_from(data: Dictionary, road_list: Array) -> void:
	window = float(data.get("window_hours", 6)) * 3600.0
	count = int(data.get("count", 0))
	scale = data.get("scale", [1])
	weights = data.get("kinds", {})
	bandits = data.get("bandits", {})
	caravan = data.get("caravan", {})
	treasure = data.get("treasure", {})
	roads = []
	for r: Dictionary in road_list:
		if r.get("points", []).size() >= 2:
			roads.append(r.points)


func _mult(keep: int) -> float:
	return float(scale[clampi(keep, 1, scale.size()) - 1])


func _scaled(base: Dictionary, keep: int) -> Dictionary:
	var out := {}
	for r: String in base:
		out[r] = roundi(float(base[r]) * _mult(keep))
	return out


# --- What's on the map -----------------------------------------------------------

func make(slot: int, w: int) -> Dictionary:
	## The encounter slot `slot` holds in its window `w`.
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 7919 + slot * 104729 + 4242
	var sum := 0
	for k: String in KINDS:
		sum += int(weights.get(k, 0))
	var roll := int(rng.randi() % maxi(sum, 1))
	var kind := KINDS[0]
	for k: String in KINDS:
		roll -= int(weights.get(k, 0))
		if roll < 0:
			kind = k
			break
	var road := int(rng.randi() % roads.size())
	# How far along the road, in thousandths of its length: the middle, away
	# from the settlements at its ends.
	var at := 300 + int(rng.randi() % 401)
	var variant := int(rng.randi() % 1000)
	var offset := window * slot / maxi(count, 1)
	var start := w * window - offset
	return {"id": "e%d-%d" % [slot, w], "slot": slot, "kind": kind, "road": road, "at": at, "variant": variant,
		"start": start, "end": start + window}


func active(t: float) -> Array:
	## The encounters on the map at time t.
	var out: Array = []
	if roads.is_empty():
		return out
	for slot in count:
		var offset := window * slot / count
		out.append(make(slot, int(floor((t + offset) / window))))
	return out


func find(t: float, id: String) -> Dictionary:
	for e: Dictionary in active(t):
		if e.id == id:
			return e
	return {}


func position(e: Dictionary, t: float) -> Vector2:
	## Where it stands; a caravan walks the middle of its road while it's on the map.
	if e.kind == "caravan":
		return _along(roads[int(e.road)], 0.2 + 0.6 * clampf((t - float(e.start)) / window, 0.0, 1.0))
	var key := "%d:%d" % [int(e.road), int(e.at)]
	if not _spots.has(key):
		_spots[key] = _clear_spot(roads[int(e.road)], float(e.at) / 1000.0)
	return _spots[key]


func _clear_spot(points: Array, f: float) -> Vector2:
	## The spot nearest f along the road that isn't on top of a settlement
	## (some roads run right past a village), or failing that the best one
	## moved off the road away from the settlement in the way. Only the game
	## draws spots, so the server doesn't need this.
	var best := _along(points, f)
	var best_room := -INF
	for k in 15:
		var g := f + ((k + 1) >> 1) * 0.04 * (1 if k % 2 == 1 else -1)
		if g < 0.12 or g > 0.88:
			continue
		var p := _along(points, g)
		var room: float = _room(p)[0]
		if room >= 0.0:
			return p
		if room > best_room:
			best_room = room
			best = p
	for k in 4:
		var near: Array = _room(best)
		if float(near[0]) >= 0.0:
			break
		var away: Vector2 = best - near[1]
		best += (away.normalized() if away.length() > 0.01 else Vector2.RIGHT) * (2.0 - float(near[0]))
	return best


func _room(p: Vector2) -> Array:
	## [how far p is outside the nearest settlement's room, where that settlement is].
	var room := INF
	var at := p
	for place: Array in places:
		var r: float = p.distance_to(place[0]) - float(place[1])
		if r < room:
			room = r
			at = place[0]
	return [room, at]


static func _along(points: Array, f: float) -> Vector2:
	## The point a fraction f of the way along a road, by distance.
	var total := 0.0
	for k in range(1, points.size()):
		total += Vector2(points[k - 1][0], points[k - 1][1]).distance_to(Vector2(points[k][0], points[k][1]))
	var left := total * f
	for k in range(1, points.size()):
		var a := Vector2(points[k - 1][0], points[k - 1][1])
		var b := Vector2(points[k][0], points[k][1])
		var d := a.distance_to(b)
		if left <= d and d > 0.0:
			return a.lerp(b, left / d)
		left -= d
	var last: Array = points[points.size() - 1]
	return Vector2(last[0], last[1])


func display_name(e: Dictionary) -> String:
	return String({"bandits": bandits, "caravan": caravan, "treasure": treasure}[e.kind].get("name", e.kind))


static func done(castle: CastleState, id: String) -> bool:
	return castle.encounters.done.has(id)


func _record(castle: CastleState, id: String, t: float) -> void:
	## Remembers a won encounter, forgetting those no longer on the map.
	var live := {}
	for e: Dictionary in active(t):
		live[e.id] = true
	var kept: Array = []
	for d: String in castle.encounters.done:
		if live.has(d):
			kept.append(d)
	kept.append(id)
	castle.encounters.done = kept


# --- What each one asks and gives ---------------------------------------------------

func bandit_army(keep: int) -> Dictionary:
	var armies: Array = bandits.get("army", [{}])
	return armies[clampi(keep, 1, armies.size()) - 1].duplicate()


func bandit_loot(keep: int) -> Dictionary:
	return {"resources": _scaled(bandits.get("loot", {}), keep)}


static func sent_army(castle: CastleState, share: String) -> Dictionary:
	## The soldiers a share of the garrison makes.
	var f := float(SHARES.get(share, 0.0))
	var army := {}
	for unit: String in castle.troops:
		var n := int(floor(int(castle.troops[unit]) * f))
		if n > 0:
			army[unit] = n
	return army


func trade(e: Dictionary, keep: int) -> Dictionary:
	## The caravan's offer: {"give", "get"}.
	var trades: Array = caravan.get("trades", [])
	var t: Dictionary = trades[int(e.variant) % trades.size()]
	return {"give": _scaled(t.give, keep), "get": _scaled(t.get, keep)}


func dig_cost(keep: int) -> Dictionary:
	return _scaled(treasure.get("cost", {}), keep)


func check(castle: CastleState, e: Dictionary, choice := "") -> String:
	## Why this encounter can't be taken on now ("" if it can).
	if e.is_empty():
		return "That's gone from the map."
	if done(castle, String(e.id)):
		return "You've already been there."
	match String(e.kind):
		"bandits":
			if sent_army(castle, choice).is_empty():
				return "Send at least one soldier."
		"caravan":
			if not castle.can_afford(trade(e, castle.keep_level()).give):
				return "You don't have enough to trade."
		"treasure":
			if castle.troop_count() < int(treasure.get("diggers", 0)):
				return "You need %d soldiers at home to dig." % int(treasure.get("diggers", 0))
			if not castle.can_afford(dig_cost(castle.keep_level())):
				return "You don't have enough food for the diggers."
	return ""


func take(castle: CastleState, id: String, choice: String, now: float) -> Dictionary:
	## Takes on an encounter: {"error"} or {"error": "", "kind", ...what
	## happened}. Bandits: {"fight", "won", "reward"}; caravans and treasure
	## sites: {"reward"} (a caravan's also has "paid").
	var e := find(now, id)
	var why := check(castle, e, choice)
	if why != "":
		return {"error": why}
	var keep := castle.keep_level()
	var seed_value := castle.castle_name.hash() + int(floor(float(e.start))) % 100003 + int(e.slot) * 31
	match String(e.kind):
		"bandits":
			var army := sent_army(castle, choice)
			var fight := Battle.fight(castle.rules, army, bandit_army(keep), seed_value)
			for unit: String in fight.a:
				castle.troops[unit] = int(castle.troops.get(unit, 0)) - int(fight.a[unit].lost)
				if int(castle.troops[unit]) <= 0:
					castle.troops.erase(unit)
			var won: bool = fight.winner == "a"
			var reward := {}
			if won:
				reward = bandit_loot(keep)
				var rng := RandomNumberGenerator.new()
				rng.seed = seed_value
				if rng.randf() < float(bandits.get("chest_chance", 0.0)):
					reward["chests"] = {String(bandits.get("chest", "wooden")): 1}
				QuestBook.give(castle, reward)
				_record(castle, id, now)
			return {"error": "", "kind": "bandits", "fight": fight, "won": won, "reward": reward}
		"caravan":
			var offer := trade(e, keep)
			castle.pay(offer.give)
			var reward := {"resources": offer.get}
			QuestBook.give(castle, reward)
			_record(castle, id, now)
			return {"error": "", "kind": "caravan", "paid": offer.give, "reward": reward}
		_:
			castle.pay(dig_cost(keep))
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var list: Array = treasure.get("chests", [])
			var sum := 0
			for c: Dictionary in list:
				sum += int(c.weight)
			var roll := int(rng.randi() % maxi(sum, 1))
			var chest := "wooden"
			for c: Dictionary in list:
				roll -= int(c.weight)
				if roll < 0:
					chest = String(c.kind)
					break
			var reward := {"resources": _scaled({"gold": treasure.get("gold", 0)}, keep), "chests": {chest: 1}}
			QuestBook.give(castle, reward)
			_record(castle, id, now)
			return {"error": "", "kind": "treasure", "reward": reward}
