class_name VillageRules
extends RefCounted
## Resource villages: hamlets on the map that each work one resource. Local
## militia holds a village until someone beats them; then it sends its yield
## to its owner's castle, and online other players can take it from them.
## The numbers are in data/villages.json, where the villages stand in
## server/world/world.json (VillagePlacer); server/rules/villages.ts is the
## same rules for the online game.
##
## A village is {"id", "name", "position": [x, z], "level", "resource"}; who
## holds it is {"id", "owner" ("" for the militia), "guard": {unit: count},
## "taken_at", "paid_at"}.

const PATH := "res://data/villages.json"
const WORLD_PATH := "res://server/world/world.json"

var yields := {}
var yield_growth := 1.0
var store_hours := 0.0
var guard_base := 0.0
var guard_growth := 1.0
var guard_armies: Array = []    ## [{"from_level", "mix": {unit: share}}], ascending
var palisade_base := 0.0
var palisade_per_level := 0.0
var slots: Array = []           ## [{"keep", "count"}], ascending
var peace_hours := 0.0
var max_level := 5
var placement := {}             ## how VillagePlacer spreads them over the map
var names := {}                 ## "first" and "second" halves of village names
var resource_names := {}        ## resource -> what such a village is called


static func load_default() -> VillageRules:
	var rules := VillageRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


static func load_villages() -> Array:
	## The villages on the map, as placed for the server (server/world/world.json).
	var world = JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	return world.get("villages", []) if world is Dictionary else []


func load_from(data: Dictionary) -> void:
	yields = data.get("yields", {})
	yield_growth = float(data.get("yield_growth", 1.0))
	store_hours = float(data.get("store_hours", 0.0))
	guard_base = float(data.get("guard_base", 0.0))
	guard_growth = float(data.get("guard_growth", 1.0))
	guard_armies = data.get("guard_armies", [])
	palisade_base = float(data.get("palisade_base", 0.0))
	palisade_per_level = float(data.get("palisade_per_level", 0.0))
	slots = data.get("slots", [])
	peace_hours = float(data.get("peace_hours", 0.0))
	max_level = int(data.get("max_level", 5))
	placement = data.get("placement", {})
	names = data.get("names", {})
	resource_names = data.get("resource_names", {})


func yield_per_hour(resource: String, level: int) -> int:
	## What a village of this resource and level sends its owner each hour.
	return roundi(float(yields.get(resource, 0.0)) * pow(yield_growth, level - 1))


func store_cap(resource: String, level: int) -> int:
	## The most a village holds before its owner's castle gets it.
	return roundi(yield_per_hour(resource, level) * store_hours)


func stock(info: Dictionary, state: Dictionary, t: float) -> int:
	## What the village holds at time `t`: its full store under the militia,
	## else its yield since it was last paid.
	var cap := store_cap(info.resource, int(info.level))
	if String(state.get("owner", "")) == "":
		return cap
	var made := yield_per_hour(info.resource, int(info.level)) * maxf(0.0, t - float(state.get("paid_at", 0.0))) / 3600.0
	return floori(minf(cap, made))


func collect(info: Dictionary, state: Dictionary, t: float) -> Dictionary:
	## What an owned village sends its owner at time `t`, and up to when that
	## pays it: {"amount", "paid_at"} (whole units only: the rest waits for
	## the next time). A full store sends everything it holds.
	var per_hour := yield_per_hour(info.resource, int(info.level))
	var paid := float(state.get("paid_at", 0.0))
	if String(state.get("owner", "")) == "" or per_hour <= 0 or t <= paid:
		return {"amount": 0, "paid_at": paid}
	var made := per_hour * (t - paid) / 3600.0
	var cap := store_cap(info.resource, int(info.level))
	if made >= cap:
		return {"amount": cap, "paid_at": t}
	var amount := floori(made)
	return {"amount": amount, "paid_at": paid + amount * 3600.0 / per_hour}


func militia(level: int) -> Dictionary:
	## The militia holding a village of this level (unit -> count).
	var total := roundi(guard_base * pow(guard_growth, level - 1))
	var mix: Dictionary = {}
	for army: Dictionary in guard_armies:
		if level >= int(army.from_level):
			mix = army.mix
	var out := {}
	var placed := 0
	var units := mix.keys()
	for i in units.size():
		var unit: String = units[i]
		var n := roundi(total * float(mix[unit])) if i < units.size() - 1 else total - placed
		if n > 0:
			out[unit] = n
			placed += n
	return out


func palisade(level: int) -> float:
	return palisade_base + palisade_per_level * (level - 1)


func defenders(info: Dictionary, state: Dictionary) -> Dictionary:
	## Who defends the village: the militia, or the soldiers its owner stationed there.
	if String(state.get("owner", "")) == "":
		return militia(int(info.level))
	return state.get("guard", {}).duplicate()


func slots_for(keep: int) -> int:
	## How many villages a castle with this keep level may hold.
	var n := 0
	for s: Dictionary in slots:
		if keep >= int(s.keep):
			n = int(s.count)
	return n


func first_slot_keep() -> int:
	return int(slots[0].keep) if not slots.is_empty() else 99


func peace_until(state: Dictionary) -> float:
	## Until when a village that just changed hands can't be attacked.
	if String(state.get("owner", "")) == "" or float(state.get("taken_at", 0.0)) <= 0.0:
		return 0.0
	return float(state.taken_at) + peace_hours * 3600.0


func check_room(keep: int, held: int) -> String:
	## Why you can't hold one more village ("" if you can).
	if held < slots_for(keep):
		return ""
	if keep < first_slot_keep():
		return "Your keep must reach level %d to hold a village." % first_slot_keep()
	return "Your keep can't hold another village yet."


func attack(units: BuildingRules, barons: BaronRules, info: Dictionary, state: Dictionary, army: Dictionary, seed_value: int,
		t: float, waves: Array = [], tools := {}, lead := {}) -> Dictionary:
	## Storms the village's palisade with `waves` (by default the army in one
	## wave) and the attackers' siege `tools`, against its defenders in
	## Battle.DEFAULT_LAYOUT. Returns the siege result plus "survivors" (the
	## attackers going home), "guard_left" (the defenders still standing) and
	## "loot" (what a win carries off from the village's store, as much as the
	## survivors can carry). The village itself is not changed: see capture().
	var result := Battle.siege(units, waves if not waves.is_empty() else Battle.auto_waves(army), defenders(info, state),
			Battle.DEFAULT_LAYOUT, seed_value, Battle.wall_from_defense(palisade(int(info.level))), {"a": tools, "lead_a": lead})
	result["survivors"] = Battle.survivors(result.a)
	result["guard_left"] = Battle.survivors(result.b)
	result["loot"] = {}
	if result.winner == "a":
		result["loot"] = BaronCamp._carried({info.resource: stock(info, state, t)},
				barons.carry(result.survivors) * (1.0 + float(lead.get("loot", 0.0))))
	return result


static func capture(state: Dictionary, owner: String, t: float) -> Dictionary:
	## The village handed to a new owner at time `t`, empty of soldiers, its peace starting.
	var out := state.duplicate(true)
	out["owner"] = owner
	out["guard"] = {}
	out["taken_at"] = t
	out["paid_at"] = t
	return out


static func untouched(id: String) -> Dictionary:
	return {"id": id, "owner": "", "guard": {}, "taken_at": 0.0, "paid_at": 0.0}
