extends Node
## Autoload that owns every castle's economy and the save file. It keeps the
## castles running in real time while the game is open, and when the game
## starts it catches them up on the time that passed while it was closed.

signal changed   ## something in a castle changed (resources tick, build finished, order given)

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1
const TICK := 1.0              ## seconds between economy updates
const AUTOSAVE := 30.0         ## seconds between autosaves

var rules: BuildingRules
var player_castle: CastleState
var castles: Array[CastleState] = []   ## the player's first, then NPC castles

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
		changed.emit()
	_save_timer += delta
	if _save_timer >= AUTOSAVE:
		_save_timer = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _loaded:
		save_game()
