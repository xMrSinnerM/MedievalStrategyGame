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

## Games are kept in SLOTS save slots under save_dir (slot_1.json ...).
const SLOTS := 3
## Where single-save versions of the game kept their save; moved to slot 1.
const OLD_SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const TICK := 1.0              ## seconds between economy updates
const AUTOSAVE := 30.0           ## seconds between autosaves
const DIPLOMACY_TICK := 30.0     ## seconds between rounds of AI diplomacy
const MAIN_CASTLE := "player_castle"   ## id of your first castle, which can't be captured
## Lords leave your main castle alone until its keep reaches this level.
const PROTECTED_BELOW_KEEP := 2
## A new NPC castle starts with this many hours of building behind it (by seed).
const NPC_HEAD_START_HOURS := Vector2(12.0, 72.0)

var rules: BuildingRules
var player_castle: CastleState
var castles: Array[CastleState] = []   ## the player's first, then NPC castles
## Wars, truces and relations between the factions.
var diplomacy: Diplomacy

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
	if not load_game():
		new_game()


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
	slot = n
	_loaded = true
	new_game()


func begin_load(n := 1) -> void:
	## Continues the game in slot n from the title screen.
	rules = BuildingRules.load_default()
	slot = n
	_loaded = true
	if not load_game():
		new_game()


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
	return Time.get_unix_time_from_system()


func new_game() -> void:
	castles.clear()
	homes.clear()
	exiled.clear()
	player_castle = CastleState.create_new(rules, MAIN_CASTLE, "Your Castle", "player", now())
	castles.append(player_castle)
	diplomacy = Diplomacy.from_data_files(now())
	save_game()
	changed.emit()


func load_game() -> bool:
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
	player_castle = find_main_castle()
	if player_castle == null:
		return false
	# Catch up on everything that happened while the game was closed.
	var t := now()
	for c in castles:
		if c.is_npc():
			NpcBrain.catch_up(c, t)
		else:
			c.advance_to(t)
	changed.emit()
	return true


func save_game() -> void:
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
			"diplomacy": diplomacy.to_dict() if diplomacy != null else {}}, "\t", true, true))
	f.close()


func _process(delta: float) -> void:
	if not _loaded:
		return
	_tick_timer += delta
	if _tick_timer >= TICK:
		_tick_timer = 0.0
		var t := now()
		for c in castles:
			c.advance_to(t)
			if c.is_npc():
				NpcBrain.think(c, t)
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
