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


static func load_default() -> BaronRules:
	var rules := BaronRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


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


func carry(army: Dictionary) -> float:
	## How much loot these soldiers can carry home.
	var n := 0
	for unit: String in army:
		n += int(army[unit])
	return n * carry_per_soldier
