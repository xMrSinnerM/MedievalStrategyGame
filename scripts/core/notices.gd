extends CanvasLayer
## Autoload that tells you when something happens in your castles: an army is
## marching on you, you were attacked, a battle was fought, or a building,
## study, batch of soldiers or siege tools finished (NoticeRules). Notices pop
## up as cards in the bottom-right corner on the map and in the castle, and
## while the game window is in the background they also go to the desktop and
## flash the taskbar. Both can be turned off in Settings.

const LIFE := 8.0          ## seconds a card stays
const URGENT_LIFE := 14.0
const MAX_CARDS := 5
const WIDTH := 360.0
const DESKTOP_GATHER := 1.5   ## notices this close together go to the desktop as one
const URGENT := Color(1.0, 0.55, 0.42)
const ABOVE := 112.0      ## room left at the bottom for the castle screen's build bar

var _cards: VBoxContainer
var _main: CastleState     ## the castle the snapshots belong to; a new game resets them
var _snaps := {}           ## castle id -> NoticeRules.snapshot()
var _told := {}            ## notice key -> when it was shown, so each shows once
var _raids := {}           ## ids of armies seen coming for you
var _desktop: Array[Dictionary] = []
var _desktop_left := 0.0


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cards = VBoxContainer.new()
	_cards.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_cards.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cards.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cards.offset_right = -12
	_cards.offset_bottom = -ABOVE
	_cards.alignment = BoxContainer.ALIGNMENT_END
	_cards.add_theme_constant_override("separation", 8)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cards)
	Economy.changed.connect(_on_changed)
	Economy.raids_changed.connect(_on_raids)
	Economy.attack_resolved.connect(_on_report)
	EventBus.siege_started.connect(_on_siege)
	EventBus.battle_fought.connect(_on_battle)


func post(title: String, text: String, icon: String, urgent := false) -> void:
	## Shows a notice in the game and, while the window is in the background, on the desktop.
	if not _in_game():
		return
	if bool(Settings.get_value("notices")):
		_add_card(title, text, icon, urgent)
	if bool(Settings.get_value("desktop_notices")) and not _focused():
		_desktop.append({"title": title, "text": text})
		_desktop_left = DESKTOP_GATHER
		DisplayServer.window_request_attention()


func _in_game() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.has_method("in_game") and scene.in_game()


func _focused() -> bool:
	return get_window().has_focus() and DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED


# --- What happened -------------------------------------------------------------

func _on_changed() -> void:
	if Economy.player_castle == null:
		return
	if Economy.player_castle != _main:
		# Another game started: what it already has isn't news.
		_main = Economy.player_castle
		_snaps.clear()
		_raids.clear()
	var seen := {}
	for c in Economy.castles:
		if c.owner != "player":
			continue
		seen[c.id] = true
		var snap := NoticeRules.snapshot(c)
		if _snaps.has(c.id):
			for n in NoticeRules.changes(Economy.rules, _snaps[c.id], snap, c == Economy.player_castle):
				_tell(n)
		_snaps[c.id] = snap
	for id: String in _snaps.keys():
		if not seen.has(id):
			_snaps.erase(id)


func _tell(n: Dictionary) -> void:
	if _told.has(n.key):
		return
	_told[n.key] = Time.get_ticks_msec()
	post(n.title, n.text, n.icon)


func _on_raids() -> void:
	## Online: another player's army set out for your castle.
	for r: Dictionary in Economy.raids:
		if r.get("mine", false) or r.get("state", "") != "out" or _raids.has(r.get("id")):
			continue
		_raids[r.get("id")] = true
		var target := "your castle"
		if r.has("village"):
			target = "your village"
		post("You are under attack!", "%s's army is marching on %s. It arrives in %s." % [r.get("attacker_name", "Someone"),
				target, _clock(float(r.get("arrive", 0.0)) - Economy.now())], "battle", true)


func _on_siege(castle_id: String, besieger: String, until: float) -> void:
	## Single player: a lord laid siege to one of your castles.
	var castle := Economy.get_castle(castle_id)
	if castle == null or castle.owner != "player":
		return
	var left := until - Time.get_ticks_msec() * 0.001
	post("Your castle is besieged!", "%s is besieging %s. The assault comes in %s." % [besieger, castle.castle_name,
			_clock(left)], "battle", true)


func _on_battle(report: Dictionary) -> void:
	## Single player: a lord stormed one of your castles.
	if report.get("player", "") != "b" or not report.get("siege", false):
		return
	var text := "%s captured %s!" if report.outcome == "captured" else (
			"%s sacked %s." if report.outcome == "sacked" else "%s failed to storm %s. Your walls held.")
	post("Your castle was stormed" if report.outcome != "held" else "Your castle held",
			text % [report.attacker, report.defender], "defence", report.outcome != "held")


func _on_report(report: Dictionary) -> void:
	## A battle you took part in was fought. The full report opens on the map.
	var won: bool = report.get("winner", "") == report.get("player", "")
	if report.get("player", "") == "b":
		var by := String(report.get("name", report.get("attacker", "")))
		if report.get("village", false):
			post("Your village was attacked", ("You held %s against %s." if won else "%s took %s from you.") \
					% ([report.get("name", ""), report.get("other", "")] if won else [report.get("other", ""), report.get("name", "")]),
					"villages", not won)
		else:
			post("Your castle was attacked", ("You held your castle against %s." if won else "%s broke through and plundered your castle.") % by,
					"defence", not won)
		return
	if report.get("empty", false):
		post("Battle report", "Your army found %s empty." % report.get("defender", "the camp"), "battle")
		return
	var place := String(report.get("defender", report.get("name", "")))
	post("Battle report", ("Your army won at %s." if won else "Your army was beaten at %s.") % place, "battle")


# --- Cards ---------------------------------------------------------------------

func _add_card(title: String, text: String, icon: String, urgent: bool) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuStyle.panel(0.94, 10))
	card.custom_minimum_size = Vector2(WIDTH, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = "Click to dismiss"
	card.set_meta("left", URGENT_LIFE if urgent else LIFE)
	card.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			card.queue_free())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var pic := Icons.rect(icon, 34)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pic)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 2)
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(words)
	var head := MenuStyle.label(title, 16, URGENT if urgent else MenuStyle.GOLD)
	head.add_theme_font_override("font", GameTheme.TITLE_FONT)
	words.add_child(head)
	var body := MenuStyle.label(text, 15)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 80, 0)
	words.add_child(body)
	for l: Label in [head, body]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cards.add_child(card)
	while _cards.get_child_count() > MAX_CARDS:
		var oldest := _cards.get_child(0)
		_cards.remove_child(oldest)
		oldest.queue_free()


func _process(delta: float) -> void:
	_cards.visible = _in_game()
	for card: Control in _cards.get_children():
		var left: float = card.get_meta("left") - delta
		card.set_meta("left", left)
		card.modulate.a = clampf(left, 0.0, 1.0)
		if left <= 0.0:
			card.queue_free()
	if not _desktop.is_empty():
		_desktop_left -= delta
		if _desktop_left <= 0.0:
			_send_desktop()
	# Forget old keys now and then; an hour covers the server catching up.
	if Engine.get_process_frames() % 3600 == 0:
		var cutoff := Time.get_ticks_msec() - 3_600_000
		for key: String in _told.keys():
			if int(_told[key]) < cutoff:
				_told.erase(key)


func _send_desktop() -> void:
	var title: String = _desktop[0].title
	var text: String = _desktop[0].text
	if _desktop.size() > 1:
		title = "Medieval Strategy"
		var lines: PackedStringArray = []
		for n in _desktop.slice(0, 3):
			lines.append(n.text)
		if _desktop.size() > 3:
			lines.append("and %d more" % (_desktop.size() - 3))
		text = "\n".join(lines)
	_desktop.clear()
	var command := NoticeRules.desktop_command(OS.get_name(), title, text)
	if not command.is_empty():
		OS.create_process(command[0], command[1])


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]
