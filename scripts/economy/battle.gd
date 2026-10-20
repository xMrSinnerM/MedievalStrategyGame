class_name Battle
extends RefCounted
## Auto-resolves a fight between two armies (unit -> soldiers). Both sides
## strike at once each round: every soldier deals its attack (times its bonus
## against each enemy type, spread over the enemy by numbers), and an enemy
## soldier falls for every point of damage equal to their defence. A side
## breaks and flees once it is down to ROUT of the soldiers it started with.
## The same armies and seed always give the same result.
##
## Sieges: the attackers camp outside for siege_time() and then storm the
## walls against the garrison, whose defence the wall multiplies
## (wall_bonus()). A castle that falls is captured, except the player's main
## castle, which can only be sacked.
##
## Siege waves (every attack on a castle or a camp, see siege()): the
## defenders stand on the left, front and right walls, with a reserve in the
## courtyard (a layout of percentages). The attackers come in waves, each
## with soldiers for every wall, and fight each wall's defenders behind the
## wall. Attackers who lose on a wall go home. Once a wall is broken, the
## next waves at it walk straight through, and the wall's last defenders fall
## back into the courtyard. Break at least one wall, then win the courtyard
## fight to take the castle: there the defenders make their last stand around
## the keep, with the wall's bonus times COURTYARD_BONUS.
##
## Siege tools (data/units.json "tools", wall_mods()): the attackers bring
## tools to each wall (ladders and rams cut the wall's bonus, mantlets shield
## them) and the defenders post their own (moats strengthen the wall, arrow
## slits and boiling pitch hurt the attackers). They change only the fights
## at their wall, not the courtyard.
##
## Commanders (GearRules): the attackers' commander and the defenders'
## castellan add their gear's stats (`tools` "lead_a" and "lead_b", stat ->
## share): harder blows at the walls and in the courtyard, a weaker or
## stronger wall.

## Share of an army's attack that lands each round.
const DAMAGE := 0.3
## A side flees when it has this share of its soldiers left.
const ROUT := 0.35
const MAX_ROUNDS := 12
## Gold the winner plunders for each enemy soldier that fell.
const LOOT_PER_KILL := 3.0
## Fights simulated to estimate the odds before attacking.
const ODDS_SAMPLES := 40
## Seconds a siege camp takes before the assault, plus more per wall level.
const SIEGE_BASE := 30.0
const SIEGE_PER_WALL := 15.0
## How much the wall can add to the garrison's defence at most (x1 + this).
const WALL_MAX := 1.5
## Wall defence at which the wall gives half of WALL_MAX.
const WALL_HALF := 200.0
## Share of each resource sacking an uncapturable castle carries off.
const SACK_SHARE := 0.3
## The three walls an attack can come at.
const WALLS: Array[String] = ["left", "front", "right"]
## Where the defenders stand unless their lord says otherwise (percent).
const DEFAULT_LAYOUT := {"left": 25, "front": 35, "right": 25, "courtyard": 15}
## How an army is spread over the walls when nobody chooses (percent).
const ATTACK_SPLIT := {"left": 30, "front": 40, "right": 30}
## [keep level, waves an attack from that castle can have], lowest first.
const WAVES_BY_KEEP := [[1, 1], [2, 2], [4, 3]]
## Seed offsets for each wall's fights and the courtyard's.
const WALL_SEED := 101
const COURTYARD_SEED := 997
## Extra defence for the last stand in the courtyard, on top of the wall's.
const COURTYARD_BONUS := 1.5


static func fight(rules: BuildingRules, a: Dictionary, b: Dictionary, seed_value: int, wall := 1.0,
		power_a := 1.0, power_b := 1.0) -> Dictionary:
	## Returns {"winner": "a" | "b", "rounds": n, "a": {unit: {"start", "lost"}},
	## "b": {...}}. With equal standing at the end, the defender (b) holds.
	## `wall` multiplies side b's defence (1 = fighting in the open);
	## `power_a` and `power_b` the damage each side deals (siege tools, wall_mods()).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var left_a := _floats(a)
	var left_b := _floats(b)
	var start_a := _total(left_a)
	var start_b := _total(left_b)
	var rounds := 0
	while rounds < MAX_ROUNDS and start_a > 0.0 and start_b > 0.0:
		rounds += 1
		var hits_b := _casualties(rules, left_a, left_b, rng.randf_range(0.8, 1.2) * power_a, wall)
		var hits_a := _casualties(rules, left_b, left_a, rng.randf_range(0.8, 1.2) * power_b, 1.0)
		_apply(left_a, hits_a)
		_apply(left_b, hits_b)
		if _total(left_a) <= start_a * ROUT or _total(left_b) <= start_b * ROUT:
			break
	var share_a := _total(left_a) / start_a if start_a > 0.0 else 0.0
	var share_b := _total(left_b) / start_b if start_b > 0.0 else 0.0
	return {
		"winner": "a" if share_a > share_b else "b",
		"rounds": rounds,
		"a": _losses(a, left_a),
		"b": _losses(b, left_b),
	}


static func resolve(attacker: CastleState, defender: CastleState, seed_value: int) -> Dictionary:
	## Fights the two castles' warbands, leaves each with its survivors and
	## gives the winner's castle the plunder (up to its storage). Returns the
	## fight() result plus "loot".
	var result := fight(attacker.rules, attacker.field, defender.field, seed_value)
	attacker.field = survivors(result.a)
	defender.field = survivors(result.b)
	var winner := attacker if result.winner == "a" else defender
	result["loot"] = _plunder(winner, lost_count(result.b if result.winner == "a" else result.a) * LOOT_PER_KILL)
	return result


static func _plunder(castle: CastleState, gold: float) -> int:
	## Adds gold to the castle up to its storage; returns how much fitted.
	var have: float = castle.resources.get("gold", 0.0)
	var loot := minf(gold, maxf(castle.storage_capacity() - have, 0.0))
	castle.resources["gold"] = have + loot
	return int(loot)


static func wall_bonus(castle: CastleState) -> float:
	## Multiplier on the garrison's defence while it holds the walls.
	return wall_from_defense(castle.defense())


static func wall_from_defense(d: float) -> float:
	return 1.0 + WALL_MAX * d / (d + WALL_HALF)


static func siege_time(castle: CastleState) -> float:
	var wall := 0
	for b in castle.buildings:
		if b.type == "wall":
			wall = maxi(wall, b.level)
	return SIEGE_BASE + SIEGE_PER_WALL * wall


static func can_capture(castle: CastleState, main_castle_id: String) -> bool:
	## Every castle can change hands except the player's main castle.
	return castle.id != main_castle_id


static func assault(attacker: CastleState, castle: CastleState, seed_value: int, main_castle_id := "player_castle",
		castellan := {}) -> Dictionary:
	## Storms `castle` with `attacker`'s warband. Both keep their survivors
	## (the warband in its field, the castle in its garrison) and the winner
	## plunders as in resolve(). If the attackers win, "outcome" says what
	## happens to the castle: "captured" (the caller hands it over, see
	## Economy.capture) or "sacked" (SACK_SHARE of its stock is carried off
	## here, up to the attacker's storage); otherwise "held". The castle's
	## defence tools fight on its walls and are lost with any wall that falls,
	## and `castellan` is what its castellan's gear adds (GearRules.effects()).
	## "sacked" adds "spoils" (resource -> amount) to the result.
	var result := siege(attacker.rules, auto_waves(attacker.field), castle.troops, castle.layout, seed_value, wall_bonus(castle),
			{"b": castle.defence_tools, "lead_b": castellan})
	if result.has("tools"):
		castle.lose_defence_tools(result.tools.lost)
	attacker.field = survivors(result.a)
	castle.troops = survivors(result.b)
	var won: bool = result.winner == "a"
	var winner := attacker if won else castle
	result["loot"] = _plunder(winner, lost_count(result.b if won else result.a) * LOOT_PER_KILL)
	if not won:
		result["outcome"] = "held"
	elif can_capture(castle, main_castle_id):
		result["outcome"] = "captured"
	else:
		result["outcome"] = "sacked"
		var spoils := {}
		var room := attacker.storage_capacity()
		for r: String in castle.resources:
			var take := minf(castle.resources[r] * SACK_SHARE, maxf(room - attacker.resources.get(r, 0.0), 0.0))
			castle.resources[r] -= take
			attacker.resources[r] = attacker.resources.get(r, 0.0) + take
			spoils[r] = int(take)
		result["spoils"] = spoils
	return result


static func odds(rules: BuildingRules, a: Dictionary, b: Dictionary, seed_value := 1, wall := 1.0) -> float:
	## Share of simulated fights side a wins, 0 .. 1.
	if _total(_floats(a)) <= 0.0:
		return 0.0
	var wins := 0
	for k in ODDS_SAMPLES:
		if fight(rules, a, b, seed_value + k, wall).winner == "a":
			wins += 1
	return float(wins) / ODDS_SAMPLES


static func siege(rules: BuildingRules, waves: Array, defenders: Dictionary, layout: Dictionary, seed_value: int, wall := 1.0,
		tools := {}) -> Dictionary:
	## Storms a castle or camp in waves (see the top of this file). `waves` is
	## an array of {wall: army} (WALLS), `layout` the defenders' percentages
	## (DEFAULT_LAYOUT's keys). Returns fight()'s keys for the whole siege
	## ("winner", "rounds", "a" and "b" with every soldier on each side) plus
	## "walls" (wall -> {"broken", "fights": [{"wave", "open"} or {"wave",
	## "winner", "a", "b"}]}), "courtyard" ({} if never reached, {"open": true}
	## if nobody was there, or {"winner", "a", "b"}) and "waves" (how many).
	## `tools` is {"a": attackers' tools, "b": defenders'}, each wall -> {tool:
	## count}; with any, the result has "tools": {"a", "b", "lost"}, "lost"
	## being the defence tools at walls that fell. Its "lead_a" and "lead_b"
	## are the commander's and castellan's effects (GearRules.effects()).
	var posts := split(defenders, layout, ["left", "right", "courtyard", "front"])
	var sent := {}
	var home := {}       # attackers going home
	var through := {}    # attackers inside the walls
	var walls := {}
	var rounds := 0
	var broken_any := false
	var yard: Dictionary = posts.courtyard
	var holding := {}    # defenders still on the walls they held
	for i in WALLS.size():
		var w: String = WALLS[i]
		var held: Dictionary = posts[w]
		var fights: Array = []
		var broken := false
		var mods := wall_mods(rules, wall, tools.get("a", {}).get(w, {}), tools.get("b", {}).get(w, {}),
				tools.get("lead_a", {}), tools.get("lead_b", {}))
		for k in waves.size():
			var troops := _ints(waves[k].get(w, {}))
			if troops.is_empty():
				continue
			_add(sent, troops)
			if broken or held.is_empty():
				broken = true
				_add(through, troops)
				fights.append({"wave": k, "open": true})
				continue
			var r := fight(rules, troops, held, seed_value + WALL_SEED * (i + 1) + k, mods.wall, mods.a, mods.b)
			rounds += r.rounds
			held = survivors(r.b)
			fights.append({"wave": k, "winner": r.winner, "a": r.a, "b": r.b})
			if r.winner == "a":
				broken = true
				_add(through, survivors(r.a))
			else:
				_add(home, survivors(r.a))
		walls[w] = {"broken": broken, "fights": fights}
		if broken:
			broken_any = true
			_add(yard, held)
		else:
			_add(holding, held)
	var winner := "b"
	var courtyard := {}
	if broken_any and not through.is_empty():
		if yard.is_empty():
			winner = "a"
			courtyard = {"open": true}
			_add(home, through)
		else:
			var r := fight(rules, through, yard, seed_value + COURTYARD_SEED, wall * COURTYARD_BONUS,
					1.0 + float(tools.get("lead_a", {}).get("yard_attack", 0.0)), 1.0 + float(tools.get("lead_b", {}).get("yard_defence", 0.0)))
			rounds += r.rounds
			winner = r.winner
			courtyard = {"winner": r.winner, "a": r.a, "b": r.b}
			yard = survivors(r.b)
			_add(home, survivors(r.a))
	_add(holding, yard)
	var result := {"winner": winner, "rounds": rounds, "a": _kept(sent, home), "b": _kept(_ints(defenders), holding),
			"walls": walls, "courtyard": courtyard, "waves": waves.size()}
	var used_a := clean_tools(tools.get("a", {}))
	var used_b := clean_tools(tools.get("b", {}))
	if not used_a.is_empty() or not used_b.is_empty():
		# Attack tools are used up; defence tools are lost with their wall.
		var lost := {}
		for w: String in WALLS:
			if walls[w].broken and used_b.has(w):
				lost[w] = used_b[w].duplicate()
		result["tools"] = {"a": used_a, "b": used_b, "lost": lost}
	return result


static func wall_mods(rules: BuildingRules, wall: float, a: Dictionary, b: Dictionary, lead_a := {}, lead_b := {}) -> Dictionary:
	## What the tools at one wall (and the commander's and castellan's gear) do
	## to its fights: {"wall": the wall's bonus, "a": the attackers' damage,
	## "b": the defenders' damage}.
	var cut := 0.0
	var shield := 0.0
	var moat := 0.0
	var volley := 0.0
	var scald := 0.0
	for t: String in rules.tools:
		var na := int(a.get(t, 0))
		var nb := int(b.get(t, 0))
		if na > 0:
			cut += na * rules.tool_effect(t, "wall_cut")
			shield += na * rules.tool_effect(t, "shield")
		if nb > 0:
			moat += nb * rules.tool_effect(t, "moat")
			volley += nb * rules.tool_effect(t, "volley")
			scald += nb * rules.tool_effect(t, "scald")
	cut += float(lead_a.get("wall_cut", 0.0))
	moat += float(lead_b.get("wall_bonus", 0.0))
	var w := wall if cut == 0.0 and moat == 0.0 else (1.0 + (wall - 1.0) * (1.0 - minf(cut, 1.0))) * (1.0 + moat)
	return {"wall": w, "a": (1.0 - minf(scald, 0.5)) * (1.0 + float(lead_a.get("wall_attack", 0.0))),
			"b": (1.0 - minf(shield, 0.5)) * (1.0 + volley) * (1.0 + float(lead_b.get("wall_defence", 0.0)))}


static func tools_total(tools: Dictionary) -> Dictionary:
	## Every tool in a set of walls' tools, by tool.
	var out := {}
	for w: String in WALLS:
		_add(out, tools.get(w, {}))
	return out


static func check_tools(rules: BuildingRules, tools: Variant, side: String, slots: int, stock: Dictionary) -> String:
	## "" if `tools` (wall -> {tool: count}) are tools of `side` ("attack" or
	## "defence") that fit their walls, at most `slots` a wall and no more
	## than `stock` has; otherwise why not.
	if tools == null:
		return ""
	if not tools is Dictionary:
		return "Bad tools."
	for w: Variant in tools:
		if not WALLS.has(w) or not tools[w] is Dictionary:
			return "Bad tools."
		var n := 0
		for tool: Variant in tools[w]:
			if not rules.has_tool(String(tool)) or rules.tool_side(String(tool)) != side:
				return "Unknown siege tool."
			var count: Variant = tools[w][tool]
			if not (count is int or count is float) or count != floorf(count) or count < 0:
				return "Bad tools."
			if count == 0:
				continue
			if not rules.tool_fits(String(tool), String(w)):
				return "%s can't be used at the %s wall." % [rules.tool_name(String(tool)), w]
			n += int(count)
		if n > slots:
			return "No siege tools fit there yet." if slots == 0 else "Only %d siege tools fit on each wall." % slots
	var total := tools_total(tools)
	for tool: String in total:
		if int(total[tool]) > int(stock.get(tool, 0)):
			return "You don't have that many siege tools."
	return ""


static func clean_tools(tools: Dictionary) -> Dictionary:
	var out := {}
	for w: String in WALLS:
		var group := _ints(tools.get(w, {}))
		if not group.is_empty():
			out[w] = group
	return out


static func siege_odds(rules: BuildingRules, waves: Array, defenders: Dictionary, layout: Dictionary, seed_value := 1, wall := 1.0,
		tools := {}) -> float:
	## Share of simulated sieges the attackers win, 0 .. 1.
	var any := false
	for wave: Dictionary in waves:
		for w: String in wave:
			if not _ints(wave[w]).is_empty():
				any = true
	if not any:
		return 0.0
	var wins := 0
	for k in ODDS_SAMPLES:
		if siege(rules, waves, defenders, layout, seed_value + k, wall, tools).winner == "a":
			wins += 1
	return float(wins) / ODDS_SAMPLES


static func auto_waves(army: Dictionary) -> Array:
	## One wave with the army spread over the walls by ATTACK_SPLIT.
	return [split(army, ATTACK_SPLIT, ["left", "right", "front"])]


static func waves_for_keep(keep: int) -> int:
	var n := 1
	for row: Array in WAVES_BY_KEEP:
		if keep >= int(row[0]):
			n = int(row[1])
	return n


static func split(army: Dictionary, shares: Dictionary, order: Array) -> Dictionary:
	## Spreads an army over the keys of `order` by percentage (`shares`),
	## rounding down; the last key gets what is left. Returns key -> army,
	## without units that got nobody.
	var out := {}
	for key: String in order:
		out[key] = {}
	for u: String in army:
		var n := int(army[u])
		if n <= 0:
			continue
		var left := n
		for i in order.size():
			var key: String = order[i]
			var part := left if i == order.size() - 1 else n * int(shares.get(key, 0)) / 100
			part = mini(part, left)
			left -= part
			if part > 0:
				out[key][u] = part
	return out


static func check_waves(waves: Variant, max_waves: int, rules: BuildingRules) -> String:
	## "" if `waves` can be sent from a castle allowing `max_waves`, otherwise
	## why not. Whether the garrison has the soldiers is checked on their sum
	## (waves_army()).
	if not waves is Array or waves.is_empty():
		return "Bad waves."
	if waves.size() > max_waves:
		return "Upgrade your keep to send more than one wave." if max_waves == 1 else "Your keep allows %d waves." % max_waves
	for wave: Variant in waves:
		if not wave is Dictionary:
			return "Bad waves."
		for w: Variant in wave:
			if not WALLS.has(w) or not wave[w] is Dictionary:
				return "Bad waves."
			for unit: Variant in wave[w]:
				if not rules.has_unit(String(unit)):
					return "Unknown unit."
				var n: Variant = wave[w][unit]
				if not (n is int or n is float) or n != floorf(n) or n < 0:
					return "Bad waves."
	return ""


static func waves_army(waves: Array) -> Dictionary:
	## Every soldier in the waves, by unit.
	var out := {}
	for wave: Dictionary in waves:
		for w: String in wave:
			_add(out, wave[w])
	return out


static func check_layout(layout: Variant) -> String:
	## "" if `layout` is a valid defence layout, otherwise why not.
	if not layout is Dictionary or layout.size() != DEFAULT_LAYOUT.size():
		return "Bad layout."
	var sum := 0
	for key: String in DEFAULT_LAYOUT:
		var v: Variant = layout.get(key)
		if not (v is int or v is float) or v != floorf(v) or v < 0 or v > 100:
			return "Bad layout."
		sum += int(v)
	return "" if sum == 100 else "The walls and courtyard must add up to 100%."


static func odds_text(chance: float) -> String:
	if chance >= 0.85:
		return "Certain victory"
	if chance >= 0.6:
		return "Likely victory"
	if chance > 0.4:
		return "An even fight"
	if chance > 0.15:
		return "Likely defeat"
	return "Hopeless"


static func survivors(side: Dictionary) -> Dictionary:
	## unit -> soldiers left, from one side of a fight() result.
	var out := {}
	for unit: String in side:
		var n: int = side[unit].start - side[unit].lost
		if n > 0:
			out[unit] = n
	return out


static func lost_count(side: Dictionary) -> int:
	var n := 0
	for unit: String in side:
		n += side[unit].lost
	return n


static func _casualties(rules: BuildingRules, attackers: Dictionary, defenders: Dictionary, luck: float, wall: float) -> Dictionary:
	var out := {}
	var total := _total(defenders)
	if total <= 0.0:
		return out
	for u: String in attackers:
		var power: float = attackers[u] * rules.unit_stat(u, "attack") * DAMAGE * luck
		for t: String in defenders:
			if defenders[t] <= 0.0:
				continue
			var share: float = defenders[t] / total
			out[t] = out.get(t, 0.0) + power * share * rules.unit_bonus(u, t) / maxf(rules.unit_stat(t, "defense") * wall, 1.0)
	return out


static func _ints(army: Dictionary) -> Dictionary:
	var out := {}
	for u: String in army:
		if int(army[u]) > 0:
			out[u] = int(army[u])
	return out


static func _add(to: Dictionary, army: Dictionary) -> void:
	for u: String in army:
		if int(army[u]) > 0:
			to[u] = int(to.get(u, 0)) + int(army[u])


static func _kept(start: Dictionary, left: Dictionary) -> Dictionary:
	## {unit: {"start", "lost"}} for soldiers `start` of whom `left` remain.
	var out := {}
	for u: String in start:
		out[u] = {"start": int(start[u]), "lost": int(start[u]) - mini(int(left.get(u, 0)), int(start[u]))}
	return out


static func _apply(army: Dictionary, hits: Dictionary) -> void:
	for t: String in hits:
		army[t] = maxf(army[t] - hits[t], 0.0)


static func _floats(army: Dictionary) -> Dictionary:
	var out := {}
	for u: String in army:
		if army[u] > 0:
			out[u] = float(army[u])
	return out


static func _total(army: Dictionary) -> float:
	var n := 0.0
	for u: String in army:
		n += army[u]
	return n


static func _losses(start: Dictionary, left: Dictionary) -> Dictionary:
	var out := {}
	for u: String in start:
		if start[u] <= 0:
			continue
		var remaining := int(roundf(left.get(u, 0.0)))
		out[u] = {"start": int(start[u]), "lost": clampi(int(start[u]) - remaining, 0, int(start[u]))}
	return out
