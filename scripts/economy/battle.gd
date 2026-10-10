class_name Battle
extends RefCounted
## Auto-resolves a fight between two armies (unit -> soldiers). Both sides
## strike at once each round: every soldier deals its attack (times its bonus
## against each enemy type, spread over the enemy by numbers), and an enemy
## soldier falls for every point of damage equal to their defence. A side
## breaks and flees once it is down to ROUT of the soldiers it started with.
## The same armies and seed always give the same result.

## Share of an army's attack that lands each round.
const DAMAGE := 0.3
## A side flees when it has this share of its soldiers left.
const ROUT := 0.35
const MAX_ROUNDS := 12
## Gold the winner plunders for each enemy soldier that fell.
const LOOT_PER_KILL := 3.0
## Fights simulated to estimate the odds before attacking.
const ODDS_SAMPLES := 40


static func fight(rules: BuildingRules, a: Dictionary, b: Dictionary, seed_value: int) -> Dictionary:
	## Returns {"winner": "a" | "b", "rounds": n, "a": {unit: {"start", "lost"}},
	## "b": {...}}. With equal standing at the end, the defender (b) holds.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var left_a := _floats(a)
	var left_b := _floats(b)
	var start_a := _total(left_a)
	var start_b := _total(left_b)
	var rounds := 0
	while rounds < MAX_ROUNDS and start_a > 0.0 and start_b > 0.0:
		rounds += 1
		var hits_b := _casualties(rules, left_a, left_b, rng.randf_range(0.8, 1.2))
		var hits_a := _casualties(rules, left_b, left_a, rng.randf_range(0.8, 1.2))
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
	var killed := lost_count(result.b if result.winner == "a" else result.a)
	var gold: float = winner.resources.get("gold", 0.0)
	var room := maxf(winner.storage_capacity() - gold, 0.0)
	var loot := minf(killed * LOOT_PER_KILL, room)
	winner.resources["gold"] = gold + loot
	result["loot"] = int(loot)
	return result


static func odds(rules: BuildingRules, a: Dictionary, b: Dictionary, seed_value := 1) -> float:
	## Share of simulated fights side a wins, 0 .. 1.
	if _total(_floats(a)) <= 0.0:
		return 0.0
	var wins := 0
	for k in ODDS_SAMPLES:
		if fight(rules, a, b, seed_value + k).winner == "a":
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


static func _casualties(rules: BuildingRules, attackers: Dictionary, defenders: Dictionary, luck: float) -> Dictionary:
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
			out[t] = out.get(t, 0.0) + power * share * rules.unit_bonus(u, t) / maxf(rules.unit_stat(t, "defense"), 1.0)
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
