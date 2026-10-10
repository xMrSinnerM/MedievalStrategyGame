extends Node
## Autoload that owns every castle's economy and the save file. It keeps the
## castles running in real time while the game is open, and when the game
## starts it catches them up on the time that passed while it was closed.
## NPC castles are run by NpcBrain under the same rules as the player's.

signal changed   ## something in a castle changed (resources tick, build finished, order given)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const TICK := 1.0              ## seconds between economy updates
const AUTOSAVE := 30.0         ## seconds between autosaves
## A new NPC castle starts with this many hours of building behind it (by seed).
const NPC_HEAD_START_HOURS := Vector2(12.0, 72.0)

var rules: BuildingRules
var player_castle: CastleState
var castles: Array[CastleState] = []   ## the player's first, then NPC castles

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
	var added := false
	for s in settlements:
		if s.get("type", "") != "castle":
			continue
		if s.get("player", false):
			player_castle.castle_name = s.get("name", player_castle.castle_name)
			continue
		if get_castle(s.id) != null:
			continue
		castles.append(new_npc_castle(rules, s.id, s.name, s.faction, now()))
		added = true
	for p in parties:
		var home := get_castle(p.get("home", ""))
		if home != null and not home.field_ready:
			home.field = {"spearman": int(p.get("troops", 20))}
			home.field_ready = true
			added = true
	if added:
		save_game()
		changed.emit()


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
	player_castle = CastleState.create_new(rules, "player_castle", "Your Castle", "player", now())
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
	for c in data.get("castles", []):
		castles.append(CastleState.from_dict(rules, c))
	player_castle = null
	for c in castles:
		if not c.is_npc():
			player_castle = c
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
	f.store_string(JSON.stringify({"version": SAVE_VERSION, "saved_at": now(), "castles": list}, "\t", true, true))
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
