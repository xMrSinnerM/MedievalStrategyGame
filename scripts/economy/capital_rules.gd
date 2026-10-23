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

const CAPITALS_PATH := "res://data/capitals.json"

var min_keep := 4
var per_player := 1
var per_alliance := 3
var bonus_base := 0.0
var bonus_per_level := 0.0
var max_bonus := 0.0


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


func total_bonus(levels: Array) -> float:
	## The production bonus for capitals of these levels, at most max_bonus.
	var sum := 0.0
	for level: Variant in levels:
		sum += bonus(int(level))
	return minf(sum, max_bonus)


func boost(levels: Array, resources: Array) -> Dictionary:
	## The castle boost (CastleState.boost) for capitals of these levels.
	var b := total_bonus(levels)
	var out := {}
	if b > 0.0:
		for r: String in resources:
			out[r] = b
	return out
