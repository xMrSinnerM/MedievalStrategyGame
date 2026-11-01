class_name GearRules
extends RefCounted
## Commanders and gear: commanders lead your attacks and the castellan your
## castle's defence, each wearing gear that robber barons drop. The numbers
## are in data/gear.json; server/rules/gear.ts is the same rules for the
## online game.
##
## Commanders also learn skills as they level up: one skill point for each
## level past the first, spent in three branches (see `skills`).
##
## Everything lives in the castle's `armoury`: {"commanders": [{id, name,
## level, xp, gear: {slot: item}, skills: {skill: rank}, away_until}], "castellan": {slot: item},
## "bag": [item], "next_item", "marks", "gems": {"ruby:1": count}}. An item
## is {id, slot, side ("attack" or "defence"), rarity, name, stats: {stat:
## percent}, gems: ["ruby:3", ...]}.
##
## Gems sit in gear's sockets and add to its stats; three of a kind and tier
## fuse into the next tier. Marks are the trade coin, earned by playing:
## beating barons, melting gear, prizes. The forge turns three pieces of one
## rarity into one of the next.

const PATH := "res://data/gear.json"
const FORGE_SEED := 50_331_653

var slots: Array = []
var slot_names := {}
var stats := {}                ## stat -> {side, name}
var slot_stats := {}           ## side -> slot -> [stat]
var caps := {}
var rarities := {}             ## rarity -> {name, color, stats, range, sell, weight}
var drop_base := 0.0
var drop_per_level := 0.0
var drop_max := 0.0
var bag_size := 0
var commander_slot_table: Array = [0]
var per_level := 0.0
var levels: Array = [0]
var xp_win_per_level := 0
var xp_player_win := 0
var xp_loss := 0
var commander_names: Array = []
var names := {}
var branches: Array = []       ## [{id, name, text}]
var skills: Array = []         ## [{id, name, branch, needs, after, max, per_rank: {stat: percent}, text}]
var retrain_gold := 0          ## per commander level
var skill_stats := {}          ## names of skill-only stats (xp)
var gems := {}                 ## kind -> {name, stat, color}
var gem_tiers: Array = []      ## [{name, value}], tier 1 first
var fuse_count := 3
var unsocket_marks: Array = []
var gem_drop := {}             ## {base, per_level, max, tiers: [[base, per_level]]}
var marks_per_level := 0.0
var forge_count := 3


static func load_default() -> GearRules:
	var rules := GearRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


func load_from(data: Dictionary) -> void:
	slots = data.get("slots", [])
	slot_names = data.get("slot_names", {})
	stats = data.get("stats", {})
	slot_stats = data.get("slot_stats", {"attack": {}, "defence": {}})
	caps = data.get("caps", {})
	rarities = data.get("rarities", {})
	drop_base = float(data.get("drop_base", 0.0))
	drop_per_level = float(data.get("drop_per_level", 0.0))
	drop_max = float(data.get("drop_max", 0.0))
	bag_size = int(data.get("bag_size", 0))
	commander_slot_table = data.get("commander_slots", [0])
	per_level = float(data.get("per_level", 0.0))
	levels = data.get("levels", [0])
	xp_win_per_level = int(data.get("xp_win_per_level", 0))
	xp_player_win = int(data.get("xp_player_win", 0))
	xp_loss = int(data.get("xp_loss", 0))
	commander_names = data.get("commander_names", [])
	names = data.get("names", {})
	branches = data.get("branches", [])
	skills = data.get("skills", [])
	retrain_gold = int(data.get("retrain_gold", 0))
	skill_stats = data.get("skill_stats", {})
	gems = data.get("gems", {})
	gem_tiers = data.get("gem_tiers", [])
	fuse_count = int(data.get("fuse", 3))
	unsocket_marks = data.get("unsocket_marks", [])
	gem_drop = data.get("gem_drop", {})
	marks_per_level = float(data.get("marks_per_level", 0.0))
	forge_count = int(data.get("forge_count", 3))


static func new_armoury() -> Dictionary:
	return {"commanders": [], "castellan": {}, "bag": [], "next_item": 1, "marks": 0, "gems": {}}


func commander_slots(keep: int) -> int:
	if commander_slot_table.is_empty() or keep < 1:
		return 0
	return int(commander_slot_table[mini(keep, commander_slot_table.size()) - 1])


func max_level() -> int:
	return levels.size()


func level_for(xp: int) -> int:
	## The level `xp` reaches (1 .. max_level()).
	var level := 0
	for need in levels:
		if xp >= int(need):
			level += 1
	return maxi(1, level)


func xp_to_next(commander: Dictionary) -> int:
	## Xp still needed for the next level, or 0 at the top.
	var level := int(commander.level)
	if level >= levels.size():
		return 0
	return int(levels[level]) - int(commander.xp)


func sync(castle: CastleState) -> void:
	## Gives a castle as many commanders as its keep allows.
	var list: Array = castle.armoury.commanders
	var want := commander_slots(castle.keep_level())
	while list.size() < want:
		var i := list.size()
		var base: String = commander_names[i % commander_names.size()] if not commander_names.is_empty() else "Commander"
		list.append({"id": i + 1, "name": base if i < commander_names.size() else base + " the Younger", "level": 1, "xp": 0,
				"gear": {}, "skills": {}, "away_until": 0.0})


func effects(gear: Dictionary, level := 1) -> Dictionary:
	## What gear (and a commander's level) does in a fight: stat -> share,
	## only the stats that are there (Battle.siege() "lead_a" / "lead_b").
	var sum := {}
	for slot: String in slots:
		if not gear.has(slot):
			continue
		var item_stats := total_stats(gear[slot])
		for stat: String in item_stats:
			sum[stat] = float(sum.get(stat, 0.0)) + float(item_stats[stat])
	if level > 1 and per_level > 0.0:
		for stat: String in ["wall_attack", "yard_attack"]:
			sum[stat] = float(sum.get(stat, 0.0)) + per_level * (level - 1)
	var out := {}
	for stat: String in stats:
		var n := minf(float(sum.get(stat, 0.0)), float(caps.get(stat, 0.0)))
		if n > 0.0:
			out[stat] = n / 100.0
	return out


func castellan_effects(castle: CastleState) -> Dictionary:
	## The castellan's gear plus the castle's defence research.
	return with_research(effects(castle.armoury.castellan), castle.research_effects("defence"))


func commander_effects(commander: Dictionary) -> Dictionary:
	## Gear and level, plus skills on top (past the gear caps).
	var fx := effects(commander.gear, int(commander.level))
	var bonus := skill_bonus(commander)
	for stat: String in bonus:
		if stats.has(stat):
			fx[stat] = float(fx.get(stat, 0.0)) + float(bonus[stat]) / 100.0
	return fx


static func with_research(fx: Dictionary, research: Dictionary) -> Dictionary:
	## Gear effects with research's added on top.
	for stat: String in research:
		fx[stat] = float(fx.get(stat, 0.0)) + float(research[stat])
	return fx


func commander(castle: CastleState, id: Variant) -> Dictionary:
	## The commander with this id, or {}.
	if not (id is int or id is float):
		return {}
	for c: Dictionary in castle.armoury.commanders:
		if int(c.id) == int(id) and float(id) == float(int(id)):
			return c
	return {}


func check_lead(castle: CastleState, id: Variant, now: float) -> Variant:
	## The lead for an army ({id, name, fx}): its commander's gear and level
	## plus the castle's attack research. Id 0 is no commander but research;
	## null is neither (`id` 0 or null, nothing researched); a String is why not.
	var research := castle.research_effects("attack")
	if id == null or ((id is int or id is float) and id == 0):
		return null if research.is_empty() else {"id": 0, "name": "", "fx": research}
	var c := commander(castle, id)
	if c.is_empty():
		return "No such commander."
	if float(c.away_until) > now:
		return "%s is still away with an army." % c.name
	return {"id": int(c.id), "name": String(c.name), "fx": with_research(commander_effects(c), research)}


func add_xp(castle: CastleState, id: int, xp: int) -> Dictionary:
	## Gives a commander xp; returns {id, name, xp, level, leveled} for the report, or {}.
	var c := commander(castle, id)
	if c.is_empty():
		return {}
	var before := int(c.level)
	xp = roundi(xp * (1.0 + float(skill_bonus(c).get("xp", 0.0)) / 100.0))
	c.xp = int(c.xp) + xp
	c.level = level_for(int(c.xp))
	return {"id": int(c.id), "name": String(c.name), "xp": xp, "level": int(c.level), "leveled": int(c.level) > before}


# --- Skills ---------------------------------------------------------------------

func skill(id: Variant) -> Dictionary:
	for k: Dictionary in skills:
		if k.id == id:
			return k
	return {}


static func skill_rank(commander: Dictionary, id: String) -> int:
	return int(commander.get("skills", {}).get(id, 0))


static func skill_points(commander: Dictionary) -> int:
	## Points not yet spent: one for each level past the first.
	var spent := 0
	for id: String in commander.get("skills", {}):
		spent += int(commander.skills[id])
	return int(commander.level) - 1 - spent


func skill_bonus(commander: Dictionary) -> Dictionary:
	## What the commander's skills add: stat -> percent (fight stats and xp).
	var out := {}
	for id: String in commander.get("skills", {}):
		var k := skill(id)
		if k.is_empty():
			continue
		for stat: String in k.per_rank:
			out[stat] = float(out.get(stat, 0.0)) + float(k.per_rank[stat]) * int(commander.skills[id])
	return out


func check_learn(castle: CastleState, id: Variant, skill_id: Variant) -> String:
	## Why this commander can't learn a rank of this skill now ("" if they can).
	var c := commander(castle, id)
	if c.is_empty():
		return "No such commander."
	var k := skill(skill_id)
	if k.is_empty():
		return "There's no such skill."
	if skill_rank(c, k.id) >= int(k.max):
		return "%s has mastered %s." % [c.name, k.name]
	if int(c.level) < int(k.needs):
		return "%s needs level %d." % [k.name, int(k.needs)]
	if String(k.after) != "" and skill_rank(c, k.after) <= 0:
		return "Learn %s first." % skill(k.after).get("name", k.after)
	if skill_points(c) <= 0:
		return "%s has no skill points left. They earn one each level." % c.name
	return ""


func learn(castle: CastleState, id: Variant, skill_id: Variant) -> String:
	var why := check_learn(castle, id, skill_id)
	if why == "":
		var c := commander(castle, id)
		c.skills[String(skill_id)] = skill_rank(c, String(skill_id)) + 1
	return why


func retrain_cost(commander: Dictionary) -> Dictionary:
	return {"gold": retrain_gold * int(commander.level)}


func check_retrain(castle: CastleState, id: Variant) -> String:
	var c := commander(castle, id)
	if c.is_empty():
		return "No such commander."
	if c.get("skills", {}).is_empty():
		return "%s hasn't learned any skills yet." % c.name
	if not castle.can_afford(retrain_cost(c)):
		return "Not enough gold."
	return ""


func retrain(castle: CastleState, id: Variant) -> String:
	## Forgets every skill, handing the points back, for gold.
	var why := check_retrain(castle, id)
	if why == "":
		var c := commander(castle, id)
		castle.pay(retrain_cost(c))
		c.skills = {}
	return why


func skill_text(k: Dictionary, ranks := 1) -> String:
	## What `ranks` of a skill do, e.g. "+8% attack at the walls".
	var parts: PackedStringArray = []
	for stat: String in k.per_rank:
		var stat_name := String(stats[stat].name) if stats.has(stat) else String(skill_stats.get(stat, stat))
		parts.append("+%d%% %s" % [int(k.per_rank[stat]) * ranks, stat_name])
	return String(k.text) % ", ".join(parts)


func drop_chance(level: int) -> float:
	return minf(drop_base + drop_per_level * (level - 1), drop_max)


func rarity_weight(rarity: String, level: int) -> float:
	var w: Array = rarities[rarity].weight
	return maxf(0.0, float(w[0]) + float(w[1]) * (level - 1))


func roll_drop(level: int, seed_value: int) -> Dictionary:
	## What a beaten camp of `level` drops (id 0 until given), or {}. The same
	## seed gives the same item (server/rules/gear.ts rollDrop()).
	if slots.is_empty():
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if rng.randf() >= drop_chance(level):
		return {}
	var kinds: Array = rarities.keys()
	var total := 0.0
	for r: String in kinds:
		total += rarity_weight(r, level)
	var pick := rng.randf() * total
	var rarity: String = kinds[kinds.size() - 1]
	for r: String in kinds:
		var w := rarity_weight(r, level)
		if pick < w:
			rarity = r
			break
		pick -= w
	var side := "attack" if rng.randi() % 2 == 0 else "defence"
	var slot: String = slots[rng.randi() % slots.size()]
	return _roll_item(rng, rarity, side, slot)


func _roll_item(rng: RandomNumberGenerator, rarity: String, side: String, slot: String) -> Dictionary:
	## A piece of gear of this rarity, side and slot with random stats and name.
	var def: Dictionary = rarities[rarity]
	var pool: Array = slot_stats[side][slot].duplicate()
	var item_stats := {}
	var lo := int(def.range[0])
	var hi := int(def.range[1])
	for k in int(def.stats):
		if pool.is_empty():
			break
		var stat: String = pool.pop_at(rng.randi() % pool.size())
		item_stats[stat] = lo + rng.randi() % (hi - lo + 1)
	var item_name := ""
	if rarity == "legendary":
		var list: Array = names.legendary[side][slot]
		item_name = list[rng.randi() % list.size()]
	else:
		var adjectives: Array = names.adjectives[rarity]
		var nouns: Array = names.nouns[side][slot]
		var adjective: String = adjectives[rng.randi() % adjectives.size()]
		item_name = "%s %s" % [adjective, nouns[rng.randi() % nouns.size()]]
	return {"id": 0, "slot": slot, "side": side, "rarity": rarity, "name": item_name, "stats": item_stats, "gems": []}


func give(castle: CastleState, item: Dictionary) -> bool:
	## Puts an item in the bag with a new id; false when the bag is full.
	var a: Dictionary = castle.armoury
	if a.bag.size() >= bag_size:
		return false
	item.id = int(a.next_item)
	a.next_item = int(a.next_item) + 1
	a.bag.append(item)
	return true


func sell_price(item: Dictionary) -> int:
	return int(rarities.get(item.rarity, {}).get("sell", 0))


func _bag_index(castle: CastleState, item_id: Variant) -> int:
	if not (item_id is int or item_id is float):
		return -1
	var bag: Array = castle.armoury.bag
	for i in bag.size():
		if int(bag[i].id) == int(item_id) and float(item_id) == float(int(item_id)):
			return i
	return -1


func sell(castle: CastleState, item_id: Variant) -> String:
	## Sells an item from the bag for gold (in full, even past the storage cap).
	var i := _bag_index(castle, item_id)
	if i < 0:
		return "There's no such item in your bag."
	var item: Dictionary = castle.armoury.bag.pop_at(i)
	_free_gems(castle, item)
	castle.resources["gold"] = float(castle.resources.get("gold", 0.0)) + sell_price(item)
	return ""


func _wearer(castle: CastleState, who: Variant, now: float) -> Variant:
	## {gear, side} of a commander (an id) or the castellan ("castellan"), or why its gear can't change now.
	if who is String and who == "castellan":
		return {"gear": castle.armoury.castellan, "side": "defence"}
	var c := commander(castle, who)
	if c.is_empty():
		return "No such commander."
	if float(c.away_until) > now:
		return "%s is away with an army." % c.name
	return {"gear": c.gear, "side": "attack"}


func equip(castle: CastleState, who: Variant, item_id: Variant, now: float) -> String:
	## Puts an item from the bag on a commander or the castellan, swapping out what was worn there.
	var w: Variant = _wearer(castle, who, now)
	if w is String:
		return w
	var i := _bag_index(castle, item_id)
	if i < 0:
		return "There's no such item in your bag."
	var bag: Array = castle.armoury.bag
	var item: Dictionary = bag[i]
	if item.side != w.side:
		return "Commanders wear attack gear." if w.side == "attack" else "The castellan wears defence gear."
	bag.remove_at(i)
	if w.gear.has(item.slot):
		bag.append(w.gear[item.slot])
	w.gear[item.slot] = item
	return ""


func unequip(castle: CastleState, who: Variant, slot: Variant, now: float) -> String:
	## Takes an item off a commander or the castellan and puts it in the bag.
	var w: Variant = _wearer(castle, who, now)
	if w is String:
		return w
	if not slot is String or not w.gear.has(slot):
		return "Nothing is worn there."
	if castle.armoury.bag.size() >= bag_size:
		return "Your bag is full."
	castle.armoury.bag.append(w.gear[slot])
	w.gear.erase(slot)
	return ""


func item_text(item: Dictionary) -> String:
	## "+6% attack at the walls, +4% loot carried" (gems included).
	var parts: PackedStringArray = []
	var all := total_stats(item)
	for stat: String in all:
		parts.append("+%d%% %s" % [int(all[stat]), stats.get(stat, {}).get("name", stat)])
	return ", ".join(parts)


func effects_text(fx: Dictionary) -> String:
	var parts: PackedStringArray = []
	for stat: String in fx:
		parts.append("+%d%% %s" % [roundi(float(fx[stat]) * 100.0), stats.get(stat, {}).get("name", stat)])
	return ", ".join(parts) if not parts.is_empty() else "no bonuses yet"


func rarity_color(rarity: String) -> Color:
	return Color(String(rarities.get(rarity, {}).get("color", "#ffffff")))


static func read_armoury(data: Variant) -> Dictionary:
	## A clean armoury from saved data (anything malformed is dropped).
	var a := new_armoury()
	if not data is Dictionary:
		return a
	for c in data.get("commanders", []):
		if c is Dictionary:
			a.commanders.append({"id": int(c.get("id", 0)), "name": String(c.get("name", "")), "level": int(c.get("level", 1)),
					"xp": int(c.get("xp", 0)), "gear": _read_gear(c.get("gear", {})), "skills": _read_skills(c.get("skills", {})),
					"away_until": float(c.get("away_until", 0.0))})
	a.castellan = _read_gear(data.get("castellan", {}))
	for x in data.get("bag", []):
		var item := _read_item(x)
		if not item.is_empty():
			a.bag.append(item)
	a.next_item = int(data.get("next_item", 1))
	a.marks = maxi(0, int(data.get("marks", 0)))
	var pouch: Variant = data.get("gems", {})
	if pouch is Dictionary:
		for k in pouch:
			if k is String and (pouch[k] is int or pouch[k] is float) and int(pouch[k]) > 0:
				a.gems[k] = int(pouch[k])
	return a


static func _read_gear(g: Variant) -> Dictionary:
	var out := {}
	if g is Dictionary:
		for slot: String in g:
			var item := _read_item(g[slot])
			if not item.is_empty():
				out[slot] = item
	return out


static func _read_skills(x: Variant) -> Dictionary:
	var out := {}
	if x is Dictionary:
		for id in x:
			if (x[id] is int or x[id] is float) and int(x[id]) > 0:
				out[String(id)] = int(x[id])
	return out


static func _read_item(x: Variant) -> Dictionary:
	if not x is Dictionary:
		return {}
	var item_stats := {}
	for k: String in x.get("stats", {}):
		item_stats[k] = int(x.stats[k])
	var held: Array = []
	for k in x.get("gems", []):
		if k is String:
			held.append(k)
	return {"id": int(x.get("id", 0)), "slot": String(x.get("slot", "")), "side": "defence" if x.get("side") == "defence" else "attack",
			"rarity": String(x.get("rarity", "common")), "name": String(x.get("name", "")), "stats": item_stats, "gems": held}


# --- Gems, Marks and the forge ----------------------------------------------------------

static func gem_key(kind: String, tier: int) -> String:
	return "%s:%d" % [kind, tier]


func gem_parts(key: Variant) -> Dictionary:
	## {kind, tier} of a gem key like "ruby:3", or {} if there's no such gem.
	if not key is String:
		return {}
	var bits := String(key).split(":")
	if bits.size() != 2 or not gems.has(bits[0]) or not bits[1].is_valid_int():
		return {}
	var tier := bits[1].to_int()
	if tier < 1 or tier > gem_tiers.size() or bits[1] != str(tier):
		return {}
	return {"kind": bits[0], "tier": tier}


func gem_value(key: String) -> int:
	var p := gem_parts(key)
	return 0 if p.is_empty() else int(gem_tiers[int(p.tier) - 1].value)


func gem_stat(key: String) -> String:
	var p := gem_parts(key)
	return "" if p.is_empty() else String(gems[p.kind].stat)


func gem_side(key: String) -> String:
	var stat := gem_stat(key)
	return String(stats.get(stat, {}).get("side", ""))


func gem_name(key: String) -> String:
	## "Flawless Ruby".
	var p := gem_parts(key)
	if p.is_empty():
		return key
	return "%s %s" % [gem_tiers[int(p.tier) - 1].name, gems[p.kind].name]


func gem_text(key: String) -> String:
	## "+7% attack at the walls".
	return "+%d%% %s" % [gem_value(key), stats.get(gem_stat(key), {}).get("name", gem_stat(key))]


func gem_color(key: String) -> Color:
	var p := gem_parts(key)
	return Color(String(gems[p.kind].color)) if not p.is_empty() else Color.WHITE


func sockets(item: Dictionary) -> int:
	return int(rarities.get(item.get("rarity", ""), {}).get("sockets", 0))


func total_stats(item: Dictionary) -> Dictionary:
	## The item's own stats plus its gems': stat -> percent.
	var out: Dictionary = {}
	for stat: String in item.get("stats", {}):
		out[stat] = int(out.get(stat, 0)) + int(item.stats[stat])
	for key in item.get("gems", []):
		var stat := gem_stat(String(key))
		if stat != "":
			out[stat] = int(out.get(stat, 0)) + gem_value(String(key))
	return out


static func gem_count(castle: CastleState, key: String) -> int:
	return int(castle.armoury.gems.get(key, 0))


static func _add_gem(castle: CastleState, key: String, n: int) -> void:
	var have := gem_count(castle, key) + n
	if have > 0:
		castle.armoury.gems[key] = have
	else:
		castle.armoury.gems.erase(key)


static func add_marks(castle: CastleState, n: int) -> void:
	castle.armoury.marks = maxi(0, int(castle.armoury.get("marks", 0)) + n)


func _free_gems(castle: CastleState, item: Dictionary) -> void:
	## Puts an item's gems back in the pouch (before it is sold, melted or forged).
	for key in item.get("gems", []):
		if not gem_parts(key).is_empty():
			_add_gem(castle, String(key), 1)
	item.gems = []


func check_socket(castle: CastleState, item_id: Variant, key: Variant) -> String:
	## Why this gem can't go into this bag item now ("" if it can).
	var i := _bag_index(castle, item_id)
	if i < 0:
		return "There's no such item in your bag."
	if gem_parts(key).is_empty():
		return "There's no such gem."
	if gem_count(castle, key) <= 0:
		return "You have no %s." % gem_name(key)
	var item: Dictionary = castle.armoury.bag[i]
	if gem_side(key) != item.side:
		return "A %s fits %s gear." % [gem_name(key), gem_side(key)]
	if item.get("gems", []).size() >= sockets(item):
		return "Every socket of the %s is taken." % item.name
	return ""


func socket(castle: CastleState, item_id: Variant, key: Variant) -> String:
	## Sets a gem from your pouch into a free socket of gear in your bag.
	var why := check_socket(castle, item_id, key)
	if why == "":
		var item: Dictionary = castle.armoury.bag[_bag_index(castle, item_id)]
		if not item.has("gems"):
			item.gems = []
		item.gems.append(String(key))
		_add_gem(castle, String(key), -1)
	return why


func unsocket_cost(key: String) -> int:
	var p := gem_parts(key)
	if p.is_empty() or unsocket_marks.is_empty():
		return 0
	return int(unsocket_marks[mini(int(p.tier), unsocket_marks.size()) - 1])


func unsocket(castle: CastleState, item_id: Variant, index: Variant) -> String:
	## Prises gem `index` out of gear in your bag, for Marks; it goes back in your pouch.
	var i := _bag_index(castle, item_id)
	if i < 0:
		return "There's no such item in your bag."
	var item: Dictionary = castle.armoury.bag[i]
	var held: Array = item.get("gems", [])
	if not (index is int or index is float) or float(index) != float(int(index)) or int(index) < 0 or int(index) >= held.size():
		return "There's no gem there."
	var key := String(held[int(index)])
	var cost := unsocket_cost(key)
	if int(castle.armoury.marks) < cost:
		return "Prising out the %s costs %d Marks." % [gem_name(key), cost]
	add_marks(castle, -cost)
	held.remove_at(int(index))
	if not gem_parts(key).is_empty():
		_add_gem(castle, key, 1)
	return ""


func check_fuse(castle: CastleState, key: Variant) -> String:
	var p := gem_parts(key)
	if p.is_empty():
		return "There's no such gem."
	if int(p.tier) >= gem_tiers.size():
		return "A %s is as fine as gems get." % gem_name(key)
	if gem_count(castle, key) < fuse_count:
		return "Fusing needs %d of the same gem." % fuse_count
	return ""


func fuse(castle: CastleState, key: Variant) -> String:
	## Fuses `fuse_count` gems of one kind and tier into one of the next tier.
	var why := check_fuse(castle, key)
	if why == "":
		var p := gem_parts(key)
		_add_gem(castle, String(key), -fuse_count)
		_add_gem(castle, gem_key(p.kind, int(p.tier) + 1), 1)
	return why


func melt_marks(item: Dictionary) -> int:
	return int(rarities.get(item.rarity, {}).get("melt", 0))


func melt(castle: CastleState, item_id: Variant) -> String:
	## Melts gear from your bag down for Marks; its gems go back in your pouch.
	var i := _bag_index(castle, item_id)
	if i < 0:
		return "There's no such item in your bag."
	var item: Dictionary = castle.armoury.bag.pop_at(i)
	_free_gems(castle, item)
	add_marks(castle, melt_marks(item))
	return ""


func next_rarity(rarity: String) -> String:
	var kinds: Array = rarities.keys()
	var i := kinds.find(rarity)
	return "" if i < 0 or i + 1 >= kinds.size() else String(kinds[i + 1])


func forge_cost(rarity: String) -> int:
	return int(rarities.get(rarity, {}).get("forge", 0))


func check_forge(castle: CastleState, ids: Variant) -> String:
	## Why these bag items can't be forged together now ("" if they can).
	if not ids is Array or ids.size() != forge_count:
		return "The forge needs %d pieces of gear." % forge_count
	var picked: Array = []
	for id in ids:
		var i := _bag_index(castle, id)
		if i < 0:
			return "There's no such item in your bag."
		if picked.has(i):
			return "Pick %d different pieces." % forge_count
		picked.append(i)
	var first: Dictionary = castle.armoury.bag[picked[0]]
	for i: int in picked:
		var item: Dictionary = castle.armoury.bag[i]
		if item.rarity != first.rarity:
			return "Forge pieces of the same rarity."
		if item.side != first.side:
			return "Forge attack gear with attack gear, defence with defence."
	if next_rarity(first.rarity) == "":
		return "Legendary gear can't be forged any higher."
	var cost := forge_cost(first.rarity)
	if int(castle.armoury.marks) < cost:
		return "Forging %s gear costs %d Marks." % [String(rarities[first.rarity].name).to_lower(), cost]
	return ""


func forge(castle: CastleState, ids: Variant) -> String:
	## Forges `forge_count` bag items of one rarity and side into one random
	## piece of the next rarity, in the slot of the first, for Marks. The new
	## piece is decided by the castle (the first id and the next item id), so
	## the game and the server agree on it.
	var why := check_forge(castle, ids)
	if why != "":
		return why
	var first: Dictionary = castle.armoury.bag[_bag_index(castle, ids[0])]
	var rarity := next_rarity(first.rarity)
	var side := String(first.side)
	var slot := String(first.slot)
	add_marks(castle, -forge_cost(first.rarity))
	for id in ids:
		var item: Dictionary = castle.armoury.bag.pop_at(_bag_index(castle, id))
		_free_gems(castle, item)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(ids[0]) * 7919 + int(castle.armoury.next_item) * 104729 + FORGE_SEED
	var made := _roll_item(rng, rarity, side, slot)
	give(castle, made)
	return ""


func gem_drop_chance(level: int) -> float:
	return minf(float(gem_drop.get("base", 0.0)) + float(gem_drop.get("per_level", 0.0)) * (level - 1), float(gem_drop.get("max", 0.0)))


func roll_gem(level: int, seed_value: int) -> String:
	## The gem a beaten camp of `level` drops ("" for none). The same seed
	## gives the same gem (server/rules/gear.ts rollGem()).
	var tiers: Array = gem_drop.get("tiers", [])
	if gems.is_empty() or tiers.is_empty():
		return ""
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	if rng.randf() >= gem_drop_chance(level):
		return ""
	var weights: Array = []
	var total := 0.0
	for w: Array in tiers:
		var n := maxf(0.0, float(w[0]) + float(w[1]) * (level - 1))
		weights.append(n)
		total += n
	var tier := tiers.size()
	var pick := rng.randf() * total
	for t in weights.size():
		if pick < float(weights[t]):
			tier = t + 1
			break
		pick -= float(weights[t])
	var kinds: Array = gems.keys()
	return gem_key(String(kinds[rng.randi() % kinds.size()]), tier)


func marks_for_win(level: int) -> int:
	return maxi(1, floori(marks_per_level * level)) if marks_per_level > 0.0 else 0


func give_spoils(castle: CastleState, level: int, seed_value: int) -> Dictionary:
	## The gem and Marks a beaten camp of `level` gives, put in the armoury: {gem, marks}.
	var gem := roll_gem(level, seed_value)
	if gem != "":
		_add_gem(castle, gem, 1)
	var marks := marks_for_win(level)
	add_marks(castle, marks)
	return {"gem": gem, "marks": marks}
