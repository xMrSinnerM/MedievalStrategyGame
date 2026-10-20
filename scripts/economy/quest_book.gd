class_name QuestBook
extends RefCounted
## Quests: one story chain told by the castle's steward, and daily tasks
## picked anew every day (00:00 UTC) with a coffer for finishing them all.
## The numbers are in data/quests.json; server/rules/quests.ts is the same
## rules for the online game.
##
## Progress is read from the castle itself (its buildings, garrison and
## lifetime stats), so nothing has to be counted twice. Daily tasks count
## from the stats as they were when the day began (castle.quests.base).

const PATH := "res://data/quests.json"
const DAY := 86400

var narrator := ""
var chapters: Array = []       ## [{title, intro}]
var story: Array = []          ## [{chapter, title, text, goal, reward}]
var daily := {}                ## {picks, scale, kinds, coffer}


static func load_default() -> QuestBook:
	var book := QuestBook.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	book.load_from(data)
	return book


func load_from(data: Dictionary) -> void:
	narrator = data.get("narrator", "")
	chapters = data.get("chapters", [])
	story = data.get("story", [])
	daily = data.get("daily", {"picks": 0, "scale": [1], "kinds": {}, "coffer": {}})


static func day_of(t: float) -> int:
	return int(floor(t / DAY))


static func total_levels(castle: CastleState) -> int:
	## All the castle's building levels added up.
	var n := 0
	for b in castle.buildings:
		n += int(b.level)
	return n


func progress(castle: CastleState, goal: Dictionary) -> Array:
	## [have, need] for a goal.
	var kind := String(goal.get("kind", ""))
	var need := int(goal.get("count", 1)) if kind == "building" else int(goal.get("amount", 0))
	var have := 0.0
	match kind:
		"building":
			for b in castle.buildings:
				if b.type == goal.get("type", "") and int(b.level) >= int(goal.get("level", 1)):
					have += 1.0
		"soldiers":
			have = castle.troop_count()
		"stat":
			have = float(castle.stats.get(goal.get("stat", ""), 0))
		"production":
			have = float(castle.production_per_hour().get(goal.get("resource", ""), 0.0))
		"storage":
			have = castle.storage_capacity()
		"levels":
			have = total_levels(castle)
	return [int(floor(have)), need]


func _keep_index(keep: int) -> int:
	## The keep level a day's targets and rewards are set by, as an index.
	return clampi(keep, 1, daily.scale.size()) - 1


static func _snapshot(castle: CastleState) -> Dictionary:
	return {"levels": float(total_levels(castle)), "trained": float(castle.stats.trained),
		"spent": float(castle.stats.spent), "barons": float(castle.stats.barons), "looted": float(castle.stats.looted)}


func pick_dailies(castle: CastleState, day: int) -> Array:
	## The kinds of daily task for this day: random, but the same for the castle all day.
	var open: Array = []
	for k: String in daily.kinds:
		if not daily.kinds[k].get("barracks", false) or castle.barracks_level() > 0:
			open.append(k)
	var rng := RandomNumberGenerator.new()
	rng.seed = day * 1000003 + castle.castle_name.hash()
	var out: Array = []
	while out.size() < int(daily.picks) and not open.is_empty():
		var i := int(rng.randi() % open.size())
		out.append(open[i])
		open.remove_at(i)
	return out


func roll_day(castle: CastleState, now: float) -> bool:
	## Starts a new day's tasks if the day has turned. Returns whether it did.
	var day := day_of(now)
	var q := castle.quests
	if int(q.day) == day:
		return false
	q.day = day
	q.keep = _keep_index(castle.keep_level()) + 1
	q.base = _snapshot(castle)
	q.claimed = []
	q.chest = false
	q.picks = pick_dailies(castle, day)
	return true


func daily_target(kind: String, keep: int) -> int:
	return int(daily.kinds[kind].targets[_keep_index(keep)])


func daily_text(kind: String, keep: int) -> String:
	var target := daily_target(kind, keep)
	if target == 1 and daily.kinds[kind].has("one"):
		return String(daily.kinds[kind].one)
	return String(daily.kinds[kind].text) % target


func daily_progress(castle: CastleState, index: int) -> Array:
	## [have, need] for today's daily task `index`.
	var q := castle.quests
	var kind := String(q.picks[index])
	var now_count := float(total_levels(castle)) if kind == "levels" else float(castle.stats.get(kind, 0))
	return [maxi(0, int(floor(now_count - float(q.base.get(kind, 0.0))))), daily_target(kind, int(q.keep))]


func daily_reward(kind: String, keep: int) -> Dictionary:
	var scale := float(daily.scale[_keep_index(keep)])
	var resources := {}
	var base: Dictionary = daily.kinds[kind].reward
	for r: String in base:
		resources[r] = roundi(float(base[r]) * scale)
	return {"resources": resources}


func coffer_streak(castle: CastleState) -> int:
	## The streak the coffer would count if opened today.
	var q := castle.quests
	return mini(int(q.streak) + 1, int(daily.coffer.max_streak)) if int(q.chest_day) == int(q.day) - 1 else 1


static func current_streak(castle: CastleState) -> int:
	## Days in a row the coffer was opened, as it stands now (0 once a day was missed).
	var q := castle.quests
	return int(q.streak) if int(q.chest_day) >= int(q.day) - 1 else 0


func coffer_reward(keep: int, streak: int) -> Dictionary:
	var c: Dictionary = daily.coffer
	var scale := float(daily.scale[_keep_index(keep)])
	var mult := scale * (1.0 + float(c.streak_bonus) * (streak - 1))
	var resources := {}
	for r: String in c.reward:
		resources[r] = roundi(float(c.reward[r]) * mult)
	var reward := {"resources": resources}
	if streak >= int(c.max_streak):
		var troops := {}
		for u: String in c.streak_troops:
			troops[u] = roundi(float(c.streak_troops[u]) * scale)
		reward["troops"] = troops
	return reward


func current_story(castle: CastleState) -> Dictionary:
	## The story quest being worked on, or {} when the chain is done.
	var i := int(castle.quests.story)
	return story[i] if i >= 0 and i < story.size() else {}


func check_claim(castle: CastleState, kind: String, index := 0) -> String:
	## Why this quest reward can't be claimed now ("" if it can).
	var q := castle.quests
	match kind:
		"story":
			var quest := current_story(castle)
			if quest.is_empty():
				return "Every quest is done."
			var p := progress(castle, quest.goal)
			return "" if p[0] >= p[1] else "That quest isn't done yet."
		"daily":
			if index < 0 or index >= q.picks.size():
				return "There's no such task."
			if q.claimed.has(index):
				return "You already have that reward."
			var p := daily_progress(castle, index)
			return "" if p[0] >= p[1] else "That task isn't done yet."
		"chest":
			if q.chest:
				return "You already opened today's coffer."
			if q.picks.is_empty() or q.claimed.size() < q.picks.size():
				return "Finish today's tasks first."
			return ""
	return "There's no such quest."


static func give(castle: CastleState, reward: Dictionary) -> void:
	## Gives a quest reward in full (even past the storage cap).
	var res: Dictionary = reward.get("resources", {})
	for r: String in res:
		if castle.resources.has(r):
			castle.resources[r] = float(castle.resources[r]) + float(res[r])
	var troops: Dictionary = reward.get("troops", {})
	for unit: String in troops:
		if castle.rules.has_unit(unit):
			castle.troops[unit] = int(castle.troops.get(unit, 0)) + int(troops[unit])


func claim(castle: CastleState, kind: String, index: int, now: float) -> String:
	## Claims the story quest, daily task `index` or the coffer ("story",
	## "daily", "chest"). Returns "" or why not.
	roll_day(castle, now)
	var why := check_claim(castle, kind, index)
	if why != "":
		return why
	var q := castle.quests
	match kind:
		"story":
			give(castle, current_story(castle).reward)
			q.story = int(q.story) + 1
		"daily":
			give(castle, daily_reward(String(q.picks[index]), int(q.keep)))
			q.claimed.append(index)
		"chest":
			var streak := coffer_streak(castle)
			give(castle, coffer_reward(int(q.keep), streak))
			q.chest = true
			q.streak = streak
			q.chest_day = q.day
	return ""


func can_claim_anything(castle: CastleState) -> bool:
	## True when the story quest, a daily task or the coffer is ready to claim.
	if check_claim(castle, "story") == "" or check_claim(castle, "chest") == "":
		return true
	for i in castle.quests.picks.size():
		if check_claim(castle, "daily", i) == "":
			return true
	return false
