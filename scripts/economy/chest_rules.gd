class_name ChestRules
extends RefCounted
## Treasure chests and the Wheel of Fortune. Chests come as rewards (the
## coffer, the Royal Gift, achievements, seasons); opening one spins its
## wheel of eight prizes, picked by weight. The spin is decided by the castle
## and how many chests it has opened, so the game can show the wheel landing
## where the server will. The numbers are in data/chests.json;
## server/rules/chests.ts is the same rules for the online game.

const PATH := "res://data/chests.json"
const ORDER := ["wooden", "iron", "golden"]

var scale: Array = [1]
var kinds := {}           ## kind -> {name, color, wheel: [{weight, reward, jackpot?}]}


static func load_default() -> ChestRules:
	var rules := ChestRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


func load_from(data: Dictionary) -> void:
	scale = data.get("scale", [1])
	kinds = data.get("kinds", {})


func count(castle: CastleState, kind: String) -> int:
	return int(castle.chests.have.get(kind, 0))


func total(castle: CastleState) -> int:
	var n := 0
	for kind: String in castle.chests.have:
		n += int(castle.chests.have[kind])
	return n


func slot_reward(kind: String, index: int, keep: int) -> Dictionary:
	## What a wheel slot gives, for this keep level.
	var mult := float(scale[clampi(keep, 1, scale.size()) - 1])
	var base: Dictionary = kinds[kind].wheel[index].reward
	var out := {}
	if base.has("resources"):
		var resources := {}
		for r: String in base.resources:
			resources[r] = roundi(float(base.resources[r]) * mult)
		out["resources"] = resources
	for k: String in ["troops", "tools", "chests"]:
		if base.has(k):
			out[k] = base[k].duplicate()
	return out


func spin(castle: CastleState, kind: String) -> int:
	## The wheel slot the next chest of this kind lands on.
	var wheel: Array = kinds[kind].wheel
	var sum := 0
	for slot: Dictionary in wheel:
		sum += int(slot.weight)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(castle.chests.opened) * 1000003 + castle.castle_name.hash() + ORDER.find(kind) * 7919
	var roll := int(rng.randi() % sum)
	for i in wheel.size():
		roll -= int(wheel[i].weight)
		if roll < 0:
			return i
	return wheel.size() - 1


func check_open(castle: CastleState, kind: String) -> String:
	if not kinds.has(kind):
		return "There's no such chest."
	if count(castle, kind) <= 0:
		return "You have no %s." % String(kinds[kind].name).to_lower()
	return ""


func open(castle: CastleState, kind: String) -> Dictionary:
	## Opens a chest: {"error"} or {"error": "", "slot", "reward"}.
	var why := check_open(castle, kind)
	if why != "":
		return {"error": why}
	var slot := spin(castle, kind)
	var reward := slot_reward(kind, slot, castle.keep_level())
	castle.chests.have[kind] = count(castle, kind) - 1
	if int(castle.chests.have[kind]) <= 0:
		castle.chests.have.erase(kind)
	castle.chests.opened = int(castle.chests.opened) + 1
	QuestBook.give(castle, reward)
	return {"error": "", "slot": slot, "reward": reward}
