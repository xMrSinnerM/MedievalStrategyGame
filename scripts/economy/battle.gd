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


static func fight(rules: BuildingRules, a: Dictionary, b: Dictionary, seed_value: int, wall := 1.0) -> Dictionary:
	## Returns {"winner": "a" | "b", "rounds": n, "a": {unit: {"start", "lost"}},
	## "b": {...}}. With equal standing at the end, the defender (b) holds.
	## `wall` multiplies side b's defence (1 = fighting in the open).
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var left_a := _floats(a)
	var left_b := _floats(b)
	var start_a := _total(left_a)
	var start_b := _total(left_b)
	var rounds := 0
	while rounds < MAX_ROUNDS and start_a > 0.0 and start_b > 0.0:
		rounds += 1
		var hits_b := _casualties(rules, left_a, left_b, rng.randf_range(0.8, 1.2), wall)
		var hits_a := _casualties(rules, left_b, left_a, rng.randf_range(0.8, 1.2), 1.0)
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
	var d := castle.defense()
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


static func assault(attacker: CastleState, castle: CastleState, seed_value: int, main_castle_id := "player_castle") -> Dictionary:
	## Storms `castle` with `attacker`'s warband. Both keep their survivors
	## (the warband in its field, the castle in its garrison) and the winner
	## plunders as in resolve(). If the attackers win, "outcome" says what
	## happens to the castle: "captured" (the caller hands it over, see
	## Economy.capture) or "sacked" (SACK_SHARE of its stock is carried off
	## here, up to the attacker's storage); otherwise "held".
	## "sacked" adds "spoils" (resource -> amount) to the result.
	var result := fight(attacker.rules, attacker.field, castle.troops, seed_value, wall_bonus(castle))
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
