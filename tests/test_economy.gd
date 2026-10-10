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


func test_new_castle() -> void:
	var c := fresh()
	check(c.keep_level() == 1, "starts with a level 1 keep")
	near(c.resources.wood, 400.0, "starting wood")
	near(c.storage_capacity(), 1000.0, "keep storage at level 1")
	near(c.production_per_hour().wood, 40.0, "woodcutter level 1 output")
	near(c.production_per_hour().food, 45.0, "farm level 1 output")
	near(c.production_per_hour().stone, 0.0, "no quarry yet")
	check(c.free_builders() == 1, "one builder at keep level 1")
	near(c.defense(), 100.0, "wall level 1 defence")


func test_production_and_cap() -> void:
	var c := fresh()
	c.advance_to(T0 + 3600.0)
	near(c.resources.wood, 440.0, "one hour of wood")
	near(c.resources.food, 345.0, "one hour of food")
	c.advance_to(T0 + 3600.0 * 100.0)
	near(c.resources.wood, 1000.0, "wood stops at the storage cap")
	# Time never runs backwards.
	c.advance_to(T0)
	near(c.resources.wood, 1000.0, "advancing to the past changes nothing")


func test_construction() -> void:
	var c := fresh()
	var id := c.place("quarry", Vector2i(4, 15), T0)
	check(id > 0, "quarry placed")
	near(c.resources.wood, 400.0 - 70.0, "quarry cost wood")
	near(c.resources.stone, 400.0 - 20.0, "quarry cost stone")
	check(c.check_place("house", Vector2i(8, 18)) == "All builders are busy", "second build blocked while the only builder works")
	check(c.place("house", Vector2i(8, 18), T0) == -1, "second build refused")
	near(c.production_per_hour().stone, 0.0, "quarry produces nothing while being built")
	# 25 s to build, then one hour of production.
	c.advance_to(T0 + 25.0 + 3600.0)
	check(c.get_building(id).level == 1, "quarry finished")
	near(c.resources.stone, 380.0 + 32.0, "stone produced from the moment the quarry finished")
	check(c.free_builders() == 1, "builder free again")


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
	near(c.resources.wood, 400.0 - 80.0 + 60.0, "75% of the wood back")
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
	near(c.storage_capacity(), keep_cap + 800.0, "storehouse adds capacity")
	var stone_expected := minf(900.0 - 20.0 - 80.0 + 32.0 * (10.0 * 3600.0 - 25.0) / 3600.0, c.storage_capacity())
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
	check(NpcBrain.think(c, T0) == 1, "an NPC puts its one builder to work")
	check(c.free_builders() == 0, "and the builder is busy")
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
	near(c.resources.food, 300.0 - 55.0, "food goes down while the stores last")
	check(c.troops.spearman == 100, "nobody deserts while there is food")
	c.resources.food = 0.0
	c.advance_to(T0 + 7200.0)
	check(c.troops.spearman == 45, "an hour without food: soldiers leave until the farms can feed the rest (%d left)" % c.troops.spearman)
	c.advance_to(T0 + 3.0 * 3600.0)
	check(c.troops.spearman == 45, "and then the garrison is stable")


func _first(c: CastleState, type: String) -> int:
	for b in c.buildings:
		if b.type == type:
			return b.id
	return -1
