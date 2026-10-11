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
var rng := RandomNumberGenerator.new()


func _initialize() -> void:
	rules = BuildingRules.load_default()
	baron_rules = BaronRules.load_default()
	rng.seed = 20261011
	var data := {
		"castles": [],
		"battles": [],
		"barons": [],
		"camp_attacks": [],
		"hashes": {},
	}
	for run in 4:
		data.castles.append(castle_run(run))
	for k in 100:
		data.battles.append(battle_case())
	for level in range(1, baron_rules.max_level + 1):
		data.barons.append({
			"level": level, "garrison": baron_rules.garrison(level), "palisade": baron_rules.palisade(level),
			"loot": baron_rules.loot(level), "defeats_needed": baron_rules.defeats_needed(level),
			"rebuild_time": baron_rules.rebuild_time(level),
			"march_time": baron_rules.march_time(level * 37.5),
		})
	for k in 4:
		data.camp_attacks.append(camp_run(k))
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
	var types := ["woodcutter", "quarry", "farm", "house", "barracks", "storehouse", "keep", "wall"]
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
		elif roll < 75:
			var unit: String = units[rng.randi() % units.size()]
			var amount := rng.randi_range(0, 30)
			step = {"op": "recruit", "t": t, "unit": unit, "amount": amount, "result": castle.recruit(unit, amount, t)}
		elif roll < 79:
			var index := rng.randi_range(-1, 3)
			step = {"op": "cancel_training", "t": t, "index": index, "result": castle.cancel_training(index, t)}
		elif roll < 84:
			var id := rng.randi_range(1, castle._next_id)
			var cell := [rng.randi_range(0, rules.grid_size), rng.randi_range(0, rules.grid_size)]
			step = {"op": "move", "id": id, "cell": cell, "result": castle.move(id, Vector2i(cell[0], cell[1]))}
		elif roll < 88:
			# A windfall, so the castle can afford big things now and then.
			var r: String = rules.resources[rng.randi() % rules.resources.size()]
			var amount := float(rng.randi_range(100, 3000))
			castle.resources[r] += amount
			step = {"op": "grant", "resource": r, "amount": amount}
		elif roll < 92:
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
		step["state"] = castle.to_dict()
		steps.append(step)
	return {"id": castle.id, "name": castle.castle_name, "t0": T0, "steps": steps}


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
		var result := camp.attack(baron_rules, rules, army, seed_value, t)
		attacks.append({"t": t, "army": army, "seed": seed_value, "ready": true, "result": result, "camp": camp.to_dict()})
	return {"start": start, "attacks": attacks}
