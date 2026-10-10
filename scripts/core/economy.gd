extends Node
## Autoload that owns every castle's economy and the save file. It keeps the
## castles running in real time while the game is open, and when the game
## starts it catches them up on the time that passed while it was closed.
## NPC castles are run by NpcBrain under the same rules as the player's.

signal changed   ## something in a castle changed (resources tick, build finished, order given)
## A castle changed hands. Owners are faction ids, or "player".
signal castle_captured(castle_id: String, old_owner: String, new_owner: String)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const TICK := 1.0              ## seconds between economy updates
const AUTOSAVE := 30.0
const MAIN_CASTLE := "player_castle"   ## id of your first castle, which can't be captured         ## seconds between autosaves
## A new NPC castle starts with this many hours of building behind it (by seed).
const NPC_HEAD_START_HOURS := Vector2(12.0, 72.0)

var rules: BuildingRules
var player_castle: CastleState
var castles: Array[CastleState] = []   ## the player's first, then NPC castles

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

var _tick_timer := 0.0
var _save_timer := 0.0
var _loaded := false


func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	rules = BuildingRules.load_default()
	if not load_game():
		new_game()


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
		if p.get("player", false):
			continue
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
	save_game()
	changed.emit()


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
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
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not write %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "saved_at": now(), "castles": list,
			"homes": homes, "exiled": exiled.keys()}, "\t", true, true))
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
	_save_timer += delta
	if _save_timer >= AUTOSAVE:
		_save_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _loaded:
		save_game()
