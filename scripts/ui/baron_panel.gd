extends PanelContainer
## Shown on the world map when you click a robber baron camp: its level and
## progress to the next, its garrison, palisade and loot, whether it is
## rebuilding, the march time and a button to open the attack screen.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)

var camp_id := ""

var _title: Label
var _level: Label
var _details: Label
var _odds: Label
var _attack: Button

var _picture: InfoPicture

func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.85, 12))
	custom_minimum_size = Vector2(440, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_picture = InfoPicture.wrap(self, box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = _label(20, Color(1.0, 0.7, 0.55))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: show_camp(""))
	head.add_child(close)
	_level = _label(15, MUTED)
	box.add_child(_level)
	_details = _label(14, TEXT)
	box.add_child(_details)
	_odds = _label(15, TEXT)
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_odds)
	_attack = GameTheme.primary(Button.new())
	_attack.focus_mode = Control.FOCUS_NONE
	_attack.pressed.connect(_send)
	box.add_child(_attack)
	EventBus.baron_selected.connect(show_camp)
	EventBus.party_selected.connect(func(id: String) -> void:
		if id != "":
			show_camp(""))
	EventBus.settlement_selected.connect(func(id: String) -> void:
		if id != "":
			show_camp(""))
	EventBus.player_selected.connect(func(who: String) -> void:
		if who != "":
			show_camp(""))
	Economy.changed.connect(_refresh)


func show_camp(id: String) -> void:
	camp_id = id
	visible = Economy.get_baron(id) != null
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	var camp := Economy.get_baron(camp_id)
	if camp == null:
		visible = false
		return
	var br := Economy.baron_rules.for_camp(camp)
	var now := Economy.now()
	_title.text = camp.camp_name
	_picture.show_place(InfoPicture.faction_place("castle", camp.id) if camp.fortress else "camp")
	_level.text = ("Invader camp, level %d" if camp.is_invader() else "Fortress, level %d" if camp.fortress
			else "Robber baron camp, level %d") % camp.level
	var lines: PackedStringArray = []
	if camp.is_invader():
		lines.append("Baron Invasion: a win gives %d event points and raises it a level" % (camp.points * camp.level))
		var inv := Economy.invasion()
		if not inv.is_empty() and float(inv.start) == camp.event:
			lines.append("Leaves in %s    Your points: %d" % [_long_clock(float(inv.end) - now), Economy.invasion_points()])
	elif camp.level < br.max_level:
		lines.append("Wins %d of %d to reach level %d" % [camp.defeats, br.defeats_needed(camp.level), camp.level + 1])
	var garrison := camp.garrison(br)
	var total := 0
	for unit: String in garrison:
		total += int(garrison[unit])
	lines.append("Garrison: %d soldiers" % total)
	for unit: String in garrison:
		lines.append("    %d %s" % [garrison[unit], Economy.rules.unit_plural(unit)])
	var wall := Battle.wall_from_defense(br.palisade(camp.level))
	lines.append("%s: defenders +%d%% defence" % ["Walls" if camp.fortress else "Palisade", roundi((wall - 1.0) * 100.0)])
	var loot := Economy.baron_loot(camp.level, camp)
	var parts: PackedStringArray = []
	for r: String in loot:
		parts.append("%d %s" % [loot[r], r])
	lines.append("Loot: " + ", ".join(parts) + Economy.loot_bonus_note())
	lines.append("March: %s each way" % _clock(Economy.march_time_to(camp)))
	if camp.fortress:
		lines.append("Its lord drops better gear than any baron")
	if not camp.is_ready(now):
		lines.append(("Its lord is rebuilding for %s" if camp.fortress else "Rebuilding for %s") % _long_clock(camp.rebuilt_at - now)
				if camp.rebuilt_at - now >= 3600.0 else ("Rebuilding for %s" % _clock(camp.rebuilt_at - now)))
	_details.text = "\n".join(lines)
	var army: Dictionary = Economy.player_castle.troops
	var mine := Economy.player_castle.troop_count()
	if mine <= 0:
		_odds.text = "Your garrison is empty. Train soldiers, or bring your warband home and move its soldiers into the garrison."
		_odds.add_theme_color_override("font_color", TEXT)
	else:
		var chance := Battle.siege_odds(Economy.rules, Battle.auto_waves(army), garrison, Battle.DEFAULT_LAYOUT, 1, wall)
		_odds.text = "Your garrison of %d: %s (%d%%)" % [mine, Battle.odds_text(chance), roundi(chance * 100.0)]
		_odds.add_theme_color_override("font_color", Color(0.95, 0.4, 0.3).lerp(Color(0.55, 0.9, 0.45), chance))
	_attack.text = "Prepare attack" if camp.is_ready(now) else "Rebuilding"
	_attack.disabled = mine <= 0 or not camp.is_ready(now)


func _send() -> void:
	EventBus.attack_screen_requested.emit(camp_id)


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


static func _long_clock(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
