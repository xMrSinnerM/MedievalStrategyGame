extends Node
## Autoload that owns every castle's economy and the save file. It keeps the
## castles running in real time while the game is open, and when the game
## starts it catches them up on the time that passed while it was closed.
## NPC castles are run by NpcBrain under the same rules as the player's.

signal changed   ## something in a castle changed (resources tick, build finished, order given)
## A castle changed hands. Owners are faction ids, or "player".
signal castle_captured(castle_id: String, old_owner: String, new_owner: String)
## Wars or truces changed; news holds what happened, as sentences.
signal diplomacy_changed(news: Array)
## One of your armies fought a robber baron camp (the report is like a battle's).
signal attack_resolved(report: Dictionary)
## An army set out, fought or came home.
signal marches_changed
## Online: the other players' castles changed (see `others`).
signal others_changed
## Online: armies sent against players set out, fought or came home (see `raids`).
signal raids_changed
## Online: a spy came back with news of this player (see `spy_reports`).
signal spy_returned(player_name: String)
## Online: your agents came back from another player's castle (the server's
## answer: success, chance, mission, resource, agents, stolen, target).
signal agents_returned(result: Dictionary)
## Online: the server sent the leaderboard (see `leaderboard`).
signal leaderboard_changed
## Online: the server sent your alliance's view (see `alliance`); `error` is
## why the last alliance order was refused, or "".
signal alliance_changed(error: String)
## Online: new chat messages arrived, or the server refused one you sent (error).
signal chat_changed(error: String)
## Online: carts or defenders sent to allies, or theirs to you, set out, arrived or came home (see `aid`).
signal aid_changed
## Online: news about help between allies, as a sentence (a cart arrived, your defenders fought).
signal aid_news(text: String)
## Online: the server sent the timed events on now and next (see `events`).
signal events_changed
## Online: robber baron camps came or went (invader camps of a Baron Invasion).
signal barons_changed
## Online: the server sent the event leaderboard (see `event_board`).
signal event_board_changed
## Online: the server sent the Ember Horde's ranking (see `horde_board`).
signal horde_board_changed
## Online: the server sent the season's ranking (see `season_board`).
signal season_board_changed
## Online: the server sent the alliance war's standings (see `war_board`).
signal war_board_changed
## Online: the server sent this week's alliance tournament (see `tournament`).
signal tournament_changed
## Online: the server sent the game owner's panel (see `admin_view`), or refused an owner's order.
signal admin_changed(error: String)
## your outpost was founded, or carts left or arrived
signal outpost_changed
## Who holds the resource villages changed (or, online, the server sent them again).
signal villages_changed
## Achievement tiers your castle has just earned, as a line for the news.
signal achievement_news(text: String)
## Online: the server sent the market (see `market`); error is "" unless an order was refused.
signal market_changed(error: String)

## Games are kept in SLOTS save slots under save_dir (slot_1.json ...).
const SLOTS := 3
## Where single-save versions of the game kept their save; moved to slot 1.
const OLD_SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const TICK := 1.0              ## seconds between economy updates
const AUTOSAVE := 30.0           ## seconds between autosaves
const DIPLOMACY_TICK := 30.0     ## seconds between rounds of AI diplomacy
const MAIN_CASTLE := "player_castle"   ## id of your first castle, which can't be captured
## Seed offset for what a beaten camp drops (server/rules/marches.ts DROP_SEED).
const DROP_SEED := 31337
## Lords leave your main castle alone until its keep reaches this level.
const PROTECTED_BELOW_KEEP := 2
## A new NPC castle starts with this many hours of building behind it (by seed).
const NPC_HEAD_START_HOURS := Vector2(12.0, 72.0)
## A fortress you look around has been built up for this many hours, plus
## FORTRESS_HOURS_PER_LEVEL for each level above 1 (fortress_castle()).
const FORTRESS_HOURS_BASE := 24.0
const FORTRESS_HOURS_PER_LEVEL := 24.0

var rules: BuildingRules
var player_castle: CastleState
var castles: Array[CastleState] = []   ## the player's first, then NPC castles
## Wars, truces and relations between the factions.
var diplomacy: Diplomacy
## Robber baron camps and how far you have levelled each of them.
var baron_rules: BaronRules
## The story quests and daily tasks (data/quests.json).
var quest_book: QuestBook
## Achievements and titles (data/achievements.json).
var achievements: Achievements
## The Royal Gift for coming back each day (data/login.json).
var login_rewards: LoginRewards
## Seasons: renown each month, its track and, online, the ranked prizes (data/seasons.json).
var season_rules: SeasonRules
## Treasure chests and their Wheel of Fortune (data/chests.json).
var chest_rules: ChestRules
## Bandit camps, merchant caravans and treasure sites along the roads (data/encounters.json).
var encounter_rules: EncounterRules
var weather_rules: WeatherRules
var sabotage_rules: SabotageRules
## The achievement tiers already announced (null: take the next ones silently).
var _known_tiers: Variant = null
## Commanders and gear (data/gear.json).
var gear_rules: GearRules
var outpost_rules: OutpostRules
var village_rules: VillageRules
## Capitals: the towns, held and attacked like villages (CapitalRules); their
## states are in village_states too.
var capital_rules: CapitalRules
var capitals: Array = []
## The resource villages on the map (server/world/world.json), and who holds
## each: id -> {"owner" ("" for the militia), "guard", "taken_at", "paid_at"}.
## Online the server's view adds "mine", "ally", "tag", "peace_until" and "stock".
var villages: Array = []
var village_states := {}
## Your outpost (OutpostRules): {name, region, x, y, carts, next_cart}, {} until
## you found one. Its castle is in `castles` with the id OutpostRules.OUTPOST_ID.
var outpost := {}
var barons: Array[BaronCamp] = []
## Your armies on the road: {"id", "camp", "army", "depart", "arrive", "back",
## "state" ("out" or "home"), "survivors", "loot"}. Times are unix seconds.
var marches: Array = []
var _next_march := 1

## Lords whose home castle changed since data/parties.json: party id -> castle id.
var homes := {}
## Lords whose faction lost its last castle; they have left the map.
var exiled := {}
## Filled by sync_castles: castle id -> map position, and lord party id -> faction.
var castle_positions := {}
var lord_factions := {}
## The faction the player's own castles fly the banner of.
var player_faction := ""

## True while your warband stands at your castle, so troops can change hands.
## Set by the world map; not saved (the warband starts at the castle).
var warband_home := false

## Folder holding the slot files (tests point it elsewhere).
var save_dir := "user://saves"
## The slot being played (1 .. SLOTS).
var slot := 1

## Playing online: the server owns your castle, camps and marches, and this
## only shows them, guessing ahead between the server's answers. There are no
## NPC castles, lords or diplomacy online yet, and nothing is saved here.
var online := false
## Seconds to add to this computer's clock to get the server's.
static var clock_offset := 0.0
## How often the online game asks the server for news, in seconds.
const ONLINE_POLL := 20.0
## How often it asks where the other players' castles are.
const WORLD_POLL := 60.0

## Online: the other players' castles, [{"name", "home_x", "home_y", "level", "protected"}].
var others: Array = []
## Online: armies you sent against players, and theirs coming for you, as the
## server lists them ({"id", "attacker_name", "defender_name", "from", "to",
## "depart", "arrive", "back", "state", "mine", "army"}).
var raids: Array = []
## Online: what your spies last saw, by player name (see spy()).
var spy_reports := {}
## Fortresses already built up to look around (fortress_castle()), by id and level.
var _fortress_looks := {}
## Online: you can't be attacked before this (Unix time), while your keep is small.
var protected_until := 0.0
## Fights between players (data/pvp.json).
var pvp := {}
## Online: the mightiest castles as the server last sent them:
## {"players": [{"name", "level", "might", "barons_beaten"}], "me", "rank", "total"}.
var leaderboard := {}
## Online: the alliance screen's view from the server: "alliance" (yours, with
## your "role", or null), "members", "requests", "invited", "invites" (to
## you), "asked" (alliances you asked to join), "alliances" (all), "rules",
## "you" (your name).
var alliance := {}
## Online: chat messages, oldest first, as the server sent them:
## [{"id", "channel" ("world" or "alliance"), "name", "tag", "text", "at"}].
var chat_messages: Array = []
## Online: whether you're in an alliance, so its chat channel is open.
var chat_in_alliance := false
## Online: true once the server's first chat answer has come.
var chat_loaded := false
## Set by the chat box while it is open, so new messages come quicker.
var chat_open := false
## How often the online game asks for chat messages, with the chat box open and closed.
const CHAT_POLL_OPEN := 4.0
const CHAT_POLL_CLOSED := 15.0
## Messages kept for the chat box.
const CHAT_KEPT := 150
## Online: carts and defenders you sent to allies ("mine") and theirs coming to
## or standing in your castle, as the server lists them: {"id", "kind"
## ("resources" or "troops"), "sender_name", "receiver_name", "resources",
## "army", "depart", "arrive", "leave", "back", "mine"}.
var aid: Array = []
## Helping allies (data/aid.json): carry_per_keep_level, station_hours.
var aid_rules := {}
## Online: the alliance war's rules (data/wars.json).
var war_rules := {}
## Online: the market as the server last sent it: "offers" (everyone else's,
## newest first, each {"id", "seller_name", "tag", "give", "give_amount",
## "want", "want_amount", "proceeds", "posted", "expires"}), "mine" (your open
## offers), "sold" (your recent sales, with "buyer_name" and "sold_at") and
## "rates" ({"wood>stone": stone asked per wood in recent sales}).
var market := {}
## The market (data/market.json): goods, unlock_keep, lot_per_keep_level,
## max_offers, min_rate, max_rate, fee, offer_hours.
var market_rules := {}
## Online: timed events as the server last sent them: {"active": [...],
## "upcoming": [...], "recent": [...]}, each {"id", "name", "description",
## "effects", "start", "end"} in Unix seconds (data/events.json); "recent" has
## the last Baron Invasion and Ember Horde once they are over.
var events := {}
## Online: the start of the last Baron Invasion you played in, and your event points in it.
var event_key := 0.0
var event_points := 0
## Online: how many of that invasion's reward tiers you have claimed.
var event_claimed := 0
## Online: the event leaderboard as the server last sent it: {"event", "players":
## [{"name", "points", "tag"}], "me", "rank", "total"}.
var event_board := {}
## Online: the start of the last Ember Horde you played in, your horde points
## in it, and {"trophies", "bought": {item id: n}, "ranked"} (your war
## trophies, Trophy Market purchases and whether you took your prize).
var horde_key := 0.0
var horde_points := 0
var horde_state := {}
## Online: the Ember Horde's ranking as the server last sent it: {"event",
## "players": [{"name", "points", "tag"}], "me", "rank", "total", "prize"}.
var horde_board := {}
## Online: the season's ranking as the server last sent it: {"key", "end",
## "players": [{"name", "points", "tag"}], "alliances": [{"tag", "name",
## "points"}], "me": {"points", "place"}, "last": {"key", "points", "place",
## "alliance_place", "claimed"} or {}}.
var season_board := {}
## Online: the alliance war as the server last sent it: {"season": {start, end,
## "alliances"}, "last": {start, end, "alliances"}, "capitals", "mine",
## "prize": {prize, claimed, can_claim, why}, "rules"} (data/wars.json).
var war_board := {}
## Online: this week's alliance tournament, its bracket and your prize, as the server sent it.
var tournament := {}
## Online: true when your account has the game owner's tools (the server decides).
var is_admin := false
## Online, for the owner: {"events": [{id, name, hours, on, start, end}], "players": [names], "log": [{at, action, details}]}.
var admin_view := {}

var _seen_report := 0          ## newest server battle report already shown
var _poll_timer := 0.0
var _world_timer := 0.0
var _chat_timer := 0.0
var _asked_for := 0.0          ## march time we last asked the server about
var _tick_timer := 0.0
var _save_timer := 0.0
var _diplomacy_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _loaded := false


func _ready() -> void:
	_rng.randomize()
	# Through the tree: tests load this script where autoload names don't resolve.
	get_node("/root/EventBus").battle_fought.connect(record_battle)


func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	rules = BuildingRules.load_default()
	baron_rules = BaronRules.load_default()
	quest_book = QuestBook.load_default()
	login_rewards = LoginRewards.load_default()
	season_rules = SeasonRules.load_default()
	chest_rules = ChestRules.load_default()
	encounter_rules = EncounterRules.load_default()
	weather_rules = WeatherRules.load_default()
	sabotage_rules = SabotageRules.load_default()
	achievements = Achievements.load_default()
	gear_rules = GearRules.load_default()
	outpost_rules = OutpostRules.load_default()
	_load_villages()
	if not load_game():
		new_game()
	gear_rules.sync(player_castle)
	_known_tiers = player_castle.achievements.tiers.duplicate()


func save_path(n := -1) -> String:
	return "%s/slot_%d.json" % [save_dir, slot if n < 0 else n]


func has_save(n := -1) -> bool:
	## Whether slot n (any slot if n is -1) holds a game.
	_move_old_save()
	if n > 0:
		return FileAccess.file_exists(save_path(n))
	for k in range(1, SLOTS + 1):
		if FileAccess.file_exists(save_path(k)):
			return true
	return false


func last_played_slot() -> int:
	## The slot saved most recently, for Continue (0 if there is none).
	var best := 0
	var best_time := -1.0
	for k in range(1, SLOTS + 1):
		var info := slot_info(k)
		if not info.is_empty() and info.saved_at > best_time:
			best_time = info.saved_at
			best = k
	return best


func slot_info(n: int) -> Dictionary:
	## A summary of the game in slot n for the menus, or {} if it is empty:
	## saved_at, keep (main castle's keep level), castles (yours), soldiers.
	if not has_save(n):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path(n)))
	if not data is Dictionary:
		return {}
	var info := {"saved_at": float(data.get("saved_at", 0.0)), "keep": 1, "castles": 0, "soldiers": 0}
	for c in data.get("castles", []):
		if c.get("owner", "") != "player":
			continue
		info.castles += 1
		for group in [c.get("troops", {}), c.get("field", {})]:
			for unit in group:
				info.soldiers += int(group[unit])
		if c.get("id", "") == MAIN_CASTLE:
			for b in c.get("buildings", []):
				if b.get("type", "") == "keep":
					info.keep = int(b.get("level", 1))
	return info


func delete_slot(n: int) -> void:
	if has_save(n):
		DirAccess.remove_absolute(save_path(n))


func begin_new(n := 1) -> void:
	## Starts a fresh game in slot n from the title screen (replacing what was there).
	rules = BuildingRules.load_default()
	baron_rules = BaronRules.load_default()
	quest_book = QuestBook.load_default()
	login_rewards = LoginRewards.load_default()
	season_rules = SeasonRules.load_default()
	chest_rules = ChestRules.load_default()
	encounter_rules = EncounterRules.load_default()
	weather_rules = WeatherRules.load_default()
	sabotage_rules = SabotageRules.load_default()
	achievements = Achievements.load_default()
	gear_rules = GearRules.load_default()
	outpost_rules = OutpostRules.load_default()
	_load_villages()
	slot = n
	_loaded = true
	new_game()
	gear_rules.sync(player_castle)
	_known_tiers = player_castle.achievements.tiers.duplicate()


func begin_load(n := 1) -> void:
	## Continues the game in slot n from the title screen.
	rules = BuildingRules.load_default()
	baron_rules = BaronRules.load_default()
	quest_book = QuestBook.load_default()
	login_rewards = LoginRewards.load_default()
	season_rules = SeasonRules.load_default()
	chest_rules = ChestRules.load_default()
	encounter_rules = EncounterRules.load_default()
	weather_rules = WeatherRules.load_default()
	sabotage_rules = SabotageRules.load_default()
	achievements = Achievements.load_default()
	gear_rules = GearRules.load_default()
	outpost_rules = OutpostRules.load_default()
	_load_villages()
	slot = n
	_loaded = true
	if not load_game():
		new_game()
	gear_rules.sync(player_castle)
	_known_tiers = player_castle.achievements.tiers.duplicate()


func _move_old_save() -> void:
	## Saves from before save slots become slot 1.
	if save_dir == "user://saves" and FileAccess.file_exists(OLD_SAVE_PATH) and not FileAccess.file_exists(save_path(1)):
		DirAccess.make_dir_recursive_absolute(save_dir)
		DirAccess.rename_absolute(OLD_SAVE_PATH, save_path(1))


func sync_castles(settlements: Array, parties: Array = []) -> void:
	## Gives every castle on the map an economy: the player's settlement uses
	## the player's castle, every other castle gets an NPC economy (created
	## with a head start the first time it appears, then saved like any other).
	## Each party's warband belongs to its "home" castle and starts with the
	## party's troops as spearmen.
	## It also writes each castle's current holder back into the settlement
	## ("faction", and "player" for yours), so the map shows captured castles.
	if online:
		# Online there are no NPC castles or lords yet: only where yours stands.
		for s in settlements:
			if s.id == MAIN_CASTLE:
				castle_positions[s.id] = castle_positions.get(s.id, Vector2(s.position[0], s.position[1]))
			if s.get("player", false):
				player_faction = s.get("faction", player_faction)
		return
	var added := false
	for p in parties:
		if p.get("player", false):
			player_faction = p.get("faction", "")
		else:
			lord_factions[p.id] = p.get("faction", "")
	for s in settlements:
		if s.get("type", "") != "castle":
			continue
		castle_positions[s.id] = Vector2(s.position[0], s.position[1])
		if s.id == player_castle.id:
			player_castle.castle_name = s.get("name", player_castle.castle_name)
			continue
		var castle := get_castle(s.id)
		if castle == null:
			castles.append(new_npc_castle(rules, s.id, s.name, s.faction, now()))
			added = true
		else:
			_mark_holder(s, castle.owner)
	for p in parties:
		var home := get_castle(home_of(p.id, p.get("home", "")))
		if home != null and not home.field_ready:
			home.field = {"spearman": int(p.get("troops", 20))}
			home.field_ready = true
			added = true
	if added:
		save_game()
		changed.emit()


func home_of(party_id: String, default := "") -> String:
	## The castle whose warband this lord leads now ("" once exiled).
	if exiled.has(party_id):
		return ""
	return homes.get(party_id, default)


func capture(castle: CastleState, new_owner: String, parties: Array = [], settlements: Array = []) -> void:
	## Hands a castle to a new owner (a faction id or "player"). Its garrison
	## and training queue are lost; buildings and stock stay. Lords based
	## there move, with their warband, to their faction's nearest castle, or
	## leave the map if their faction has none left. Pass GameData.parties
	## (each lord's first home) and GameData.settlements (updated to match).
	## The caller saves the game.
	var old_owner := castle.owner
	castle.owner = new_owner
	castle.troops = {}
	castle.training.clear()
	castle.hunger = 0.0
	var warband := castle.field
	castle.field = {}
	for p in parties:
		if p.get("player", false) or home_of(p.id, p.get("home", "")) != castle.id:
			continue
		var faction: String = lord_factions.get(p.id, p.get("faction", ""))
		var refuge := _nearest_castle_of(faction, castle_positions.get(castle.id, Vector2.ZERO))
		if refuge == null:
			exiled[p.id] = true
			homes.erase(p.id)
			continue
		homes[p.id] = refuge.id
		for unit: String in warband:
			refuge.field[unit] = refuge.field.get(unit, 0) + warband[unit]
		refuge.field_ready = true
		warband = {}
	for s in settlements:
		if s.id == castle.id:
			_mark_holder(s, new_owner)
	castle_captured.emit(castle.id, old_owner, new_owner)
	changed.emit()


func find_main_castle() -> CastleState:
	## The castle you started with; captured castles are yours too but never main.
	var fallback: CastleState = null
	for c in castles:
		if c.id == MAIN_CASTLE:
			return c
		if fallback == null and not c.is_npc():
			fallback = c
	return fallback


func newcomer_protected() -> bool:
	## Newcomer's protection: no sieges of your main castle while you find your feet.
	return player_castle != null and player_castle.keep_level() < PROTECTED_BELOW_KEEP


func castles_of(owner: String) -> Array[CastleState]:
	var out: Array[CastleState] = []
	for c in castles:
		if c.owner == owner:
			out.append(c)
	return out


func _nearest_castle_of(faction: String, from: Vector2) -> CastleState:
	var best: CastleState = null
	var best_d := INF
	for c in castles:
		if c.owner != faction:
			continue
		var d := from.distance_to(castle_positions.get(c.id, Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = c
	return best


func _mark_holder(settlement: Dictionary, owner: String) -> void:
	if owner == "player":
		settlement.faction = player_faction
		settlement.player = true
	else:
		settlement.faction = owner
		settlement.erase("player")


static func new_npc_castle(p_rules: BuildingRules, id: String, castle_name: String, faction: String, at: float) -> CastleState:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var head_start := rng.randf_range(NPC_HEAD_START_HOURS.x, NPC_HEAD_START_HOURS.y) * 3600.0
	var castle := CastleState.create_new(p_rules, id, castle_name, faction, at - head_start)
	NpcBrain.catch_up(castle, at)
	return castle


func sync_barons(camps: Array) -> void:
	## Makes sure every camp listed (id, name, position, optional level) has a
	## state in this game; camps keep the level you raised them to.
	var added := false
	for c: Dictionary in camps:
		if get_baron(c.id) == null:
			barons.append(BaronCamp.create(c.id, c.get("name", c.id),
					Vector2(c.position[0], c.position[1]), int(c.get("level", 1))))
			added = true
	if added:
		save_game()


func home_position() -> Vector2:
	## Where your armies march from: your main castle on the map.
	return castle_positions.get(MAIN_CASTLE, Vector2.ZERO)


func march_time_to(camp: BaronCamp) -> float:
	return baron_rules.march_time(home_position().distance_to(camp.position)) * player_castle.march_factor() * weather_slow(camp.position)


func weather_slow(to: Vector2) -> float:
	## How much the weather slows a march from home to `to` setting off now (1 = not at all).
	return weather_rules.march_slow(home_position(), to, now()) if weather_rules != null else 1.0


func weather_on_march(to: Vector2) -> Dictionary:
	## The rain or storm a march from home to `to` would set off through now ({} for none).
	return weather_rules.march_cell(home_position(), to, now()) if weather_rules != null else {}


func check_attack(camp_id: String, army: Dictionary, waves: Array = [], tools := {}, commander := 0) -> String:
	## Why this army can't be sent against the camp ("" if it can). With
	## `waves`, the army must be their sum (Battle.waves_army()); `tools` are
	## attack tools from your store for each wall; `commander` the id of the
	## commander to lead it (0 for none).
	var camp := get_baron(camp_id)
	if camp == null:
		return "No such camp."
	if not camp.is_ready(now()):
		return "The camp is still rebuilding."
	var bad := _check_waves(waves)
	if bad != "":
		return bad
	bad = check_tools(tools)
	if bad != "":
		return bad
	var lead: Variant = gear_rules.check_lead(player_castle, commander, now())
	if lead is String:
		return lead
	var total := 0
	for unit: String in army:
		if int(army[unit]) < 0 or int(army[unit]) > int(player_castle.troops.get(unit, 0)):
			return "Your garrison doesn't have that many soldiers."
		total += int(army[unit])
	if total <= 0:
		return "Choose some soldiers to send."
	return ""


func send_attack(camp_id: String, army: Dictionary, waves: Array = [], tools := {}, commander := 0) -> String:
	## Sends soldiers from your main castle's garrison against a camp, in
	## `waves` if given (see Battle.siege(); the army is then their sum), with
	## siege `tools` for its walls, led by `commander` (an id, 0 for none).
	## They march there, fight, and come home with what they can carry; the
	## tools are used up, and the commander is away until they are home.
	if not waves.is_empty():
		army = Battle.waves_army(waves)
	var why := check_attack(camp_id, army, waves, tools, commander)
	if why != "":
		return why
	var sent := {}
	for unit: String in army:
		if int(army[unit]) > 0:
			sent[unit] = int(army[unit])
			player_castle.troops[unit] = int(player_castle.troops[unit]) - int(army[unit])
	var t := now()
	var travel := march_time_to(get_baron(camp_id))
	var march := {"id": _next_march, "camp": camp_id, "army": sent, "depart": t,
			"arrive": t + travel, "back": t + 2.0 * travel, "state": "out", "survivors": {}, "loot": {}}
	var order := {"action": "attack", "camp": camp_id, "army": sent}
	if not waves.is_empty():
		march["waves"] = waves
		order["waves"] = waves
	var kit := Battle.clean_tools(tools)
	if not kit.is_empty():
		player_castle.use_tools(kit)
		march["tools"] = kit
		order["tools"] = kit
	var lead: Variant = gear_rules.check_lead(player_castle, commander, t)
	# A lead with id 0 is research alone, without a commander.
	if lead is Dictionary:
		march["lead"] = lead
		if int(lead.id) > 0:
			gear_rules.commander(player_castle, lead.id).away_until = float(march.back)
			order["commander"] = int(lead.id)
	marches.append(march)
	_next_march += 1
	if online:
		get_node("/root/Online").order(order)
	save_game()
	changed.emit()
	marches_changed.emit()
	return ""


func troops_away() -> int:
	var n := 0
	for m: Dictionary in marches:
		var side: Dictionary = m.army if m.state == "out" else m.survivors
		for unit: String in side:
			n += int(side[unit])
	for a: Dictionary in aid:
		if a.get("mine", false) and a.kind == "troops":
			for unit: String in a.army:
				n += int(a.army[unit])
	return n


func advance_marches(t: float) -> void:
	## Fights the battles and brings home the armies whose time has come, in
	## order, including those that happened while the game was closed.
	var events: Array = []
	for m: Dictionary in marches:
		if m.state == "out" and t >= float(m.arrive):
			events.append([float(m.arrive), m])
		elif m.state == "home" and t >= float(m.back):
			events.append([float(m.back), m])
		elif m.state == "out" and t >= float(m.back):
			events.append([float(m.arrive), m])
	if events.is_empty():
		return
	events.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for e: Array in events:
		var m: Dictionary = e[1]
		if m.state == "out":
			_fight_camp(m)
		if m.state == "home" and t >= float(m.back):
			_come_home(m)
	marches = marches.filter(func(m: Dictionary) -> bool: return m.state != "done")
	save_game()
	marches_changed.emit()


func _fight_camp(m: Dictionary) -> void:
	if m.has("village"):
		_fight_village(m)
		return
	var camp := get_baron(m.camp)
	m.state = "home"
	if camp == null or not camp.is_ready(float(m.arrive)):
		# Someone else got there first; the camp lies in ashes.
		m.survivors = m.army
		attack_resolved.emit({"player": "a", "baron": true, "empty": true, "defender": camp.camp_name if camp else "",
				"winner": "a", "a": {}, "b": {}, "loot": 0, "place": ""})
		return
	var lead: Dictionary = m.get("lead", {})
	var seed_value := int(m.id) * 7919 + hash(m.camp)
	var result := camp.attack(baron_rules, rules, m.army, seed_value, float(m.arrive), m.get("waves", []),
			m.get("tools", {}), lead.get("fx", {}))
	m.survivors = result.survivors
	m.loot = result.loot
	if result.winner == "a":
		player_castle.stats.barons = int(player_castle.stats.barons) + 1
	var led := {}
	if int(lead.get("id", 0)) > 0:
		var xp: int = gear_rules.xp_win_per_level * int(result.level) if result.winner == "a" else gear_rules.xp_loss
		led = gear_rules.add_xp(player_castle, int(lead.id), xp)
	var item := gear_rules.roll_drop(int(result.level), seed_value + DROP_SEED) if result.winner == "a" else {}
	var bag_full := not item.is_empty() and not gear_rules.give(player_castle, item)
	attack_resolved.emit({
		"lead": led, "gear": item, "bag_full": bag_full,
		"player": "a", "baron": true, "attacker": "Your army", "defender": camp.camp_name,
		"attacker_faction": player_faction, "defender_faction": "barons", "place": camp.camp_name,
		"winner": result.winner, "a": result.a, "b": result.b, "loot": 0, "spoils": result.loot,
		"walls": result.walls, "courtyard": result.courtyard, "tools": result.get("tools", {}),
		"level": result.level, "leveled": result.leveled, "new_level": camp.level,
		"defeats": camp.defeats, "needed": baron_rules.for_camp(camp).defeats_needed(camp.level),
		"home_in": maxf(0.0, float(m.back) - now()),
	})


func _come_home(m: Dictionary) -> void:
	for unit: String in m.survivors:
		player_castle.troops[unit] = int(player_castle.troops.get(unit, 0)) + int(m.survivors[unit])
	var cap := player_castle.storage_capacity()
	for r: String in m.loot:
		var have := float(player_castle.resources.get(r, 0.0))
		player_castle.resources[r] = maxf(have, minf(cap, have + float(m.loot[r])))
		player_castle.stats.looted = float(player_castle.stats.looted) + float(m.loot[r])
	m.state = "done"


func march_target(m: Dictionary) -> Dictionary:
	## Where a march is headed: {"name", "position"} of its camp or village ({} if gone).
	if m.has("village"):
		var info := village_info(String(m.village))
		return {} if info.is_empty() else {"name": info.name, "position": village_position(info.id)}
	var camp := get_baron(String(m.get("camp", "")))
	return {} if camp == null else {"name": camp.camp_name, "position": camp.position}


func get_baron(camp_id: String) -> BaronCamp:
	for b in barons:
		if b.id == camp_id:
			return b
	return null


func faction_of(owner: String) -> String:
	## The faction a castle owner belongs to ("player" is the player's faction).
	return player_faction if owner == "player" else owner


func faction_power() -> Dictionary:
	## Rough military strength per faction: soldiers in its castles and
	## warbands, plus 100 for each castle.
	var power := {}
	for c in castles:
		var f := faction_of(c.owner)
		power[f] = float(power.get(f, 0.0)) + 100.0 + c.troop_count() + c.field_count()
	return power


func record_battle(report: Dictionary) -> void:
	## Counts a battle (EventBus.battle_fought) towards the war between its factions.
	if diplomacy == null:
		return
	var a := faction_of(report.get("attacker_faction", ""))
	var d := faction_of(report.get("defender_faction", ""))
	var won_a: bool = report.get("winner", "") == "a"
	if report.get("siege", false):
		diplomacy.record_siege(a, d, report.get("outcome", "held"))
		return
	var losers: Dictionary = report.get("b" if won_a else "a", {})
	var kills := 0
	for unit in losers:
		kills += int(losers[unit].get("lost", 0))
	diplomacy.record_battle(a if won_a else d, d if won_a else a, kills)


# --- The player's diplomacy (gold comes from the main castle) -----------------

func declare_war(faction: String) -> String:
	## Returns "" or why war can't be declared.
	var why := diplomacy.declare_war(player_faction, faction, now())
	if why == "":
		_diplomacy_done()
	return why


func propose_peace(faction: String, gold := 0) -> bool:
	if gold > int(player_castle.resources.get("gold", 0.0)):
		return false
	if not diplomacy.propose_peace(player_faction, faction, gold, now()):
		return false
	player_castle.resources.gold = float(player_castle.resources.get("gold", 0.0)) - gold
	_diplomacy_done()
	return true


func send_gift(faction: String, gold: int) -> float:
	## Returns the relation gained (0 if the gold isn't there).
	if gold <= 0 or gold > int(player_castle.resources.get("gold", 0.0)) or faction == player_faction:
		return 0.0
	player_castle.resources.gold = float(player_castle.resources.gold) - gold
	var points := diplomacy.give_gift(player_faction, faction, gold, now())
	save_game()
	changed.emit()
	return points


func _diplomacy_done() -> void:
	save_game()
	changed.emit()
	diplomacy_changed.emit([diplomacy.news.back().text] if not diplomacy.news.is_empty() else [])


func get_castle(castle_id: String) -> CastleState:
	for c in castles:
		if c.id == castle_id:
			return c
	return null


static func now() -> float:
	return Time.get_unix_time_from_system() + clock_offset


func new_game() -> void:
	online = false
	clock_offset = 0.0
	castles.clear()
	homes.clear()
	exiled.clear()
	player_castle = CastleState.create_new(rules, MAIN_CASTLE, "Your Castle", "player", now())
	castles.append(player_castle)
	outpost = {}
	village_states = {}
	diplomacy = Diplomacy.from_data_files(now())
	barons.clear()
	marches.clear()
	save_game()
	changed.emit()


func load_game() -> bool:
	online = false
	clock_offset = 0.0
	_move_old_save()
	if not FileAccess.file_exists(save_path()):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path()))
	if not data is Dictionary or int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("Save file is unreadable or from another version; starting a new game.")
		return false
	castles.clear()
	homes = data.get("homes", {})
	exiled.clear()
	for id in data.get("exiled", []):
		exiled[id] = true
	for c in data.get("castles", []):
		castles.append(CastleState.from_dict(rules, c))
	diplomacy = Diplomacy.from_dict(data.get("diplomacy", {}), now())
	barons.clear()
	for b in data.get("barons", []):
		barons.append(BaronCamp.from_dict(b))
	marches = data.get("marches", [])
	_next_march = int(data.get("next_march", 1))
	outpost = data.get("outpost", {})
	village_states = data.get("villages", {})
	player_castle = find_main_castle()
	if player_castle == null:
		return false
	# Catch up on everything that happened while the game was closed.
	var t := now()
	_deliver_carts(t)
	for c in castles:
		if c.is_npc():
			NpcBrain.catch_up(c, t)
		else:
			c.advance_to(t)
	advance_marches(t)
	_collect_villages(t)
	changed.emit()
	return true


func save_game() -> void:
	if online:
		return   # the server keeps the online game
	var list: Array = []
	for c in castles:
		list.append(c.to_dict())
	DirAccess.make_dir_recursive_absolute(save_dir)
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f == null:
		push_error("Could not write %s" % save_path())
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "saved_at": now(), "castles": list,
			"homes": homes, "exiled": exiled.keys(),
			"diplomacy": diplomacy.to_dict() if diplomacy != null else {},
			"barons": barons.map(func(b: BaronCamp) -> Dictionary: return b.to_dict()),
			"marches": marches, "next_march": _next_march, "outpost": outpost, "villages": village_states}, "\t", true, true))
	f.close()


func _process(delta: float) -> void:
	if not _loaded:
		return
	if online:
		_process_online(delta)
		return
	_tick_timer += delta
	if _tick_timer >= TICK:
		_tick_timer = 0.0
		var t := now()
		_deliver_carts(t)
		for c in castles:
			c.advance_to(t)
			if c.is_npc():
				NpcBrain.think(c, t)
		advance_marches(t)
		_collect_villages(t)
		quest_book.roll_day(player_castle, t)
		season_rules.roll(player_castle, t)
		gear_rules.sync(player_castle)
		achievements.note(player_castle, false)
		_announce_achievements()
		changed.emit()
	_diplomacy_timer += delta
	if _diplomacy_timer >= DIPLOMACY_TICK and diplomacy != null:
		_diplomacy_timer = 0.0
		var made := diplomacy.think(now(), _rng, faction_power(), newcomer_protected())
		if not made.is_empty():
			diplomacy_changed.emit(made)
	_save_timer += delta
	if _save_timer >= AUTOSAVE:
		_save_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _loaded:
		save_game()


# --- Online ---------------------------------------------------------------------

func begin_online(answer: Dictionary) -> void:
	## Starts the online game from the server's answer to "state" or "join".
	rules = BuildingRules.load_default()
	baron_rules = BaronRules.load_default()
	quest_book = QuestBook.load_default()
	login_rewards = LoginRewards.load_default()
	season_rules = SeasonRules.load_default()
	chest_rules = ChestRules.load_default()
	encounter_rules = EncounterRules.load_default()
	weather_rules = WeatherRules.load_default()
	sabotage_rules = SabotageRules.load_default()
	achievements = Achievements.load_default()
	_known_tiers = null
	gear_rules = GearRules.load_default()
	outpost_rules = OutpostRules.load_default()
	_load_villages()
	online = true
	_loaded = true
	slot = 0
	castles.clear()
	homes.clear()
	exiled.clear()
	castle_positions.clear()
	diplomacy = Diplomacy.from_data_files(now())
	player_castle = CastleState.create_new(rules, MAIN_CASTLE, "Your Castle", "player", now())
	castles.append(player_castle)
	outpost = {}
	village_states = {}
	barons.clear()
	marches = []
	warband_home = false
	_seen_report = 0
	for r in answer.get("reports", []):
		_seen_report = maxi(_seen_report, int(r.get("id", 0)))
	_poll_timer = 0.0
	_asked_for = 0.0
	others = []
	raids = []
	spy_reports = {}
	leaderboard = {}
	alliance = {}
	chat_messages = []
	chat_in_alliance = false
	chat_loaded = false
	_chat_timer = 0.0
	aid = []
	events = {}
	event_key = 0.0
	event_points = 0
	event_claimed = 0
	event_board = {}
	horde_key = 0.0
	horde_points = 0
	horde_state = {}
	horde_board = {}
	war_board = {}
	tournament = {}
	is_admin = false
	admin_view = {}
	protected_until = 0.0
	if pvp.is_empty():
		pvp = get_node("/root/GameData").load_json("res://data/pvp.json")
	if aid_rules.is_empty():
		aid_rules = get_node("/root/GameData").load_json("res://data/aid.json")
	if war_rules.is_empty():
		war_rules = get_node("/root/GameData").load_json("res://data/wars.json")
	if market_rules.is_empty():
		market_rules = get_node("/root/GameData").load_json("res://data/market.json")
	market = {}
	_world_timer = WORLD_POLL
	apply_server(answer)
	get_node("/root/Online").order({"action": "alliance"})
	get_node("/root/Online").order({"action": "chat", "after": 0})
	get_node("/root/Online").order({"action": "admin"})


func end_online() -> void:
	online = false
	others = []
	raids = []
	aid = []
	_loaded = false
	clock_offset = 0.0


func apply_server(answer: Dictionary) -> void:
	## Replaces your castle, camps and marches with the server's, and shows
	## the battle reports that are new.
	if not online:
		return
	if answer.has("now"):
		clock_offset = float(answer.now) - Time.get_unix_time_from_system()
	var p = answer.get("player")
	if not p is Dictionary:
		return
	player_castle.copy_from(CastleState.from_dict(rules, p.get("castle", {})))
	castle_positions[MAIN_CASTLE] = Vector2(float(p.get("home_x", 0.0)), float(p.get("home_y", 0.0)))
	_take_outpost(p.get("outpost"))
	var listed := {}
	var camps_moved := false
	for c: Dictionary in p.get("camps", []):
		var fresh := BaronCamp.from_dict(c)
		listed[fresh.id] = true
		var camp := get_baron(fresh.id)
		if camp == null:
			barons.append(fresh)
			camps_moved = true
		else:
			camp.level = fresh.level
			camp.defeats = fresh.defeats
			camp.rebuilt_at = fresh.rebuilt_at
			camp.fortress = fresh.fortress
			camp.weak_until = fresh.weak_until
			camp.weak_cut = fresh.weak_cut
	# Invader camps leave when their invasion is over.
	var kept := barons.filter(func(b: BaronCamp) -> bool: return listed.has(b.id))
	if kept.size() != barons.size():
		barons.assign(kept)
		camps_moved = true
	event_key = float(p.get("event_key", 0.0))
	event_points = int(p.get("event_points", 0))
	event_claimed = int(p.get("event_claimed", 0))
	horde_key = float(p.get("horde_key", 0.0))
	horde_points = int(p.get("horde_points", 0))
	horde_state = p.get("horde", {}) if p.get("horde") is Dictionary else {}
	marches = p.get("marches", [])
	_next_march = int(p.get("next_march", _next_march))
	protected_until = float(p.get("protected_until", 0.0))
	if answer.has("raids"):
		raids = answer.raids
		raids_changed.emit()
	if answer.has("aid"):
		aid = answer.aid
		aid_changed.emit()
	if answer.get("events") is Dictionary:
		events = answer.events
		events_changed.emit()
	if answer.get("villages") is Array:
		_take_villages(answer.villages)
	var fresh_reports: Array = []
	for r in answer.get("reports", []):
		if int(r.get("id", 0)) > _seen_report:
			fresh_reports.push_front(r)
	for r in fresh_reports:
		_seen_report = maxi(_seen_report, int(r.id))
		var report: Dictionary = r.get("report", {})
		if report.get("kind", "") == "aid":
			aid_news.emit(aid_text(report))
		elif report.get("kind", "") == "village" and report.get("result", "") != "fought":
			aid_news.emit(village_text(report))
		elif report.get("kind", "") == "gift":
			aid_news.emit(gift_text(report))
		elif report.get("kind", "") == "market":
			aid_news.emit(market_text(report))
		elif report.get("kind", "") == "sabotage":
			if report.get("role", "") == "target":
				aid_news.emit(sabotage_text(report))
		else:
			attack_resolved.emit(_server_report(report))
	if camps_moved:
		barons_changed.emit()
	_announce_achievements()
	changed.emit()
	marches_changed.emit()


func _server_report(r: Dictionary) -> Dictionary:
	## A server battle report in the shape the battle report window expects.
	if r.get("kind", "") == "village":
		var attacking: bool = r.get("role", "") == "attacker"
		return {"player": "a" if attacking else "b", "village": true, "raid": true, "name": r.get("name", ""),
				"other": r.get("other", ""), "attacker": "", "defender": "", "place": r.get("name", ""),
				"winner": r.get("winner", "b"), "a": r.get("a", {}), "b": r.get("b", {}), "loot": 0,
				"spoils": r.get("spoils", {}), "walls": r.get("walls", {}), "courtyard": r.get("courtyard", {}),
				"tools": r.get("tools", {}), "lead": r.get("lead", {}), "captured": r.get("captured", false),
				"no_room": r.get("no_room", false), "level": int(r.get("level", 1)), "resource": r.get("resource", ""),
				"capital": r.get("capital", false)}
	if r.get("kind", "") == "raid":
		var attacking: bool = r.get("role", "") == "attacker"
		var other := String(r.get("name", ""))
		return {"player": "a" if attacking else "b", "raid": true, "role": r.get("role", ""), "name": other,
				"attacker": "Your army" if attacking else other, "defender": other if attacking else "Your castle",
				"attacker_faction": player_faction, "defender_faction": "", "place": "",
				"winner": r.get("winner", "b"), "a": r.get("a", {}), "b": r.get("b", {}), "loot": 0,
				"spoils": r.get("spoils", {}), "wall": float(r.get("wall", 1.0)), "helped_by": r.get("helped_by", []),
				"walls": r.get("walls", {}), "courtyard": r.get("courtyard", {}), "tools": r.get("tools", {}),
				"lead": r.get("lead", {})}
	if r.get("empty", false):
		return {"player": "a", "baron": true, "empty": true, "defender": r.get("name", ""),
				"winner": "a", "a": {}, "b": {}, "loot": 0, "place": ""}
	var back := float(r.get("at", now()))
	for m: Dictionary in marches:
		if int(m.id) == int(r.get("march", -1)):
			back = float(m.back)
	return {
		"player": "a", "baron": true, "attacker": "Your army", "defender": r.get("name", ""),
		"attacker_faction": player_faction, "defender_faction": "barons", "place": r.get("name", ""),
		"winner": r.get("winner", "b"), "a": r.get("a", {}), "b": r.get("b", {}), "loot": 0,
		"spoils": r.get("spoils", {}), "level": int(r.get("level", 1)), "leveled": r.get("leveled", false),
		"new_level": int(r.get("new_level", 1)), "defeats": int(r.get("defeats", 0)),
		"needed": int(r.get("needed", 1)), "home_in": maxf(0.0, back - now()),
		"invader": r.has("event"), "points": int(r.get("points", 0)),
		"horde": r.has("horde"), "trophies": int(r.get("trophies", 0)),
		"walls": r.get("walls", {}), "courtyard": r.get("courtyard", {}), "tools": r.get("tools", {}),
		"lead": r.get("lead", {}), "gear": r.get("gear", {}), "bag_full": r.get("bag_full", false),
		"fortress": r.get("fortress", false),
	}


func _process_online(delta: float) -> void:
	# Run your castle ahead with the same rules so timers and stock move
	# smoothly; the server's next answer replaces it.
	_tick_timer += delta
	if _tick_timer >= TICK:
		_tick_timer = 0.0
		_deliver_carts(now())
		player_castle.advance_to(now())
		if outpost_castle() != null:
			outpost_castle().advance_to(now())
		quest_book.roll_day(player_castle, now())
		season_rules.roll(player_castle, now())
		gear_rules.sync(player_castle)
		achievements.note(player_castle, true)
		_announce_achievements()
		changed.emit()
	# Ask the server for news now and then, and as soon as an army is due
	# to fight or come home.
	_poll_timer += delta
	var due := _next_march_event()
	if _poll_timer >= ONLINE_POLL or (due > 0.0 and now() >= due + 0.5 and due > _asked_for):
		_poll_timer = 0.0
		if due > 0.0 and now() >= due:
			_asked_for = due
		get_node("/root/Online").refresh()
	_world_timer += delta
	if _world_timer >= WORLD_POLL:
		_world_timer = 0.0
		get_node("/root/Online").order({"action": "world"})
		get_node("/root/Online").order({"action": "alliance"})
	# Chat: only when nothing else is waiting, so it never holds up your orders.
	_chat_timer += delta
	if _chat_timer >= (CHAT_POLL_OPEN if chat_open else CHAT_POLL_CLOSED) and not get_node("/root/Online").busy():
		_chat_timer = 0.0
		get_node("/root/Online").order({"action": "chat", "after": last_chat_id()})


func set_others(players: Array) -> void:
	## The server's list of the other players' castles.
	if not online:
		return
	others = players
	others_changed.emit()


func _next_march_event() -> float:
	var due := 0.0
	for m: Dictionary in marches:
		var t := float(m.arrive) if m.state == "out" else float(m.back)
		if due == 0.0 or t < due:
			due = t
	for r: Dictionary in raids:
		var t := float(r.arrive) if r.state == "out" else (float(r.back) if r.get("mine", false) else 0.0)
		if t > 0.0 and (due == 0.0 or t < due):
			due = t
	# Carts arriving, and your defenders coming home.
	for a: Dictionary in aid:
		var t := float(a.arrive) if a.kind == "resources" else (float(a.back) if a.get("mine", false) else 0.0)
		if t > 0.0 and (due == 0.0 or t < due):
			due = t
	return due


# --- Online: other players --------------------------------------------------------

func get_other(player_name: String) -> Dictionary:
	## The other player with this name, as the server last listed them ({} if none).
	for p: Dictionary in others:
		if String(p.name) == player_name:
			return p
	return {}


func visit_player(player_name: String, outpost := false) -> void:
	## Asks the server for another player's buildings (or their outpost's) and
	## opens them on the castle screen when they come (castle_visit_requested).
	get_node("/root/Online").order({"action": "view_castle", "target": player_name, "outpost": outpost})


func _show_visit(seen: Dictionary) -> void:
	var banner: Dictionary = get_node("/root/GameData").player_banner(String(seen.get("name", "")))
	get_node("/root/EventBus").castle_visit_requested.emit(visited_castle(rules, seen, String(banner.id), now()))


static func visited_castle(p_rules: BuildingRules, seen: Dictionary, banner: String, at: float) -> CastleState:
	## Another player's castle as the server showed it (castleView in game.ts):
	## its buildings only, flying their banner.
	var player_name := String(seen.get("name", ""))
	return CastleState.from_dict(p_rules, {
		"id": ("visit-outpost:" if seen.get("outpost", false) else "visit:") + player_name,
		"name": String(seen.get("castle_name", player_name)), "owner": banner,
		"buildings": seen.get("buildings", []), "last_update": at})


func fortress_castle(camp: BaronCamp) -> CastleState:
	## The castle a fortress's lord has built, to look around.
	var key := "%s:%d" % [camp.id, camp.level]
	if not _fortress_looks.has(key):
		_fortress_looks[key] = built_fortress(rules, camp, get_node("/root/GameData").get_settlement(camp.id).get("faction", ""), now())
	return _fortress_looks[key]


static func built_fortress(p_rules: BuildingRules, camp: BaronCamp, faction: String, at: float) -> CastleState:
	## A kingdom's castle economy run for longer the higher the fortress's
	## level: the same every time for the same fortress and level.
	var head_start := (FORTRESS_HOURS_BASE + FORTRESS_HOURS_PER_LEVEL * (camp.level - 1)) * 3600.0
	var castle := CastleState.create_new(p_rules, camp.id, camp.camp_name, faction, at - head_start)
	# A week at a time: catch_up() only builds through the last week it is given.
	var t := at - head_start
	while t < at:
		t = minf(t + NpcBrain.MAX_CATCH_UP, at)
		NpcBrain.catch_up(castle, t)
	return castle


func other_position(player_name: String) -> Vector2:
	var p := get_other(player_name)
	return Vector2(float(p.home_x), float(p.home_y)) if not p.is_empty() else Vector2.ZERO


func march_time_to_player(player_name: String) -> float:
	return baron_rules.march_time(home_position().distance_to(other_position(player_name))) * player_castle.march_factor() \
			* weather_slow(other_position(player_name))


func is_protected() -> bool:
	## Whether you are still under beginner protection.
	return protected_until > now() and player_castle.keep_level() < int(pvp.get("protection_until_keep", 3))


func too_small(level: int) -> bool:
	## Whether a castle at keep `level` is too far below yours to attack.
	return pvp.has("attack_keep_gap") and player_castle.keep_level() - level > int(pvp.attack_keep_gap)


func spy_cost() -> Dictionary:
	return pvp.get("spy_cost", {})


func check_raid(player_name: String, army: Dictionary, waves: Array = [], tools := {}, commander := 0) -> String:
	## Why this army can't be sent against that player ("" if it can). With
	## `waves`, the army must be their sum (Battle.waves_army()).
	var target := get_other(player_name)
	if target.is_empty():
		return "There's no player by that name."
	if target.get("ally", false):
		return "You can't attack a member of your own alliance."
	if target.get("protected", false):
		return "That castle is under beginner protection."
	if too_small(int(target.get("level", 1))):
		return "That castle is too small for you to attack."
	var bad := _check_waves(waves)
	if bad != "":
		return bad
	bad = check_tools(tools)
	if bad != "":
		return bad
	var lead: Variant = gear_rules.check_lead(player_castle, commander, now())
	if lead is String:
		return lead
	var total := 0
	for unit: String in army:
		var n := int(army[unit])
		if n < 0 or n > int(player_castle.troops.get(unit, 0)):
			return "Your garrison doesn't have that many soldiers."
		total += n
	return "" if total > 0 else "Choose some soldiers to send."


func send_raid(player_name: String, army: Dictionary, waves: Array = [], tools := {}, commander := 0) -> String:
	## Sends soldiers from your garrison against another player's castle, in
	## `waves` if given, with siege `tools`, led by `commander` (an id, 0 for
	## none). The server decides; the soldiers, tools and commander leave
	## your castle here straight away.
	if not waves.is_empty():
		army = Battle.waves_army(waves)
	var why := check_raid(player_name, army, waves, tools, commander)
	if why != "":
		return why
	var sent := {}
	for unit: String in army:
		if int(army[unit]) > 0:
			sent[unit] = int(army[unit])
			player_castle.troops[unit] = int(player_castle.troops[unit]) - int(army[unit])
	protected_until = 0.0
	var order := {"action": "attack_player", "target": player_name, "army": sent}
	if not waves.is_empty():
		order["waves"] = waves
	var kit := Battle.clean_tools(tools)
	if not kit.is_empty():
		player_castle.use_tools(kit)
		order["tools"] = kit
	if commander != 0:
		gear_rules.commander(player_castle, commander).away_until = now() + 2.0 * march_time_to_player(player_name)
		order["commander"] = commander
	get_node("/root/Online").order(order)
	changed.emit()
	return ""


func set_layout(castle: CastleState, layout: Dictionary) -> String:
	## Sets how a castle's defenders spread over its walls and courtyard
	## (percentages, see Battle.siege()). Returns "" or why not.
	var why := Battle.check_layout(layout)
	if why != "":
		return why
	var clean := {}
	for key: String in Battle.DEFAULT_LAYOUT:
		clean[key] = int(layout[key])
	castle.layout = clean
	if online and castle == player_castle:
		get_node("/root/Online").order({"action": "set_layout", "layout": clean})
	save_game()
	changed.emit()
	return ""


func check_tools(tools: Dictionary) -> String:
	## Why these attack tools can't go with an attack ("" if they can).
	return Battle.check_tools(rules, tools, "attack", tool_slots(), player_castle.tools)


func tool_slots() -> int:
	## How many attack tools your keep lets you bring to each wall.
	return rules.tool_slots(player_castle.keep_level())


func set_defence_tools(castle: CastleState, tools: Dictionary) -> String:
	## Posts defence tools on a castle's walls. Returns "" or why not.
	var why := castle.set_defence_tools(tools)
	if why != "":
		return why
	if online and castle == player_castle:
		get_node("/root/Online").order({"action": "set_tools", "tools": castle.defence_tools})
	save_game()
	changed.emit()
	return ""


func max_waves() -> int:
	## How many waves your keep lets you send in one attack.
	return Battle.waves_for_keep(player_castle.keep_level())


func _check_waves(waves: Array) -> String:
	return "" if waves.is_empty() else Battle.check_waves(waves, max_waves(), rules)


func spy(player_name: String) -> String:
	## Sends a spy to another player's castle; the news comes with the
	## server's answer (spy_returned).
	if not player_castle.can_afford(spy_cost()):
		return "Not enough gold to send a spy."
	get_node("/root/Online").order({"action": "spy", "target": player_name})
	return ""


func sabotage_camp(camp_id: String, mission: String, agents: int) -> Dictionary:
	## Sends agents into a robber baron's camp: {"error"} or {"error": "",
	## "success", "stolen", "chance"} (SabotageRules.against_camp). Online the
	## server sends them too (the luck comes out the same).
	var camp := get_baron(camp_id)
	if camp == null:
		return {"error": "No such camp."}
	var out := sabotage_rules.against_camp(player_castle, camp, baron_rules, mission, agents, now())
	if out.error != "":
		return out
	if online:
		get_node("/root/Online").order({"action": "sabotage_camp", "camp": camp_id, "mission": mission, "agents": agents})
	else:
		save_game()
	barons_changed.emit()
	changed.emit()
	return out


func sabotage_player(player_name: String, mission: String, resource: String, agents: int) -> String:
	## Online: sends agents into another player's castle. What they did comes
	## with the server's answer (agents_returned).
	var why := sabotage_rules.check(player_castle, SabotageRules.player_key(player_name), mission, agents, now(), true)
	if why != "":
		return why
	get_node("/root/Online").order({"action": "sabotage_player", "target": player_name, "mission": mission,
			"resource": resource, "agents": agents})
	return ""


func ask_leaderboard() -> void:
	## Asks the server for the leaderboard; it arrives with leaderboard_changed.
	get_node("/root/Online").order({"action": "leaderboard"})


# --- Online: alliances ---------------------------------------------------------------

func alliance_order(body: Dictionary) -> void:
	## Sends an alliance order ({"action": "invite", "target": ...}); the new
	## view arrives with alliance_changed.
	get_node("/root/Online").order(body)


func my_alliance() -> Dictionary:
	## Your alliance ({} if you aren't in one): id, name, tag, open, description, role.
	return alliance.get("alliance") if alliance.get("alliance") is Dictionary else {}


func check_found_alliance() -> String:
	## Why you can't found an alliance now ("" if you can).
	var rules: Dictionary = alliance.get("rules", {})
	if not my_alliance().is_empty():
		return "Leave your alliance first."
	if player_castle.keep_level() < int(rules.get("found_keep", 1)):
		return "Founding an alliance needs keep level %d." % int(rules.get("found_keep", 1))
	if not player_castle.can_afford(rules.get("found_cost", {})):
		return "Not enough gold to found an alliance."
	return ""


func found_alliance(alliance_name: String, tag: String) -> String:
	var why := check_found_alliance()
	if why != "":
		return why
	get_node("/root/Online").order({"action": "found_alliance", "name": alliance_name, "tag": tag})
	return ""


func set_alliance(view: Dictionary, error: String) -> void:
	if not online:
		return
	var before = my_alliance().get("id")
	alliance = view
	if my_alliance().get("id") != before and chat_loaded:
		# A new alliance: forget the old one's chat and fetch the new one's recent talk.
		chat_messages = chat_messages.filter(func(m: Dictionary) -> bool: return m.get("channel", "") != "alliance")
		chat_in_alliance = not my_alliance().is_empty()
		get_node("/root/Online").order({"action": "chat", "after": 0})
		chat_changed.emit("")
	alliance_changed.emit(error)


# --- Online: timed events ---------------------------------------------------------------

func events_on() -> Array:
	## The timed events on now (by the server's clock), even if one began
	## since the server's last answer.
	var t := now()
	var out: Array = []
	for e: Dictionary in events.get("active", []) + events.get("upcoming", []):
		if float(e.get("start", 0.0)) <= t and t < float(e.get("end", 0.0)):
			out.append(e)
	return out


func next_event() -> Dictionary:
	## The next timed event to begin ({} if none is known).
	var t := now()
	var best := {}
	for e: Dictionary in events.get("upcoming", []):
		if float(e.start) > t and (best.is_empty() or float(e.start) < float(best.start)):
			best = e
	return best


func event_effect(effect: String) -> float:
	## The product of an effect over the events on now (1.0 when none, and offline).
	var factor := 1.0
	if online:
		for e: Dictionary in events_on():
			factor *= float(e.get("effects", {}).get(effect, 1.0))
	return factor


func baron_loot(level: int, camp: BaronCamp = null) -> Dictionary:
	## What a camp of this level (a fortress, if `camp` is one) drops now,
	## with any event bonus (as the server works it out).
	var loot := (baron_rules if camp == null else baron_rules.for_camp(camp)).loot(level)
	var factor := event_effect("baron_loot")
	if factor != 1.0:
		for r: String in loot:
			loot[r] = floori(int(loot[r]) * factor)
	return loot


func invasion() -> Dictionary:
	## The Baron Invasion on now ({} if none).
	for e: Dictionary in events_on():
		if e.has("invasion"):
			return e
	return {}


func invasion_points() -> int:
	## Your event points in the invasion on now (0 if none).
	var e := invasion()
	return event_points if not e.is_empty() and float(e.start) == event_key else 0


func last_invasion() -> Dictionary:
	## The Baron Invasion on now, or else the last one ({} if none is known).
	var on := invasion()
	if not on.is_empty():
		return on
	for e: Dictionary in events.get("recent", []):
		if e.has("invasion") and float(e.end) <= now():
			return e
	for e: Dictionary in events.get("upcoming", []):
		if e.has("invasion"):
			var last := e.duplicate()
			last.start = float(e.start) - 7 * 86400.0
			last.end = float(e.end) - 7 * 86400.0
			return last
	return {}


func reward_tiers() -> Array:
	## The Baron Invasion's reward tiers: [{"points", "resources", "troops"}].
	return last_invasion().get("invasion", {}).get("rewards", [])


func my_event_points() -> int:
	## Your points in the last Baron Invasion (0 if you didn't play in it).
	var last := last_invasion()
	return event_points if not last.is_empty() and float(last.start) == event_key else 0


func check_reward(tier: int) -> String:
	## Why this reward tier can't be claimed now ("" if it can).
	var tiers := reward_tiers()
	if tier < 0 or tier >= tiers.size():
		return "There's no such reward."
	var claimed := event_claimed if my_event_points() > 0 else 0
	if tier < claimed:
		return "You already have that reward."
	if tier > claimed:
		return "Claim the rewards in order."
	if my_event_points() < int(tiers[tier].points):
		return "That reward needs %d event points." % int(tiers[tier].points)
	return ""


func claim_reward(tier: int) -> String:
	## Asks the server for a reward tier; the castle shows it with the server's answer.
	var why := check_reward(tier)
	if why == "":
		get_node("/root/Online").order({"action": "claim_reward", "tier": tier})
	return why


# --- Online: the Ember Horde ------------------------------------------------------------

func horde_event() -> Dictionary:
	## The Ember Horde on now ({} if none).
	for e: Dictionary in events_on():
		if e.has("horde"):
			return e
	return {}


func last_horde() -> Dictionary:
	## The Ember Horde on now, or else the last one ({} if none is known).
	var on := horde_event()
	if not on.is_empty():
		return on
	for e: Dictionary in events.get("recent", []):
		if e.has("horde") and float(e.end) <= now():
			return e
	for e: Dictionary in events.get("upcoming", []):
		if e.has("horde"):
			var last := e.duplicate()
			last.start = float(e.start) - 7 * 86400.0
			last.end = float(e.end) - 7 * 86400.0
			return last
	return {}


func in_last_horde() -> bool:
	## Whether you met the last Ember Horde: your points, trophies and purchases are its.
	var last := last_horde()
	return not last.is_empty() and horde_key > 0.0 and float(last.start) == horde_key


func my_horde_points() -> int:
	## Your horde points in the last Ember Horde (0 if you didn't meet it).
	return horde_points if in_last_horde() else 0


func war_trophies() -> int:
	## Your war trophies to spend in the Trophy Market (0 if you didn't meet the last horde).
	return int(horde_state.get("trophies", 0)) if in_last_horde() else 0


func horde_bought(item_id: String) -> int:
	## How many times you bought this Trophy Market item from the last horde.
	return int(horde_state.get("bought", {}).get(item_id, 0)) if in_last_horde() else 0


func horde_prize_taken() -> bool:
	return in_last_horde() and bool(horde_state.get("ranked", false))


func horde_rules() -> Dictionary:
	## The Ember Horde's camps, Trophy Market and prizes (data/events.json), as the server sent them.
	return last_horde().get("horde", {})


func check_horde_buy(item: Dictionary) -> String:
	## Why this Trophy Market item can't be bought now ("" if it can).
	if not in_last_horde():
		return "The Trophy Market opens when the Ember Horde arrives."
	if horde_bought(String(item.id)) >= int(item.stock):
		return "That's sold out until the next horde."
	if war_trophies() < int(item.cost):
		return "That costs %d war trophies." % int(item.cost)
	var cap := player_castle.storage_capacity()
	var res: Dictionary = item.get("resources", {})
	for r: String in res:
		if float(player_castle.resources.get(r, 0.0)) + float(res[r]) > cap:
			return "Make room in your storage first: it can't hold all of that."
	return ""


func buy_horde(item: Dictionary) -> String:
	## Asks the server for a Trophy Market item; your castle shows it with the server's answer.
	var why := check_horde_buy(item)
	if why == "":
		get_node("/root/Online").order({"action": "buy_horde", "item": String(item.id)})
	return why


func claim_horde_prize() -> String:
	## Asks the server for your ranked prize once the horde has gone.
	if my_horde_points() <= 0:
		return "Beat horde camps for points to earn a prize."
	if now() < float(last_horde().get("end", 0.0)):
		return "The prizes are given once the horde has gone."
	if horde_prize_taken():
		return "You already have your prize."
	get_node("/root/Online").order({"action": "claim_horde_prize"})
	return ""


func ask_horde_board() -> void:
	## Asks the server for the Ember Horde's ranking; it arrives with horde_board_changed.
	get_node("/root/Online").order({"action": "horde_board"})


func ask_war_board() -> void:
	## Asks the server for the alliance war's standings; they arrive with war_board_changed.
	get_node("/root/Online").order({"action": "war_board"})


func ask_tournament() -> void:
	## Asks the server for this week's alliance tournament; it arrives with tournament_changed.
	get_node("/root/Online").order({"action": "tournament"})


func claim_tournament_prize() -> String:
	## Asks the server for your prize for how far your alliance got in the last tournament.
	var prize: Dictionary = tournament.get("prize", {})
	if not bool(prize.get("can_claim", false)):
		return String(prize.get("why", "There's no prize to claim."))
	get_node("/root/Online").order({"action": "claim_tournament_prize"})
	ask_tournament()
	return ""


func claim_war_prize() -> String:
	## Asks the server for your prize for your alliance's place in the last war season.
	var prize: Dictionary = war_board.get("prize", {})
	if not bool(prize.get("can_claim", false)):
		return String(prize.get("why", "There's no prize to claim."))
	get_node("/root/Online").order({"action": "claim_war_prize"})
	ask_war_board()
	return ""


func castellan_effects(castle: CastleState) -> Dictionary:
	## What the castellan's gear adds to a castle's defence: only your main castle has one.
	if gear_rules == null or castle != player_castle:
		return {}
	return gear_rules.castellan_effects(castle)


func equip_gear(who: Variant, item_id: int) -> String:
	## Puts gear from your bag on a commander (an id) or the castellan ("castellan").
	return _gear_order(gear_rules.equip(player_castle, who, item_id, now()), {"action": "equip", "who": who, "item": item_id})


func unequip_gear(who: Variant, slot: String) -> String:
	## Takes gear off a commander or the castellan and puts it in your bag.
	return _gear_order(gear_rules.unequip(player_castle, who, slot, now()), {"action": "unequip", "who": who, "slot": slot})


func sell_gear(item_id: int) -> String:
	## Sells gear from your bag for gold.
	return _gear_order(gear_rules.sell(player_castle, item_id), {"action": "sell_gear", "item": item_id})


func learn_skill(commander_id: int, skill_id: String) -> String:
	## Spends a commander's skill point on a skill.
	return _gear_order(gear_rules.learn(player_castle, commander_id, skill_id),
			{"action": "learn_skill", "commander": commander_id, "skill": skill_id})


func retrain_commander(commander_id: int) -> String:
	## Forgets a commander's skills for gold, handing the points back.
	return _gear_order(gear_rules.retrain(player_castle, commander_id), {"action": "retrain_commander", "commander": commander_id})


func _gear_order(why: String, order: Dictionary) -> String:
	if why != "":
		return why
	if online:
		get_node("/root/Online").order(order)
	else:
		save_game()
	changed.emit()
	return ""


# --- Outpost --------------------------------------------------------------------

func outpost_castle() -> CastleState:
	## Your outpost's castle, or null before you found one.
	return get_castle(OutpostRules.OUTPOST_ID) if not outpost.is_empty() else null


func outpost_position() -> Vector2:
	return Vector2(float(outpost.get("x", 0.0)), float(outpost.get("y", 0.0)))


func outpost_spot() -> Variant:
	## Where an outpost would stand: offline the free player spot (server/world/world.json)
	## nearest your castle; online the server picks it the same way ([x, y], or null).
	if online:
		return [0.0, 0.0]
	var world = JSON.parse_string(FileAccess.get_file_as_string("res://server/world/world.json"))
	if not world is Dictionary:
		return null
	return OutpostRules.nearest_spot(world.get("spots", []), home_position(), [])


func check_found_outpost(region: String) -> String:
	return outpost_rules.check_found(player_castle, not outpost.is_empty(), region, outpost_spot())


func found_outpost(region: String) -> String:
	## Founds your outpost in a region (data/outposts.json), paid from your main castle.
	## Online the server founds it; its answer brings the outpost.
	var spot: Variant = outpost_spot()
	var why := outpost_rules.check_found(player_castle, not outpost.is_empty(), region, spot)
	if why != "":
		return why
	if online:
		get_node("/root/Online").order({"action": "found_outpost", "region": region})
		return ""
	var castle := outpost_rules.found(player_castle, region, now())
	castles.append(castle)
	outpost = {"name": castle.castle_name, "region": region, "x": float(spot[0]), "y": float(spot[1]), "carts": [], "next_cart": 1}
	save_game()
	outpost_changed.emit()
	changed.emit()
	return ""


func cart_time() -> float:
	## How long carts take between your castles.
	return baron_rules.march_time(home_position().distance_to(outpost_position()))


func check_carts(from_outpost: bool, resources: Dictionary) -> String:
	var castle := outpost_castle()
	if castle == null:
		return "You have no outpost."
	return outpost_rules.check_carts(castle if from_outpost else player_castle, resources)


func send_carts(from_outpost: bool, resources: Dictionary) -> String:
	## Sends carts of resources from one of your castles to the other.
	var why := check_carts(from_outpost, resources)
	if why != "":
		return why
	var from := outpost_castle() if from_outpost else player_castle
	var load := {}
	for r: String in resources:
		if int(resources[r]) > 0:
			load[r] = int(resources[r])
			from.resources[r] = float(from.resources[r]) - int(resources[r])
	var t := now()
	var id := int(outpost.get("next_cart", 1))
	outpost.carts.append({"id": id, "to": "home" if from_outpost else "outpost", "resources": load, "depart": t,
			"arrive": t + cart_time()})
	outpost.next_cart = id + 1
	if online:
		get_node("/root/Online").order({"action": "send_carts", "from": "outpost" if from_outpost else "home", "resources": load})
	else:
		save_game()
	outpost_changed.emit()
	changed.emit()
	return ""


func _deliver_carts(t: float) -> void:
	var castle := outpost_castle()
	if castle == null or outpost.get("carts", []).is_empty():
		return
	var before: int = outpost.carts.size()
	outpost.carts = OutpostRules.deliver_carts(player_castle, castle, outpost.carts, t)
	if outpost.carts.size() != before:
		outpost_changed.emit()


func _take_outpost(given: Variant) -> void:
	## Online: your outpost as the server has it.
	var castle := get_castle(OutpostRules.OUTPOST_ID)
	if not given is Dictionary:
		if castle != null:
			castles.erase(castle)
			outpost = {}
			outpost_changed.emit()
		return
	var fresh := CastleState.from_dict(rules, given.get("castle", {}))
	var founded := castle == null
	if founded:
		castles.append(fresh)
	else:
		castle.copy_from(fresh)
	var carts_before: int = outpost.get("carts", []).size()
	outpost = {"name": given.get("name", ""), "region": given.get("region", ""), "x": float(given.get("x", 0.0)),
			"y": float(given.get("y", 0.0)), "carts": given.get("carts", []), "next_cart": int(given.get("next_cart", 1))}
	if founded or outpost.carts.size() != carts_before:
		outpost_changed.emit()


# --- Resource villages ------------------------------------------------------------

## Who holds your villages offline (online the server uses your name).
const OFFLINE_OWNER := "You"


func _load_villages() -> void:
	village_rules = VillageRules.load_default()
	capital_rules = CapitalRules.load_capital_rules()
	if villages.is_empty():
		villages = VillageRules.load_villages()
	if capitals.is_empty():
		capitals = CapitalRules.load_capitals()


func village_info(id: String) -> Dictionary:
	## A village or a capital, as the map has it ({} if there's none).
	for v: Dictionary in villages:
		if String(v.id) == id:
			return v
	for v: Dictionary in capitals:
		if String(v.id) == id:
			return v
	return {}


func is_capital(id: String) -> bool:
	return bool(village_info(id).get("capital", false))


func village_rules_for(id: String) -> VillageRules:
	## The rules for this village, or for this capital.
	return capital_rules if is_capital(id) else village_rules


func village_state(id: String) -> Dictionary:
	## Who holds the village (the militia if nobody has touched it).
	return village_states.get(id, VillageRules.untouched(id))


func village_position(id: String) -> Vector2:
	var info := village_info(id)
	return Vector2(float(info.position[0]), float(info.position[1])) if not info.is_empty() else Vector2.ZERO


func is_my_village(id: String) -> bool:
	var state := village_state(id)
	return bool(state.get("mine", false)) if online else String(state.get("owner", "")) == OFFLINE_OWNER


func my_villages() -> Array:
	## The villages you hold, as village_info() has them.
	return villages.filter(func(v: Dictionary) -> bool: return is_my_village(String(v.id)))


func my_capitals() -> Array:
	## The capitals you hold.
	return capitals.filter(func(v: Dictionary) -> bool: return is_my_village(String(v.id)))


func capital_levels() -> Array:
	## The levels of the capitals your alliance holds (online), or you hold (offline).
	var out := []
	for v: Dictionary in capitals:
		if is_my_village(String(v.id)) or (online and village_state(String(v.id)).get("ally", false)):
			out.append(int(v.level))
	return out


func capital_guilds() -> Array:
	## The guild hall levels in the capitals that count for capital_levels().
	var out := []
	for v: Dictionary in capitals:
		var id := String(v.id)
		if is_my_village(id) or (online and village_state(id).get("ally", false)):
			var level := capital_rules.building_level(village_state(id), "guildhall", now())
			if level > 0:
				out.append(level)
	return out


func capital_bonus() -> float:
	## How much more your castles produce thanks to capitals and their guild halls.
	return capital_rules.total_bonus(capital_levels(), capital_guilds())


func alliance_capitals() -> int:
	## How many capitals your alliance holds, you included (online).
	return capital_levels().size()


func _apply_capital_boost() -> void:
	## Offline: your castle produces more for the capitals you hold (online the server sets it).
	if not online:
		player_castle.boost = capital_rules.boost(capital_levels(), rules.resources, capital_guilds())


func village_slots() -> int:
	## How many villages your keep can hold.
	return village_rules.slots_for(player_castle.keep_level())


func village_income() -> Dictionary:
	## What your villages send you each hour, by resource.
	var out := {}
	for v: Dictionary in my_villages():
		out[v.resource] = int(out.get(v.resource, 0)) + village_rules.yield_per_hour(v.resource, int(v.level))
	return out


func village_stock(id: String) -> int:
	## What the village holds now, for whoever takes it.
	var state := village_state(id)
	if online and state.has("stock"):
		return int(state.stock)
	return village_rules_for(id).stock(village_info(id), state, now())


func village_peace_until(id: String) -> float:
	var state := village_state(id)
	return float(state.get("peace_until", 0.0)) if online else village_rules_for(id).peace_until(state)


func village_march_time(id: String) -> float:
	return baron_rules.march_time(home_position().distance_to(village_position(id))) * player_castle.march_factor() \
			* weather_slow(village_position(id))


func check_village_attack(id: String, army: Dictionary, waves: Array = [], tools := {}, commander := 0) -> String:
	## Why this army can't be sent to take the village or capital ("" if it
	## can); the same checks as the server's (supabase/functions/game/villages.ts).
	var info := village_info(id)
	if info.is_empty():
		return "There's no such village."
	var state := village_state(id)
	var what := "capital" if info.get("capital", false) else "village"
	if is_my_village(id):
		return "This %s is already yours." % what
	if state.get("ally", false):
		return "This %s belongs to your alliance." % what
	if now() < village_peace_until(id):
		return "This %s just changed hands and is at peace for now." % what
	var why := _check_room(id)
	if why != "":
		return why
	why = _check_waves(waves)
	if why != "":
		return why
	why = check_tools(tools)
	if why != "":
		return why
	var lead: Variant = gear_rules.check_lead(player_castle, commander, now())
	if lead is String:
		return lead
	return _check_army(army)


func _check_room(id: String) -> String:
	## Why your keep (and, online, your alliance) can't hold this village or capital as well.
	if not is_capital(id):
		return village_rules.check_room(player_castle.keep_level(), my_villages().size())
	var why := capital_rules.check_room(player_castle.keep_level(), my_capitals().size())
	if why == "" and online:
		why = capital_rules.check_alliance(alliance_capitals())
	return why


func _check_army(army: Dictionary) -> String:
	var total := 0
	for unit: String in army:
		var n := int(army[unit])
		if n < 0 or n > int(player_castle.troops.get(unit, 0)):
			return "Your garrison doesn't have that many soldiers."
		total += n
	return "" if total > 0 else "Choose some soldiers to send."


func send_village_attack(id: String, army: Dictionary, waves: Array = [], tools := {}, commander := 0) -> String:
	## Sends soldiers from your garrison to take a village, like an attack on
	## a camp: in `waves` if given, with siege `tools`, led by `commander`.
	## Online the server decides; the soldiers leave your castle here straight away.
	if not waves.is_empty():
		army = Battle.waves_army(waves)
	var why := check_village_attack(id, army, waves, tools, commander)
	if why != "":
		return why
	var sent := {}
	for unit: String in army:
		if int(army[unit]) > 0:
			sent[unit] = int(army[unit])
			player_castle.troops[unit] = int(player_castle.troops[unit]) - int(army[unit])
	var t := now()
	var travel := village_march_time(id)
	var kit := Battle.clean_tools(tools)
	if not kit.is_empty():
		player_castle.use_tools(kit)
	var lead: Variant = gear_rules.check_lead(player_castle, commander, t)
	if lead is Dictionary and int(lead.id) > 0:
		gear_rules.commander(player_castle, lead.id).away_until = t + 2.0 * travel
	if online:
		var order := {"action": "attack_village", "village": id, "army": sent}
		if not waves.is_empty():
			order["waves"] = waves
		if not kit.is_empty():
			order["tools"] = kit
		if lead is Dictionary and int(lead.id) > 0:
			order["commander"] = int(lead.id)
		if String(village_state(id).get("owner", "")) != "":
			protected_until = 0.0
		get_node("/root/Online").order(order)
		changed.emit()
		return ""
	var march := {"id": _next_march, "village": id, "army": sent, "depart": t, "arrive": t + travel,
			"back": t + 2.0 * travel, "state": "out", "survivors": {}, "loot": {}}
	if not waves.is_empty():
		march["waves"] = waves
	if not kit.is_empty():
		march["tools"] = kit
	if lead is Dictionary:
		march["lead"] = lead
	marches.append(march)
	_next_march += 1
	save_game()
	changed.emit()
	marches_changed.emit()
	return ""


func _fight_village(m: Dictionary) -> void:
	## Offline: your army reaches a village or capital. A win carries off its
	## store and, if your keep has room, makes it yours.
	var id := String(m.village)
	var info := village_info(id)
	m.state = "home"
	if info.is_empty() or is_my_village(id):
		m.survivors = m.army
		return
	var state := village_state(id)
	var lead: Dictionary = m.get("lead", {})
	var result := village_rules_for(id).attack(rules, baron_rules, info, state, m.army, int(m.id) * 7919 + hash(id), float(m.arrive),
			m.get("waves", []), m.get("tools", {}), lead.get("fx", {}))
	m.survivors = result.survivors
	m.loot = result.loot
	var won: bool = result.winner == "a"
	var room := _check_room(id) == ""
	if won and room:
		village_states[id] = VillageRules.capture(state, OFFLINE_OWNER, float(m.arrive))
		_apply_capital_boost()
		villages_changed.emit()
	var led := {}
	if int(lead.get("id", 0)) > 0:
		led = gear_rules.add_xp(player_castle, int(lead.id), gear_rules.xp_win_per_level * int(info.level) if won else gear_rules.xp_loss)
	attack_resolved.emit({
		"player": "a", "village": true, "name": info.name, "other": "", "place": info.name,
		"winner": result.winner, "a": result.a, "b": result.b, "loot": 0, "spoils": result.loot,
		"walls": result.walls, "courtyard": result.courtyard, "tools": result.get("tools", {}), "lead": led,
		"captured": won and room, "no_room": won and not room, "level": int(info.level), "resource": info.resource,
		"capital": bool(info.get("capital", false)), "home_in": maxf(0.0, float(m.back) - now()),
	})


func _collect_villages(t: float) -> void:
	## Offline: what your villages and capitals made comes into your castle,
	## up to its storage, and your capitals boost its production.
	_apply_capital_boost()
	var cap := player_castle.storage_capacity()
	for v: Dictionary in villages + capitals:
		var id := String(v.id)
		if not is_my_village(id):
			continue
		var paid := village_rules_for(id).collect(v, village_state(id), t)
		if int(paid.amount) <= 0:
			continue
		village_states[id].paid_at = paid.paid_at
		var have := float(player_castle.resources.get(v.resource, 0.0))
		player_castle.resources[v.resource] = maxf(have, minf(cap, have + int(paid.amount)))


func check_station(id: String, army: Dictionary) -> String:
	if not online:
		return "Only villages online need guards."
	if not is_my_village(id):
		return "That village isn't yours."
	return _check_army(army)


func station(id: String, army: Dictionary) -> String:
	## Online: sends soldiers from your garrison to guard your village.
	var why := check_station(id, army)
	if why != "":
		return why
	var sent := {}
	for unit: String in army:
		if int(army[unit]) > 0:
			sent[unit] = int(army[unit])
			player_castle.troops[unit] = int(player_castle.troops[unit]) - int(army[unit])
	get_node("/root/Online").order({"action": "station", "village": id, "army": sent})
	changed.emit()
	return ""


func recall_guard(id: String) -> void:
	## Online: your guards leave the village for home.
	get_node("/root/Online").order({"action": "recall_guard", "village": id})


func abandon_village(id: String) -> String:
	## Gives the village back to the militia (online its guards walk home first).
	if not is_my_village(id):
		return "That village isn't yours."
	if online:
		get_node("/root/Online").order({"action": "abandon_village", "village": id})
		return ""
	# A capital's town buildings stay in the town.
	var left := VillageRules.settled(village_state(id), now())
	village_states.erase(id)
	if left.has("buildings"):
		village_states[id] = VillageRules.untouched(id)
		village_states[id]["buildings"] = left.buildings
	_apply_capital_boost()
	save_game()
	villages_changed.emit()
	changed.emit()
	return ""


func check_capital_build(id: String, building: String) -> String:
	## Why you can't start the next level of this town building in your capital ("" if you can).
	if not is_capital(id):
		return "That's not a capital."
	if not is_my_village(id):
		return "That capital isn't yours."
	return capital_rules.check_build(village_state(id), building, now(), player_castle)


func build_in_capital(id: String, building: String) -> String:
	## Starts the next level of a town building in your capital, paid from
	## your castle. Online the server decides.
	var why := check_capital_build(id, building)
	if why != "":
		return why
	if online:
		get_node("/root/Online").order({"action": "build_capital", "village": id, "building": building})
		return ""
	var t := now()
	player_castle.pay(capital_rules.building_cost(building, capital_rules.building_level(village_state(id), building, t) + 1))
	village_states[id] = capital_rules.start_build(village_state(id), building, t)
	save_game()
	villages_changed.emit()
	changed.emit()
	return ""


func _take_villages(list: Array) -> void:
	## Online: who holds each village, as the server has it.
	var fresh := {}
	for v: Variant in list:
		if v is Dictionary and v.has("id"):
			fresh[String(v.id)] = v
	if JSON.stringify(fresh) != JSON.stringify(village_states):
		village_states = fresh
		villages_changed.emit()


func village_text(r: Dictionary) -> String:
	## A line for a village report with no battle in it.
	match String(r.get("result", "")):
		"peace":
			return "Your army reached %s, but it had just changed hands and is at peace. They're coming home." % r.get("name", "")
		"joined":
			return "Your army reached %s, which is already yours, and stayed to guard it." % r.get("name", "")
		"lost":
			return "Your guards reached %s, but %s had taken it. They're coming home." % [r.get("name", ""), r.get("other", "someone")]
	return ""


func claim_quest(kind: String, index := 0) -> String:
	## Claims a quest reward: "story", "daily" task `index` or the "chest".
	## Online the server gives it too, and its answer replaces the castle.
	var why := quest_book.claim(player_castle, kind, index, now())
	if why != "":
		return why
	if online:
		get_node("/root/Online").order({"action": "claim_quest", "kind": kind, "index": index})
	else:
		save_game()
	changed.emit()
	return ""


func claim_login() -> String:
	## Takes today's Royal Gift. Online the server gives it too, and its
	## answer replaces the castle.
	var why := login_rewards.claim(player_castle, now())
	if why != "":
		return why
	if online:
		get_node("/root/Online").order({"action": "claim_login"})
	else:
		save_game()
	changed.emit()
	return ""


func login_waiting() -> bool:
	## Today's Royal Gift hasn't been taken yet.
	return login_rewards != null and player_castle != null and login_rewards.check_claim(player_castle, now()) == ""


func claim_season_track() -> String:
	## Claims the next reward on the season's renown track. Online the server
	## gives it too, and its answer replaces the castle.
	var why := season_rules.claim_track(player_castle, now())
	if why != "":
		return why
	if online:
		get_node("/root/Online").order({"action": "claim_season"})
	else:
		save_game()
	changed.emit()
	return ""


func claim_season_prize() -> String:
	## Online: asks the server for last season's prizes for your place and
	## your alliance's; the castle comes back with them.
	if not online:
		return "Season prizes are for the online game."
	var why := SeasonRules.check_prize(player_castle)
	if why != "":
		return why
	get_node("/root/Online").order({"action": "claim_season_prize"})
	ask_season_board()
	return ""


func ask_season_board() -> void:
	## Asks the server for the season's ranking; it arrives with season_board_changed.
	get_node("/root/Online").order({"action": "season_board"})


func season_waiting() -> bool:
	## A season track reward, or online last season's prize, is ready to claim.
	if season_rules == null or player_castle == null:
		return false
	return season_rules.check_track(player_castle) == "" or (online and SeasonRules.check_prize(player_castle) == "")


func open_chest(kind: String) -> Dictionary:
	## Opens a treasure chest: {"error"} or {"error": "", "slot", "reward"}.
	## Online the server opens it too (the spin comes out the same), and its
	## answer replaces the castle.
	var out := chest_rules.open(player_castle, kind)
	if out.error != "":
		return out
	if online:
		get_node("/root/Online").order({"action": "open_chest", "kind": kind})
	else:
		save_game()
	changed.emit()
	return out


func take_encounter(id: String, choice := "") -> Dictionary:
	## Takes on a map encounter (bandits: with a "quarter", "half" or "all"
	## of the garrison). Returns {"error"} or what happened (EncounterRules.take).
	## Online the server does the same (it comes out the same), and its answer
	## replaces the castle.
	var out := encounter_rules.take(player_castle, id, choice, now())
	if out.error != "":
		return out
	if online:
		get_node("/root/Online").order({"action": "encounter", "id": id, "choice": choice})
	else:
		save_game()
	changed.emit()
	return out


func claim_achievement(id: String) -> String:
	## Claims the next earned reward of an achievement. Online the server
	## gives it too, and its answer replaces the castle.
	var why := achievements.claim(player_castle, id, online)
	if why != "":
		return why
	if online:
		get_node("/root/Online").order({"action": "claim_achievement", "id": id})
	else:
		save_game()
	changed.emit()
	return ""


func set_title(key: String) -> String:
	## Shows an earned title with your name ("id:tier"), or none for "".
	var why := achievements.set_title(player_castle, key)
	if why != "":
		return why
	if online:
		get_node("/root/Online").order({"action": "set_title", "title": key})
	else:
		save_game()
	changed.emit()
	return ""


func my_title() -> String:
	## The title your castle shows ("the Builder"), or "".
	return achievements.shown_title(player_castle) if achievements != null and player_castle != null else ""


func title_of(player: Dictionary) -> String:
	## Another player's title, from the server's list ("" for none).
	return achievements.title_text(String(player.get("title", ""))) if achievements != null else ""


func _announce_achievements() -> void:
	## Tells the news about tiers earned since the last look.
	var tiers: Dictionary = player_castle.achievements.tiers
	if _known_tiers == null:
		_known_tiers = tiers.duplicate()
		return
	var parts: PackedStringArray = []
	for id: String in tiers:
		var had := int(_known_tiers.get(id, 0))
		var def := achievements.get_def(id)
		for t in range(had + 1, int(tiers[id]) + 1):
			parts.append("%s (%s)" % [def.get("name", id), achievements.tier_names[t - 1] if t <= achievements.tier_names.size() else str(t)])
	_known_tiers = tiers.duplicate()
	if parts.size() > 2:
		achievement_news.emit("%d achievement tiers earned! Press Y to claim the rewards and pick your title." % parts.size())
	elif not parts.is_empty():
		achievement_news.emit("Achievement earned: %s. Press Y to claim the reward and pick your title." % ", ".join(parts))


func ask_event_board() -> void:
	## Asks the server for the event leaderboard; it arrives with event_board_changed.
	get_node("/root/Online").order({"action": "event_board"})


func reward_text(tier: Dictionary) -> String:
	## "300 wood, 300 stone", "20 Spearmen", "2 Ladders" or "1 iron chest".
	var parts: PackedStringArray = []
	var res: Dictionary = tier.get("resources", {})
	for r: String in res:
		parts.append("%d %s" % [int(res[r]), r])
	var troops: Dictionary = tier.get("troops", {})
	for unit: String in troops:
		parts.append("%d %s" % [int(troops[unit]), rules.unit_plural(unit) if rules.has_unit(unit) else unit])
	var tools: Dictionary = tier.get("tools", {})
	for tool: String in tools:
		var tool_name := String(rules.tools[tool].get("name", tool)) if rules.has_tool(tool) else tool
		parts.append("%d %s" % [int(tools[tool]), tool_name.to_lower() + ("s" if int(tools[tool]) != 1 and not tool_name.ends_with("s") else "")])
	var chests: Dictionary = tier.get("chests", {})
	for kind: String in chests:
		var chest_name := String(chest_rules.kinds[kind].name).to_lower() if chest_rules != null and chest_rules.kinds.has(kind) else kind + " chest"
		parts.append("%d %s%s" % [int(chests[kind]), chest_name, "s" if int(chests[kind]) != 1 else ""])
	return ", ".join(parts)


func loot_bonus_note() -> String:
	## " (+50% Plunder Weekend)" while an event raises baron loot, else "".
	var factor := event_effect("baron_loot")
	if factor == 1.0:
		return ""
	var names: PackedStringArray = []
	for e: Dictionary in events_on():
		if e.get("effects", {}).has("baron_loot"):
			names.append(String(e.name))
	return " (%+d%% %s)" % [roundi((factor - 1.0) * 100.0), ", ".join(names)]


# --- Online: helping allies ------------------------------------------------------------

func carry_limit() -> int:
	## How much one cart shipment can carry from your castle.
	return int(aid_rules.get("carry_per_keep_level", 500)) * maxi(1, player_castle.keep_level())


func _check_ally(player_name: String) -> String:
	var target := get_other(player_name)
	if target.is_empty():
		return "There's no player by that name."
	if not target.get("ally", false):
		return "You can only help members of your own alliance."
	return ""


func check_shipment(player_name: String, resources: Dictionary) -> String:
	## Why these resources can't be sent to that ally ("" if they can).
	var why := _check_ally(player_name)
	if why != "":
		return why
	var total := 0
	for r: String in resources:
		var n := int(resources[r])
		if n < 0:
			return "Choose what to send."
		if n > floori(float(player_castle.resources.get(r, 0.0))):
			return "You don't have that much %s." % r
		total += n
	if total <= 0:
		return "Choose what to send."
	if total > carry_limit():
		return "Your carts carry at most %d at a time." % carry_limit()
	return ""


func send_resources(player_name: String, resources: Dictionary) -> String:
	## Sends a cart of resources to an ally. The server decides; they leave
	## your storage here straight away.
	var why := check_shipment(player_name, resources)
	if why != "":
		return why
	var sent := {}
	for r: String in resources:
		if int(resources[r]) > 0:
			sent[r] = int(resources[r])
			player_castle.resources[r] = float(player_castle.resources[r]) - int(resources[r])
	get_node("/root/Online").order({"action": "send_resources", "target": player_name, "resources": sent})
	changed.emit()
	return ""


func check_defenders(player_name: String, army: Dictionary) -> String:
	## Why these soldiers can't go and defend that ally's castle ("" if they can).
	var why := _check_ally(player_name)
	if why != "":
		return why
	var total := 0
	for unit: String in army:
		var n := int(army[unit])
		if n < 0 or n > int(player_castle.troops.get(unit, 0)):
			return "Your garrison doesn't have that many soldiers."
		total += n
	return "" if total > 0 else "Choose some soldiers to send."


func send_defenders(player_name: String, army: Dictionary) -> String:
	## Sends soldiers to stand in an ally's castle for station_hours.
	var why := check_defenders(player_name, army)
	if why != "":
		return why
	var sent := {}
	for unit: String in army:
		if int(army[unit]) > 0:
			sent[unit] = int(army[unit])
			player_castle.troops[unit] = int(player_castle.troops[unit]) - int(army[unit])
	get_node("/root/Online").order({"action": "send_defenders", "target": player_name, "army": sent})
	changed.emit()
	return ""


func recall_defenders(id: int) -> void:
	## Calls your defenders home from an ally's castle (or turns them round on the road).
	get_node("/root/Online").order({"action": "recall_defenders", "id": id})


func aid_to(player_name: String) -> Array:
	## Your carts and defenders on their way to, standing in, or coming back from this ally.
	return aid.filter(func(a: Dictionary) -> bool: return a.get("mine", false) and String(a.receiver_name) == player_name)


func defenders_here() -> Array:
	## Allies' defenders standing in your castle now.
	var t := now()
	return aid.filter(func(a: Dictionary) -> bool:
		return not a.get("mine", false) and a.kind == "troops" and float(a.arrive) <= t and t < float(a.leave))


func aid_text(r: Dictionary) -> String:
	## A server report about help between allies as one sentence.
	var other := String(r.get("name", ""))
	match String(r.get("event", "")):
		"received":
			return "%s's cart arrived: %s." % [other, _amounts(r.get("resources", {}))]
		"delivered":
			var text := "Your cart reached %s: %s." % [other, _amounts(r.get("resources", {}))]
			var spilled: Dictionary = r.get("spilled", {})
			if not spilled.is_empty():
				text += " Their storage was full, so %s was lost." % _amounts(spilled)
			return text
		"defended":
			var held: bool = r.get("held", false)
			var lost: Dictionary = r.get("lost", {})
			var losses := "losing %s" % _amounts(lost, true) if not lost.is_empty() else "without losses"
			return ("Your defenders helped %s hold off %s, %s." if held else "%s's castle fell to %s. Your defenders fought, %s.") \
					% [other, String(r.get("attacker", "")), losses]
	return ""


func gift_text(r: Dictionary) -> String:
	## A gift from the game owner as one sentence.
	var parts: PackedStringArray = []
	if not (r.get("resources", {}) as Dictionary).is_empty():
		parts.append(_amounts(r.get("resources", {})))
	if not (r.get("troops", {}) as Dictionary).is_empty():
		parts.append(_amounts(r.get("troops", {}), true))
	return "The game owner sent you a gift: %s." % ", ".join(parts)


func set_admin(view: Dictionary, error: String) -> void:
	## The server's answer to an owner's order (or to the check whether you are the owner).
	is_admin = bool(view.get("is_admin", false))
	admin_view = view if is_admin else {}
	admin_changed.emit(error)


func admin_order(body: Dictionary) -> void:
	## Sends one of the owner's orders: admin_start_event, admin_stop_event, admin_give.
	## The server checks that you are the owner; the panel updates with its answer.
	get_node("/root/Online").order(body)
	if body.get("action", "") == "admin_give":
		get_node("/root/Online").order({"action": "state"})


func _amounts(d: Dictionary, units := false) -> String:
	var parts: PackedStringArray = []
	for k: String in d:
		if int(d[k]) > 0:
			parts.append("%d %s" % [int(d[k]), rules.unit_plural(k) if units else k])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


# --- Online: the market --------------------------------------------------------------

func ask_market() -> void:
	## Asks the server for the market's offers; they arrive with market_changed.
	get_node("/root/Online").order({"action": "market"})


func set_market(view: Dictionary, error: String) -> void:
	## The server's answer to a market order.
	if not online:
		return
	market = view
	market_changed.emit(error)


func market_lot_limit() -> int:
	## How much one offer can give from your castle.
	return int(market_rules.get("lot_per_keep_level", 1000)) * maxi(1, player_castle.keep_level())


func market_proceeds(want_amount: int) -> int:
	## What you get when an offer wanting this much sells, after the market's cut.
	return want_amount - ceili(want_amount * float(market_rules.get("fee", 0.0)))


func check_offer(give: String, give_amount: int, want: String, want_amount: int) -> String:
	## Why this offer can't go up at the market ("" if it can). The server checks again.
	var unlock := int(market_rules.get("unlock_keep", 1))
	if player_castle.keep_level() < unlock:
		return "The market opens at keep level %d." % unlock
	var goods: Array = market_rules.get("goods", [])
	if not goods.has(give) or not goods.has(want):
		return "Choose what to trade."
	if give == want:
		return "Trade one good for another."
	if give_amount <= 0 or want_amount <= 0:
		return "Choose how much."
	if give_amount > floori(float(player_castle.resources.get(give, 0.0))):
		return "You don't have that much %s." % give
	if give_amount > market_lot_limit():
		return "One offer gives at most %d." % market_lot_limit()
	var lo := float(market_rules.get("min_rate", 0.5))
	var hi := float(market_rules.get("max_rate", 2.0))
	var rate := float(want_amount) / give_amount
	if rate < lo - 1e-9 or rate > hi + 1e-9:
		return "Ask between %s and %s %s for each %s." % [_rate_text(lo), _rate_text(hi), want, give]
	if market.get("mine", []).size() >= int(market_rules.get("max_offers", 5)):
		return "You can have at most %d offers up at once." % int(market_rules.get("max_offers", 5))
	return ""


func post_offer(give: String, give_amount: int, want: String, want_amount: int) -> String:
	## Puts an offer up at the market; the goods leave your storage here straight away.
	var why := check_offer(give, give_amount, want, want_amount)
	if why != "":
		return why
	player_castle.resources[give] = float(player_castle.resources[give]) - give_amount
	get_node("/root/Online").order({"action": "post_offer", "give": give, "give_amount": give_amount,
			"want": want, "want_amount": want_amount})
	changed.emit()
	return ""


func check_buy(offer: Dictionary) -> String:
	## Why you can't buy this offer ("" if you can).
	var unlock := int(market_rules.get("unlock_keep", 1))
	if player_castle.keep_level() < unlock:
		return "The market opens at keep level %d." % unlock
	if floori(float(player_castle.resources.get(offer.want, 0.0))) < int(offer.want_amount):
		return "You don't have enough %s." % offer.want
	if float(player_castle.resources.get(offer.give, 0.0)) + int(offer.give_amount) > player_castle.storage_capacity():
		return "Your storage has no room for that much %s." % offer.give
	return ""


func buy_offer(offer: Dictionary) -> String:
	## Buys a whole offer: you pay what it wants and get its goods at once.
	var why := check_buy(offer)
	if why != "":
		return why
	get_node("/root/Online").order({"action": "buy_offer", "id": int(offer.id)})
	return ""


func cancel_offer(id: int) -> void:
	## Takes your offer down; its goods come back to your storage.
	get_node("/root/Online").order({"action": "cancel_offer", "id": id})


func sabotage_text(r: Dictionary) -> String:
	## A server report of someone's agents in your castle as one sentence.
	var who := String(r.get("name", ""))
	if not bool(r.get("success", false)):
		return "Your guards caught agents sent by %s. They got away with nothing." % who
	match String(r.get("mission", "")):
		"steal":
			return "Agents sent by %s stole %s from your stores." % [who, reward_text({"resources": r.get("stolen", {})})]
		"burn_stores":
			return "Agents sent by %s set your stores on fire: %s burned." % [who, reward_text({"resources": r.get("burned", {})})]
	return "Agents sent by %s fired your gate: your walls are weaker for %d hours." % [who, roundi(sabotage_rules.walls_time / 3600.0)]


func market_text(r: Dictionary) -> String:
	## A server report about the market as one sentence.
	var give := "%d %s" % [int(r.get("give_amount", 0)), String(r.get("give", ""))]
	var want := "%d %s" % [int(r.get("want_amount", 0)), String(r.get("want", ""))]
	match String(r.get("event", "")):
		"sold":
			return "%s bought your %s at the market. You get %d %s after the market's cut." % [String(r.get("name", "")),
					give, int(r.get("proceeds", 0)), String(r.get("want", ""))]
		"bought":
			return "You bought %s from %s for %s." % [give, String(r.get("name", "")), want]
		"expired":
			return "Nobody bought your %s for %s; it is back in your storage." % [give, want]
		"spilled":
			return "Your storage was full, so %s from the market was lost." % _amounts(r.get("lost", {}))
	return ""


static func _rate_text(x: float) -> String:
	return str(snappedf(x, 0.01))


# --- Online: chat ---------------------------------------------------------------------

func last_chat_id() -> int:
	return int(chat_messages.back().id) if not chat_messages.is_empty() else 0


func send_chat(channel: String, text: String) -> String:
	## Sends a message to "world" or "alliance"; "" if it went to the server,
	## else why not. The server's answer arrives with chat_changed.
	var clean := text.strip_edges()
	if clean == "":
		return "Write something first."
	if clean.length() > 200:
		return "Messages are at most 200 characters long."
	if channel == "alliance" and not chat_in_alliance:
		return "You aren't in an alliance."
	get_node("/root/Online").order({"action": "chat_send", "channel": channel, "text": clean, "after": last_chat_id()})
	_chat_timer = 0.0
	return ""


func set_chat(view: Dictionary, error: String) -> void:
	## The server's answer to "chat" or "chat_send": messages we may not have yet.
	if not online:
		return
	var have := {}
	for m: Dictionary in chat_messages:
		have[int(m.id)] = true
	var added := false
	for m: Dictionary in view.get("messages", []):
		if not have.has(int(m.get("id", 0))):
			chat_messages.append(m)
			added = true
	if added:
		chat_messages.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	if chat_messages.size() > CHAT_KEPT:
		chat_messages = chat_messages.slice(chat_messages.size() - CHAT_KEPT)
	chat_in_alliance = bool(view.get("in_alliance", false))
	chat_loaded = true
	chat_changed.emit(error)


func take_order_result(body: Dictionary, answer: Dictionary) -> void:
	## Extra answers to orders: what a spy saw, the leaderboards.
	if body.get("action", "") == "leaderboard" and answer.get("result") is Dictionary:
		leaderboard = answer.result
		leaderboard_changed.emit()
		return
	if body.get("action", "") == "event_board" and answer.get("result") is Dictionary:
		event_board = answer.result
		event_board_changed.emit()
		return
	if body.get("action", "") == "season_board" and answer.get("result") is Dictionary:
		season_board = answer.result
		season_board_changed.emit()
		return
	if body.get("action", "") == "horde_board" and answer.get("result") is Dictionary:
		horde_board = answer.result
		horde_board_changed.emit()
		return
	if body.get("action", "") == "tournament" and answer.get("result") is Dictionary and answer.result.get("tournament") is Dictionary:
		tournament = answer.result.tournament
		tournament_changed.emit()
		return
	if body.get("action", "") == "war_board" and answer.get("result") is Dictionary and answer.result.get("war") is Dictionary:
		war_board = answer.result.war
		war_board_changed.emit()
		return
	if body.get("action", "") == "view_castle" and answer.get("result") is Dictionary:
		_show_visit(answer.result)
		return
	if body.get("action", "") == "sabotage_player" and answer.get("result") is Dictionary:
		agents_returned.emit(answer.result)
	if body.get("action", "") == "spy" and answer.get("result") is Dictionary:
		var seen: Dictionary = answer.result
		spy_reports[String(seen.get("name", body.get("target", "")))] = seen
		spy_returned.emit(String(seen.get("name", "")))
