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


static func create(camp_id: String, display_name: String, pos: Vector2, start_level := 1) -> BaronCamp:
	var camp := BaronCamp.new()
	camp.id = camp_id
	camp.camp_name = display_name
	camp.position = pos
	camp.level = start_level
	return camp


func is_ready(now: float) -> bool:
	return now >= rebuilt_at


func garrison(rules: BaronRules) -> Dictionary:
	return rules.garrison(level)


func attack(rules: BaronRules, units: BuildingRules, army: Dictionary, seed_value: int, now: float) -> Dictionary:
	## Fights the camp's garrison behind its palisade. Returns Battle.fight()'s
	## result plus "level" (before), "leveled" (the camp rose a level),
	## "loot" (resource -> amount carried off, empty if the attack failed)
	## and "survivors" (the attackers coming home).
	var result := Battle.fight(units, army, garrison(rules), seed_value,
			Battle.wall_from_defense(rules.palisade(level)))
	result["level"] = level
	result["leveled"] = false
	result["survivors"] = Battle.survivors(result.a)
	result["loot"] = {}
	if result.winner != "a":
		return result
	result["loot"] = _carried(rules.loot(level), rules.carry(result.survivors))
	rebuilt_at = now + rules.rebuild_time(level)
	defeats += 1
	if defeats >= rules.defeats_needed(level) and level < rules.max_level:
		level += 1
		defeats = 0
		result["leveled"] = true
	return result


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
	return {"id": id, "name": camp_name, "position": [position.x, position.y], "level": level,
			"defeats": defeats, "rebuilt_at": rebuilt_at}


static func from_dict(data: Dictionary) -> BaronCamp:
	var pos: Array = data.get("position", [0.0, 0.0])
	var camp := create(data.get("id", ""), data.get("name", ""), Vector2(pos[0], pos[1]), int(data.get("level", 1)))
	camp.defeats = int(data.get("defeats", 0))
	camp.rebuilt_at = float(data.get("rebuilt_at", 0.0))
	return camp
