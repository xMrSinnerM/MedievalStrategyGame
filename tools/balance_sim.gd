extends SceneTree
## Balance simulator: plays a new castle forward through the game's own rules
## (CastleState, NpcBrain, BaronCamp, Battle) and prints how the game paces
## out. Two players are simulated side by side:
##   builder  builds and trains like an NPC lord (NpcBrain) and never attacks
##   raider   does the same, and sends its garrison against robber baron camps
##            whenever it is home and can win with good odds
## Run:
##   godot --headless --path . --script res://tools/balance_sim.gd -- days=30 out=user://balance.md
## It prints a Markdown report (and writes it to `out` if given).

const STEP := 600.0             ## seconds between decisions
const T0 := 1_000_000.0
const RAID_ODDS := 0.8          ## the raider attacks only with at least these odds
const CAMP_LEVELS := 40         ## camps from level 1 up, one per level
const CAMP_SPACING := 40.0      ## map units between camps of neighbouring levels
const CAMP_NEAR := 80.0         ## distance to the level 1 camp
const REPORT_DAYS := [0.25, 0.5, 1, 2, 3, 5, 7, 10, 14, 21, 30, 45, 60, 90]

var rules: BuildingRules
var baron_rules: BaronRules
var lines: PackedStringArray = []
var checkins := 0               ## times a day the players look at the game (0: every STEP)


func _initialize() -> void:
	rules = BuildingRules.load_default()
	baron_rules = BaronRules.load_default()
	var days := 30.0
	var out := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("days="):
			days = float(arg.trim_prefix("days="))
		elif arg.begins_with("checkins="):
			checkins = int(arg.trim_prefix("checkins="))
		elif arg.begins_with("out="):
			out = arg.trim_prefix("out=")
	_say("# Balance simulation, %d days" % days)
	_say("")
	_say(("Both players start from the standard new castle and decide every %d minutes. " % int(STEP / 60.0) if checkins <= 0 else
			"Both players start from the standard new castle and play %d times a day, spread from 8:00 to 23:00. " % checkins)
			+ "The raider sends its garrison at the camp that pays best (expected loot less the cost of the soldiers it expects to lose) with at least %d%% odds (one camp per level, " % roundi(RAID_ODDS * 100.0)
			+ "level N about %d map units away)." % roundi(CAMP_NEAR + CAMP_SPACING * 9))
	_say("")
	_static_tables()
	var builder := _run(days, false)
	var raider := _run(days, true)
	_milestones(builder, raider)
	_timeline("Builder", builder)
	_timeline("Raider", raider)
	_raids(raider)
	var text := "\n".join(lines)
	print(text)
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(text + "\n")
	quit(0)


# --- Static numbers ----------------------------------------------------------------

func _static_tables() -> void:
	_say("## Keep levels")
	_say("")
	_say("| Keep | Cost (wood/stone/gold) | Build time | Storage | Builders | Other buildings up to |")
	_say("|---|---|---|---|---|---|")
	var max_keep := int(rules.types.keep.get("max_level", 5))
	for lv in range(1, max_keep + 1):
		var c := rules.cost("keep", lv)
		_say("| %d | %s | %s | %d | %d | %d |" % [lv, _res(c), _time(rules.build_time("keep", lv)),
				int(rules.storage("keep", lv)), rules.builders(lv), rules.max_level("woodcutter", lv)])
	_say("")
	_say("## Robber baron camps")
	_say("")
	_say("| Level | Garrison | Palisade | Loot (total) | Defeats to level up | Rebuild |")
	_say("|---|---|---|---|---|---|")
	for lv in [1, 2, 3, 5, 8, 10, 15, 20, 25, 30, 40]:
		var g := baron_rules.garrison(lv)
		var n := 0
		for u: String in g:
			n += int(g[u])
		var loot := baron_rules.loot(lv)
		var total := 0
		for r: String in loot:
			total += int(loot[r])
		_say("| %d | %d | +%d%% | %d | %d | %s |" % [lv, n, roundi((Battle.wall_from_defense(baron_rules.palisade(lv)) - 1.0) * 100.0),
				total, baron_rules.defeats_needed(lv), _time(baron_rules.rebuild_time(lv))])
	_say("")


# --- One player --------------------------------------------------------------------

func _run(days: float, raids: bool) -> Dictionary:
	var c := CastleState.create_new(rules, "sim", "Sim", "player", T0)
	var camps: Array[BaronCamp] = []
	for lv in range(1, CAMP_LEVELS + 1):
		var camp := BaronCamp.create("c%d" % lv, "Camp %d" % lv, Vector2(CAMP_NEAR + CAMP_SPACING * (lv - 1), 0), lv)
		camps.append(camp)
	var march := {}            # the army out, if any: {camp, army, arrive, back, survivors, loot}
	var log: Array = []        # raid results
	var snapshots: Array = []
	var keep_at := {1: 0.0}
	var last_levels := 0
	var done_at := 0.0         # when the last upgrade finished
	var looted := {}
	var produced := {}
	var report_i := 0
	var t := T0
	var end := T0 + days * 86400.0
	var seed := 1
	while t < end:
		var before := c.resources.duplicate()
		var rates := c.production_per_hour()
		t += STEP
		c.advance_to(t)
		for r: String in rates:
			produced[r] = float(produced.get(r, 0.0)) + float(rates[r]) * STEP / 3600.0
		var awake := _awake(t)
		if awake:
			NpcBrain.think(c, t)
		if c.keep_level() not in keep_at:
			keep_at[c.keep_level()] = t - T0
		var levels := 0
		for b in c.buildings:
			levels += int(b.level)
		if levels != last_levels:
			last_levels = levels
			done_at = t - T0
		if raids:
			if not march.is_empty() and t >= float(march.arrive) and not march.has("result"):
				var camp: BaronCamp = march.camp
				seed += 1
				var lv := camp.level
				var result := camp.attack(baron_rules, rules, march.army, seed, float(march.arrive))
				march["result"] = result
				log.append({"t": float(march.arrive) - T0, "level": lv, "won": result.winner == "a",
						"sent": _count(march.army), "lost": _count(march.army) - _count(result.survivors),
						"loot": _sum(result.loot)})
			if not march.is_empty() and t >= float(march.back):
				var result: Dictionary = march.result
				for u: String in result.survivors:
					c.troops[u] = int(c.troops.get(u, 0)) + int(result.survivors[u])
				var cap := c.storage_capacity()
				for r: String in result.loot:
					var have := float(c.resources.get(r, 0.0))
					var added := maxf(0.0, minf(cap, have + float(result.loot[r])) - have)
					c.resources[r] = have + added
					looted[r] = float(looted.get(r, 0.0)) + added
				march = {}
			if awake:
				_train_more(c, t)
			if march.is_empty() and awake:
				march = _pick_raid(c, camps, t)
		while report_i < REPORT_DAYS.size() and t - T0 >= float(REPORT_DAYS[report_i]) * 86400.0:
			snapshots.append(_snapshot(c, float(REPORT_DAYS[report_i]), looted, produced))
			report_i += 1
	return {"castle": c, "keep_at": keep_at, "done_at": done_at, "levels": last_levels, "snapshots": snapshots, "log": log, "looted": looted, "produced": produced}


func _train_more(c: CastleState, t: float) -> void:
	## The raider trains past NpcBrain's garrison cap: the strongest unit it
	## can, from stock above a third of the storage, while the farms can feed
	## them (soldiers may eat up to 70% of the food).
	if c.barracks_level() <= 0 or c.training.size() >= 2:
		return
	var food_left: float = c.production_per_hour().get("food", 0.0) * 0.7 - c.upkeep_per_hour()
	for b in c.training:
		food_left -= b.remaining * rules.unit_upkeep(b.unit)
	var best := ""
	for u: String in rules.units:
		if rules.unit_barracks_level(u) <= c.barracks_level():
			if best == "" or rules.unit_barracks_level(u) > rules.unit_barracks_level(best):
				best = u
	var n := mini(rules.max_batch, int(food_left / rules.unit_upkeep(best)))
	var cost := rules.unit_cost(best)
	for r: String in cost:
		if float(cost[r]) > 0.0:
			n = mini(n, int((float(c.resources.get(r, 0.0)) - c.storage_capacity() / 3.0) / float(cost[r])))
	if n > 0:
		c.recruit(best, n, t)


func _awake(t: float) -> bool:
	## Whether the player looks at the game in the STEP ending at `t`.
	if checkins <= 0:
		return true
	for i in checkins:
		var hour := 8.0 + (15.0 * i / maxf(1.0, checkins - 1.0) if checkins > 1 else 12.0)
		var at := fmod(t - T0, 86400.0)
		var mark := hour * 3600.0
		if at >= mark and at - STEP < mark:
			return true
	return false


func _pick_raid(c: CastleState, camps: Array[BaronCamp], t: float) -> Dictionary:
	## Sends the garrison at the ready camp that pays best: the loot it can
	## expect to carry home (from a few simulated sieges) less what the
	## soldiers it expects to lose cost, if that is positive and the odds are at
	## least RAID_ODDS.
	var army := {}
	for u: String in c.troops:
		if int(c.troops[u]) > 0:
			army[u] = int(c.troops[u])
	if _count(army) < 10:
		return {}
	var best: BaronCamp = null
	var best_value := 0.0
	for camp in camps:
		if not camp.is_ready(t):
			continue
		var g := camp.garrison(baron_rules)
		# Only camps worth the trip and within reach (keeps the simulation quick).
		if _count(g) * 6 < _count(army) and camp.level < camps.size():
			continue
		if _count(army) < _count(g) / 2:
			break
		var wall := Battle.wall_from_defense(baron_rules.palisade(camp.level))
		var wins := 0
		var value := 0.0
		for k in 8:
			var r := Battle.siege(rules, Battle.auto_waves(army), g, Battle.DEFAULT_LAYOUT, 7000 + k, wall)
			var surv := Battle.survivors(r.a)
			if r.winner == "a":
				wins += 1
				value += minf(baron_rules.carry(surv), _sum(baron_rules.loot(camp.level)))
			for u: String in army:
				value -= (int(army[u]) - int(surv.get(u, 0))) * _sum(rules.unit_cost(u))
		value /= 8.0
		if float(wins) / 8.0 >= RAID_ODDS and value > best_value:
			best_value = value
			best = camp
	if best == null:
		return {}
	for u: String in army:
		c.troops[u] = int(c.troops[u]) - int(army[u])
	var travel := baron_rules.march_time(best.position.length())
	return {"camp": best, "army": army, "arrive": t + travel, "back": t + 2.0 * travel}


func _snapshot(c: CastleState, day: float, looted: Dictionary, produced: Dictionary) -> Dictionary:
	var levels := 0
	for b in c.buildings:
		levels += int(b.level)
	return {"day": day, "keep": c.keep_level(), "levels": levels, "buildings": c.buildings.size(),
			"rates": c.net_per_hour(), "storage": c.storage_capacity(), "troops": c.troop_count(),
			"barracks": c.barracks_level(), "wall": _level(c, "wall"), "resources": c.resources.duplicate(),
			"looted": _sum(looted), "produced": _sum(produced)}


# --- Report ------------------------------------------------------------------------

func _milestones(builder: Dictionary, raider: Dictionary) -> void:
	_say("## When each keep level is reached")
	_say("")
	_say("| Keep | Builder | Raider |")
	_say("|---|---|---|")
	var max_keep := int(rules.types.keep.get("max_level", 5))
	for lv in range(2, max_keep + 1):
		_say("| %d | %s | %s |" % [lv, _when(builder.keep_at, lv), _when(raider.keep_at, lv)])
	_say("| Last upgrade | %s (%d levels) | %s (%d levels) |" % [_time(builder.done_at), builder.levels, _time(raider.done_at), raider.levels])
	_say("")


func _timeline(title: String, run: Dictionary) -> void:
	_say("## %s over time" % title)
	_say("")
	_say("| Day | Keep | Building levels | Wood/h | Stone/h | Food/h (net) | Gold/h | Storage | Hours to fill | Soldiers | Barracks | Looted so far | Produced so far |")
	_say("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
	for s: Dictionary in run.snapshots:
		var r: Dictionary = s.rates
		var fastest := maxf(1.0, maxf(maxf(r.get("wood", 0.0), r.get("stone", 0.0)), maxf(r.get("food", 0.0), r.get("gold", 0.0))))
		_say("| %s | %d | %d | %d | %d | %d | %d | %d | %.1f | %d | %d | %d | %d |" % [_day(s.day), s.keep, s.levels,
				roundi(r.get("wood", 0.0)), roundi(r.get("stone", 0.0)), roundi(r.get("food", 0.0)), roundi(r.get("gold", 0.0)),
				roundi(s.storage), s.storage / fastest, s.troops, s.barracks, roundi(s.looted), roundi(s.produced)])
	_say("")


func _raids(run: Dictionary) -> void:
	var log: Array = run.log
	_say("## Raider's attacks")
	_say("")
	if log.is_empty():
		_say("No attacks.")
		return
	var wins := 0
	var lost := 0
	var top := 0
	for e: Dictionary in log:
		if e.won:
			wins += 1
			top = maxi(top, int(e.level))
		lost += int(e.lost)
	_say("%d attacks, %d won, %d soldiers lost, highest camp beaten: level %d." % [log.size(), wins, lost, top])
	_say("")
	_say("| Day | Camp level | Sent | Lost | Won | Loot |")
	_say("|---|---|---|---|---|---|")
	var shown := 0
	var every := maxi(1, log.size() / 25)
	for i in log.size():
		if i % every != 0 and i != log.size() - 1:
			continue
		var e: Dictionary = log[i]
		_say("| %.1f | %d | %d | %d | %s | %d |" % [float(e.t) / 86400.0, e.level, e.sent, e.lost, "yes" if e.won else "no", e.loot])
		shown += 1
	_say("")


# --- Helpers -----------------------------------------------------------------------

func _say(text: String) -> void:
	lines.append(text)


func _count(army: Dictionary) -> int:
	var n := 0
	for u: String in army:
		n += int(army[u])
	return n


func _sum(d: Dictionary) -> float:
	var n := 0.0
	for k: String in d:
		n += float(d[k])
	return n


func _level(c: CastleState, type: String) -> int:
	for b in c.buildings:
		if b.type == type:
			return int(b.level)
	return 0


func _res(cost: Dictionary) -> String:
	return "%d/%d/%d" % [int(cost.get("wood", 0)), int(cost.get("stone", 0)), int(cost.get("gold", 0))]


func _when(at: Dictionary, lv: int) -> String:
	return _time(float(at[lv])) if at.has(lv) else "not reached"


static func _day(d: float) -> String:
	return "%d" % int(d) if d == floorf(d) else "%.2f" % d


static func _time(seconds: float) -> String:
	if seconds < 3600.0:
		return "%dm" % roundi(seconds / 60.0)
	if seconds < 86400.0:
		return "%.1fh" % (seconds / 3600.0)
	return "%.1fd" % (seconds / 86400.0)
