extends SceneTree
## Tests for the castle economy. Run from the project folder:
##   godot --headless --path . --script res://tests/test_economy.gd
## Prints each failed check and exits with code 1 if any failed.

var failures := 0
var checks := 0
var rules: BuildingRules
const T0 := 1_000_000.0


func _initialize() -> void:
	rules = BuildingRules.load_default()
	test_new_castle()
	test_production_and_cap()
	test_construction()
	test_keep_limits()
	test_cancel_refund()
	test_placement()
	test_offline_catch_up_in_order()
	test_save_round_trip()
	test_npc_brain()
	test_recruitment()
	test_upkeep_and_desertion()
	test_warband()
	test_battle()
	test_siege()
	test_siege_waves()
	test_capture()
	test_save_slots()
	test_diplomacy()
	test_diplomacy_ai()
	test_baron_rules()
	test_baron_camp()
	test_baron_placer()
	test_marches()
	test_march_waves()
	test_set_layout()
	test_quests()
	test_tools()
	test_gear()
	test_outpost()
	print("%d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func near(a: float, b: float, what: String, tolerance := 0.01) -> void:
	check(absf(a - b) <= tolerance, "%s: expected %s, got %s" % [what, b, a])


func fresh() -> CastleState:
	return CastleState.create_new(rules, "test", "Test", "player", T0)


func start(r: String) -> float:
	## What a new castle starts with of a resource (data/buildings.json).
	return float(rules.start.resources[r])


func test_new_castle() -> void:
	var c := fresh()
	check(c.keep_level() == 1, "starts with a level 1 keep")
	near(c.resources.wood, start("wood"), "starting wood")
	near(c.storage_capacity(), float(rules.types.keep.storage), "keep storage at level 1")
	near(c.production_per_hour().wood, 40.0, "woodcutter level 1 output")
	near(c.production_per_hour().food, 45.0, "farm level 1 output")
	near(c.production_per_hour().stone, 0.0, "no quarry yet")
	check(c.free_builders() == rules.builders(1), "the keep's builders at level 1")
	near(c.defense(), 100.0, "wall level 1 defence")


func test_production_and_cap() -> void:
	var c := fresh()
	c.advance_to(T0 + 3600.0)
	near(c.resources.wood, start("wood") + 40.0, "one hour of wood")
	near(c.resources.food, start("food") + 45.0, "one hour of food")
	c.advance_to(T0 + 3600.0 * 100.0)
	near(c.resources.wood, c.storage_capacity(), "wood stops at the storage cap")
	# Time never runs backwards.
	c.advance_to(T0)
	near(c.resources.wood, c.storage_capacity(), "advancing to the past changes nothing")


func test_construction() -> void:
	var c := fresh()
	var id := c.place("quarry", Vector2i(4, 15), T0)
	check(id > 0, "quarry placed")
	near(c.resources.wood, start("wood") - 70.0, "quarry cost wood")
	near(c.resources.stone, start("stone") - 20.0, "quarry cost stone")
	for k in rules.builders(1) - 1:
		check(c.place("farm", Vector2i(18, 3 * k), T0) > 0, "every other builder put to work")
	check(c.check_place("house", Vector2i(8, 18)) == "All builders are busy", "another build blocked while every builder works")
	check(c.place("house", Vector2i(8, 18), T0) == -1, "another build refused")
	near(c.production_per_hour().stone, 0.0, "quarry produces nothing while being built")
	# Build time, then one hour of production.
	var built := rules.build_time("quarry", 1)
	c.advance_to(T0 + built + 3600.0)
	check(c.get_building(id).level == 1, "quarry finished")
	near(c.resources.stone, start("stone") - 20.0 - 20.0 * (rules.builders(1) - 1) + 32.0, "stone produced from the moment the quarry finished")
	check(c.free_builders() == rules.builders(1), "builders free again")


func test_keep_limits() -> void:
	var c := fresh()
	c.resources = {"wood": 1000.0, "stone": 1000.0, "food": 1000.0, "gold": 1000.0}
	var wc := _first(c, "woodcutter")
	check(c.upgrade(wc, T0), "woodcutter to level 2")
	c.advance_to(T0 + 1000.0)
	check(c.get_building(wc).level == 2, "woodcutter reached level 2")
	check(c.check_upgrade(wc) == "Upgrade the keep first", "level 3 needs keep level 2")
	check(rules.max_count("woodcutter", 1) == 2, "two woodcutters at keep level 1")
	check(c.place("woodcutter", Vector2i(0, 20), T0 + 1000.0) > 0, "second woodcutter allowed")
	c.advance_to(T0 + 2000.0)
	check(c.check_place("woodcutter", Vector2i(20, 20)) == "Upgrade the keep to build more of these", "third woodcutter needs a bigger keep")
	check(c.check_place("keep", Vector2i(20, 20)) == "The castle already has one", "only one keep")
	check(c.check_place("wall", Vector2i(0, 0)) != "", "the wall can't be placed on the grid")


func test_cancel_refund() -> void:
	var c := fresh()
	var id := c.place("house", Vector2i(18, 18), T0)
	check(c.cancel(id, T0), "house cancelled")
	check(c.get_building(id).is_empty(), "a cancelled new building disappears")
	near(c.resources.wood, start("wood") - 80.0 + 60.0, "75% of the wood back")
	var wc := _first(c, "woodcutter")
	c.upgrade(wc, T0)
	c.cancel(wc, T0)
	check(c.get_building(wc).level == 1, "a cancelled upgrade keeps the old level")


func test_placement() -> void:
	var c := fresh()
	check(not c.fits("farm", Vector2i(11, 11)), "can't overlap the keep")
	check(not c.fits("farm", Vector2i(22, 22)), "can't stick out of the grid")
	check(c.fits("farm", Vector2i(18, 0)), "free corner fits a farm")
	var farm := _first(c, "farm")
	check(c.move(farm, Vector2i(18, 0)), "farm moved")
	check(c.get_building(farm).cell == Vector2i(18, 0), "farm at its new spot")
	check(not c.move(farm, Vector2i(10, 10)), "can't move onto the keep")
	check(c.check_build("house") == "", "a house can be started")
	check(c.check_place("house", Vector2i(11, 11)) == "There's no room there", "but not on top of the keep")
	c.resources.wood = 0.0
	check(c.check_build("house") == "Not enough resources", "the build menu knows when you can't afford it")


func test_offline_catch_up_in_order() -> void:
	# Two builders at keep level 3; a quarry and a storehouse finish at
	# different times while "offline", and production follows each step.
	var c := fresh()
	c.get_building(_first(c, "keep")).level = 3
	c.resources = {"wood": 900.0, "stone": 900.0, "food": 0.0, "gold": 0.0}
	var q := c.place("quarry", Vector2i(4, 15), T0)
	var s := c.place("storehouse", Vector2i(18, 18), T0)
	check(q > 0 and s > 0, "two builds at once with two builders")
	var keep_cap := rules.storage("keep", 3)
	c.advance_to(T0 + 10.0 * 3600.0)
	check(c.get_building(q).level == 1 and c.get_building(s).level == 1, "both finished offline")
	near(c.storage_capacity(), keep_cap + rules.storage("storehouse", 1), "storehouse adds capacity")
	var stone_expected := minf(900.0 - 20.0 - 80.0 + 32.0 * (10.0 * 3600.0 - rules.build_time("quarry", 1)) / 3600.0, c.storage_capacity())
	near(c.resources.stone, stone_expected, "stone over ten offline hours", 0.05)


func test_save_round_trip() -> void:
	var c := fresh()
	c.place("quarry", Vector2i(4, 15), T0)
	c.advance_to(T0 + 10.0)
	var copy := CastleState.from_dict(rules, JSON.parse_string(JSON.stringify(c.to_dict(), "", true, true)))
	check(var_to_str(copy.to_dict()) == var_to_str(c.to_dict()), "save and load give the same castle")
	copy.advance_to(T0 + 4000.0)
	c.advance_to(T0 + 4000.0)
	near(copy.resources.stone, c.resources.stone, "loaded castle keeps running the same way")
	check(copy.place("house", Vector2i(18, 18), T0 + 4000.0) > 0 and copy.get_building(copy.buildings[-1].id).type == "house", "new ids keep working after loading")


func test_npc_brain() -> void:
	var c := CastleState.create_new(rules, "npc", "NPC", "aldmere", T0)
	c.resources = {"wood": 0.0, "stone": 0.0, "food": 0.0, "gold": 0.0}
	check(NpcBrain.think(c, T0) == 0, "an NPC with no resources builds nothing")
	c = CastleState.create_new(rules, "npc", "NPC", "aldmere", T0)
	check(NpcBrain.think(c, T0) == rules.builders(1), "an NPC puts its builders to work")
	check(c.free_builders() == 0, "and every builder is busy")
	NpcBrain.catch_up(c, T0 + 3.0 * 86400.0)
	check(c.keep_level() >= 2, "three days in, the NPC has upgraded its keep (level %d)" % c.keep_level())
	check(c.buildings.size() > 6, "and put up more buildings (%d)" % c.buildings.size())
	var overlaps := false
	var negative := false
	for b in c.buildings:
		if b.cell.x >= 0 and not c.fits(b.type, b.cell, b.id):
			overlaps = true
	for r: String in c.resources:
		if c.resources[r] < -0.001:
			negative = true
	print("NPC after 3 days: keep %d, %s" % [c.keep_level(), ", ".join(c.buildings.map(func(b): return "%s %d" % [b.type, b.level]))])
	print("NPC garrison: %s, food %+d/h" % [c.troops, int(c.net_per_hour().food)])
	check(c.barracks_level() >= 1, "the NPC has built a barracks")
	check(c.troop_count() > 0, "and trained soldiers (%d)" % c.troop_count())
	check(c.net_per_hour().food >= 0.0, "without starving them")
	check(not overlaps, "NPC buildings don't overlap")
	check(not negative, "NPC never spends more than it has")
	var twin := CastleState.create_new(rules, "npc", "NPC", "aldmere", T0)
	NpcBrain.think(twin, T0)
	NpcBrain.catch_up(twin, T0 + 3.0 * 86400.0)
	check(var_to_str(twin.to_dict()) == var_to_str(c.to_dict()), "NPC decisions are repeatable")


func with_barracks() -> CastleState:
	var c := fresh()
	c.place("barracks", Vector2i(18, 18), T0)
	c.advance_to(T0 + 60.0)
	c.resources = {"wood": 1000.0, "stone": 1000.0, "food": 1000.0, "gold": 1000.0}
	c.last_update = T0 + 60.0
	return c


func test_recruitment() -> void:
	var c := fresh()
	check(c.check_recruit("spearman", 5) == "Build a barracks first", "no training without a barracks")
	c = with_barracks()
	var t := T0 + 60.0
	check(c.barracks_level() == 1, "barracks built")
	check(c.check_recruit("archer", 1) == "Needs barracks level 2", "archers need a better barracks")
	check(c.check_recruit("spearman", 0) != "", "can't train zero soldiers")
	check(c.recruit("spearman", 5, t), "five spearmen queued")
	near(c.resources.gold, 1000.0 - 60.0, "spearmen paid in gold up front")
	near(c.resources.food, 1000.0 - 50.0, "and in food")
	c.advance_to(t + 50.0)
	check(c.troops.get("spearman", 0) == 2, "two of five trained after 50 s (20 s each)")
	check(c.recruit("spearman", 2, t + 50.0), "a second batch queues behind the first")
	near(c.training_left(t + 50.0), 10.0 + 2 * 20.0 + 2 * 20.0, "time left covers the whole queue")
	c.advance_to(t + 140.0)
	check(c.troops.spearman == 7 and c.training.is_empty(), "both batches trained in order")
	check(c.recruit("spearman", 10, t + 140.0), "ten more queued")
	var gold: float = c.resources.gold
	check(c.cancel_training(0, t + 140.0), "batch cancelled")
	near(c.resources.gold, gold + 10 * 12 * 0.75, "75% of the gold back")
	check(c.training.is_empty(), "queue empty after cancelling")
	for i in c.rules.queue_size:
		c.recruit("spearman", 1, t + 140.0)
	check(c.check_recruit("spearman", 1) == "The training queue is full", "the queue has a limit")
	c.get_building(_first(c, "barracks")).level = 3
	near(c.rules.unit_time("spearman", 3), 17.0, "a level 3 barracks trains faster")
	var copy := CastleState.from_dict(rules, JSON.parse_string(JSON.stringify(c.to_dict(), "", true, true)))
	check(var_to_str(copy.to_dict()) == var_to_str(c.to_dict()), "troops and the training queue survive saving")


func test_upkeep_and_desertion() -> void:
	var c := fresh()
	c.troops = {"spearman": 100}
	near(c.net_per_hour().food, 45.0 - 100.0, "100 spearmen eat 100 food an hour")
	c.advance_to(T0 + 3600.0)
	near(c.resources.food, start("food") - 55.0, "food goes down while the stores last")
	check(c.troops.spearman == 100, "nobody deserts while there is food")
	c.resources.food = 0.0
	c.advance_to(T0 + 7200.0)
	check(c.troops.spearman == 45, "an hour without food: soldiers leave until the farms can feed the rest (%d left)" % c.troops.spearman)
	c.advance_to(T0 + 3.0 * 3600.0)
	check(c.troops.spearman == 45, "and then the garrison is stable")


func test_warband() -> void:
	var c := fresh()
	c.troops = {"spearman": 30, "archer": 5}
	check(c.send_to_field("spearman", 10) == 10, "ten spearmen join the warband")
	check(c.send_to_field("archer", 50) == 5, "you can't send more than the garrison has")
	check(c.troop_count() == 20 and c.field_count() == 15, "garrison 20, warband 15")
	check(c.return_from_field("spearman", 4) == 4 and c.troops.spearman == 24, "four spearmen come home")
	near(c.upkeep_per_hour(), 35.0, "the castle feeds its warband too")
	var copy := CastleState.from_dict(rules, JSON.parse_string(JSON.stringify(c.to_dict(), "", true, true)))
	check(copy.field_count() == c.field_count(), "the warband survives saving")
	# Starving: the biggest eater deserts first, garrison or warband alike.
	c.resources.food = 0.0
	c.troops = {"spearman": 10}
	c.field = {"spearman": 90}
	c.advance_to(T0 + 3600.0)
	check(c.troop_count() + c.field_count() == 45 and c.field_count() < 90, "hungry warband soldiers desert too (%d + %d left)" % [c.troop_count(), c.field_count()])
	# A lord at home tops up the warband but leaves half the garrison.
	var npc := fresh()
	npc.troops = {"spearman": 100, "swordsman": 20}
	var joined := NpcBrain.resupply(npc)
	check(joined == 60, "a lord takes up to 60 soldiers at keep level 1 (%d)" % joined)
	check(npc.field.get("swordsman", 0) == 20, "the best soldiers go first")
	check(npc.troop_count() == 60, "and half the garrison stays")


func test_battle() -> void:
	var even := 0
	for k in 40:
		if Battle.fight(rules, {"spearman": 50}, {"spearman": 50}, k).winner == "a":
			even += 1
	check(even > 8 and even < 32, "equal armies win about half the time (%d of 40)" % even)
	var r: Dictionary = Battle.fight(rules, {"spearman": 80}, {"spearman": 40}, 3)
	check(r.winner == "a", "twice the soldiers win")
	check(r.a.spearman.lost < r.b.spearman.lost, "and lose fewer")
	check(r.b.spearman.start - r.b.spearman.lost <= int(40 * Battle.ROUT) + 1, "the loser flees at %d%% strength" % int(Battle.ROUT * 100))
	var again: Dictionary = Battle.fight(rules, {"spearman": 80}, {"spearman": 40}, 3)
	check(JSON.stringify(again) == JSON.stringify(r), "the same seed gives the same battle")
	# Spearmen beat horsemen that would beat the same number of archers.
	near(Battle.odds(rules, {"spearman": 40}, {"horseman": 20}), 1.0, "spearmen hold against half as many horsemen", 0.15)
	near(Battle.odds(rules, {"archer": 40}, {"horseman": 20}), 0.0, "horsemen ride down twice as many archers", 0.15)
	check(Battle.odds(rules, {}, {"spearman": 1}) == 0.0, "no soldiers, no chance")
	# Resolving moves the survivors back into each warband and pays the plunder.
	var a := fresh()
	var b := fresh()
	a.field = {"spearman": 60, "archer": 20}
	b.field = {"spearman": 30}
	var gold: float = a.resources.gold
	var res: Dictionary = Battle.resolve(a, b, 11)
	check(res.winner == "a", "the bigger warband wins")
	check(a.field_count() == 80 - Battle.lost_count(res.a), "the winner keeps its survivors")
	check(b.field_count() == 30 - Battle.lost_count(res.b), "the loser keeps the soldiers who fled")
	near(a.resources.gold, gold + Battle.lost_count(res.b) * Battle.LOOT_PER_KILL, "plunder for every fallen enemy")
	check(res.loot == int(Battle.lost_count(res.b) * Battle.LOOT_PER_KILL), "the report shows the plunder")


func test_siege() -> void:
	var castle := fresh()
	near(Battle.wall_bonus(castle), 1.0 + 1.5 * 100.0 / 300.0, "a level 1 wall adds half its defence again")
	near(Battle.siege_time(castle), 45.0, "a siege of a level 1 wall takes 45 s")
	var even := Battle.odds(rules, {"spearman": 50}, {"spearman": 50})
	var walled := Battle.odds(rules, {"spearman": 50}, {"spearman": 50}, 1, Battle.wall_bonus(castle))
	check(walled < even - 0.2, "walls help the defenders (%.2f in the open, %.2f against walls)" % [even, walled])
	# A strong warband takes an NPC castle...
	var lord := fresh()
	lord.field = {"swordsman": 80}
	castle.id = "npc_castle"
	castle.owner = "varnholt"
	castle.troops = {"spearman": 30}
	var r: Dictionary = Battle.assault(lord, castle, 5)
	check(r.outcome == "captured", "a castle that falls is captured (%s)" % r.outcome)
	check(castle.troop_count() == 30 - Battle.lost_count(r.b), "the garrison keeps whoever survived")
	check(lord.field_count() == 80 - Battle.lost_count(r.a), "the warband keeps its survivors")
	# ...but the player's main castle can only be sacked.
	var home := fresh()
	home.id = "player_castle"
	home.troops = {"spearman": 10}
	var stone: float = home.resources.stone
	lord.resources.stone = 0.0
	var s: Dictionary = Battle.assault(lord, home, 6)
	check(s.outcome == "sacked", "your main castle is sacked, not captured")
	near(home.resources.stone, stone * (1.0 - Battle.SACK_SHARE), "sacking carries off part of the stock")
	near(lord.resources.stone, stone * Battle.SACK_SHARE, "into the attacker's castle")
	check(s.spoils.stone == int(stone * Battle.SACK_SHARE), "the report lists the spoils")
	# A weak warband breaks on the walls.
	var raider := fresh()
	raider.field = {"spearman": 20}
	var keep := fresh()
	keep.id = "npc_castle"
	keep.troops = {"spearman": 20}
	check(Battle.assault(raider, keep, 7).outcome == "held", "an even fight against walls is lost")


func test_siege_waves() -> void:
	# Spreading soldiers: rounded down, the last key gets the rest.
	var parts := Battle.split({"spearman": 10, "archer": 1}, Battle.DEFAULT_LAYOUT, ["left", "right", "courtyard", "front"])
	check(parts.left == {"spearman": 2} and parts.right == {"spearman": 2} and parts.courtyard == {"spearman": 1}
			and parts.front == {"spearman": 5, "archer": 1}, "layout split")
	check(Battle.auto_waves({"spearman": 10}) == [{"left": {"spearman": 3}, "right": {"spearman": 3}, "front": {"spearman": 4}}], "auto waves")
	check(Battle.waves_for_keep(1) == 1 and Battle.waves_for_keep(2) == 2 and Battle.waves_for_keep(3) == 2
			and Battle.waves_for_keep(5) == 3, "waves by keep")
	check(Battle.check_layout(Battle.DEFAULT_LAYOUT) == "", "default layout is valid")
	check(Battle.check_layout({"left": 50, "front": 50, "right": 0, "courtyard": 10}) != "", "layout must add up to 100")
	check(Battle.check_layout({"left": 50, "front": 50}) != "", "layout needs every post")
	# Nobody on the left wall: the attackers walk in, and nobody in the courtyard either.
	var open_left := {"left": 0, "front": 100, "right": 0, "courtyard": 0}
	var r := Battle.siege(rules, [{"left": {"spearman": 5}}], {"spearman": 50}, open_left, 1, 2.0)
	check(r.winner == "a" and r.walls.left.broken and r.courtyard.get("open", false), "an empty wall and courtyard fall at once")
	check(r.a.spearman.lost == 0 and r.b.spearman.lost == 0, "nobody fell")
	# A wall that holds sends its attackers home; the other walls' defenders never fight.
	r = Battle.siege(rules, [{"front": {"spearman": 5}}], {"spearman": 100}, Battle.DEFAULT_LAYOUT, 3, 2.0)
	check(r.winner == "b" and not r.walls.front.broken and r.courtyard.is_empty(), "the front held")
	check(r.walls.left.fights.is_empty() and r.b.spearman.lost < 35, "only the front fought")
	# A big wave breaks the front, the next wave walks through it.
	r = Battle.siege(rules, [{"front": {"swordsman": 200}}, {"front": {"archer": 20}}], {"spearman": 60}, Battle.DEFAULT_LAYOUT, 5, 1.5)
	check(r.walls.front.broken and r.walls.front.fights.size() == 2 and r.walls.front.fights[1].get("open", false), "second wave walks through")
	check(r.winner == "a" and r.courtyard.has("winner"), "won in the courtyard")
	check(r.a.archer.lost == 0 and r.waves == 2, "the second wave lost nobody at the wall")
	var start := 0
	for u: String in r.b:
		start += r.b[u].start
	check(start == 60, "every defender counted once")
	# A camp attack is a siege, and the odds use the same rules.
	var chance := Battle.siege_odds(rules, Battle.auto_waves({"swordsman": 300}), {"spearman": 20}, Battle.DEFAULT_LAYOUT, 1, 1.5)
	check(chance == 1.0, "a crushing army always wins")
	check(Battle.siege_odds(rules, [{}], {"spearman": 20}, Battle.DEFAULT_LAYOUT) == 0.0, "no soldiers, no chance")
	# Waves sent with an attack, and the castle's own layout (saved with it).
	check(Battle.check_waves([{"left": {"spearman": 3}}], 1, rules) == "", "one wave is fine")
	check(Battle.check_waves([{}, {}], 1, rules) != "", "the keep limits the waves")
	check(Battle.check_waves([{"middle": {"spearman": 3}}], 2, rules) != "", "only the three walls")
	check(Battle.waves_army([{"left": {"spearman": 3}}, {"left": {"spearman": 2}, "front": {"archer": 1}}]) == {"spearman": 5, "archer": 1}, "waves army")
	var c := fresh()
	check(c.layout == Battle.DEFAULT_LAYOUT, "castles start with the default layout")
	c.layout = {"left": 10, "front": 60, "right": 10, "courtyard": 20}
	check(CastleState.from_dict(rules, c.to_dict()).layout == c.layout, "the layout is saved")
	var old := c.to_dict()
	old.erase("layout")
	check(CastleState.from_dict(rules, old).layout == Battle.DEFAULT_LAYOUT, "old saves get the default layout")


func test_capture() -> void:
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"   # sync_castles saves; keep real saves out of it
	eco.rules = rules
	eco.player_castle = CastleState.create_new(rules, "player_castle", "Mine", "player", T0)
	var north := CastleState.create_new(rules, "north", "North", "varnholt", T0)
	var south := CastleState.create_new(rules, "south", "South", "varnholt", T0)
	var far := CastleState.create_new(rules, "far", "Far", "varnholt", T0)
	eco.castles = [eco.player_castle, north, south, far] as Array[CastleState]
	var settlements: Array = [
		{"id": "player_castle", "type": "castle", "faction": "aldmere", "player": true, "position": [0, 0], "name": "Mine"},
		{"id": "north", "type": "castle", "faction": "varnholt", "position": [0, 100], "name": "North"},
		{"id": "south", "type": "castle", "faction": "varnholt", "position": [0, 200], "name": "South"},
		{"id": "far", "type": "castle", "faction": "varnholt", "position": [0, 900], "name": "Far"},
	]
	var parties: Array = [
		{"id": "you", "faction": "aldmere", "home": "player_castle", "player": true, "troops": 24},
		{"id": "jarl", "faction": "varnholt", "home": "north", "troops": 30},
	]
	eco.sync_castles(settlements, parties)
	check(north.field.get("spearman", 0) == 30, "the jarl's warband starts at North")
	check(eco.player_castle.field.get("spearman", 0) == 24, "your warband starts with its spearmen too")
	north.troops = {"spearman": 5}
	eco.capture(north, "player", parties, settlements)
	check(north.owner == "player" and not north.is_npc(), "North is now yours")
	check(north.troop_count() == 0 and north.field_count() == 0, "its garrison and warband are gone")
	check(eco.home_of("jarl", "north") == "south", "the jarl falls back to the nearest castle")
	check(south.field.get("spearman", 0) == 30, "and brings the warband along")
	check(settlements[1].faction == "aldmere" and settlements[1].get("player", false), "the map shows North as yours")
	eco.capture(south, "aldmere", parties, settlements)
	check(eco.home_of("jarl", "north") == "far", "next the jarl goes to Far")
	eco.capture(north, "varnholt", parties, settlements)
	check(settlements[1].faction == "varnholt" and not settlements[1].has("player"), "North can be lost again")
	check(eco.home_of("jarl", "north") == "far", "retaking North doesn't move the jarl")
	eco.capture(far, "aldmere", parties, settlements)
	eco.capture(north, "aldmere", parties, settlements)
	check(eco.home_of("jarl", "north") == "", "with no castle left the jarl is gone")
	check(eco.exiled.has("jarl"), "and counted as exiled")
	check(eco.newcomer_protected(), "a new main castle is safe from sieges")
	for b in eco.player_castle.buildings:
		if b.type == "keep":
			b.level = Economy.PROTECTED_BELOW_KEEP
	check(not eco.newcomer_protected(), "until its keep reaches level %d" % Economy.PROTECTED_BELOW_KEEP)
	# With several castles of your own, the main one is still found on loading.
	eco.castles = [north, eco.player_castle, south] as Array[CastleState]
	north.owner = "player"
	check(eco.find_main_castle() == eco.player_castle, "your main castle is the one you started with")
	eco.delete_slot(1)
	eco.free()


func test_save_slots() -> void:
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	for k in range(1, eco.SLOTS + 1):
		eco.delete_slot(k)
	check(not eco.has_save(), "no saves to begin with")
	eco.begin_new(2)
	eco.player_castle.troops = {"spearman": 7}
	eco.player_castle.field = {"archer": 3}
	eco.save_game()
	check(eco.has_save(2) and not eco.has_save(1), "a new game in slot 2 is saved there")
	var info: Dictionary = eco.slot_info(2)
	check(info.keep == 1 and info.castles == 1 and info.soldiers == 10, "slot 2 summary: %s" % info)
	check(eco.slot_info(1).is_empty(), "an empty slot has no summary")
	eco.begin_new(3)
	check(eco.last_played_slot() == 3, "Continue picks the slot saved last")
	eco.begin_load(2)
	check(eco.player_castle.troop_count() == 7, "loading slot 2 brings its garrison back")
	eco.delete_slot(3)
	check(not eco.has_save(3) and eco.last_played_slot() == 2, "a deleted slot is empty again")
	eco.delete_slot(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()

func test_diplomacy() -> void:
	var ids := ["aldmere", "varnholt", "ashkar", "corvane"]
	var d := Diplomacy.create_new(ids, [["aldmere", "varnholt"]], "aldmere", T0)
	check(d.at_war("varnholt", "aldmere") and not d.at_war("aldmere", "ashkar"), "starting wars come from the data")
	near(d.relation("aldmere", "varnholt"), Diplomacy.START_AT_WAR, "factions at war start out hostile")
	d.change_relation("aldmere", "ashkar", 500.0)
	near(d.relation("ashkar", "aldmere"), 100.0, "relations stop at 100")
	# Declaring war.
	var before := d.relation("aldmere", "corvane")
	check(d.declare_war("aldmere", "ashkar", T0) == "", "you can declare war on a faction at peace")
	check(d.at_war("aldmere", "ashkar"), "and then you are at war")
	check(d.relation("aldmere", "ashkar") <= -50.0, "declaring war ruins relations")
	near(d.relation("aldmere", "corvane"), before - Diplomacy.WARMONGER, "others think less of a warmonger")
	check(d.declare_war("aldmere", "ashkar", T0) != "", "you can't declare the same war twice")
	check(d.news.back().text == "You declared war on Ashkar.", "war makes the news: %s" % d.news.back().text)
	# War score.
	d.record_battle("ashkar", "aldmere", 40)
	near(d.war_score("ashkar", "aldmere"), Diplomacy.SCORE_BATTLE + 4.0, "a won battle counts for the winner")
	near(d.war_score("aldmere", "ashkar"), -(Diplomacy.SCORE_BATTLE + 4.0), "and against the loser")
	d.record_siege("aldmere", "ashkar", "captured")
	near(d.war_score("aldmere", "ashkar"), Diplomacy.SCORE_CAPTURE - 9.0, "taking a castle counts most")
	d.record_battle("corvane", "ashkar", 10)
	check(not d.wars.has(Diplomacy.key("corvane", "ashkar")), "battles outside a war change nothing")
	# Peace terms: winning factions refuse, losing ones accept, others want gold.
	d.record_siege("aldmere", "ashkar", "captured")
	d.record_siege("aldmere", "ashkar", "captured")
	var terms: Dictionary = d.peace_terms("aldmere", "ashkar", T0 + 60.0)
	check(terms.possible and terms.price == 0, "a faction losing badly accepts peace for nothing: %s" % terms)
	terms = d.peace_terms("ashkar", "aldmere", T0)
	terms = d.peace_terms("aldmere", "varnholt", T0)
	check(terms.possible and terms.price > 0, "an even war needs gold: %s" % terms)
	check(not d.propose_peace("aldmere", "varnholt", terms.price - 1, T0), "too little gold is refused")
	check(d.propose_peace("aldmere", "varnholt", terms.price, T0), "enough gold buys peace")
	check(not d.at_war("aldmere", "varnholt"), "peace ends the war")
	check(d.truce_left("aldmere", "varnholt", T0) > 0.0, "and starts a truce")
	check(d.declare_war("varnholt", "aldmere", T0 + 60.0) != "", "no war during a truce")
	check(d.declare_war("varnholt", "aldmere", T0 + Diplomacy.TRUCE + 1.0) == "", "war is possible after the truce")
	d.record_siege("varnholt", "aldmere", "captured")
	d.record_siege("varnholt", "aldmere", "captured")
	terms = d.peace_terms("aldmere", "varnholt", T0 + Diplomacy.TRUCE + 2.0)
	check(not terms.possible, "a faction that is winning won't hear of peace")
	# Gifts buy goodwill, less per coin for big gifts, and only so much.
	var g1 := d.give_gift("aldmere", "corvane", 100, T0)
	var g2 := d.gift_value("aldmere", "corvane", 1000, T0 + 1.0)
	check(g1 > 5.0 and g1 < 8.0, "a 100 gold gift is worth a little (%.1f)" % g1)
	check(g2 < 10.0 * g1, "ten times the gold buys less than ten times the goodwill")
	for i in 10:
		d.give_gift("aldmere", "corvane", 1000, T0 + 2.0)
	near(d.gift_value("aldmere", "corvane", 1000, T0 + 3.0), 0.0, "gifts stop helping for a while")
	check(d.gift_value("aldmere", "corvane", 1000, T0 + Diplomacy.GIFT_WINDOW + 3.0) > 0.0, "and work again later")
	# Saving.
	var copy := Diplomacy.from_dict(JSON.parse_string(JSON.stringify(d.to_dict())), T0)
	check(copy.at_war("aldmere", "varnholt") and copy.at_war("aldmere", "ashkar"), "wars are saved")
	near(copy.relation("aldmere", "corvane"), d.relation("aldmere", "corvane"), "relations are saved")
	near(copy.war_score("varnholt", "aldmere"), d.war_score("varnholt", "aldmere"), "war scores are saved")
	check(copy.truce_left("aldmere", "varnholt", T0) == d.truce_left("aldmere", "varnholt", T0), "truces are saved")
	check(copy.news.size() == d.news.size(), "and the news")
	check(copy.player_faction == "aldmere", "you rule Aldmere")


func test_diplomacy_ai() -> void:
	var ids := ["aldmere", "varnholt", "ashkar", "thornwald", "corvane"]
	var d := Diplomacy.create_new(ids, [["ashkar", "thornwald"], ["thornwald", "corvane"]], "aldmere", T0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var power := {"aldmere": 500.0, "varnholt": 500.0, "ashkar": 600.0, "thornwald": 400.0, "corvane": 500.0}
	d.record_siege("ashkar", "thornwald", "captured")
	d.record_siege("ashkar", "thornwald", "captured")
	var t := T0
	var wars_seen := {}
	var peace_seen := false
	var most_wars := 0
	for i in 400:   # 200 minutes of half-minute rounds
		t += 30.0
		for k in d.wars:
			wars_seen[k] = true
		for text: String in d.think(t, rng, power):
			if text.contains("made peace"):
				peace_seen = true
		for f in ids:
			most_wars = maxi(most_wars, d.enemies_of(f).size())
	check(most_wars <= Diplomacy.MAX_WARS + 1, "no faction fights everyone at once (%d wars)" % most_wars)
	check(peace_seen, "AI factions make peace")
	check(wars_seen.size() > 2, "and start new wars (%d wars seen)" % wars_seen.size())
	var in_range := true
	for k: String in d.relations:
		in_range = in_range and d.relations[k] >= -100.0 and d.relations[k] <= 100.0
	check(in_range, "relations stay between -100 and 100")
	# A faction losing to you offers peace; you are never made to declare war.
	var e := Diplomacy.create_new(ids, [["aldmere", "varnholt"]], "aldmere", T0)
	for i in 4:
		e.record_battle("aldmere", "varnholt", 50)
	var offered := false
	t = T0
	for i in 100:
		t += 30.0
		e.think(t, rng, power, true)
		offered = offered or e.offers.has("varnholt")
	check(offered, "Varnholt, losing, offers you peace")
	check(e.at_war("aldmere", "varnholt"), "but peace with you is never made without you")
	var declared_by_you := false
	for item: Dictionary in e.news:
		declared_by_you = declared_by_you or item.text.begins_with("You declared")
	check(not declared_by_you, "and you are never made to declare war")
	check(e.enemies_of("aldmere").size() == 1, "newcomer protection keeps new wars off you")
	var terms: Dictionary = e.peace_terms("aldmere", "varnholt", t)
	check(not e.offers.has("varnholt") or terms.price == 0, "an offer of peace costs nothing to accept")


func test_baron_rules() -> void:
	var br := BaronRules.load_default()
	var g1 := br.garrison(1)
	var g10 := br.garrison(10)
	var n1 := 0
	var n10 := 0
	for u in g1:
		n1 += g1[u]
	for u in g10:
		n10 += g10[u]
	check(n1 == 14, "a level 1 camp holds 14 soldiers (%s)" % g1)
	check(n10 > 3 * n1, "a level 10 camp holds far more (%d)" % n10)
	check(g1.keys().all(func(u: String) -> bool: return rules.units.has(u)), "garrisons use real units")
	check(not g1.has("horseman") and g10.has("horseman"), "horsemen join the garrison at higher levels")
	check(br.loot(5).gold > br.loot(1).gold and br.palisade(5) > br.palisade(1), "loot and palisade grow with level")
	check(br.defeats_needed(1) == 1 and br.defeats_needed(12) == 2 and br.defeats_needed(25) == 3, "higher levels need more wins")
	check(br.rebuild_time(10) > br.rebuild_time(1), "big camps take longer to rebuild")
	near(br.carry({"spearman": 10, "archer": 5}), 15 * br.carry_per_soldier, "every soldier carries loot")


func test_baron_camp() -> void:
	var br := BaronRules.load_default()
	var camp := BaronCamp.create("camp_1", "Black Hollow", Vector2(100, 200))
	check(camp.is_ready(T0), "a new camp can be attacked")
	var weak := {"spearman": 4}
	var r := camp.attack(br, rules, weak, 1, T0)
	check(r.winner == "b" and r.loot.is_empty(), "too few soldiers are beaten off")
	check(camp.level == 1 and camp.is_ready(T0), "a camp that holds keeps its level and stays open")
	var army := {"spearman": 24, "archer": 10}
	r = camp.attack(br, rules, army, 2, T0)
	check(r.winner == "a", "a decent army beats a level 1 camp")
	check(r.leveled and camp.level == 2, "and the camp rises to level 2")
	var carried := 0
	for res in r.loot:
		carried += r.loot[res]
	check(carried > 0 and carried <= br.carry(r.survivors), "the winners carry off what they can (%d)" % carried)
	check(not camp.is_ready(T0 + 10.0), "a beaten camp needs time to rebuild")
	check(camp.is_ready(T0 + br.rebuild_time(1)), "and can be attacked again once rebuilt")
	# Levelling up all the way, the camp grows tougher and richer.
	var big := {"swordsman": 400, "archer": 200, "horseman": 100}
	var t := T0
	var loot_at := {}
	while camp.level < 12:
		t += 10000.0
		var before := camp.level
		r = camp.attack(br, rules, big, camp.level, t)
		check(r.winner == "a", "a big army wins at level %d" % before)
		if r.leveled:
			loot_at[before] = r.loot.gold
	check(loot_at.get(11, 0) > loot_at.get(2, 0), "higher camps pay more (%s)" % loot_at)
	camp.defeats = 1
	var copy := BaronCamp.from_dict(JSON.parse_string(JSON.stringify(camp.to_dict())))
	check(copy.level == camp.level and copy.defeats == 1 and copy.position == camp.position, "a camp saves and loads")
	near(copy.rebuilt_at, camp.rebuilt_at, "including its rebuild time")
	check(not copy.is_invader() and not copy.to_dict().has("event"), "an ordinary camp isn't an invader")
	var invader := BaronCamp.from_dict({"id": "invader_1", "name": "Raiders' Camp", "position": [5, 6], "level": 3,
			"event": 1792000000.0, "points": 10})
	var invader_copy := BaronCamp.from_dict(JSON.parse_string(JSON.stringify(invader.to_dict())))
	check(invader_copy.is_invader() and invader_copy.points == 10 and invader_copy.event == 1792000000.0,
			"an invader camp keeps its invasion and points")
	# Economy keeps each camp's level in the save slot.
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	eco.sync_barons([{"id": "camp_1", "name": "Black Hollow", "position": [100, 200]}])
	eco.get_baron("camp_1").level = 7
	eco.save_game()
	eco.begin_load(1)
	check(eco.get_baron("camp_1") != null and eco.get_baron("camp_1").level == 7, "camp levels are saved with the game")
	eco.sync_barons([{"id": "camp_1", "name": "Black Hollow", "position": [100, 200]}])
	check(eco.barons.size() == 1 and eco.get_baron("camp_1").level == 7, "syncing again keeps the level")
	eco.delete_slot(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()


func test_baron_placer() -> void:
	var br := BaronRules.load_default()
	var water := func(x: float, z: float) -> bool: return x > 300.0   # west strip is sea
	var towns: Array = [{"position": [1000, 1000]}, {"position": [500, 1500]}]
	var home := Vector2(1100, 1000)
	var camps := BaronPlacer.place(br, water, towns, home, 2048.0)
	check(camps.size() == int(br.camps.count), "every camp finds a spot (%d)" % camps.size())
	var ok := true
	var names := {}
	var nearest_level := 99
	var nearest_d := 1e9
	for c: Dictionary in camps:
		var p := Vector2(c.position[0], c.position[1])
		ok = ok and p.x > 300.0
		for t: Dictionary in towns:
			ok = ok and p.distance_to(Vector2(t.position[0], t.position[1])) >= float(br.camps.settlement_gap)
		names[c.name] = true
		if p.distance_to(home) < nearest_d:
			nearest_d = p.distance_to(home)
			nearest_level = c.level
	check(ok, "camps stand on dry land away from settlements")
	check(names.size() == camps.size(), "every camp has its own name")
	check(nearest_level == 1, "the camp nearest your castle starts at level 1")
	check(camps.any(func(c: Dictionary) -> bool: return c.level >= 5), "far camps start higher")
	var again := BaronPlacer.place(br, water, towns, home, 2048.0)
	check(again == camps, "the same seed gives the same camps")


func test_marches() -> void:
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	eco.castle_positions[eco.MAIN_CASTLE] = Vector2(0, 0)
	eco.sync_barons([{"id": "near", "name": "Near", "position": [60, 0]},
			{"id": "far", "name": "Far", "position": [600, 0], "level": 9}])
	eco.player_castle.troops = {"spearman": 30, "archer": 10}
	check(eco.check_attack("near", {"spearman": 50}) != "", "you can't send more soldiers than you have")
	check(eco.check_attack("near", {}) != "", "or nobody")
	var reports: Array = []
	eco.attack_resolved.connect(func(r: Dictionary) -> void: reports.append(r))
	var army := {"spearman": 25, "archer": 10}
	check(eco.send_attack("near", army) == "", "an army sets out")
	check(eco.player_castle.troops.spearman == 5 and eco.player_castle.troops.archer == 0, "and leaves the garrison")
	check(eco.troops_away() == 35, "35 soldiers are on the road")
	var m: Dictionary = eco.marches[0]
	near(m.arrive - m.depart, 10.0, "a short march takes the minimum time")
	near(m.back - m.depart, 20.0, "and as long again to come home")
	eco.advance_marches(m.depart + 5.0)
	check(reports.is_empty(), "nothing happens on the way")
	eco.advance_marches(m.arrive + 1.0)
	check(reports.size() == 1 and reports[0].winner == "a", "the army beats the camp on arrival")
	check(reports[0].leveled and eco.get_baron("near").level == 2, "and the camp levels up")
	check(m.state == "home", "then the army heads home")
	var wood_before: float = eco.player_castle.resources.wood
	var loot: Dictionary = m.loot
	var survivors := 0
	for u in m.survivors:
		survivors += m.survivors[u]
	eco.advance_marches(m.back + 1.0)
	check(eco.marches.is_empty(), "and arrives")
	check(eco.player_castle.troop_count() == 5 + survivors, "the survivors rejoin the garrison")
	near(eco.player_castle.resources.wood, minf(eco.player_castle.storage_capacity(), wood_before + loot.wood), "the loot goes into storage")
	check(eco.check_attack("near", {"spearman": 1}) != "", "the beaten camp is rebuilding")
	check(int(eco.player_castle.stats.barons) == 1, "the quests count the beaten baron")
	var looted := 0.0
	for r in loot:
		looted += loot[r]
	near(eco.player_castle.stats.looted, looted, "and the loot brought home")
	# A whole trip while the game was closed resolves on loading.
	eco.player_castle.troops = {"spearman": 300}
	check(eco.send_attack("far", {"spearman": 300}) == "", "a big army sets out for a far camp")
	var trip: Dictionary = eco.marches[0]
	near(trip.arrive - trip.depart, 100.0, "600 map units take 100 seconds at speed 6")
	trip.depart -= 1000.0
	trip.arrive -= 1000.0
	trip.back -= 1000.0
	eco.save_game()
	reports.clear()
	eco.begin_load(1)
	check(eco.marches.is_empty() and reports.size() == 1, "a trip that ended while away is settled on loading")
	check(eco.player_castle.troop_count() > 0 and eco.player_castle.troop_count() <= 300, "and the army is home")
	eco.delete_slot(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()


func test_march_waves() -> void:
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	eco.castle_positions[eco.MAIN_CASTLE] = Vector2(0, 0)
	eco.sync_barons([{"id": "near", "name": "Near", "position": [60, 0]}])
	eco.player_castle.troops = {"spearman": 30, "archer": 10}
	check(eco.max_waves() == 1, "a level 1 keep sends one wave")
	var two := [{"left": {"spearman": 5}}, {"front": {"spearman": 5}}]
	check(eco.send_attack("near", {}, two) == "Upgrade your keep to send more than one wave.", "not two")
	check(eco.send_attack("near", {}, [{"left": {"spearman": 40}}]) != "", "nor more soldiers than the garrison holds")
	check(eco.send_attack("near", {}, [{"moat": {"spearman": 5}}]) == "Bad waves.", "nor at a wall that isn't there")
	var reports: Array = []
	eco.attack_resolved.connect(func(r: Dictionary) -> void: reports.append(r))
	var waves := [{"left": {"spearman": 25, "archer": 10}}]
	check(eco.send_attack("near", {}, waves) == "", "one wave at the left wall sets out")
	var m: Dictionary = eco.marches[0]
	check(m.army == {"spearman": 25, "archer": 10} and m.waves == waves, "the march keeps the army and its waves")
	check(eco.player_castle.troops.spearman == 5, "and the soldiers leave the garrison")
	eco.save_game()
	eco.begin_load(1)
	check(eco.marches.size() == 1 and eco.marches[0].waves.size() == 1, "the waves are saved")
	eco.advance_marches(float(eco.marches[0].arrive) + 1.0)
	check(reports.size() == 1, "the army fights on arrival")
	var walls: Dictionary = reports[0].walls
	check(walls.left.fights.size() == 1 and walls.front.fights.is_empty() and walls.right.fights.is_empty(),
			"only the left wall is stormed")
	var panel: GDScript = load("res://scripts/ui/attack_panel.gd")
	var spread: Array = panel.spread({"spearman": 10, "archer": 3}, 3, Battle.ATTACK_SPLIT)
	check(spread.size() == 3 and Battle.waves_army(spread) == {"spearman": 10, "archer": 3}, "Auto spreads every soldier over the waves")
	var report: GDScript = load("res://scripts/ui/battle_report.gd")
	check(report.wall_result({"broken": false, "fights": []}) == "Not attacked", "an unattacked wall")
	check(report.wall_result({"broken": true, "fights": [{"wave": 0, "winner": "b"}, {"wave": 1, "winner": "a"}]}) == "Broken in wave 2",
			"a wall broken by the second wave")
	check(report.wall_result({"broken": true, "fights": [{"wave": 0, "open": true}]}) == "Undefended", "an empty wall")
	check(report.courtyard_result({}, true) == "Not reached" and report.courtyard_result({"winner": "b"}, false) == "Held",
			"the courtyard, seen from either side")
	eco.delete_slot(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()


func test_set_layout() -> void:
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	check(eco.player_castle.layout == Battle.DEFAULT_LAYOUT, "a new castle uses the default layout")
	check(eco.set_layout(eco.player_castle, {"left": 50, "front": 40, "right": 20, "courtyard": 20}) != "", "a layout must add up to 100%")
	check(eco.set_layout(eco.player_castle, {"left": 10, "front": 60.0, "right": 10, "courtyard": 20}) == "", "a good layout is set")
	check(eco.player_castle.layout == {"left": 10, "front": 60, "right": 10, "courtyard": 20}, "as whole numbers")
	eco.begin_load(1)
	check(eco.player_castle.layout.front == 60, "and saved")
	eco.delete_slot(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()


func _first(c: CastleState, type: String) -> int:
	for b in c.buildings:
		if b.type == type:
			return b.id
	return -1


func test_quests() -> void:
	var book := QuestBook.load_default()
	check(book.story.size() == 30 and book.chapters.size() == 5, "30 story quests in 5 chapters")
	for q: Dictionary in book.story:
		var g: Dictionary = q.goal
		if g.kind == "building":
			check(rules.has_type(g.type) and int(g.level) <= rules.max_level(g.type, 5), "%s can be done" % q.title)
	var day0 := 20000 * QuestBook.DAY
	var c := CastleState.create_new(rules, "q", "Valentin's Castle", "player", day0)
	# Lifetime stats: soldiers trained and resources spent, less refunds.
	c.buildings.append({"id": 99, "type": "barracks", "level": 1, "cell": Vector2i(0, 0), "target": 0, "finish": 0.0})
	c.recruit("spearman", 5, day0)
	near(c.stats.spent, 110.0, "5 spearmen cost 110")
	c.cancel_training(0, day0 + 1)
	near(c.stats.spent, 27.5, "cancelling gives 75% back")
	c.recruit("spearman", 3, day0 + 2)
	c.advance_to(day0 + 3600)
	check(int(c.stats.trained) == 3, "3 soldiers trained")
	var saved := CastleState.from_dict(rules, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(saved.stats == c.stats, "stats are saved")
	var old := c.to_dict()
	old.erase("stats")
	old.erase("quests")
	check(CastleState.from_dict(rules, old).quests.story == 0, "old saves start the quests from the beginning")
	# The story, in order.
	var fresh_castle := fresh()
	check(book.claim(fresh_castle, "story", 0, day0) == "That quest isn't done yet.", "the first quest wants a level 2 woodcutter")
	for b in fresh_castle.buildings:
		if b.type == "woodcutter":
			b.level = 2
	fresh_castle.resources.wood = fresh_castle.storage_capacity()
	check(book.claim(fresh_castle, "story", 0, day0) == "", "then it can be claimed")
	near(fresh_castle.resources.wood, fresh_castle.storage_capacity() + 150.0, "with its reward in full, past the cap")
	check(int(fresh_castle.quests.story) == 1, "and the next quest begins")
	# Daily tasks: a new set each day, counted from the start of the day.
	var d := fresh()
	check(book.roll_day(d, day0 + 5) and not book.roll_day(d, day0 + QuestBook.DAY - 1), "one set of tasks a day")
	check(d.quests.picks.size() == 2 and not d.quests.picks.has("trained"), "no soldier tasks without a barracks")
	var spent: int = d.quests.picks.find("spent")
	d.stats.spent += 1499.5
	check(book.claim(d, "daily", spent, day0 + 10) == "That task isn't done yet.", "1499.5 of 1500 isn't enough")
	d.stats.spent += 0.5
	var gold: float = d.resources.gold
	check(book.claim(d, "daily", spent, day0 + 10) == "", "1500 is")
	near(d.resources.gold, gold + 60.0, "the task's gold")
	check(book.claim(d, "daily", spent, day0 + 10) == "You already have that reward.", "once a day")
	check(book.claim(d, "chest", 0, day0 + 10) == "Finish today's tasks first.", "the coffer waits for every task")
	# The coffer grows with a streak of days, and a missed day starts it over.
	var got := []
	for day in [0, 1, 2, 3, 4, 5, 6, 7, 9]:
		var t: float = day0 + day * QuestBook.DAY
		book.roll_day(d, t)
		for k: String in d.quests.picks:
			if k == "levels":
				for b in d.buildings:
					if b.type == "farm":
						b.level += 10
			else:
				d.stats[k] = d.stats[k] + 1000000
		for i in d.quests.picks.size():
			if not d.quests.claimed.has(i):
				book.claim(d, "daily", i, t)
		var food: float = d.resources.food
		var swords: int = d.troops.get("swordsman", 0)
		check(book.claim(d, "chest", 0, t) == "", "the coffer opens on day %d" % day)
		got.append([roundi(d.resources.food - food), d.troops.get("swordsman", 0) - swords])
	check(got[0] == [150, 0] and got[1] == [188, 0], "the second day in a row gives a quarter more: %s" % [got.slice(0, 2)])
	check(got[6] == [375, 4] and got[7] == [375, 4], "the seventh gives 2.5 times and swordsmen: %s" % [got.slice(6, 8)])
	check(got[8] == [150, 0], "a missed day starts the streak over: %s" % [got[8]])
	# Offline, the economy claims and saves.
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	eco.quest_book.roll_day(eco.player_castle, eco.now())
	check(eco.claim_quest("story") != "", "nothing to claim in a new game")
	for b in eco.player_castle.buildings:
		if b.type == "woodcutter":
			b.level = 2
	check(eco.claim_quest("story") == "", "the economy claims a finished quest")
	check(int(eco.player_castle.quests.story) == 1, "and keeps it")
	eco.free()


func test_tools() -> void:
	# The workshop builds tools one batch after another.
	var c := fresh()
	check(c.check_craft("ladder", 1) == "Build a siege workshop first", "no workshop, no tools")
	c.buildings.append({"id": 98, "type": "workshop", "level": 1, "cell": Vector2i(0, 0), "target": 0, "finish": 0.0})
	check(c.check_craft("ram", 1) == "Needs workshop level 5", "rams need a bigger workshop")
	c.resources.wood = 1000.0
	check(c.craft("ladder", 3, T0), "3 ladders queued")
	near(c.resources.wood, 820.0, "for 60 wood each")
	near(c.stats.spent, 180.0, "and it counts as spending")
	c.advance_to(T0 + 41)
	check(c.tools == {"ladder": 2}, "20 seconds a ladder: %s" % [c.tools])
	var saved := CastleState.from_dict(rules, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(saved.tools == c.tools and saved.crafting.size() == 1, "tools and the queue are saved")
	check(c.cancel_crafting(0, T0 + 42) and c.crafting.is_empty() and c.tools == {"ladder": 2}, "the last ladder is cancelled")
	# What tools do at a wall.
	near(Battle.wall_mods(rules, 2.0, {"ladder": 5}, {}).wall, 1.6, "5 ladders take 40% off the wall bonus")
	near(Battle.wall_mods(rules, 2.0, {}, {"moat": 4}).wall, 2.4, "a moat makes it stronger")
	near(Battle.wall_mods(rules, 1.5, {"mantlet": 20}, {"pitch": 3}).b, 0.5, "mantlets halve the defenders' blows at most")
	near(Battle.wall_mods(rules, 1.5, {}, {"pitch": 3}).a, 0.85, "pitch hurts the attackers")
	var waves := [{"front": {"swordsman": 50}}]
	var bare := Battle.siege_odds(rules, waves, {"spearman": 120}, Battle.DEFAULT_LAYOUT, 1, 2.2)
	var laddered := Battle.siege_odds(rules, waves, {"spearman": 120}, Battle.DEFAULT_LAYOUT, 1, 2.2, {"a": {"front": {"ladder": 8}}})
	check(laddered > bare, "ladders win sieges: %s > %s" % [laddered, bare])
	check(Battle.check_tools(rules, {"left": {"ram": 1}}, "attack", 4, {"ram": 1}) == "Battering ram can't be used at the left wall.",
			"rams only go to the gate")
	check(Battle.check_tools(rules, {"left": {"ladder": 3}, "right": {"ladder": 3}}, "attack", 4, {"ladder": 5})
			== "You don't have that many siege tools.", "no more than in store")
	# Defence tools stand on the walls and fall with them.
	var d := fresh()
	d.tools = {"arrow_slits": 4, "moat": 2}
	var wall: Dictionary = d.buildings.filter(func(x: Dictionary) -> bool: return x.type == "wall")[0]
	wall.level = 0
	check(d.set_defence_tools({"left": {"arrow_slits": 1}}) == "No siege tools fit there yet.", "no wall, no defence tools")
	wall.level = 2
	check(d.set_defence_tools({"left": {"arrow_slits": 5}}) == "Only 4 siege tools fit on each wall.", "4 per wall at wall level 2")
	check(d.set_defence_tools({"left": {"arrow_slits": 4}, "front": {"moat": 2}}) == "", "posted on two walls")
	d.lose_defence_tools({"left": {"arrow_slits": 4}})
	check(d.defence_tools == {"front": {"moat": 2}} and d.tools == {"moat": 2}, "the left wall fell and its arrow slits with it")
	# Offline, attack tools go with the army and are used up.
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	eco.castle_positions[eco.MAIN_CASTLE] = Vector2(0, 0)
	eco.sync_barons([{"id": "near", "name": "Near", "position": [60, 0]}])
	eco.player_castle.troops = {"swordsman": 30}
	eco.player_castle.tools = {"ladder": 3}
	var plan := [{"front": {"swordsman": 30}}]
	check(eco.send_attack("near", {}, plan, {"front": {"ladder": 3}}) == "Only 2 siege tools fit on each wall.", "a level 1 keep brings 2 per wall")
	var reports: Array = []
	eco.attack_resolved.connect(func(r: Dictionary) -> void: reports.append(r))
	check(eco.send_attack("near", {}, plan, {"front": {"ladder": 2}}) == "", "2 ladders go with the army")
	check(eco.player_castle.tools == {"ladder": 1}, "and leave the store")
	eco.advance_marches(float(eco.marches[0].arrive) + 1.0)
	check(reports.size() == 1 and reports[0].tools.a == {"front": {"ladder": 2}}, "the report shows the ladders")
	var panel: GDScript = load("res://scripts/ui/battle_report.gd")
	check(panel.has_method("tools_line"), "the battle report can show tools")
	eco.delete_slot(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()


func test_gear() -> void:
	var gear := GearRules.load_default()
	var c := fresh()
	gear.sync(c)
	check(c.armoury.commanders.size() == 1 and c.armoury.commanders[0].name == "Sir Edric Vane", "one commander at keep 1")
	for b in c.buildings:
		if b.type == "keep":
			b.level = 5
	gear.sync(c)
	check(c.armoury.commanders.size() == 3, "three at keep 5")
	# Drops: the same seed, the same item; better gear from stronger camps.
	check(gear.roll_drop(12, 4242) == gear.roll_drop(12, 4242), "drops are fixed by their seed")
	var best := {"common": 0, "legendary": 0}
	for level in [1, 40]:
		for k in 400:
			var item := gear.roll_drop(level, k)
			if not item.is_empty() and best.has(item.rarity):
				best[item.rarity] += 1
	check(best.legendary > 0 and best.common > 0, "common and legendary gear both drop: %s" % [best])
	# Wearing gear.
	var helm := {"id": 0, "slot": "helmet", "side": "attack", "rarity": "rare", "name": "Runed Sallet", "stats": {"wall_attack": 9}}
	var flag := {"id": 0, "slot": "banner", "side": "defence", "rarity": "epic", "name": "Keep Banner", "stats": {"wall_bonus": 11}}
	check(gear.give(c, helm) and gear.give(c, flag) and helm.id == 1 and flag.id == 2, "drops get ids in the bag")
	check(gear.equip(c, 1, 2, T0) == "Commanders wear attack gear.", "no defence gear on a commander")
	check(gear.equip(c, 1, 1, T0) == "" and gear.equip(c, "castellan", 2, T0) == "", "worn")
	check(gear.commander_effects(c.armoury.commanders[0]) == {"wall_attack": 0.09}, "the helmet's bonus")
	check(gear.castellan_effects(c) == {"wall_bonus": 0.11}, "the castellan's banner")
	c.armoury.commanders[0].xp = 30
	c.armoury.commanders[0].level = gear.level_for(30)
	near(gear.commander_effects(c.armoury.commanders[0]).wall_attack, 0.15, "level 4 adds 6% to the helmet's 9%")
	var saved := CastleState.from_dict(rules, JSON.parse_string(JSON.stringify(c.to_dict())))
	check(saved.armoury == c.armoury, "the armoury is saved")
	check(gear.unequip(c, 1, "helmet", T0) == "" and gear.sell(c, 1) == "", "taken off and sold")
	near(c.resources.gold, start("gold") + 250.0, "a rare item sells for 250 gold")
	# Offline: a commander leads an attack, earns xp and is away meanwhile.
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	eco.castle_positions[eco.MAIN_CASTLE] = Vector2(0, 0)
	eco.sync_barons([{"id": "near", "name": "Near", "position": [60, 0]}])
	eco.player_castle.troops = {"swordsman": 60}
	var reports: Array = []
	eco.attack_resolved.connect(func(r: Dictionary) -> void: reports.append(r))
	check(eco.send_attack("near", {"swordsman": 30}, [], {}, 9) == "No such commander.", "no such commander")
	check(eco.send_attack("near", {"swordsman": 30}, [], {}, 1) == "", "Sir Edric leads the army")
	check(eco.send_attack("near", {"swordsman": 10}, [], {}, 1) == "Sir Edric Vane is still away with an army.", "and can't lead two")
	eco.advance_marches(float(eco.marches[0].arrive) + 1.0)
	check(reports.size() == 1 and reports[0].lead.xp == 1 and int(eco.player_castle.armoury.commanders[0].xp) == 1,
			"a level 1 camp gives 1 xp: %s" % [reports[0].get("lead")])
	var report: GDScript = load("res://scripts/ui/battle_report.gd")
	check(report.has_method("gear_line"), "the battle report shows commanders and gear")
	eco.delete_slot(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()


func test_outpost() -> void:
	var o := OutpostRules.load_default()
	var main := fresh()
	check(o.check_found(main, false, "wood", [1.0, 1.0]) == "Your keep must reach level %d first." % o.keep_needed, "keep too low")
	for b in main.buildings:
		if b.type == "keep":
			b.level = o.keep_needed
	for r: String in main.resources:
		main.resources[r] = 9000.0
	check(o.check_found(main, false, "silk", [1.0, 1.0]) == "Choose a region for your outpost.", "no such region")
	check(o.check_found(main, false, "wood", null) == "There's no free land for an outpost.", "no spot")
	check(o.check_found(main, false, "wood", [1.0, 1.0]) == "", "can found")
	var post := o.found(main, "wood", T0)
	near(main.resources.wood, 9000.0 - float(o.cost.wood), "paid from the main castle")
	check(post.id == OutpostRules.OUTPOST_ID and post.castle_name == "Timberland", "named after its region")
	check(post.check_build("barracks") == "An outpost can't have one of these", "no barracks")
	check(post.check_build("woodcutter") == "", "woodcutters allowed")
	# The region's bonus: the same woodcutter makes half as much again.
	var plain := fresh()
	for c: CastleState in [plain, post]:
		c.place("woodcutter", Vector2i(2, 2), T0)
		c.advance_to(T0 + 86_400.0)
	check(plain.production_per_hour().wood > 0.0, "a woodcutter makes wood")
	near(post.production_per_hour().wood, plain.production_per_hour().wood * 1.5, "Timberland makes 50% more wood")
	for b in post.buildings:
		if b.type == "keep":
			b.level = o.keep_cap
			check(post.check_upgrade(b.id) == "An outpost's keep can't go higher", "keep capped")
	var saved := CastleState.from_dict(rules, JSON.parse_string(JSON.stringify(post.to_dict())))
	check(saved.boost == post.boost and saved.limits.keep == o.keep_cap, "boost and limits are saved")
	# Carts.
	check(o.check_carts(main, {}) == "Load something onto the carts.", "empty carts")
	check(o.check_carts(main, {"wood": 99999}) == "Not enough resources.", "too much")
	var cap := o.cart_capacity(main)
	check(o.check_carts(main, {"wood": cap + 1}) != "", "over capacity")
	var stock := float(post.resources.stone)
	var carts := [{"id": 1, "to": "outpost", "resources": {"stone": 400}, "depart": T0, "arrive": T0 + 86_400.0 + 100.0}]
	carts = OutpostRules.deliver_carts(main, post, carts, T0 + 86_400.0 + 50.0)
	check(carts.size() == 1, "not there yet")
	carts = OutpostRules.deliver_carts(main, post, carts, T0 + 86_400.0 + 200.0)
	check(carts.is_empty() and post.resources.stone >= stock + 400.0 - 0.01, "the stone arrived")
	check(OutpostRules.nearest_spot([[0, 0], [10, 0], [3, 4], [50, 50]], Vector2(0, 0), [Vector2(3, 4)]) == [10.0, 0.0],
			"the nearest free spot, not home and not taken")
	# The whole thing through the economy, offline, saved and loaded.
	var eco = load("res://scripts/core/economy.gd").new()
	eco.save_dir = "user://test_saves"
	eco.begin_new(1)
	check(eco.check_found_outpost("stone") == "Your keep must reach level %d first." % o.keep_needed, "economy: keep too low")
	for b in eco.player_castle.buildings:
		if b.type == "keep":
			b.level = o.keep_needed
	for r: String in eco.player_castle.resources:
		eco.player_castle.resources[r] = 9000.0
	check(eco.found_outpost("stone") == "", "economy: founded")
	check(eco.outpost_castle() != null and eco.outpost.region == "stone" and eco.check_found_outpost("wood") == "You already have an outpost.",
			"economy: one outpost")
	check(eco.send_carts(false, {"food": 300}) == "" and eco.outpost.carts.size() == 1, "economy: carts sent")
	eco.save_game()
	eco.begin_load(1)
	check(eco.outpost_castle() != null and eco.outpost_castle().boost == {"stone": 0.5} and eco.outpost.carts.size() == 1,
			"economy: the outpost and its carts are saved")
	var food := float(eco.outpost_castle().resources.food)
	eco._deliver_carts(float(eco.outpost.carts[0].arrive) + 1.0)
	check(eco.outpost.carts.is_empty() and eco.outpost_castle().resources.food >= food + 299.0, "economy: carts unload at the outpost")
	eco.delete_slot(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_saves"))
	eco.free()
