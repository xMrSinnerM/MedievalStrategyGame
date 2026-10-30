class_name SeasonRules
extends RefCounted
## Seasons: one a calendar month (UTC). The castle earns renown in a season
## from what it does in it (building levels finished, soldiers trained, robber
## barons beaten, loot brought home and, online, battles against players),
## counted from its lifetime stats as they were when the season began. Renown
## milestones give rewards on a track; online, the players and alliances with
## the most renown when the month ends win prizes and a title for that
## season. The numbers are in data/seasons.json; server/rules/seasons.ts is
## the same rules for the online game.
##
## Kept in castle.season: the season it counts for (key, months since year
## 0), the stats it counts from (base), track rewards claimed, the season
## before ({key, points, claimed}) and the season titles won (honours).

const PATH := "res://data/seasons.json"
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August",
	"September", "October", "November", "December"]

var weights := {}
var scale: Array = [1]
var track: Array = []          ## [{renown, reward}]
var renowned := ""
var player_prizes: Array = []  ## [{top, id, title, reward}]
var alliance_prizes: Array = []
var _titles := {}              ## prize id -> title, and "renowned"

static var _default: SeasonRules


static func load_default() -> SeasonRules:
	var rules := SeasonRules.new()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not data is Dictionary:
		push_error("Could not read %s" % PATH)
		data = {}
	rules.load_from(data)
	_default = rules
	return rules


static func shared() -> SeasonRules:
	## The rules from data/seasons.json, loaded once (for title names).
	return _default if _default != null else load_default()


func load_from(data: Dictionary) -> void:
	weights = data.get("renown", {})
	scale = data.get("scale", [1])
	track = data.get("track", [])
	renowned = data.get("renowned", "")
	player_prizes = data.get("players", [])
	alliance_prizes = data.get("alliances", [])
	_titles = {"renowned": renowned}
	for p: Dictionary in player_prizes + alliance_prizes:
		_titles[String(p.id)] = String(p.title)


# --- The calendar --------------------------------------------------------------

static func key_of(t: float) -> int:
	## The season (month) a time falls in, as months since year 0.
	var d := Time.get_datetime_dict_from_unix_time(int(floor(t)))
	return int(d.year) * 12 + int(d.month) - 1


static func start_of(key: int) -> float:
	return float(Time.get_unix_time_from_datetime_dict({"year": key / 12, "month": key % 12 + 1, "day": 1,
		"hour": 0, "minute": 0, "second": 0}))


static func end_of(key: int) -> float:
	return start_of(key + 1)


static func name_of(key: int) -> String:
	## "October 2026".
	return "%s %d" % [MONTHS[key % 12], key / 12]


# --- Renown --------------------------------------------------------------------

static func snapshot(castle: CastleState) -> Dictionary:
	var out := {"levels": float(QuestBook.total_levels(castle))}
	for k: String in ["trained", "barons", "looted", "pvp_won", "pvp_held"]:
		out[k] = float(castle.stats.get(k, 0))
	return out


func breakdown(castle: CastleState) -> Dictionary:
	## Renown this season by what earned it.
	var now_counts := snapshot(castle)
	var base: Dictionary = castle.season.base
	var out := {}
	for k: String in weights:
		out[k] = maxf(0.0, float(now_counts.get(k, 0.0)) - float(base.get(k, now_counts.get(k, 0.0)))) * float(weights[k])
	return out


func renown(castle: CastleState) -> int:
	var total := 0.0
	var parts := breakdown(castle)
	for k: String in parts:
		total += float(parts[k])
	return int(floor(total))


func roll(castle: CastleState, now: float) -> bool:
	## Starts the castle's new season once the month has turned, keeping what
	## it earned in the one before for the ranking. Returns whether it did.
	var key := key_of(now)
	var s := castle.season
	if int(s.key) == key:
		return false
	if int(s.key) >= 0:
		s.last = {"key": int(s.key), "points": renown(castle), "claimed": false}
	s.key = key
	s.base = snapshot(castle)
	s.track = 0
	return true


# --- The track -----------------------------------------------------------------

func track_reward(index: int, keep: int) -> Dictionary:
	var mult := float(scale[clampi(keep, 1, scale.size()) - 1])
	var base: Dictionary = track[index].reward
	var resources := {}
	for r: String in base.get("resources", {}):
		resources[r] = roundi(float(base.resources[r]) * mult)
	var out := {"resources": resources}
	if base.has("troops"):
		out["troops"] = base.troops.duplicate()
	return out


func check_track(castle: CastleState) -> String:
	## Why the next track reward can't be claimed ("" if it can).
	var i := int(castle.season.track)
	if i >= track.size():
		return "Every reward this season is claimed."
	if renown(castle) < int(track[i].renown):
		return "You need %d renown for that." % int(track[i].renown)
	return ""


func claim_track(castle: CastleState, now: float) -> String:
	## Claims the next track reward. Returns "" or why not.
	roll(castle, now)
	var why := check_track(castle)
	if why != "":
		return why
	var i := int(castle.season.track)
	QuestBook.give(castle, track_reward(i, castle.keep_level()))
	castle.season.track = i + 1
	if i + 1 == track.size():
		_honour(castle, "season:%d:renowned" % int(castle.season.key))
	return ""


# --- Prizes (online) -----------------------------------------------------------

static func prize_for(prizes: Array, place: int) -> Dictionary:
	## The first prize whose `top` covers this place (1 is first), or {}.
	if place < 1:
		return {}
	for p: Dictionary in prizes:
		if place <= int(p.top):
			return p
	return {}


static func check_prize(castle: CastleState) -> String:
	var last: Dictionary = castle.season.last
	if last.is_empty() or int(last.get("points", 0)) <= 0:
		return "You earned no renown last season."
	if last.get("claimed", false):
		return "You already have last season's prize."
	return ""


func claim_prize(castle: CastleState, place: int, alliance_place: int, now: float) -> String:
	## Claims last season's prizes for your place and your alliance's.
	## Returns "" or why not.
	roll(castle, now)
	var why := check_prize(castle)
	if why != "":
		return why
	var key := int(castle.season.last.key)
	for p: Dictionary in [prize_for(player_prizes, place), prize_for(alliance_prizes, alliance_place)]:
		if p.is_empty():
			continue
		QuestBook.give(castle, p.reward)
		_honour(castle, "season:%d:%s" % [key, p.id])
	castle.season.last.claimed = true
	return ""


static func _honour(castle: CastleState, key: String) -> void:
	if not castle.season.honours.has(key):
		castle.season.honours.append(key)


func title_text(key: String) -> String:
	## "Champion of October 2026" for "season:<key>:champion"; "" if unknown.
	var parts := key.split(":")
	if parts.size() != 3 or parts[0] != "season" or not parts[1].is_valid_int() or not _titles.has(parts[2]):
		return ""
	if parts[2] == "renowned":
		return "%s of %s" % [renowned, name_of(int(parts[1]))]
	return "%s of %s" % [_titles[parts[2]], name_of(int(parts[1]))]
