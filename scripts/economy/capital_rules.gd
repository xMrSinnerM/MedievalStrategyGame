class_name CapitalRules
extends VillageRules
## Capitals: the towns on the map. They work like resource villages (a guard
## holds each until someone beats them, then it sends its holder gold every
## hour), with a far stronger guard behind stone walls, and they make every
## castle of the holder's alliance produce more. The numbers are in
## data/capitals.json, the towns in server/world/world.json;
## server/rules/villages.ts (CapitalRules) is the same for the online game.
##
## A capital is a village with "capital": true and the "faction" whose town it is.
##
## Whoever holds a capital can raise town buildings there (`buildings` in
## data/capitals.json), paid from their home castle, one at a time, with no
## way to hurry them: town walls, a market for more gold, a guardhouse whose
## watch fights beside the holder's guards, and a guild hall that adds to the
## alliance's production. They stay with the town when it changes hands.

const CAPITALS_PATH := "res://data/capitals.json"

var min_keep := 4
var per_player := 1
var per_alliance := 3
var bonus_base := 0.0
var bonus_per_level := 0.0
var max_bonus := 0.0
var buildings := {}     ## town buildings: id -> {"name", "max_level", "cost", "cost_growth", "time", "time_growth", effect}
var guild_max := 0.0


static func load_capital_rules() -> CapitalRules:
	var rules := CapitalRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(CAPITALS_PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % CAPITALS_PATH)
		data = {}
	rules.load_from(data)
	return rules


static func load_capitals() -> Array:
	## The capitals on the map, as exported for the server (server/world/world.json).
	var world = JSON.parse_string(FileAccess.get_file_as_string(WORLD_PATH))
	return world.get("capitals", []) if world is Dictionary else []


func load_from(data: Dictionary) -> void:
	super.load_from(data)
	min_keep = int(data.get("min_keep", 4))
	per_player = int(data.get("per_player", 1))
	per_alliance = int(data.get("per_alliance", 3))
	bonus_base = float(data.get("bonus_base", 0.0))
	bonus_per_level = float(data.get("bonus_per_level", 0.0))
	max_bonus = float(data.get("max_bonus", 0.0))
	buildings = data.get("buildings", {})
	guild_max = float(data.get("guild_max", 0.0))


func slots_for(keep: int) -> int:
	return per_player if keep >= min_keep else 0


func first_slot_keep() -> int:
	return min_keep


func check_room(keep: int, held: int) -> String:
	## Why you can't hold one more capital ("" if you can).
	if keep < min_keep:
		return "Your keep must reach level %d to take a capital." % min_keep
	if held >= per_player:
		return "You already hold a capital." if per_player == 1 else "You already hold %d capitals." % per_player
	return ""


func check_alliance(held: int) -> String:
	## Why your alliance can't hold one more capital, given how many it holds.
	return "" if held < per_alliance else "Your alliance already holds %d capitals." % per_alliance


func bonus(level: int) -> float:
	## How much more every castle of the holder's alliance produces for one capital.
	return bonus_base + bonus_per_level * (level - 1)


func total_bonus(levels: Array, guilds: Array = []) -> float:
	## The production bonus for capitals of these levels, at most max_bonus,
	## plus what guild halls of these levels add, at most guild_max.
	var sum := 0.0
	for level: Variant in levels:
		sum += bonus(int(level))
	var guild := 0.0
	for level: Variant in guilds:
		guild += building_effect("guildhall", int(level))
	return minf(sum, max_bonus) + minf(guild, guild_max)


func boost(levels: Array, resources: Array, guilds: Array = []) -> Dictionary:
	## The castle boost (CastleState.boost) for capitals of these levels, with guild halls of these levels.
	var b := total_bonus(levels, guilds)
	var out := {}
	if b > 0.0:
		for r: String in resources:
			out[r] = b
	return out


# --- Town buildings -------------------------------------------------------------

func building_levels(state: Dictionary, t: float) -> Dictionary:
	## The town's buildings at time `t` (building -> level), one finished by then included.
	var out: Dictionary = state.get("buildings", {}).duplicate()
	var b: Variant = state.get("building", null)
	if b is Dictionary and float(b.get("finish", 0.0)) <= t:
		out[String(b.id)] = int(b.level)
	return out


func building_level(state: Dictionary, id: String, t: float) -> int:
	return int(building_levels(state, t).get(id, 0))


func under_way(state: Dictionary, t: float) -> Dictionary:
	## The building going up at time `t` ({"id", "level", "finish"}), {} if none.
	var b: Variant = state.get("building", null)
	return b if b is Dictionary and float(b.get("finish", 0.0)) > t else {}


func building_cost(id: String, level: int) -> Dictionary:
	## What raising this building to `level` costs.
	var def: Dictionary = buildings.get(id, {})
	var out := {}
	var cost: Dictionary = def.get("cost", {})
	for r: String in cost:
		out[r] = roundi(float(cost[r]) * pow(float(def.get("cost_growth", 1.0)), level - 1))
	return out


func building_time(id: String, level: int) -> float:
	## How many seconds raising this building to `level` takes.
	var def: Dictionary = buildings.get(id, {})
	return roundf(float(def.get("time", 0.0)) * pow(float(def.get("time_growth", 1.0)), level - 1))


func building_effect(id: String, level: int) -> float:
	## What this building does at `level`: walls' defence, the market's share
	## more gold, the guardhouse's soldiers or the guild hall's share more production.
	var def: Dictionary = buildings.get(id, {})
	for key: String in ["defense", "yield_bonus", "guards", "production"]:
		if def.has(key):
			return float(def[key]) * level
	return 0.0


func check_build(state: Dictionary, id: String, t: float, castle: CastleState) -> String:
	## Why the holder can't start the next level of this town building now ("" if they can).
	if not buildings.has(id):
		return "There's no such town building."
	if not under_way(state, t).is_empty():
		return "The town is already building something."
	var level := building_level(state, id, t)
	if level >= int(buildings[id].get("max_level", 1)):
		return "%s is at its highest level." % String(buildings[id].get("name", id))
	if not castle.can_afford(building_cost(id, level + 1)):
		return "Not enough resources"
	return ""


func start_build(state: Dictionary, id: String, t: float) -> Dictionary:
	## The state with the next level of this building going up from `t`.
	var out := state.duplicate(true)
	var levels := building_levels(state, t)
	var next := int(levels.get(id, 0)) + 1
	if not levels.is_empty():
		out["buildings"] = levels
	out["building"] = {"id": id, "level": next, "finish": t + building_time(id, next)}
	return out


func rate(info: Dictionary, state: Dictionary, t: float) -> int:
	## The town's gold an hour, with what its market adds.
	var base := yield_per_hour(info.resource, int(info.level))
	return roundi(base * (1.0 + building_effect("market", building_level(state, "market", t))))


func wall_defense(info: Dictionary, state: Dictionary, t: float) -> float:
	return palisade(int(info.level)) + building_effect("walls", building_level(state, "walls", t))


func watch(info: Dictionary, state: Dictionary, t: float) -> Dictionary:
	## The guardhouse's soldiers (in the town guard's mix), fighting for the town's holder.
	var level := building_level(state, "guardhouse", t)
	if level <= 0 or String(state.get("owner", "")) == "":
		return {}
	return _mix(roundi(building_effect("guardhouse", level)), int(info.level))


func defenders(info: Dictionary, state: Dictionary, t := 0.0) -> Dictionary:
	## The town guard, or its holder's guards with the guardhouse's watch beside them.
	var out := super.defenders(info, state, t)
	var extra := watch(info, state, t)
	for unit: String in extra:
		out[unit] = int(out.get(unit, 0)) + int(extra[unit])
	return out


func attack(units: BuildingRules, barons: BaronRules, info: Dictionary, state: Dictionary, army: Dictionary, seed_value: int,
		t: float, waves: Array = [], tools := {}, lead := {}) -> Dictionary:
	## As for a village; "guard_left" is the holder's own guards still
	## standing, each unit's losses shared with the watch.
	var result := super.attack(units, barons, info, state, army, seed_value, t, waves, tools, lead)
	var extra := watch(info, state, t)
	if extra.is_empty():
		return result
	var guard: Dictionary = state.get("guard", {})
	var left := {}
	for unit: String in result.guard_left:
		var own := int(guard.get(unit, 0))
		var n := floori(float(result.guard_left[unit]) * own / float(own + int(extra.get(unit, 0)))) if own > 0 else 0
		if n > 0:
			left[unit] = n
	result["guard_left"] = left
	return result
