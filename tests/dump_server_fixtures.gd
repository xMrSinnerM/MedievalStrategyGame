extends SceneTree
## Writes server/tests/fixtures.json: random castle orders, battles and
## robber baron attacks run through the game's own rules, with every result.
## The server's TypeScript rules replay them and must get the same answers
## (server/tests/rules.test.ts). Run after changing the rules or the data:
##   godot --headless --path . --script res://tests/dump_server_fixtures.gd

const OUT := "res://server/tests/fixtures.json"
const T0 := 1_000_000.0

var rules: BuildingRules
var baron_rules: BaronRules
var quest_book: QuestBook
var gear: GearRules
var outposts: OutpostRules
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rules = BuildingRules.load_default()
	baron_rules = BaronRules.load_default()
	quest_book = QuestBook.load_default()
	gear = GearRules.load_default()
	outposts = OutpostRules.load_default()
	rng.seed = 20261011
	var data := {
		"castles": [],
		"battles": [],
		"sieges": [],
		"barons": [],
		"camp_attacks": [],
		"dailies": [],
		"drops": [],
		"armoury": {},
		"outpost": {},
		"hashes": {},
	}
	for run in 4:
		data.castles.append(castle_run(run))
	for k in 100:
		data.battles.append(battle_case())
	for k in 80:
		data.sieges.append(siege_case())
	for level in range(1, baron_rules.max_level + 1):
		data.barons.append({
			"level": level, "garrison": baron_rules.garrison(level), "palisade": baron_rules.palisade(level),
			"loot": baron_rules.loot(level), "defeats_needed": baron_rules.defeats_needed(level),
			"rebuild_time": baron_rules.rebuild_time(level),
			"march_time": baron_rules.march_time(level * 37.5),
		})
	for k in 4:
		data.camp_attacks.append(camp_run(k))
	for k in 60:
		data.dailies.append(dailies_case())
	for k in 300:
		var level := rng.randi_range(1, 40)
		var seed_value := rng.randi_range(0, 2_000_000_000)
		data.drops.append({"level": level, "seed": seed_value, "item": gear.roll_drop(level, seed_value)})
	data.armoury = armoury_run()
	data.outpost = outpost_run()
	for s in ["baron_0", "baron_7", "baron_29", "", "Ölberg", "a long camp id"]:
		data.hashes[s] = hash(s)
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", false, true))
	file.close()
	print("wrote %s" % OUT)
	quit()


func castle_run(run: int) -> Dictionary:
	## A castle given random orders over a few days of game time.
	var castle := CastleState.create_new(rules, "c%d" % run, "Castle %d" % run, "player", T0)
	var t := T0
	var steps: Array = []
	var types := ["woodcutter", "quarry", "farm", "house", "barracks", "storehouse", "keep", "wall", "workshop"]
	var tool_ids := rules.tools.keys()
	var units := rules.units.keys()
	for i in 220:
		var step := {}
		var roll := rng.randi() % 100
		if roll < 25:
			t += float(rng.randi_range(1, 5400))
			castle.advance_to(t)
			step = {"op": "advance", "t": t}
		elif roll < 40:
			var type: String = types[rng.randi() % types.size()]
			var cell := [rng.randi_range(-1, rules.grid_size), rng.randi_range(-1, rules.grid_size)]
			var ok := castle.place(type, Vector2i(cell[0], cell[1]), t)
			step = {"op": "place", "t": t, "type": type, "cell": cell, "result": ok}
		elif roll < 55:
			var id := rng.randi_range(1, castle._next_id)
			step = {"op": "upgrade", "t": t, "id": id, "result": castle.upgrade(id, t)}
		elif roll < 60:
			var id := rng.randi_range(1, castle._next_id)
			step = {"op": "cancel", "t": t, "id": id, "result": castle.cancel(id, t)}
		elif roll < 70:
			var unit: String = units[rng.randi() % units.size()]
			var amount := rng.randi_range(0, 30)
			step = {"op": "recruit", "t": t, "unit": unit, "amount": amount, "result": castle.recruit(unit, amount, t)}
		elif roll < 75:
			var tool: String = tool_ids[rng.randi() % tool_ids.size()]
			var amount := rng.randi_range(0, 12)
			step = {"op": "craft", "t": t, "tool": tool, "amount": amount, "result": castle.craft(tool, amount, t)}
		elif roll < 77:
			var index := rng.randi_range(-1, 3)
			step = {"op": "cancel_training", "t": t, "index": index, "result": castle.cancel_training(index, t)}
		elif roll < 79:
			var index := rng.randi_range(-1, 3)
			step = {"op": "cancel_crafting", "t": t, "index": index, "result": castle.cancel_crafting(index, t)}
		elif roll < 82:
			var id := rng.randi_range(1, castle._next_id)
			var cell := [rng.randi_range(0, rules.grid_size), rng.randi_range(0, rules.grid_size)]
			step = {"op": "move", "id": id, "cell": cell, "result": castle.move(id, Vector2i(cell[0], cell[1]))}
		elif roll < 86:
			# A windfall, so the castle can afford big things now and then.
			var r: String = rules.resources[rng.randi() % rules.resources.size()]
			var amount := float(rng.randi_range(100, 3000))
			castle.resources[r] += amount
			step = {"op": "grant", "resource": r, "amount": amount}
		elif roll < 90:
			# Quests: the day's tasks, then a claim that may or may not be allowed.
			var kind: String = ["story", "daily", "daily", "daily", "chest"][rng.randi() % 5]
			var index := rng.randi_range(-1, 2)
			step = {"op": "quest", "t": t, "kind": kind, "index": index, "result": quest_book.claim(castle, kind, index, t)}
		elif roll < 91:
			# Defence tools on the walls, often more than the castle has.
			var gift: String = tool_ids[rng.randi() % tool_ids.size()]
			var n := rng.randi_range(0, 6)
			castle.tools[gift] = int(castle.tools.get(gift, 0)) + n
			var posted := random_tools(rng.randi_range(0, 4), "defence")
			step = {"op": "set_tools", "gift": gift, "n": n, "tools": posted, "result": castle.set_defence_tools(posted)}
			if rng.randi() % 3 == 0 and step.result == "":
				var lost := random_tools(2)
				castle.lose_defence_tools(lost)
				step["lost"] = lost
		elif roll < 92:
			# Battles fought elsewhere, so the barons and loot tasks move.
			var barons := rng.randi_range(0, 3)
			var looted := float(rng.randi_range(0, 4000))
			castle.stats.barons += barons
			castle.stats.looted += looted
			step = {"op": "stats", "barons": barons, "looted": looted}
		elif roll < 94:
			# Soldiers from elsewhere, sometimes more than the farms can feed.
			var unit: String = units[rng.randi() % units.size()]
			var amount := rng.randi_range(5, 400)
			var to_field := rng.randi() % 3 == 0
			var group: Dictionary = castle.field if to_field else castle.troops
			group[unit] = int(group.get(unit, 0)) + amount
			step = {"op": "soldiers", "unit": unit, "amount": amount, "field": to_field}
		else:
			step = {"op": "checks", "t": t, "build": {}, "upgrade": {}, "recruit": {}}
			for type: String in types:
				step.build[type] = castle.check_build(type)
			for b in castle.buildings:
				step.upgrade[str(b.id)] = castle.check_upgrade(b.id)
			for unit: String in units:
				step.recruit[unit] = castle.check_recruit(unit, 10)
			step["craft"] = {}
			for tool: String in tool_ids:
				step.craft[tool] = castle.check_craft(tool, 10)
			step["story"] = quest_book.progress(castle, quest_book.current_story(castle).goal) \
				if not quest_book.current_story(castle).is_empty() else []
			step["daily"] = []
			for k in castle.quests.picks.size():
				step.daily.append(quest_book.daily_progress(castle, k))
			step["coffer"] = quest_book.coffer_reward(int(castle.quests.keep), quest_book.coffer_streak(castle))
			step["goals"] = quest_book.story.map(func(g: Dictionary) -> Array: return quest_book.progress(castle, g.goal))
		step["state"] = castle.to_dict()
		steps.append(step)
	return {"id": castle.id, "name": castle.castle_name, "t0": T0, "steps": steps}


func dailies_case() -> Dictionary:
	## Which daily tasks a castle gets on some day, with and without a barracks.
	var name: String = ["Your Castle", "Bob's Castle", "Ölberg's Castle", "x"][rng.randi() % 4] + str(rng.randi() % 50)
	var castle := CastleState.create_new(rules, "c", name, "player", T0)
	var day := rng.randi_range(0, 40000)
	var out := {"name": name, "day": day, "none": quest_book.pick_dailies(castle, day)}
	castle.buildings.append({"id": 99, "type": "barracks", "level": 1, "cell": Vector2i(0, 0), "target": 0, "finish": 0.0})
	out["barracks"] = quest_book.pick_dailies(castle, day)
	return out


func random_army(max_each: int) -> Dictionary:
	var army := {}
	for unit: String in rules.units:
		if rng.randi() % 3 != 0:
			army[unit] = rng.randi_range(0, max_each)
	return army


func battle_case() -> Dictionary:
	var a := random_army(rng.randi_range(1, 300))
	var b := random_army(rng.randi_range(1, 300))
	var seed_value := rng.randi_range(0, 2_000_000_000)
	var wall := 1.0 if rng.randi() % 2 == 0 else Battle.wall_from_defense(rng.randf_range(0.0, 900.0))
	return {"a": a, "b": b, "seed": seed_value, "wall": wall, "result": Battle.fight(rules, a, b, seed_value, wall),
			"odds": Battle.odds(rules, a, b, seed_value, wall)}


func random_tools(max_each: int, side := "") -> Dictionary:
	## Tools (of one side, or any) on random walls (the checks sort out which are allowed).
	var out := {}
	for w: String in Battle.WALLS:
		if rng.randi() % 2 == 0:
			var group := {}
			for tool: String in rules.tools:
				if (side == "" or rules.tool_side(tool) == side) and rng.randi() % 2 == 0:
					group[tool] = rng.randi_range(0, max_each)
			out[w] = group
	return out


func siege_case() -> Dictionary:
	## Random waves against a random layout, sometimes with empty walls.
	var waves: Array = []
	for k in rng.randi_range(1, 3):
		var wave := {}
		for w: String in Battle.WALLS:
			if rng.randi() % 4 != 0:
				wave[w] = random_army(rng.randi_range(0, 120))
		waves.append(wave)
	var layout := {"left": 0, "front": 0, "right": 0, "courtyard": 0}
	var left := 100
	for key: String in ["left", "right", "courtyard"]:
		layout[key] = rng.randi_range(0, left)
		left -= layout[key]
	layout["front"] = left
	if rng.randi() % 3 == 0:
		layout = Battle.DEFAULT_LAYOUT
	var defenders := random_army(rng.randi_range(0, 250))
	var seed_value := rng.randi_range(0, 2_000_000_000)
	var wall := Battle.wall_from_defense(rng.randf_range(0.0, 900.0))
	var army := random_army(rng.randi_range(1, 300))
	var tools := {}
	if rng.randi() % 2 == 0:
		tools = {"a": random_tools(8), "b": random_tools(8)}
	if rng.randi() % 2 == 0:
		tools["lead_a"] = random_fx("attack")
		tools["lead_b"] = random_fx("defence")
	var stock := {}
	for tool: String in rules.tools:
		stock[tool] = rng.randi_range(0, 10)
	var checks := {}
	for side: String in ["attack", "defence"]:
		var slots := rng.randi_range(0, 12)
		checks[side] = {"slots": slots, "result": Battle.check_tools(rules, tools.get("a", {}), side, slots, stock)}
	return {"waves": waves, "layout": layout, "defenders": defenders, "seed": seed_value, "wall": wall, "tools": tools,
			"stock": stock, "checks": checks,
			"result": Battle.siege(rules, waves, defenders, layout, seed_value, wall, tools),
			"odds": Battle.siege_odds(rules, waves, defenders, layout, seed_value, wall, tools),
			"army": army, "auto": Battle.auto_waves(army),
			"split": Battle.split(defenders, layout, ["left", "right", "courtyard", "front"])}


func camp_run(k: int) -> Dictionary:
	## One camp attacked again and again with growing armies.
	var camp := BaronCamp.create("baron_%d" % k, "Camp %d" % k, Vector2(100, 200), 1 + k * 3)
	var start := camp.to_dict()
	var t := T0
	var attacks: Array = []
	for i in 25:
		t += float(rng.randi_range(0, 900))
		var army := random_army(rng.randi_range(5, 40 + i * 25))
		var seed_value := rng.randi_range(0, 100000)
		if not camp.is_ready(t):
			attacks.append({"t": t, "army": army, "seed": seed_value, "ready": false, "camp": camp.to_dict()})
			continue
		var lead := random_fx("attack") if rng.randi() % 2 == 0 else {}
		var result := camp.attack(baron_rules, rules, army, seed_value, t, [], {}, lead)
		attacks.append({"t": t, "army": army, "seed": seed_value, "ready": true, "lead": lead, "result": result, "camp": camp.to_dict()})
	return {"start": start, "attacks": attacks}


func random_fx(side: String) -> Dictionary:
	## What a commander's or castellan's gear might add: some of a side's stats.
	var out := {}
	for stat: String in gear.stats:
		if gear.stats[stat].side == side and rng.randi() % 2 == 0:
			out[stat] = rng.randi_range(0, 60) / 100.0
	return out


func armoury_run() -> Dictionary:
	## A castle's commanders and gear through random drops, equips, sales and xp.
	var castle := CastleState.create_new(rules, "g", "Gear Castle", "player", T0)
	for b in castle.buildings:
		if b.type == "keep":
			b.level = 5
	gear.sync(castle)
	castle.armoury.commanders[1].away_until = T0 + 100.0
	var drops: Array = []
	for k in 45:
		var item := gear.roll_drop(rng.randi_range(1, 40), rng.randi_range(0, 2_000_000_000))
		drops.append(item.duplicate(true))
		if not item.is_empty():
			gear.give(castle, item)
	var whos: Array = [1, 2, 3, 4, "castellan", "nobody"]
	var ops: Array = []
	for k in 120:
		var who: Variant = whos[rng.randi() % whos.size()]
		var t := T0 + rng.randi_range(0, 200)
		var op := {"t": t, "who": who}
		match rng.randi() % 4:
			0, 1:
				op["kind"] = "equip"
				op["item"] = rng.randi_range(0, int(castle.armoury.next_item))
				op["result"] = gear.equip(castle, who, op.item, t)
			2:
				op["kind"] = "unequip"
				op["slot"] = gear.slots[rng.randi() % gear.slots.size()] if rng.randi() % 5 != 0 else "boots"
				op["result"] = gear.unequip(castle, who, op.slot, t)
			3:
				if rng.randi() % 3 == 0:
					op["kind"] = "sell"
					op["item"] = rng.randi_range(0, int(castle.armoury.next_item))
					op["result"] = gear.sell(castle, op.item)
				else:
					op["kind"] = "xp"
					op["id"] = rng.randi_range(0, 4)
					op["xp"] = rng.randi_range(0, 60)
					op["result"] = gear.add_xp(castle, op.id, op.xp)
		ops.append(op)
	var fx: Array = []
	for c: Dictionary in castle.armoury.commanders:
		fx.append(gear.commander_effects(c))
	var leads: Array = []
	for id in [0, 1, 2, 3, 9]:
		var lead: Variant = gear.check_lead(castle, id, T0 + 50.0)
		leads.append(lead if lead != null else "none")
	return {"drops": drops, "ops": ops, "castle": castle.to_dict(), "fx": fx, "castellan": gear.castellan_effects(castle),
			"leads": leads, "levels": range(0, 320, 7).map(func(x: int) -> int: return gear.level_for(x))}


func outpost_run() -> Dictionary:
	## A main castle founding an outpost, random orders for the outpost (some of
	## them things an outpost can't do), and carts between the two castles.
	var main := CastleState.create_new(rules, "c", "Main Castle", "player", T0)
	var t := T0
	var checks := {"too_low": outposts.check_found(main, false, "wood", [1.0, 1.0])}
	for b in main.buildings:
		if b.type == "keep":
			b.level = outposts.keep_needed
	checks["poor"] = outposts.check_found(main, false, "wood", [1.0, 1.0])
	for r: String in main.resources:
		main.resources[r] = 9000.0
	checks["has"] = outposts.check_found(main, true, "wood", [1.0, 1.0])
	checks["region"] = outposts.check_found(main, false, "silk", [1.0, 1.0])
	checks["spot"] = outposts.check_found(main, false, "stone", null)
	checks["ok"] = outposts.check_found(main, false, "stone", [1.0, 1.0])
	var outpost := outposts.found(main, "stone", t)
	var types := ["woodcutter", "quarry", "farm", "house", "barracks", "storehouse", "keep", "wall", "workshop"]
	var steps: Array = []
	var carts: Array = []
	var next_cart := 1
	for i in 160:
		var step := {}
		var roll := rng.randi() % 100
		if roll < 25:
			t += float(rng.randi_range(1, 5400))
			carts = OutpostRules.deliver_carts(main, outpost, carts, t)
			main.advance_to(t)
			outpost.advance_to(t)
			step = {"op": "advance", "t": t}
		elif roll < 45:
			var type: String = types[rng.randi() % types.size()]
			var cell := [rng.randi_range(0, rules.grid_size - 1), rng.randi_range(0, rules.grid_size - 1)]
			step = {"op": "place", "t": t, "type": type, "cell": cell, "result": outpost.place(type, Vector2i(cell[0], cell[1]), t)}
		elif roll < 60:
			var id := rng.randi_range(1, outpost._next_id)
			step = {"op": "upgrade", "t": t, "id": id, "result": outpost.upgrade(id, t)}
		elif roll < 65:
			var r: String = rules.resources[rng.randi() % rules.resources.size()]
			var amount := float(rng.randi_range(500, 5000))
			outpost.resources[r] += amount
			step = {"op": "grant", "resource": r, "amount": amount}
		elif roll < 85:
			var home := rng.randi() % 2 == 0
			var from := main if home else outpost
			var load := {}
			for r: String in rules.resources:
				if rng.randi() % 2 == 0:
					load[r] = rng.randi_range(0, 900)
			if rng.randi() % 10 == 0:
				load["silk"] = 5
			var result := outposts.check_carts(from, load)
			step = {"op": "carts", "t": t, "home": home, "load": load, "result": result, "cap": outposts.cart_capacity(from)}
			if result == "":
				for r: String in load:
					from.resources[r] = float(from.resources[r]) - float(load[r])
				var travel := float(rng.randi_range(60, 4000))
				carts.append({"id": next_cart, "to": "outpost" if home else "home", "resources": load, "depart": t, "arrive": t + travel})
				next_cart += 1
				step["travel"] = travel
		else:
			step = {"op": "checks", "build": {}, "upgrade": {}}
			for type: String in types:
				step.build[type] = outpost.check_build(type)
			for b in outpost.buildings:
				step.upgrade[str(b.id)] = outpost.check_upgrade(b.id)
		step["main"] = main.to_dict()
		step["outpost"] = outpost.to_dict()
		step["carts"] = carts.duplicate(true)
		steps.append(step)
	var spots := []
	for k in 30:
		spots.append([float(rng.randi_range(0, 40)) * 50.0, float(rng.randi_range(0, 40)) * 50.0])
	var nearest := []
	for k in 10:
		var home: Array = spots[rng.randi() % spots.size()]
		var taken := []
		for j in rng.randi_range(0, 8):
			taken.append(spots[rng.randi() % spots.size()])
		var taken_v := taken.map(func(s: Array) -> Vector2: return Vector2(s[0], s[1]))
		nearest.append({"home": home, "taken": taken, "spot": OutpostRules.nearest_spot(spots, Vector2(home[0], home[1]), taken_v)})
	return {"t0": T0, "checks": checks, "region": "stone", "steps": steps, "spots": spots, "nearest": nearest}
