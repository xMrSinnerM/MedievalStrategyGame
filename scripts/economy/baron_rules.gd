class_name BaronRules
extends RefCounted
## The numbers behind robber baron camps, read from data/barons.json: how big
## a camp's garrison is at each level, what it is made of, how strong its
## palisade is, what loot it holds, how many defeats raise its level and how
## long a beaten camp takes to rebuild.
##
## Values for level N grow from the level-1 value: base * growth^(N - 1).
## Everything here is a pure function of the level, so a server can compute
## the same numbers.

const PATH := "res://data/barons.json"
const FORTRESS_PATH := "res://data/fortresses.json"
const HORDE_PATH := "res://data/horde.json"
const STRONGHOLD_PATH := "res://data/stronghold.json"
const KINGDOMS_PATH := "res://data/kingdoms.json"

var max_level := 40
var garrison_base := 14.0
var garrison_growth := 1.16
var armies: Array = []            ## [{"from_level", "mix": {unit: share}}], ascending
var palisade_base := 20.0
var palisade_per_level := 15.0
var loot_base: Dictionary = {}
var loot_growth := 1.15
var carry_per_soldier := 12.0
var defeats_per_level: Array = [] ## [{"from_level", "defeats"}], ascending
var rebuild_base := 300.0
var rebuild_per_level := 30.0
var march_speed := 6.0            ## map units an army covers per second
var camps: Dictionary = {}        ## how camps are spread over the map (BaronPlacer)
var names: Dictionary = {}        ## "first" and "second" halves of camp names
var drop_level_bonus := 0         ## a fortress drops gear like a camp this many levels higher
## The numbers for fortresses (data/fortresses.json): online, the old
## kingdoms' castles are camps with "fortress" set (BaronCamp.fortress).
var fortress: BaronRules
## The numbers for the Ember Horde's camps (data/horde.json): online, a timed
## event's camps with "horde" set (BaronCamp.horde).
var horde: BaronRules
## The numbers for the Warlord's Stronghold (data/stronghold.json): online, the
## alliance event's camp with "boss" set (BaronCamp.boss).
var boss: BaronRules
## The numbers for camps in the other kingdoms (data/kingdoms.json): kingdom
## id -> these rules with the kingdom's `barons` changes (BaronCamp.kingdom).
var kingdoms := {}
## Kingdom camps only: seconds the army sails before it marches, and where
## in the kingdom it marches from (your castle there).
var voyage := 0.0
var origin: Variant = null


static func load_default() -> BaronRules:
	var rules := BaronRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	var forts = JSON.parse_string(FileAccess.get_file_as_string(FORTRESS_PATH))
	if forts is Dictionary:
		rules.fortress = BaronRules.new()
		rules.fortress.load_from(forts)
	var horde_data = JSON.parse_string(FileAccess.get_file_as_string(HORDE_PATH))
	if horde_data is Dictionary:
		rules.horde = BaronRules.new()
		rules.horde.load_from(horde_data)
	var stronghold = JSON.parse_string(FileAccess.get_file_as_string(STRONGHOLD_PATH))
	if stronghold is Dictionary:
		rules.boss = BaronRules.new()
		rules.boss.load_from(stronghold)
	var lands = JSON.parse_string(FileAccess.get_file_as_string(KINGDOMS_PATH))
	if lands is Dictionary:
		rules.load_kingdoms(data, lands)
	return rules


func load_kingdoms(base: Dictionary, lands: Dictionary) -> void:
	## Makes the rules for each kingdom's camps: `base` (data/barons.json) with the kingdom's `barons` on top.
	var all: Dictionary = lands.get("kingdoms", {})
	for id: String in all:
		var merged := base.duplicate()
		merged.merge(all[id].get("barons", {}), true)
		var k := BaronRules.new()
		k.load_from(merged)
		k.voyage = float(all[id].get("voyage", 0.0))
		var spot: Array = all[id].get("castle", [0.0, 0.0])
		k.origin = Vector2(float(spot[0]), float(spot[1]))
		kingdoms[id] = k


func for_camp(camp: BaronCamp) -> BaronRules:
	## The rules for this camp: the fortress rules for a fortress, the horde's for a horde camp, else these.
	if camp.is_boss() and boss != null:
		return boss
	if camp.is_horde() and horde != null:
		return horde
	if camp.kingdom != "" and kingdoms.has(camp.kingdom):
		return kingdoms[camp.kingdom]
	return fortress if camp.fortress and fortress != null else self


func load_from(data: Dictionary) -> void:
	max_level = int(data.get("max_level", max_level))
	garrison_base = float(data.get("garrison_base", garrison_base))
	garrison_growth = float(data.get("garrison_growth", garrison_growth))
	armies = data.get("armies", [])
	palisade_base = float(data.get("palisade_base", palisade_base))
	palisade_per_level = float(data.get("palisade_per_level", palisade_per_level))
	loot_base = data.get("loot_base", {})
	loot_growth = float(data.get("loot_growth", loot_growth))
	carry_per_soldier = float(data.get("carry_per_soldier", carry_per_soldier))
	defeats_per_level = data.get("defeats_per_level", [{"from_level": 1, "defeats": 1}])
	rebuild_base = float(data.get("rebuild_base", rebuild_base))
	rebuild_per_level = float(data.get("rebuild_per_level", rebuild_per_level))
	march_speed = float(data.get("march_speed", march_speed))
	camps = data.get("camps", {})
	names = data.get("names", {})
	drop_level_bonus = int(data.get("drop_level_bonus", 0))


func garrison(level: int) -> Dictionary:
	## The soldiers defending a camp of this level (unit -> count).
	var total := roundi(garrison_base * pow(garrison_growth, level - 1))
	var mix: Dictionary = {}
	for army: Dictionary in armies:
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
	## The camp's wall defence, used like a castle's (Battle.wall_from_defense).
	return palisade_base + palisade_per_level * (level - 1)


func loot(level: int) -> Dictionary:
	## Everything a camp of this level holds; the winners carry off what they can.
	var out := {}
	for r: String in loot_base:
		out[r] = roundi(float(loot_base[r]) * pow(loot_growth, level - 1))
	return out


func defeats_needed(level: int) -> int:
	## Defeats at this level before the camp rises to the next.
	var n := 1
	for step: Dictionary in defeats_per_level:
		if level >= int(step.from_level):
			n = int(step.defeats)
	return n


func rebuild_time(level: int) -> float:
	## Seconds a camp beaten at this level takes to rebuild.
	return rebuild_base + rebuild_per_level * (level - 1)


func march_time(distance: float) -> float:
	## Seconds an army takes to march this far (one way).
	return maxf(10.0, distance / march_speed)


func travel_time(camp: BaronCamp, home: Vector2) -> float:
	## Seconds an army takes to reach this camp (one way): the march from
	## `home`, or for a kingdom's camp the voyage and the march from your
	## castle there.
	var r := for_camp(camp)
	if r.origin == null:
		return march_time(home.distance_to(camp.position))
	return r.voyage + march_time((r.origin as Vector2).distance_to(camp.position))


func carry(army: Dictionary) -> float:
	## How much loot these soldiers can carry home.
	var n := 0
	for unit: String in army:
		n += int(army[unit])
	return n * carry_per_soldier
