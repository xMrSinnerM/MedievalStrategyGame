class_name LoginRewards
extends RefCounted
## The Royal Gift: a reward for coming back each day (00:00 UTC, like the
## daily tasks). A week of gifts that grow towards day 7; missing a day
## starts the week over, and every full week in a row makes them a little
## bigger. The numbers are in data/login.json; server/rules/login.ts is the
## same rules for the online game. Kept in castle.login: the last day taken,
## days in a row and days in all.

const PATH := "res://data/login.json"
const DAY := 86400

var gift_name := ""
var giver := ""
var line := ""
var scale: Array = [1]
var week_bonus := 0.0
var max_weeks := 0
var days: Array = []       ## a reward per day of the week: {resources, troops?}


static func load_default() -> LoginRewards:
	var gifts := LoginRewards.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	gifts.load_from(data)
	return gifts


func load_from(data: Dictionary) -> void:
	gift_name = data.get("name", "")
	giver = data.get("giver", "")
	line = data.get("line", "")
	scale = data.get("scale", [1])
	week_bonus = float(data.get("week_bonus", 0.0))
	max_weeks = int(data.get("max_weeks", 0))
	days = data.get("days", [])


static func day_of(t: float) -> int:
	return int(floor(t / DAY))


static func taken_today(castle: CastleState, now: float) -> bool:
	return int(castle.login.last) == day_of(now)


static func current_streak(castle: CastleState, now: float) -> int:
	## Days in a row as it stands now (0 once a day was missed).
	return int(castle.login.streak) if int(castle.login.last) >= day_of(now) - 1 else 0


static func next_streak(castle: CastleState, now: float) -> int:
	## The days in a row today's gift counts (or counted, once taken).
	var last := int(castle.login.last)
	var today := day_of(now)
	if last == today:
		return int(castle.login.streak)
	return int(castle.login.streak) + 1 if last == today - 1 else 1


func week_day(streak: int) -> int:
	## The day of the week's gifts (0 to 6) a streak lands on.
	return (maxi(streak, 1) - 1) % maxi(days.size(), 1)


func weeks_kept(streak: int) -> int:
	## Full weeks in a row before this day, as far as they add to the gifts.
	return mini((maxi(streak, 1) - 1) / maxi(days.size(), 1), max_weeks)


func reward(day: int, keep: int, weeks := 0) -> Dictionary:
	## The gift on day `day` of the week (0 to 6) for this keep level, after
	## `weeks` full weeks in a row.
	var mult := float(scale[clampi(keep, 1, scale.size()) - 1]) * (1.0 + week_bonus * weeks)
	var base: Dictionary = days[clampi(day, 0, days.size() - 1)]
	var resources := {}
	for r: String in base.get("resources", {}):
		resources[r] = roundi(float(base.resources[r]) * mult)
	var out := {"resources": resources}
	if base.has("troops"):
		out["troops"] = base.troops.duplicate()
	return out


func today_reward(castle: CastleState, now: float) -> Dictionary:
	var streak := next_streak(castle, now)
	return reward(week_day(streak), castle.keep_level(), weeks_kept(streak))


func check_claim(castle: CastleState, now: float) -> String:
	## Why the gift can't be taken now ("" if it can).
	if days.is_empty():
		return "There's no gift."
	if taken_today(castle, now):
		return "You already have today's gift. Come back tomorrow."
	return ""


func claim(castle: CastleState, now: float) -> String:
	## Takes today's gift. Returns "" or why not.
	var why := check_claim(castle, now)
	if why != "":
		return why
	var streak := next_streak(castle, now)
	QuestBook.give(castle, reward(week_day(streak), castle.keep_level(), weeks_kept(streak)))
	castle.login.last = day_of(now)
	castle.login.streak = streak
	castle.login.total = int(castle.login.total) + 1
	return ""
