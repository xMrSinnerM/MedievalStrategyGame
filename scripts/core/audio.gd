extends Node
## Autoload that plays the music, the ambience and the sound effects.
##
## Music follows the screen you're on (set_mood): a playlist each for the
## title screen, the world map, the castle and battles, shuffled with a short
## pause between tracks and crossfaded when the screen changes. The attack
## screen switches to battle music while it's open (set_battle). Each screen
## also has a looping ambience under the music.
##
## Effects are played by name (play). Every button clicks by itself; the
## other sounds are asked for by the screens, or picked up here from signals:
## buildings and studies finishing, armies marching, alarms and chat.
##
## Music, effects and ambience have their own audio buses, whose volumes are
## in the Settings ("master_volume", "music_volume", ...). See
## assets/audio/CREDITS.md for where the sounds come from.

const DIR := "res://assets/audio/"
const MUSIC := {
	"menu": ["menu_honor_bound"],
	"map": ["map_highland_mist", "map_celtica", "map_mountain_idyll", "map_albian_nocturne"],
	"castle": ["castle_harvest_festival", "castle_forging_a_city_state", "castle_harvest_moon"],
	"battle": ["battle_tale_of_warriors", "battle_taiko"],
}
const AMBIENCE := {"map": "map_countryside", "castle": "castle_bustle"}
## name -> [files in sfx/ (one is picked at random), volume in dB]
const EFFECTS := {
	"click": [["click"], 2.0],
	"place": [["place_a", "place_b", "place_c", "place_d"], -4.0],
	"remove": [["remove_a", "remove_b", "remove_c", "remove_d"], -4.0],
	"denied": [["denied"], 0.0],
	"build_done": [["build_done"], 0.0],
	"recruit": [["recruit"], -2.0],
	"research": [["select_library"], -2.0],
	"research_done": [["research_done"], -2.0],
	"reward": [["reward"], -2.0],
	"march": [["march"], -2.0],
	"alarm": [["alarm"], -4.0],
	"chat": [["chat"], -8.0],
	"sword": [["sword_10", "sword_11", "sword_12", "sword_14", "sword_15", "sword_16"], -3.0],
	"victory": [["victory"], -3.0],
	"defeat": [["defeat"], 0.0],
	# Picking things on the world map and in the castle.
	"select_castle": [["select_fortress"], -2.0],
	"select_town": [["select_civ_center"], 2.0],
	"select_village": [["select_farmstead"], 4.0],
	"select_camp": [["select_barracks"], -2.0],
	"select_party": [["select_party"], -2.0],
	"select_keep": [["select_civ_center"], 2.0],
	"select_wall": [["select_wall", "select_gate"], -2.0],
	"select_woodcutter": [["select_tree"], 2.0],
	"select_quarry": [["select_stone"], 2.0],
	"select_farm": [["select_field"], 2.0],
	"select_house": [["select_house"], 6.0],
	"select_barracks": [["select_barracks"], -2.0],
	"select_storehouse": [["select_storehouse"], -2.0],
	"select_workshop": [["select_forge"], -3.0],
	"select_academy": [["select_library"], -2.0],
	"select_tower": [["select_tower"], 0.0],
	"select_market": [["select_market"], 0.0],
}
const BUSES := {"Music": "music_volume", "Effects": "effects_volume", "Ambience": "ambience_volume"}
const FADE := 2.0             ## seconds to crossfade between playlists
const GAP := 3.0              ## seconds of quiet between two tracks
const VOICES := 10            ## effects that can sound at once
const QUIET_DB := -60.0

var mood := ""                ## "menu", "map" or "castle"
var _battle := false
var _list := ""               ## the playlist playing now
var _music: Array[AudioStreamPlayer] = []   ## two, for crossfades
var _front := 0               ## which of the two is playing
var _last_track := {}         ## playlist -> the track played last, so it doesn't repeat
var _next_in := -1.0          ## seconds until the next track starts (-1: none waiting)
var _ambience: AudioStreamPlayer
var _ambience_name := ""
var _voices: Array[AudioStreamPlayer] = []
var _voice := 0
var _last_played := {}        ## effect -> msec, so a burst of the same sound plays once
var _cache := {}
# What the player's castle has finished, to hear when something new is done.
var _watched := ""
var _levels := 0
var _studies := 0
var _raids_seen := {}
var _chat_seen := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus: String in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	for k in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = QUIET_DB
		p.finished.connect(_on_track_finished.bind(p))
		add_child(p)
		_music.append(p)
	_ambience = AudioStreamPlayer.new()
	_ambience.bus = "Ambience"
	add_child(_ambience)
	for k in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Effects"
		add_child(p)
		_voices.append(p)
	apply_volumes()
	Settings.changed.connect(apply_volumes)
	get_tree().node_added.connect(_on_node_added)
	Economy.changed.connect(_check_castle)
	Economy.raids_changed.connect(_check_raids)
	Economy.chat_changed.connect(func(_error: String) -> void: _check_chat())
	EventBus.siege_requested.connect(func(_id: String) -> void: play("march"))
	EventBus.attack_requested.connect(func(_id: String) -> void: play("march"))
	EventBus.siege_started.connect(func(castle_id: String, _besieger: String, _until: float) -> void:
		var castle := Economy.get_castle(castle_id)
		if castle != null and castle.owner == "player":
			play("alarm"))


func apply_volumes() -> void:
	_set_bus("Master", float(Settings.get_value("master_volume")))
	for bus: String in BUSES:
		_set_bus(bus, float(Settings.get_value(BUSES[bus])))


func _set_bus(bus: String, volume: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_mute(i, volume <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volume, 0.001)))


# --- Music and ambience ------------------------------------------------------------

func set_mood(new_mood: String) -> void:
	## The screen on now: "menu", "map" or "castle".
	if new_mood == mood:
		return
	mood = new_mood
	if mood == "menu":
		_watched = ""          # a new game starts its own count
		_raids_seen.clear()
		_chat_seen = -1
	_update_music()
	_set_ambience(AMBIENCE.get(mood, ""))


func set_battle(on: bool) -> void:
	## Battle music while the attack screen is open.
	if on == _battle:
		return
	_battle = on
	_update_music()


func _update_music() -> void:
	var list := "battle" if _battle else mood
	if list == _list:
		return
	_list = list
	_start_track(true)


func _start_track(crossfade: bool) -> void:
	_next_in = -1.0
	var tracks: Array = MUSIC.get(_list, [])
	var old := _music[_front]
	if tracks.is_empty():
		_fade(old, QUIET_DB, FADE, true)
		return
	var pick: String = tracks.pick_random()
	if tracks.size() > 1:
		while pick == _last_track.get(_list, ""):
			pick = tracks.pick_random()
	_last_track[_list] = pick
	_front = 1 - _front
	var p := _music[_front]
	p.stream = _load("music/" + pick)
	p.volume_db = QUIET_DB if crossfade else 0.0
	p.play()
	if crossfade:
		_fade(p, 0.0, FADE, false)
		_fade(old, QUIET_DB, FADE, true)


func _fade(p: AudioStreamPlayer, to_db: float, seconds: float, stop_after: bool) -> void:
	if stop_after and not p.playing:
		return
	var tween := create_tween()
	tween.tween_property(p, "volume_db", to_db, seconds)
	if stop_after:
		tween.tween_callback(func() -> void:
			if p != _music[_front] or _list == "":
				p.stop())


func _on_track_finished(p: AudioStreamPlayer) -> void:
	if p == _music[_front] and _list != "":
		_next_in = GAP


func _process(delta: float) -> void:
	if _next_in < 0.0:
		return
	_next_in -= delta
	if _next_in <= 0.0:
		_start_track(false)


func _set_ambience(ambience: String) -> void:
	if ambience == _ambience_name:
		return
	_ambience_name = ambience
	if ambience == "":
		_ambience.stop()
		return
	var stream: AudioStream = _load("ambience/" + ambience)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_ambience.stream = stream
	_ambience.volume_db = QUIET_DB
	_ambience.play()
	create_tween().tween_property(_ambience, "volume_db", 0.0, FADE)


# --- Effects -----------------------------------------------------------------------

func play(effect: String, pitch_spread := 0.05) -> void:
	## Plays one of EFFECTS, a little higher or lower each time so repeats don't grate.
	var entry: Array = EFFECTS.get(effect, [])
	if entry.is_empty():
		push_warning("No sound effect called %s" % effect)
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(effect, -1000)) < 60:
		return
	_last_played[effect] = now
	var p := _voices[_voice]
	_voice = (_voice + 1) % VOICES
	p.stream = _load("sfx/" + String(entry[0].pick_random()))
	p.volume_db = float(entry[1])
	p.pitch_scale = randf_range(1.0 - pitch_spread, 1.0 + pitch_spread)
	p.play()


func play_later(effect: String, seconds: float) -> void:
	get_tree().create_timer(seconds, true).timeout.connect(play.bind(effect))


func battle_result(won: bool) -> void:
	## Swords clash, then a fanfare or a lament: for battle reports.
	play("sword")
	play_later("sword", 0.22)
	play_later("sword", 0.5)
	play_later("victory" if won else "defeat", 0.9)


func has_effect(effect: String) -> bool:
	return EFFECTS.has(effect)


func _load(path: String) -> AudioStream:
	if not _cache.has(path):
		_cache[path] = load(DIR + path + ".ogg")
	return _cache[path]


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.pressed.is_connected(_on_button):
		node.pressed.connect(_on_button)


func _on_button() -> void:
	play("click", 0.02)


# --- Things that happen on their own -----------------------------------------------

func _check_castle() -> void:
	## A building or a study finishing in your castle.
	var castle: CastleState = Economy.player_castle
	if castle == null:
		return
	var levels := 0
	for b in castle.buildings:
		levels += int(b.level)
	var studies := 0
	for study: String in castle.research:
		studies += int(castle.research[study])
	if castle.id != _watched:
		_watched = castle.id
	elif levels > _levels:
		play("build_done")
	elif studies > _studies:
		play("research_done")
	_levels = levels
	_studies = studies


func _check_raids() -> void:
	## Online: another player's army setting out for your castle.
	for r: Dictionary in Economy.raids:
		if r.get("mine", false) or r.get("state", "") != "out":
			continue
		var key := str(r.get("id", ""))
		if not _raids_seen.has(key):
			_raids_seen[key] = true
			play("alarm")


func _check_chat() -> void:
	## Online: a chat message from someone else.
	if not Economy.chat_loaded:
		return
	var newest := Economy.last_chat_id()
	if _chat_seen >= 0 and newest > _chat_seen and not Economy.chat_messages.is_empty():
		var m: Dictionary = Economy.chat_messages[-1]
		if String(m.get("name", "")) != Economy.player_castle.castle_name:
			play("chat")
	_chat_seen = newest
