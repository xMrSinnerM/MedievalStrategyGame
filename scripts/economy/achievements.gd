class_name Achievements
extends RefCounted
## Achievements and titles: lifetime goals in three tiers (bronze, silver,
## gold). A tier is earned for good the moment its count is reached, gives
## a reward to claim and a title the lord can show on their castle. The
## numbers are in data/achievements.json; server/rules/achievements.ts is the
## same rules for the online game.
##
## Like the quests, progress is read from the castle itself (its buildings,
## garrison, research, commanders and lifetime stats). Earned tiers are kept
## in castle.achievements, so a count that falls again (soldiers at home, a
## broken coffer streak) doesn't take them away.

const PATH := "res://data/achievements.json"

var list: Array = []          ## [{id, name, text, measure, needs: [3], titles: [3], online?}]
var points: Array = []        ## points per tier
var tier_names: Array = []
var rewards: Array = []       ## a reward per tier: {resources}
var _by_id := {}


static func load_default() -> Achievements:
	var book := Achievements.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	book.load_from(data)
	return book


func load_from(data: Dictionary) -> void:
	list = data.get("list", [])
	points = data.get("points", [])
	tier_names = data.get("tier_names", [])
	rewards = data.get("rewards", [])
	_by_id.clear()
	for a: Dictionary in list:
		_by_id[String(a.id)] = a


func get_def(id: String) -> Dictionary:
	return _by_id.get(id, {})


func shown(online: bool) -> Array:
	## The achievements that count in this game (online ones only online).
	return list.filter(func(a: Dictionary) -> bool: return online or not a.get("online", false))


static func measure(castle: CastleState, def: Dictionary) -> int:
	## Where the castle stands now on what this achievement counts.
	var m := String(def.get("measure", ""))
	if m.begins_with("stat:"):
		return int(floor(float(castle.stats.get(m.substr(5), 0))))
	match m:
		"levels":
			return QuestBook.total_levels(castle)
		"keep":
			return castle.keep_level()
		"story":
			return int(castle.quests.story)
		"streak":
			return int(castle.quests.streak)
		"logins":
			return int(castle.login.total)
		"research":
			var n := 0
			for study: String in castle.research:
				n += int(castle.research[study])
			return n
		"commander":
			var best := 0
			for c: Dictionary in castle.armoury.get("commanders", []):
				best = maxi(best, int(c.get("level", 0)))
			return best
		"soldiers":
			return castle.troop_count()
	return 0


static func reached(def: Dictionary, value: int) -> int:
	## How many tiers this count reaches.
	var n := 0
	for need in def.get("needs", []):
		if value >= int(need):
			n += 1
	return n


func earned(castle: CastleState, id: String) -> int:
	return int(castle.achievements.tiers.get(id, 0))


func claimed(castle: CastleState, id: String) -> int:
	return int(castle.achievements.claimed.get(id, 0))


func note(castle: CastleState, online: bool) -> Array:
	## Records the tiers the castle has reached since last time. Returns them
	## as [[id, tier], ...] (tier from 1), for the news.
	var fresh: Array = []
	for def: Dictionary in shown(online):
		var id := String(def.id)
		var now_tier := reached(def, measure(castle, def))
		var had := earned(castle, id)
		if now_tier > had:
			castle.achievements.tiers[id] = now_tier
			for t in range(had + 1, now_tier + 1):
				fresh.append([id, t])
	return fresh


func check_claim(castle: CastleState, id: String) -> String:
	## Why the next reward of this achievement can't be claimed ("" if it can).
	if get_def(id).is_empty():
		return "There's no such achievement."
	if earned(castle, id) == 0:
		return "You haven't earned that yet."
	if claimed(castle, id) >= earned(castle, id):
		return "You already have that reward."
	return ""


func reward(tier: int) -> Dictionary:
	## The reward for a tier (from 1).
	return rewards[tier - 1] if tier >= 1 and tier <= rewards.size() else {}


func claim(castle: CastleState, id: String, online: bool) -> String:
	## Gives the next earned reward of this achievement. Returns "" or why not.
	note(castle, online)
	var why := check_claim(castle, id)
	if why != "":
		return why
	var tier := claimed(castle, id) + 1
	QuestBook.give(castle, reward(tier))
	castle.achievements.claimed[id] = tier
	return ""


func can_claim_anything(castle: CastleState) -> bool:
	for def: Dictionary in list:
		if check_claim(castle, String(def.id)) == "":
			return true
	return false


func score(castle: CastleState) -> int:
	## Achievement points: the points of every tier earned.
	var n := 0
	for id: String in castle.achievements.tiers:
		for t in mini(int(castle.achievements.tiers[id]), points.size()):
			n += int(points[t])
	return n


static func title_key(id: String, tier: int) -> String:
	return "%s:%d" % [id, tier]


func title_text(key: String) -> String:
	## "the Builder" for "builder:1", "Champion of October 2026" for a season
	## title ("season:<month>:champion", SeasonRules); "" for no title or one
	## that doesn't exist.
	if key.begins_with("season:"):
		return SeasonRules.shared().title_text(key)
	var parts := key.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return ""
	var titles: Array = get_def(parts[0]).get("titles", [])
	var tier := int(parts[1])
	return String(titles[tier - 1]) if tier >= 1 and tier <= titles.size() else ""


func check_title(castle: CastleState, key: String) -> String:
	## Why this title can't be shown ("" if it can; "" also clears it).
	if key == "":
		return ""
	if title_text(key) == "":
		return "There's no such title."
	if key.begins_with("season:"):
		return "" if castle.season.honours.has(key) else "You haven't earned that title yet."
	var parts := key.split(":")
	return "" if earned(castle, parts[0]) >= int(parts[1]) else "You haven't earned that title yet."


func set_title(castle: CastleState, key: String) -> String:
	var why := check_title(castle, key)
	if why == "":
		castle.achievements.title = key
	return why


func shown_title(castle: CastleState) -> String:
	## The title the castle shows, or "".
	return title_text(String(castle.achievements.title))


static func with_title(who: String, title: String) -> String:
	## "Valentin the Builder", or "Valentin, Baron-Breaker" for titles that aren't "the ...".
	if title == "":
		return who
	return "%s %s" % [who, title] if title.begins_with("the ") else "%s, %s" % [who, title]
