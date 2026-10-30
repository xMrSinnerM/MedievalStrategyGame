extends PanelContainer
## The alliance war (K on the world map, online): alliances fight over the
## capitals in weekly seasons. Shows this season's standings, who holds each
## capital and what it earns them, the last season's champions and the prize
## your alliance's place won you. War points are won only by holding, taking
## and defending capitals (data/wars.json); nothing is bought with money.

const HordeSection := preload("res://scripts/ui/horde_section.gd")
const ME := Color(1.0, 0.85, 0.45)
const DONE := Color(0.55, 0.9, 0.45)
const LAST_SHOWN := 5

var _rule: Label
var _season: Label
var _standings: GridContainer
var _capitals: GridContainer
var _last: GridContainer
var _champions: Label
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
	var title := MenuStyle.title("Alliance War", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_season = MenuStyle.label("", 17, MenuStyle.TEXT)
	box.add_child(_season)
	_rule = MenuStyle.label("", 14, MenuStyle.MUTED)
	_rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rule.custom_minimum_size = Vector2(880, 0)
	box.add_child(_rule)
	set_meta("window_help", _rule)
	box.add_child(HSeparator.new())
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	box.add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(MenuStyle.label("This season", 19, MenuStyle.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_standings = _grid(6)
	_standings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_standings)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	right.add_child(MenuStyle.label("Capitals", 19, MenuStyle.GOLD))
	_capitals = _grid(4)
	right.add_child(_capitals)
	box.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 36)
	box.add_child(bottom)
	var past := VBoxContainer.new()
	past.add_theme_constant_override("separation", 6)
	past.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(past)
	past.add_child(MenuStyle.label("Last season", 19, MenuStyle.GOLD))
	_champions = MenuStyle.label("", 15, MenuStyle.TEXT)
	past.add_child(_champions)
	_last = _grid(3)
	past.add_child(_last)
	var yours := VBoxContainer.new()
	yours.add_theme_constant_override("separation", 6)
	yours.custom_minimum_size = Vector2(400, 0)
	bottom.add_child(yours)
	yours.add_child(MenuStyle.label("Your alliance", 19, MenuStyle.GOLD))
	_mine = MenuStyle.label("", 15, ME)
	_mine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mine.custom_minimum_size = Vector2(400, 0)
	yours.add_child(_mine)
	_prize = MenuStyle.label("", 15, MenuStyle.TEXT)
	_prize.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prize.custom_minimum_size = Vector2(400, 0)
	yours.add_child(_prize)
	_claim = GameTheme.primary(Button.new())
	_claim.text = "Claim prize"
	_claim.focus_mode = Control.FOCUS_NONE
	_claim.custom_minimum_size = Vector2(160, 32)
	_claim.add_theme_font_size_override("font_size", 15)
	_claim.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_claim.pressed.connect(func() -> void:
		_claim.disabled = true
		Economy.claim_war_prize())
	yours.add_child(_claim)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(MenuStyle.button("Refresh", Economy.ask_war_board, 180.0))
	var close_button := MenuStyle.button("Close", close_panel, 180.0)
	buttons.add_child(close_button)
	set_meta("window_close", close_button)   ## in a GameWindow its own close button does this
	box.add_child(buttons)
	Economy.war_board_changed.connect(_fill)


func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer >= 1.0:
		_timer = 0.0
		_fill_season()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_K and not get_tree().paused and Economy.online:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and visible:
		close_panel()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	_fill()
	Economy.ask_war_board()
	visible = true


func close_panel() -> void:
	visible = false


func _fill() -> void:
	var board: Dictionary = Economy.war_board
	_fill_season()
	_fill_rule(board.get("rules", {}))
	_fill_standings(board.get("season", {}).get("alliances", []), _my_alliance())
	_fill_capitals(board.get("capitals", []))
	_fill_last(board.get("last", {}).get("alliances", []))
	_fill_mine()


func _my_alliance() -> int:
	var mine: Variant = Economy.war_board.get("mine")
	return int(mine.get("alliance_id", -1)) if mine is Dictionary else -1


func _fill_season() -> void:
	var season: Dictionary = Economy.war_board.get("season", {})
	if season.is_empty():
		_season.text = "Asking the server..."
		return
	_season.text = "This season ends in %s, on %s UTC. Then a new one begins." % [
			_days(float(season.end) - Economy.now()), _when(float(season.end))]


func _fill_rule(rules: Dictionary) -> void:
	if rules.is_empty():
		_rule.text = ""
		return
	_rule.text = "Alliances win war points with the capitals: %d an hour for each level of a capital they hold, %d for each level of one they take (once a season), and points for every attacker who falls at a capital they keep. When the season ends, every member of an alliance with points claims a prize for its place." % [
			int(rules.get("hold_per_hour", 0)), int(rules.get("capture", 0))]


func _fill_standings(rows: Array, mine: int) -> void:
	_clear(_standings)
	for text in ["#", "Alliance", "Points", "Capitals", "Taken", "Held"]:
		_standings.add_child(_cell(text, MenuStyle.MUTED, 14, text != "Alliance"))
	if rows.is_empty():
		_standings.add_child(_cell("", MenuStyle.MUTED, 15, true))
		var none := _cell("No alliance has war points yet this season.", MenuStyle.MUTED, 15, false)
		_standings.add_child(none)
		for i in 4:
			_standings.add_child(_cell("", MenuStyle.MUTED, 15, true))
		return
	for a: Dictionary in rows:
		var color := ME if int(a.get("alliance_id", 0)) == mine else MenuStyle.TEXT
		_standings.add_child(_cell(str(int(a.get("rank", 0))), color, 16, true))
		var who := _cell("[%s] %s" % [String(a.get("tag", "")), String(a.get("name", ""))], color, 16, false)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_standings.add_child(who)
		_standings.add_child(_cell(str(int(a.get("points", 0))), color, 16, true))
		_standings.add_child(_cell(str(int(a.get("capitals", 0))), color, 16, true))
		_standings.add_child(_cell(str(int(a.get("captures", 0))), color, 16, true))
		_standings.add_child(_cell(str(int(a.get("defences", 0))), color, 16, true))


func _fill_capitals(rows: Array) -> void:
	_clear(_capitals)
	for text in ["Town", "Level", "Held by", "Per hour"]:
		_capitals.add_child(_cell(text, MenuStyle.MUTED, 14, text == "Level" or text == "Per hour"))
	var mine := _my_alliance()
	for c: Dictionary in rows:
		var ours := c.get("alliance_id") != null and int(c.alliance_id) == mine
		var color := ME if ours else MenuStyle.TEXT
		_capitals.add_child(_cell(String(c.get("name", "")), color, 15, false))
		_capitals.add_child(_cell(str(int(c.get("level", 1))), color, 15, true))
		var owner := String(c.get("owner", ""))
		var tag := String(c.get("tag", ""))
		var held := "Town guard" if owner == "" else ("[%s] %s" % [tag, owner] if tag != "" else owner)
		_capitals.add_child(_cell(held, color if owner != "" else MenuStyle.MUTED, 15, false))
		var per_hour := int(c.get("per_hour", 0))
		_capitals.add_child(_cell("+%d" % per_hour if per_hour > 0 else "-", color if per_hour > 0 else MenuStyle.MUTED, 15, true))


func _fill_last(rows: Array) -> void:
	_clear(_last)
	if rows.is_empty():
		_champions.text = "No alliance won war points last season."
		return
	var first: Dictionary = rows[0]
	_champions.text = "Champions: [%s] %s with %d points." % [String(first.get("tag", "")), String(first.get("name", "")),
			int(first.get("points", 0))]
	var mine := _my_alliance()
	for a: Dictionary in rows.slice(0, LAST_SHOWN):
		var color := ME if int(a.get("alliance_id", 0)) == mine else MenuStyle.TEXT
		_last.add_child(_cell("#%d" % int(a.get("rank", 0)), color, 15, true))
		var who := _cell("[%s] %s" % [String(a.get("tag", "")), String(a.get("name", ""))], color, 15, false)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_last.add_child(who)
		_last.add_child(_cell(str(int(a.get("points", 0))), color, 15, true))


func _fill_mine() -> void:
	var board: Dictionary = Economy.war_board
	_claim.visible = false
	if board.is_empty():
		_mine.text = ""
		_prize.text = ""
		return
	var mine: Variant = board.get("mine")
	if not mine is Dictionary:
		_mine.text = "Join an alliance to fight for the capitals."
	else:
		var now: Variant = mine.get("now")
		var held := int(mine.get("capitals", 0))
		if now is Dictionary:
			_mine.text = "#%d this season with %d points, holding %d %s." % [int(now.get("rank", 0)), int(now.get("points", 0)),
					held, "capital" if held == 1 else "capitals"]
		else:
			_mine.text = "No war points yet this season. Take a capital to start winning them."
	var p: Dictionary = board.get("prize", {})
	var prize: Variant = p.get("prize")
	var gives := HordeSection.item_text(prize) if prize is Dictionary else ""
	if bool(p.get("claimed", false)):
		_prize.text = "Last season's prize (claimed): " + gives
		_prize.add_theme_color_override("font_color", DONE)
	elif bool(p.get("can_claim", false)):
		var last: Variant = mine.get("last") if mine is Dictionary else null
		_prize.text = "Last season your alliance came #%d. Your prize: %s" % [
				int(last.get("rank", 0)) if last is Dictionary else 0, gives]
		_prize.add_theme_color_override("font_color", MenuStyle.TEXT)
		_claim.visible = true
		_claim.disabled = false
	else:
		_prize.text = String(p.get("why", ""))
		if prize is Dictionary:
			_prize.text += " (the prize was: %s)" % gives
		_prize.add_theme_color_override("font_color", MenuStyle.MUTED)


func _grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 22)
	g.add_theme_constant_override("v_separation", 4)
	return g


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func _cell(text: String, color: Color, size: int, right: bool) -> Label:
	var l := MenuStyle.label(text, size, color)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]


static func _when(t: float) -> String:
	## "Monday 00:00".
	var d := Time.get_datetime_dict_from_unix_time(int(t))
	var days := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
	return "%s %02d:%02d" % [days[int(d.weekday)], int(d.hour), int(d.minute)]
