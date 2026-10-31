extends PanelContainer
## The weekly alliance tournament (the Tournament tab of the Alliance window,
## online): a knockout bracket between the mightiest alliances, drawn on
## Monday. In each match both alliances score the renown their members earn
## while it lasts; the higher score goes through. Shows the bracket with the
## scores, the round on and the prize your alliance's run won you
## (data/tournaments.json). Nothing here is bought with money.

const HordeSection := preload("res://scripts/ui/horde_section.gd")
const ME := Color(1.0, 0.85, 0.45)
const WON := Color(0.55, 0.9, 0.45)
const OUT := Color(0.6, 0.55, 0.5)
const PLACES := {1: "won the tournament", 2: "reached the final", 4: "reached the semi-finals", 8: "reached the quarter-finals"}

var _status: Label
var _rule: Label
var _bracket: HBoxContainer
var _mine: Label
var _prize: Label
var _claim: Button
var _timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(940, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	box.add_child(head)
	var title := MenuStyle.title("Alliance Tournament", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_status = MenuStyle.label("", 17, MenuStyle.TEXT)
	box.add_child(_status)
	_rule = MenuStyle.label("", 14, MenuStyle.MUTED)
	_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule.custom_minimum_size = Vector2(880, 0)
	box.add_child(_rule)
	set_meta("window_help", _rule)
	box.add_child(HSeparator.new())
	_bracket = HBoxContainer.new()
	_bracket.add_theme_constant_override("separation", 28)
	_bracket.custom_minimum_size = Vector2(0, 330)
	box.add_child(_bracket)
	box.add_child(HSeparator.new())
	box.add_child(MenuStyle.label("Your alliance", 19, MenuStyle.GOLD))
	_mine = MenuStyle.label("", 15, ME)
	_mine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mine.custom_minimum_size = Vector2(880, 0)
	box.add_child(_mine)
	_prize = MenuStyle.label("", 15, MenuStyle.TEXT)
	_prize.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prize.custom_minimum_size = Vector2(880, 0)
	box.add_child(_prize)
	_claim = GameTheme.primary(Button.new())
	_claim.text = "Claim prize"
	_claim.focus_mode = Control.FOCUS_NONE
	_claim.custom_minimum_size = Vector2(160, 32)
	_claim.add_theme_font_size_override("font_size", 15)
	_claim.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_claim.pressed.connect(func() -> void:
		_claim.disabled = true
		Economy.claim_tournament_prize())
	box.add_child(_claim)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(MenuStyle.button("Refresh", Economy.ask_tournament, 180.0))
	var close_button := MenuStyle.button("Close", close_panel, 180.0)
	buttons.add_child(close_button)
	set_meta("window_close", close_button)   ## in a GameWindow its own close button does this
	box.add_child(buttons)
	Economy.tournament_changed.connect(_fill)


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_fill_status()


func open_panel() -> void:
	_fill()
	Economy.ask_tournament()
	visible = true


func close_panel() -> void:
	visible = false


func _fill() -> void:
	var board: Dictionary = Economy.tournament
	_fill_status()
	_fill_rule(board.get("rules", {}))
	_fill_bracket(board)
	_fill_mine(board)


func _names(board: Dictionary) -> Dictionary:
	var out := {}
	for e: Dictionary in board.get("entrants", []):
		out[int(e.id)] = e
	return out


func _fill_status() -> void:
	var board: Dictionary = Economy.tournament
	if board.is_empty():
		_status.text = "Asking the server..."
		return
	var now := Economy.now()
	var rounds: Array = board.get("rounds", [])
	if rounds.is_empty():
		_status.text = "No tournament this week: it takes two alliances with members. The next bracket is drawn in %s." % \
				_days(float(board.get("end", now)) - now)
		return
	for r: Dictionary in rounds:
		if now < float(r.start):
			_status.text = "The %s start in %s, on %s UTC." % [String(r.name).to_lower(), _days(float(r.start) - now),
					_when(float(r.start))]
			if String(r.name) == "Final":
				_status.text = "The final starts in %s, on %s UTC." % [_days(float(r.start) - now), _when(float(r.start))]
			return
		if now < float(r.end):
			_status.text = "%s: %s left. Earn renown to score for your alliance!" % [String(r.name), _days(float(r.end) - now)]
			return
	_status.text = "This week's tournament is over. The next bracket is drawn in %s." % _days(float(board.get("end", now)) - now)


func _fill_rule(rules: Dictionary) -> void:
	if rules.is_empty():
		_rule.text = ""
		return
	_rule.text = "Every Monday the %d mightiest alliances are drawn into a knockout bracket. In a match, each alliance scores the renown its members earn while it lasts: building, training, beating robber barons, bringing home loot and winning battles against players. The higher score goes through (a tie to the higher seed), and once the final is over every member claims a prize for how far their alliance got." % \
			int(rules.get("size", 8))


func _fill_bracket(board: Dictionary) -> void:
	for child in _bracket.get_children():
		_bracket.remove_child(child)
		child.queue_free()
	var rounds: Array = board.get("rounds", [])
	var names := _names(board)
	var mine := int(board.get("mine", -1)) if board.get("mine") != null else -1
	var now := Economy.now()
	for i in rounds.size():
		var r: Dictionary = rounds[i]
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 6)
		_bracket.add_child(column)
		column.add_child(MenuStyle.label(String(r.name), 18, MenuStyle.GOLD))
		var on := now >= float(r.start) and now < float(r.end)
		var when := MenuStyle.label("%s - %s%s" % [_when(float(r.start)), _when(float(r.end)), "  (now)" if on else ""], 13,
				ME if on else MenuStyle.MUTED)
		column.add_child(when)
		var matches := VBoxContainer.new()
		matches.size_flags_vertical = Control.SIZE_EXPAND_FILL
		matches.alignment = BoxContainer.ALIGNMENT_CENTER
		matches.add_theme_constant_override("separation", 12 + 40 * i)
		column.add_child(matches)
		for m: Dictionary in r.get("matches", []):
			matches.add_child(_match_box(m, names, mine, now >= float(r.start)))


func _match_box(m: Dictionary, names: Dictionary, mine: int, started: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", GameTheme.panel_box(0.55, 6))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)
	var winner: Variant = m.get("winner")
	for side in ["a", "b"]:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var id: Variant = m.get(side)
		var who := MenuStyle.label("", 15, MenuStyle.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		who.clip_text = true
		var score := MenuStyle.label("", 15, MenuStyle.TEXT)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		score.custom_minimum_size = Vector2(54, 0)
		row.add_child(who)
		row.add_child(score)
		if id == null:
			who.text = "bye"
			who.add_theme_color_override("font_color", OUT)
			continue
		if int(id) == 0:
			who.text = "to be decided"
			who.add_theme_color_override("font_color", OUT)
			continue
		var e: Dictionary = names.get(int(id), {})
		who.text = "%d. [%s] %s" % [int(e.get("seed", 0)), String(e.get("tag", "")), String(e.get("name", "?"))]
		if started and m.get("a") != null and m.get("b") != null:
			score.text = str(int(m.get(side + "_points", 0)))
		var color := MenuStyle.TEXT
		if winner != null:
			color = WON if int(winner) == int(id) else OUT
		if int(id) == mine:
			color = ME if winner == null or int(winner) == int(id) else color
		who.add_theme_color_override("font_color", color)
		score.add_theme_color_override("font_color", color)
	return panel


func _fill_mine(board: Dictionary) -> void:
	_claim.visible = false
	if board.is_empty():
		_mine.text = ""
		_prize.text = ""
		return
	if board.get("mine") == null:
		_mine.text = "Join an alliance to play in the tournaments."
	else:
		_mine.text = _my_run(board)
	var p: Dictionary = board.get("prize", {})
	var prize: Variant = p.get("prize")
	var gives := HordeSection.item_text(prize) if prize is Dictionary else ""
	var place := int(p.get("place", 0))
	if bool(p.get("claimed", false)):
		_prize.text = "Your tournament prize (claimed): " + gives
		_prize.add_theme_color_override("font_color", WON)
	elif bool(p.get("can_claim", false)):
		_prize.text = "Your alliance %s. Your prize: %s" % [String(PLACES.get(place, "played")), gives]
		_prize.add_theme_color_override("font_color", MenuStyle.TEXT)
		_claim.visible = true
		_claim.disabled = false
	else:
		_prize.text = String(p.get("why", ""))
		_prize.add_theme_color_override("font_color", MenuStyle.MUTED)


func _my_run(board: Dictionary) -> String:
	## Where your alliance stands in this week's bracket.
	var mine := int(board.mine)
	var now := Economy.now()
	var rounds: Array = board.get("rounds", [])
	var last := ""
	for r: Dictionary in rounds:
		for m: Dictionary in r.get("matches", []):
			if m.get("a") == null or m.get("b") == null:
				if (m.get("a") != null and int(m.a) == mine) or (m.get("b") != null and int(m.b) == mine):
					last = "A bye in the %s: you go straight through." % String(r.name).to_lower()
				continue
			var us := "a" if int(m.a) == mine else ("b" if int(m.b) == mine else "")
			if us == "":
				continue
			var them := "b" if us == "a" else "a"
			var foe: Dictionary = _names(board).get(int(m[them]), {})
			var vs := "[%s] %s" % [String(foe.get("tag", "")), String(foe.get("name", ""))]
			if now < float(r.start):
				return "Next: %s against %s." % [String(r.name), vs]
			var score := "%d to %d" % [int(m[us + "_points"]), int(m[them + "_points"])]
			if m.get("winner") == null:
				return "%s against %s: %s. Every bit of renown your members earn counts." % [String(r.name), vs, score]
			if int(m.winner) != mine:
				return "Knocked out in the %s by %s, %s." % [String(r.name).to_lower(), vs, score]
			last = "Won the %s against %s, %s." % [String(r.name).to_lower(), vs, score]
	if last != "":
		return last
	return "Your alliance isn't in this week's bracket. The mightiest alliances are drawn every Monday."


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]


static func _when(t: float) -> String:
	## "Mon 00:00".
	var d := Time.get_datetime_dict_from_unix_time(int(t))
	var days := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	return "%s %02d:%02d" % [days[int(d.weekday)], int(d.hour), int(d.minute)]
