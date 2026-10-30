class_name SabotageRules
extends RefCounted
## Spies and sabotage: hired agents sent into a robber baron's camp or,
## online, another player's castle, to steal, burn the stores or weaken the
## walls for a while. The numbers are in data/sabotage.json;
## server/rules/sabotage.ts is the same rules (the server decides missions
## against players).
##
## A castle keeps {"sent": {target key: time}, "count": missions sent} in
## castle.sabotage (the count seeds each mission's luck, so the game and the
## server agree on missions against camps), and
## "walls_until" / "walls_cut" while its own walls are weakened. A camp
## keeps weak_until / weak_cut (BaronCamp).

const PATH := "res://data/sabotage.json"
const MISSIONS := ["steal", "burn_stores", "burn_walls"]

var agent_gold := 0
var max_agents := 0
var cooldown := 0.0
var chance_rules := {}
var scale: Array = [1]
var carry_per_agent := 0
var steal_share := 0.0
var burn_share := 0.0
var walls_cut := 0.0
var walls_time := 0.0
var missions := {}


static func load_default() -> SabotageRules:
	var rules := SabotageRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	return rules


func load_from(data: Dictionary) -> void:
	agent_gold = int(data.get("agent_gold", 0))
	max_agents = int(data.get("max_agents", 0))
	cooldown = float(data.get("cooldown_hours", 0)) * 3600.0
	chance_rules = data.get("chance", {})
	scale = data.get("scale", [1])
	carry_per_agent = int(data.get("carry_per_agent", 0))
	steal_share = float(data.get("steal_share", 0.0))
	burn_share = float(data.get("burn_share", 0.0))
	walls_cut = float(data.get("walls_cut", 0.0))
	walls_time = float(data.get("walls_hours", 0)) * 3600.0
	missions = data.get("missions", {})


func cost(agents: int) -> Dictionary:
	return {"gold": agent_gold * agents}


func _clamp_chance(c: float) -> float:
	return clampf(c, float(chance_rules.get("min", 0.0)), float(chance_rules.get("max", 1.0)))


func camp_chance(agents: int, camp_level: int) -> float:
	return _clamp_chance(float(chance_rules.get("base", 0.0)) + float(chance_rules.get("per_agent", 0.0)) * agents
		- float(chance_rules.get("per_camp_level", 0.0)) * (camp_level - 1))


func player_chance(agents: int, my_keep: int, their_keep: int) -> float:
	return _clamp_chance(float(chance_rules.get("base", 0.0)) + float(chance_rules.get("per_agent", 0.0)) * agents
		- float(chance_rules.get("per_keep", 0.0)) * maxi(0, their_keep - my_keep))


func carry(agents: int, keep: int) -> int:
	return carry_per_agent * agents * int(scale[clampi(keep, 1, scale.size()) - 1])


static func camp_key(camp_id: String) -> String:
	return "camp:" + camp_id


static func player_key(player_name: String) -> String:
	return "player:" + player_name


func wait_left(castle: CastleState, key: String, now: float) -> float:
	## Seconds until agents can be sent to this target again (0 if now).
	var last := float(castle.sabotage.get("sent", {}).get(key, -INF))
	return maxf(0.0, last + cooldown - now)


func check(castle: CastleState, key: String, mission: Variant, agents: Variant, now: float, player := false) -> String:
	## Why these agents can't go now ("" if they can).
	if not (mission is String) or not missions.has(mission):
		return "There's no such mission."
	if not player and bool(missions[mission].get("players_only", false)):
		return "Camps keep no stores worth burning."
	if not (agents is int or agents is float) or float(agents) != floor(float(agents)) or int(agents) < 1 or int(agents) > max_agents:
		return "Send between 1 and %d agents." % max_agents
	if wait_left(castle, key, now) > 0.0:
		return "Your agents there are lying low for another %d minutes." % ceili(wait_left(castle, key, now) / 60.0)
	if not castle.can_afford(cost(int(agents))):
		return "Not enough gold to hire %d agents." % int(agents)
	return ""


func _send(castle: CastleState, key: String, agents: int, now: float) -> void:
	## Pays the agents and remembers when they went (forgetting old targets).
	castle.pay(cost(agents))
	var sent := {}
	var old: Dictionary = castle.sabotage.get("sent", {})
	for k: String in old:
		if float(old[k]) + cooldown > now:
			sent[k] = old[k]
	sent[key] = now
	castle.sabotage["sent"] = sent
	castle.sabotage["count"] = int(castle.sabotage.get("count", 0)) + 1


static func seed_for(castle: CastleState, key: String, agents: int) -> int:
	return castle.castle_name.hash() + key.hash() % 100003 + int(castle.sabotage.get("count", 0)) * 7919 + agents * 17


static func roll(chance: float, seed_value: int) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randf() < chance


# --- Against a robber baron's camp ---------------------------------------------------

func against_camp(castle: CastleState, camp: BaronCamp, barons: BaronRules, mission: Variant, agents: Variant, now: float) -> Dictionary:
	## Sends agents into a camp: {"error"} or {"error": "", "success", "stolen", "chance"}.
	var key := camp_key(camp.id)
	var why := check(castle, key, mission, agents, now)
	if why != "":
		return {"error": why}
	var n := int(agents)
	var chance := camp_chance(n, camp.level)
	var success := roll(chance, seed_for(castle, key, n))
	_send(castle, key, n, now)
	var stolen := {}
	if success:
		if mission == "steal":
			var stock := {}
			for r: String in barons.for_camp(camp).loot(camp.level):
				stock[r] = floori(float(barons.for_camp(camp).loot(camp.level)[r]) * steal_share)
			stolen = BaronCamp._carried(stock, carry(n, castle.keep_level()))
			for r: String in stolen:
				castle.resources[r] = float(castle.resources.get(r, 0.0)) + float(stolen[r])
		else:
			camp.weak_until = now + walls_time
			camp.weak_cut = walls_cut
	return {"error": "", "success": success, "stolen": stolen, "chance": chance}


# --- Against a player (the server decides; the game shows the odds) -----------------

func steal_from(their: CastleState, resource: String, agents: int, my_keep: int) -> int:
	## How much of a resource agents carry off from this castle.
	if not their.resources.has(resource):
		return 0
	var free := maxf(float(their.resources[resource]) - their.hidden(), 0.0)
	return mini(carry(agents, my_keep), floori(free * steal_share))


func burned(their: CastleState) -> Dictionary:
	## What burning the stores destroys: a share of every resource above the hidden cellars.
	var out := {}
	for r: String in their.resources:
		var n := floori(maxf(float(their.resources[r]) - their.hidden(), 0.0) * burn_share)
		if n > 0:
			out[r] = n
	return out


static func walls_factor(castle: CastleState, t: float) -> float:
	## What's left of a castle's wall strength at time t after sabotage.
	if float(castle.sabotage.get("walls_until", 0.0)) > t:
		return 1.0 - float(castle.sabotage.get("walls_cut", 0.0))
	return 1.0


func mission_name(mission: String) -> String:
	return String(missions.get(mission, {}).get("name", mission))
