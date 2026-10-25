extends VBoxContainer
## The Ember Horde on the event screen (online): how the horde stands, your
## horde points and war trophies, the Trophy Market, and the players with the
## most horde points, with the ranked prize you can claim once the horde has
## gone. Everything here is earned by beating horde camps; nothing is bought
## with money.

const ME := Color(1.0, 0.85, 0.45)
const DONE := Color(0.55, 0.9, 0.45)
const ROWS_SHOWN := 10

var _status: Label
var _market: GridContainer
var _board: GridContainer
var _rank: Label
var _prize: Label
var _claim: Button


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_status = MenuStyle.label("", 15, MenuStyle.MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(900, 0)
	add_child(_status)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	add_child(columns)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	columns.add_child(left)
	left.add_child(MenuStyle.label("Trophy Market", 19, MenuStyle.GOLD))
	_market = GridContainer.new()
	_market.columns = 4
	_market.add_theme_constant_override("h_separation", 16)
	_market.add_theme_constant_override("v_separation", 4)
	left.add_child(_market)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	right.custom_minimum_size = Vector2(300, 0)
	columns.add_child(right)
	right.add_child(MenuStyle.label("Most horde points", 19, MenuStyle.GOLD))
	_board = GridContainer.new()
	_board.columns = 3
	_board.add_theme_constant_override("h_separation", 20)
	_board.add_theme_constant_override("v_separation", 3)
	right.add_child(_board)
	_rank = MenuStyle.label("", 15, ME)
	_rank.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_rank)
	_prize = MenuStyle.label("", 15, MenuStyle.TEXT)
	_prize.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prize.custom_minimum_size = Vector2(300, 0)
	right.add_child(_prize)
	_claim = GameTheme.primary(Button.new())
	_claim.text = "Claim prize"
	_claim.focus_mode = Control.FOCUS_NONE
	_claim.custom_minimum_size = Vector2(160, 32)
	_claim.add_theme_font_size_override("font_size", 15)
	_claim.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_claim.pressed.connect(func() -> void:
		_claim.disabled = true
		Economy.claim_horde_prize())
	right.add_child(_claim)
	Economy.horde_board_changed.connect(_fill_board)
	Economy.changed.connect(func() -> void:
		if is_visible_in_tree():
			fill())


func fill() -> void:
	_fill_status()
	_fill_market()
	_fill_board()


func _fill_status() -> void:
	var last := Economy.last_horde()
	if last.is_empty():
		_status.text = "No Ember Horde on the calendar."
		return
	var t := Economy.now()
	var points := Economy.my_horde_points()
	if t < float(last.end):
		_status.text = "Riding now, gone in %s. The horde has made camp near your castle: every win gives horde points and war trophies for each level of the camp, and the Warlord's camp gives three times as many. Your points: %d    War trophies: %d" % [
				_days(float(last.end) - t), points, Economy.war_trophies()]
	else:
		_status.text = "The horde has gone. Spend your trophies and claim your prize before it comes back in %s. Your points: %d    War trophies: %d" % [
				_days(float(last.start) + 7 * 86400.0 - t), points, Economy.war_trophies()]


func _fill_market() -> void:
	for child in _market.get_children():
		_market.remove_child(child)
		child.queue_free()
	var open := Economy.in_last_horde()
	for item: Dictionary in Economy.horde_rules().get("market", []):
		var left := int(item.stock) - Economy.horde_bought(String(item.id))
		var why := Economy.check_horde_buy(item)
		var color := MenuStyle.TEXT if why == "" else MenuStyle.MUTED
		var name := MenuStyle.label(String(item.name), 15, color)
		name.tooltip_text = item_text(item)
		name.mouse_filter = Control.MOUSE_FILTER_PASS
		_market.add_child(name)
		var what := MenuStyle.label(item_text(item), 14, color)
		what.custom_minimum_size = Vector2(220, 0)
		what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_market.add_child(what)
		_market.add_child(MenuStyle.label("%d left" % maxi(0, left) if open else "", 14, MenuStyle.MUTED))
		var buy := GameTheme.primary(Button.new()) if why == "" else Button.new()
		buy.text = "%d trophies" % int(item.cost)
		buy.focus_mode = Control.FOCUS_NONE
		buy.custom_minimum_size = Vector2(120, 28)
		buy.add_theme_font_size_override("font_size", 14)
		buy.disabled = why != ""
		buy.tooltip_text = why
		buy.pressed.connect(func() -> void:
			buy.disabled = true
			Economy.buy_horde(item))
		_market.add_child(buy)


static func item_text(item: Dictionary) -> String:
	## "1200 wood, 1200 stone", "40 Spearmen", "10 Siege ladders", or the gear's stats.
	var parts: PackedStringArray = []
	var res: Dictionary = item.get("resources", {})
	for r: String in res:
		parts.append("%d %s" % [int(res[r]), r])
	var troops: Dictionary = item.get("troops", {})
	for unit: String in troops:
		parts.append("%d %s" % [int(troops[unit]), Economy.rules.unit_plural(unit) if Economy.rules.has_unit(unit) else unit])
	var tools: Dictionary = item.get("tools", {})
	for tool: String in tools:
		parts.append("%d %s" % [int(tools[tool]), Economy.rules.tool_plural(tool) if Economy.rules.has_tool(tool) else tool])
	var gear: Dictionary = item.get("gear", {})
	if not gear.is_empty():
		var stats: PackedStringArray = []
		for s: String in gear.get("stats", {}):
			stats.append("+%d%% %s" % [int(gear.stats[s]), String(Economy.gear_rules.stats.get(s, {}).get("name", s))
					if Economy.gear_rules != null else s])
		parts.append("%s %s gear: %s" % [String(gear.get("rarity", "")).capitalize(), String(gear.get("slot", "")),
				", ".join(stats)])
	if int(item.get("trophies", 0)) > 0:
		parts.append("%d war trophies" % int(item.trophies))
	return ", ".join(parts)


func _fill_board() -> void:
	for child in _board.get_children():
		_board.remove_child(child)
		child.queue_free()
	var board: Dictionary = Economy.horde_board
	var me: Variant = board.get("me")
	var my_name := String(me.get("name", "")) if me is Dictionary else ""
	var rank := 0
	for p: Dictionary in board.get("players", []):
		rank += 1
		if rank > ROWS_SHOWN:
			break
		var color := ME if String(p.name) == my_name else MenuStyle.TEXT
		_board.add_child(_cell(str(rank), color, true))
		var tag := String(p.get("tag", ""))
		var who := _cell(("[%s] " % tag if tag != "" else "") + String(p.name), color, false)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_board.add_child(who)
		_board.add_child(_cell(str(int(p.get("points", 0))), color, true))
	_claim.visible = false
	if board.is_empty():
		_rank.text = "Asking the server..."
		_prize.text = _prize_list()
		return
	if me is Dictionary:
		_rank.text = "You are #%d of %d with %d points." % [int(board.get("rank", 0)), int(board.get("total", 0)), int(me.get("points", 0))]
	elif rank == 0:
		_rank.text = "Nobody has horde points yet."
	else:
		_rank.text = "%d players have horde points. Beat horde camps to join them." % int(board.get("total", 0))
	var prize: Variant = board.get("prize")
	var over := Economy.now() >= float(Economy.last_horde().get("end", INF))
	if prize is Dictionary:
		var gives := item_text(prize)
		if Economy.horde_prize_taken():
			_prize.text = "Your prize (claimed): " + gives
			_prize.add_theme_color_override("font_color", DONE)
		elif over:
			_prize.text = "Your prize: " + gives
			_prize.add_theme_color_override("font_color", MenuStyle.TEXT)
			_claim.visible = true
			_claim.disabled = false
		else:
			_prize.text = "If it ended now, your prize: %s. Prizes are given once the horde has gone." % gives
			_prize.add_theme_color_override("font_color", MenuStyle.MUTED)
	else:
		_prize.text = _prize_list()
		_prize.add_theme_color_override("font_color", MenuStyle.MUTED)


func _prize_list() -> String:
	## The ranked prizes, best first.
	var lines: PackedStringArray = ["Prizes once the horde has gone:"]
	var from := 1
	for p: Dictionary in Economy.horde_rules().get("prizes", []):
		var up_to := int(p.get("up_to", 0))
		var who := "Everyone else with points" if up_to <= 0 else ("#1" if up_to == 1 else "#%d to #%d" % [from, up_to])
		lines.append("%s: %s" % [who, item_text(p)])
		from = up_to + 1
	return "\n".join(lines)


static func _cell(text: String, color: Color, right: bool) -> Label:
	var l := MenuStyle.label(text, 15, color)
	if right:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]
