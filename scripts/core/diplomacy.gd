class_name Diplomacy
extends RefCounted
## Who is at war with whom, and how the factions feel about each other.
## Owned and saved by Economy. Times are unix seconds, like the castles'.
##
## Relations run from -100 (hatred) to 100 (friendship). Wars change hands
## during play: the AI factions declare war on factions they dislike and make
## peace when a war goes badly or drags on. Peace brings a truce during which
## neither side may declare war again. The player rules player_faction, so
## that faction never decides anything on its own; AI factions losing a war
## against it offer peace instead (see offers).

const RELATION_MIN := -100.0
const RELATION_MAX := 100.0
const TRUCE := 1800.0              ## seconds of truce after a peace
const MAX_WARS := 2                ## an AI faction starts no war while fighting this many
const MIN_WAR := 1200.0            ## AI factions fight at least this long before peace
const LONG_WAR := 3600.0          ## after this, AI factions tire of a war
const HATE := -30.0                ## below this relation, an AI faction may declare war
const START_AT_WAR := -60.0        ## relation of factions at war when a game starts
const DECLARE_PENALTY := 40.0      ## relation lost with the faction you declare war on
const WARMONGER := 5.0             ## relation lost with everyone else when you do
const PEACE_BONUS := 20.0          ## relation gained by making peace
const GIFT_WINDOW := 3600.0        ## gifts to one faction count together over this long
const GIFT_MAX := 30.0             ## relation gifts can buy per faction per window
const PEACE_NEEDED := 25.0         ## willingness an AI faction needs to accept peace
const GOLD_PER_POINT := 10.0       ## gold that adds one point of willingness
const OFFER_TIME := 300.0          ## seconds a peace offer to the player stays open
## War score for winning a battle, per enemy soldier killed, and for castles.
const SCORE_BATTLE := 5.0
const SCORE_PER_KILL := 0.1
const SCORE_CAPTURE := 25.0
const SCORE_SACK := 10.0
const SCORE_MAX := 100.0
const NEWS_KEPT := 30

var factions: Array[String] = []
var names := {}         ## faction -> its name, for the news
var player_faction := ""
var relations := {}     ## pair key -> relation
var leanings := {}      ## pair key -> the relation it drifts back to (old friends, old rivals)
var wars := {}          ## pair key -> {"since": time, "score": score for the pair's first faction}
var truces := {}        ## pair key -> time the truce ends
var gifts := {}         ## pair key -> {"since": time, "total": relation bought}
var offers := {}        ## AI faction -> time its peace offer to the player expires
var news: Array = []    ## newest last: {"time", "text"}


static func create_new(faction_ids: Array, starting_wars: Array, player: String, now: float) -> Diplomacy:
	var d := Diplomacy.new()
	d.player_faction = player
	for id in faction_ids:
		d.factions.append(String(id))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	for i in d.factions.size():
		for j in range(i + 1, d.factions.size()):
			var k := key(d.factions[i], d.factions[j])
			d.leanings[k] = roundf(rng.randf_range(-45.0, 30.0))
			d.relations[k] = d.leanings[k] + roundf(rng.randf_range(-10.0, 10.0))
	for pair in starting_wars:
		var k := key(pair[0], pair[1])
		d.relations[k] = START_AT_WAR
		d.wars[k] = {"since": now, "score": 0.0}
	return d


static func from_data_files(now: float) -> Diplomacy:
	## A new game's diplomacy from data/factions.json. The player rules the
	## faction of their castle in data/player.json.
	var data := _load_json("res://data/factions.json")
	var ids: Array = []
	for f in data.get("factions", []):
		ids.append(f.id)
	var castle: Dictionary = _load_json("res://data/player.json").get("castle", {})
	var d := create_new(ids, data.get("wars", []), castle.get("faction", ""), now)
	for f in data.get("factions", []):
		d.names[f.id] = f.name
	return d


static func _load_json(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func at_war(a: String, b: String) -> bool:
	return a != b and wars.has(key(a, b))


func relation(a: String, b: String) -> float:
	return 0.0 if a == b else float(relations.get(key(a, b), 0.0))


static func relation_word(value: float) -> String:
	if value <= -50.0:
		return "Hostile"
	if value < HATE / 2.0:
		return "Unfriendly"
	if value <= 15.0:
		return "Neutral"
	if value <= 50.0:
		return "Friendly"
	return "Close friends"


func change_relation(a: String, b: String, delta: float) -> void:
	if a == b:
		return
	relations[key(a, b)] = clampf(relation(a, b) + delta, RELATION_MIN, RELATION_MAX)


func truce_left(a: String, b: String, now: float) -> float:
	return maxf(0.0, float(truces.get(key(a, b), 0.0)) - now)


func enemies_of(a: String) -> Array[String]:
	var out: Array[String] = []
	for f in factions:
		if at_war(a, f):
			out.append(f)
	return out


func war_score(a: String, b: String) -> float:
	## How the war is going for a: positive when a is winning.
	var war: Dictionary = wars.get(key(a, b), {})
	if war.is_empty():
		return 0.0
	var score := float(war.score)
	return score if a < b else -score


func war_length(a: String, b: String, now: float) -> float:
	var war: Dictionary = wars.get(key(a, b), {})
	return 0.0 if war.is_empty() else now - float(war.since)


# --- War and peace -----------------------------------------------------------

func check_declare(a: String, b: String, now: float) -> String:
	## Why a can't declare war on b right now ("" if it can).
	if a == b or not factions.has(a) or not factions.has(b):
		return "No such faction."
	if at_war(a, b):
		return "Already at war."
	var left := truce_left(a, b, now)
	if left > 0.0:
		return "A truce holds for %d more minutes." % ceili(left / 60.0)
	return ""


func declare_war(a: String, b: String, now: float) -> String:
	## a declares war on b. Returns "" or why it can't.
	var why := check_declare(a, b, now)
	if why != "":
		return why
	var k := key(a, b)
	wars[k] = {"since": now, "score": 0.0}
	relations[k] = minf(relation(a, b) - DECLARE_PENALTY, -50.0)
	for f in factions:
		if f != a and f != b:
			change_relation(a, f, -WARMONGER)
	offers.erase(a)
	offers.erase(b)
	_news(now, "%s declared war on %s." % [faction_name(a), faction_name(b)])
	return ""


func make_peace(a: String, b: String, now: float) -> void:
	var k := key(a, b)
	if not wars.has(k):
		return
	wars.erase(k)
	truces[k] = now + TRUCE
	change_relation(a, b, PEACE_BONUS)
	if a == player_faction:
		offers.erase(b)
	elif b == player_faction:
		offers.erase(a)
	_news(now, "%s and %s made peace." % [faction_name(a), faction_name(b)])


func peace_terms(asker: String, target: String, now: float) -> Dictionary:
	## What it takes for target (an AI faction) to accept peace from asker:
	## {"possible": bool, "price": gold (0 means it would accept for nothing),
	## "reason": text}. Factions accept when they are losing, when the war has
	## dragged on, when they like the asker, or for gold.
	if not at_war(asker, target):
		return {"possible": false, "price": 0, "reason": "You are not at war."}
	if offers.has(target):
		return {"possible": true, "price": 0, "reason": "They have offered peace themselves."}
	var standing := war_score(target, asker)
	if standing > 40.0:
		return {"possible": false, "price": 0, "reason": "They are winning and won't hear of peace."}
	var weariness := minf(20.0, war_length(asker, target, now) / 60.0 * 0.5)
	var willing := -standing + weariness + relation(asker, target) / 4.0
	var price := maxi(0, ceili((PEACE_NEEDED - willing) * GOLD_PER_POINT))
	var reason := "They will make peace." if price == 0 else "They want %d gold for peace." % price
	return {"possible": true, "price": price, "reason": reason}


func propose_peace(asker: String, target: String, gold: int, now: float) -> bool:
	## True if target accepts (and peace is made). The caller pays the gold.
	var terms := peace_terms(asker, target, now)
	if not terms.possible or gold < int(terms.price):
		return false
	make_peace(asker, target, now)
	return true


func gift_value(giver: String, receiver: String, gold: int, now: float) -> float:
	## Relation a gift of gold would buy. Bigger gifts buy less per coin, and
	## gifts to one faction can't buy more than GIFT_MAX per GIFT_WINDOW.
	var record: Dictionary = gifts.get(key(giver, receiver), {})
	var spent := 0.0
	if not record.is_empty() and now - float(record.since) < GIFT_WINDOW:
		spent = float(record.total)
	var points := 20.0 * gold / (gold + 200.0)
	return clampf(points, 0.0, GIFT_MAX - spent)


func give_gift(giver: String, receiver: String, gold: int, now: float) -> float:
	## Applies a gift and returns the relation gained. The caller pays the gold.
	var points := gift_value(giver, receiver, gold, now)
	var k := key(giver, receiver)
	var record: Dictionary = gifts.get(k, {})
	if record.is_empty() or now - float(record.since) >= GIFT_WINDOW:
		record = {"since": now, "total": 0.0}
	record.total = float(record.total) + points
	gifts[k] = record
	change_relation(giver, receiver, points)
	return points


func record_battle(winner: String, loser: String, kills: int) -> void:
	_add_score(winner, loser, SCORE_BATTLE + kills * SCORE_PER_KILL)


func record_siege(attacker: String, defender: String, outcome: String) -> void:
	match outcome:
		"captured":
			_add_score(attacker, defender, SCORE_CAPTURE)
		"sacked":
			_add_score(attacker, defender, SCORE_SACK)
		"held":
			_add_score(defender, attacker, SCORE_BATTLE)


func _add_score(winner: String, loser: String, points: float) -> void:
	var k := key(winner, loser)
	if not wars.has(k):
		return
	var war: Dictionary = wars[k]
	var signed := points if winner < loser else -points
	war.score = clampf(float(war.score) + signed, -SCORE_MAX, SCORE_MAX)


# --- The AI factions ---------------------------------------------------------

func think(now: float, rng: RandomNumberGenerator, power: Dictionary, player_protected := false) -> Array:
	## One round of AI diplomacy (Economy calls it every half minute). power
	## maps faction -> military strength. Returns the news it made, as text.
	var made := news.size()
	for k in offers.keys():
		if float(offers[k]) < now:
			offers.erase(k)
	for i in factions.size():
		for j in range(i + 1, factions.size()):
			var a := factions[i]
			var b := factions[j]
			if at_war(a, b):
				_think_war(a, b, now, rng)
			else:
				_think_peace(a, b, now, rng, power, player_protected)
	return news.slice(made).map(func(item: Dictionary) -> String: return item.text)


func _think_war(a: String, b: String, now: float, rng: RandomNumberGenerator) -> void:
	change_relation(a, b, -1.0)
	var length := war_length(a, b, now)
	if length < MIN_WAR:
		return
	var score := war_score(a, b)
	var chance := 0.01 + absf(score) / 1000.0 + (0.03 if length > LONG_WAR else 0.0)
	if a == player_faction or b == player_faction:
		# The AI side only offers; the player decides.
		var ai := b if a == player_faction else a
		if war_score(ai, player_faction) <= -20.0 and not offers.has(ai) and rng.randf() < chance * 2.0:
			offers[ai] = now + OFFER_TIME
			_news(now, "%s offers you peace." % faction_name(ai))
		return
	if rng.randf() < chance:
		make_peace(a, b, now)


func _think_peace(a: String, b: String, now: float, rng: RandomNumberGenerator, power: Dictionary,
		player_protected: bool) -> void:
	# Relations wander, drifting back to how the two usually get on.
	var k := key(a, b)
	change_relation(a, b, rng.randf_range(-3.0, 3.0) + (float(leanings.get(k, 0.0)) - relation(a, b)) * 0.05)
	if truce_left(a, b, now) > 0.0 or relation(a, b) >= HATE:
		return
	# Whichever side is stronger (and not the player's) may strike.
	var pa := float(power.get(a, 0.0))
	var pb := float(power.get(b, 0.0))
	var aggressor := a if pa >= pb else b
	var victim := b if aggressor == a else a
	if aggressor == player_faction:
		aggressor = victim
		victim = player_faction
	if victim == player_faction and player_protected:
		return
	if enemies_of(aggressor).size() >= MAX_WARS:
		return
	if float(power.get(aggressor, 0.0)) < 0.8 * float(power.get(victim, 0.0)):
		return
	var chance := 0.01 + (HATE - relation(a, b)) / 2000.0
	if rng.randf() < chance:
		declare_war(aggressor, victim, now)


# --- News and saving ---------------------------------------------------------

func faction_name(id: String) -> String:
	if id == player_faction:
		return "You"
	return names.get(id, id.capitalize())


func _news(now: float, text: String) -> void:
	# Reads better with "You" in the middle of a sentence too.
	text = text.replace(" You.", " you.").replace("and You ", "and you ")
	news.append({"time": now, "text": text})
	if news.size() > NEWS_KEPT:
		news = news.slice(news.size() - NEWS_KEPT)


func to_dict() -> Dictionary:
	return {"relations": relations, "wars": wars, "truces": truces, "gifts": gifts,
			"offers": offers, "news": news}


static func from_dict(data: Dictionary, now: float) -> Diplomacy:
	## Restores saved diplomacy over a fresh start, so factions added to the
	## data files since the save still get relations.
	var d := from_data_files(now)
	for k in data.get("relations", {}):
		d.relations[k] = float(data.relations[k])
	d.wars = data.get("wars", d.wars)
	d.truces = data.get("truces", {})
	d.gifts = data.get("gifts", {})
	d.offers = data.get("offers", {})
	d.news = data.get("news", [])
	return d
