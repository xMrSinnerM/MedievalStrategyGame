class_name BaronCamp
extends RefCounted
## One robber baron's camp, as one player knows it. Every win against it
## counts towards its next level (BaronRules.defeats_needed), and a higher
## level means a bigger garrison, a stronger palisade and richer loot. A beaten
## camp needs time to rebuild before it can be attacked again; a camp that
## holds keeps its level. Like the castles, the state is plain data with
## explicit times, so a server can keep it for each player.

var id := ""
var camp_name := ""
var position := Vector2.ZERO
var level := 1
var defeats := 0             ## wins against it at its current level
var rebuilt_at := 0.0        ## unix time it can be attacked again
## Online only: an invader camp of a Baron Invasion (a timed event) has the
## start of its invasion here, and gives `points` event points per level for
## a win. The server decides its fights; it rises a level with every win.
var event := 0.0
var points := 0
## Online only: a camp of the Ember Horde (a timed event) has the start of
## the horde's run here, and gives `points` horde points and `trophies` war
## trophies per level for a win, with the horde rules (BaronRules.for_camp()).
var horde := 0.0
var trophies := 0
## Online only: a fortress, one of the old kingdoms' castles, with the
## fortress rules (BaronRules.for_camp()).
var fortress := false
## Until when saboteurs have weakened the palisade, and by how much (SabotageRules).
var weak_until := 0.0
var weak_cut := 0.0


static func create(camp_id: String, display_name: String, pos: Vector2, start_level := 1) -> BaronCamp:
	var camp := BaronCamp.new()
	camp.id = camp_id
	camp.camp_name = display_name
	camp.position = pos
	camp.level = start_level
	return camp


func is_invader() -> bool:
	return event > 0.0


func is_horde() -> bool:
	return horde > 0.0


func is_ready(now: float) -> bool:
	return now >= rebuilt_at


func garrison(rules: BaronRules) -> Dictionary:
	return rules.for_camp(self).garrison(level)


func attack(rules: BaronRules, units: BuildingRules, army: Dictionary, seed_value: int, now: float, waves: Array = [],
		tools := {}, lead := {}) -> Dictionary:
	## Storms the camp's palisade in `waves`, or with the army spread over its
	## walls in one wave, with the attackers' siege `tools` (Battle.siege(), the garrison in
	## Battle.DEFAULT_LAYOUT). Returns the
	## siege result plus "level" (before), "leveled" (the camp rose a level),
	## "loot" (resource -> amount carried off, empty if the attack failed)
	## and "survivors" (the attackers coming home). `lead` is what the army's
	## commander adds (GearRules.effects()): harder blows, and "loot" more carried.
	var barons := rules
	rules = barons.for_camp(self)
	var result := Battle.siege(units, waves if not waves.is_empty() else Battle.auto_waves(army), garrison(barons), Battle.DEFAULT_LAYOUT,
			seed_value, Battle.wall_from_defense(rules.palisade(level) * walls_factor(now)), {"a": tools, "lead_a": lead})
	result["level"] = level
	result["leveled"] = false
	result["survivors"] = Battle.survivors(result.a)
	result["loot"] = {}
	if result.winner != "a":
		return result
	result["loot"] = _carried(rules.loot(level), rules.carry(result.survivors) * (1.0 + float(lead.get("loot", 0.0))))
	rebuilt_at = now + rules.rebuild_time(level)
	defeats += 1
	if defeats >= rules.defeats_needed(level) and level < rules.max_level:
		level += 1
		defeats = 0
		result["leveled"] = true
	return result


func walls_factor(t: float) -> float:
	## What's left of the palisade's strength at time t after sabotage.
	return 1.0 - weak_cut if weak_until > t else 1.0


static func _carried(stock: Dictionary, capacity: float) -> Dictionary:
	## Takes an even share of every resource, up to what the army can carry.
	var total := 0.0
	for r: String in stock:
		total += float(stock[r])
	var share := 1.0 if total <= capacity else capacity / total
	var out := {}
	for r: String in stock:
		out[r] = floori(float(stock[r]) * share)
	return out


func to_dict() -> Dictionary:
	var out := {"id": id, "name": camp_name, "position": [position.x, position.y], "level": level,
			"defeats": defeats, "rebuilt_at": rebuilt_at}
	if is_invader():
		out["event"] = event
		out["points"] = points
	if is_horde():
		out["horde"] = horde
		out["points"] = points
		out["trophies"] = trophies
	if fortress:
		out["fortress"] = true
	if weak_until > 0.0:
		out["weak_until"] = weak_until
		out["weak_cut"] = weak_cut
	return out


static func from_dict(data: Dictionary) -> BaronCamp:
	var pos: Array = data.get("position", [0.0, 0.0])
	var camp := create(data.get("id", ""), data.get("name", ""), Vector2(pos[0], pos[1]), int(data.get("level", 1)))
	camp.defeats = int(data.get("defeats", 0))
	camp.rebuilt_at = float(data.get("rebuilt_at", 0.0))
	camp.event = float(data.get("event", 0.0))
	camp.points = int(data.get("points", 0))
	camp.horde = float(data.get("horde", 0.0))
	camp.trophies = int(data.get("trophies", 0))
	camp.fortress = bool(data.get("fortress", false))
	camp.weak_until = float(data.get("weak_until", 0.0))
	camp.weak_cut = float(data.get("weak_cut", 0.0))
	return camp
