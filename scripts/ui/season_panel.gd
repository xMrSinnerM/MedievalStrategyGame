extends PanelContainer
## The season screen (a tab of the quest window): this month's renown and
## what earned it, the track of renown rewards, and online the season's best
## players and alliances, the prizes when the month ends and last season's
## prize to claim (SeasonRules).

const DONE := Color(0.55, 0.9, 0.45)
const READY := Color(1.0, 0.85, 0.45)
const LOCKED := Color(0.5, 0.45, 0.38)
const PARTS := {"levels": "building levels", "trained": "soldiers trained", "barons": "robber barons",
	"looted": "loot", "pvp_won": "battles won", "pvp_held": "attacks held off"}
const ONE := {"levels": "building level", "barons": "robber baron beaten", "pvp_won": "battle won against a player",
	"pvp_held": "attack held off"}
const BOARD_EVERY := 60.0

var _season: Label
var _renown: Label
var _parts: Label
var _bar: ProgressBar
var _track: HBoxContainer
var _ranking: VBoxContainer
var _players: GridContainer
var _alliances: GridContainer
var _me: Label
var _prizes: Label
var _last: Label
var _last_claim: Button
var _status: Label
var _signature := ""
var _board_timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(1000, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	box.add_child(head)
	var title := MenuStyle.title("Season", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	set_meta("window_close", close)
	var help := MenuStyle.label("", 14, MenuStyle.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	set_meta("window_help", help)
	box.add_child(help)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	box.add_child(top)
	var laurel := Icons.rect("laurel", 52)
	laurel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(laurel)
	var lines := VBoxContainer.new()
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(lines)
	_season = MenuStyle.label("", 20, MenuStyle.GOLD)
	_season.add_theme_font_override("font", GameTheme.TITLE_FONT)
	lines.add_child(_season)
	_renown = MenuStyle.label("", 17, MenuStyle.TEXT)
	lines.add_child(_renown)
	_parts = MenuStyle.label("", 14, MenuStyle.MUTED)
	_parts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lines.add_child(_parts)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 12)
	box.add_child(_bar)
	_track = HBoxContainer.new()
	_track.add_theme_constant_override("separation", 6)
	_track.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_track)

	_ranking = VBoxContainer.new()
	_ranking.add_theme_constant_override("separation", 8)
	box.add_child(_ranking)
	_ranking.add_child(HSeparator.new())
	var last_row := HBoxContainer.new()
	last_row.add_theme_constant_override("separation", 12)
	_ranking.add_child(last_row)
	_last = MenuStyle.label("", 15, MenuStyle.TEXT)
	_last.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_last.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	last_row.add_child(_last)
	_last_claim = Button.new()
	_last_claim.text = "Claim prize"
	_last_claim.focus_mode = Control.FOCUS_NONE
	_last_claim.custom_minimum_size = Vector2(150, 34)
	_last_claim.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_last_claim.pressed.connect(_on_claim_prize)
	GameTheme.primary(_last_claim)
	last_row.add_child(_last_claim)
	var boards := HBoxContainer.new()
	boards.add_theme_constant_override("separation", 30)
	_ranking.add_child(boards)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boards.add_child(left)
	left.add_child(MenuStyle.label("Best lords this season", 18, MenuStyle.GOLD))
	_players = _grid(4)
	left.add_child(_players)
	_me = MenuStyle.label("", 15, READY)
	left.add_child(_me)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boards.add_child(right)
	right.add_child(MenuStyle.label("Best alliances", 18, MenuStyle.GOLD))
	_alliances = _grid(3)
	right.add_child(_alliances)
	_prizes = MenuStyle.label("", 14, MenuStyle.MUTED)
	_prizes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_prizes)
	_status = MenuStyle.label("", 15, DONE)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_fill())
	Economy.season_board_changed.connect(func() -> void:
		_signature = ""
		if visible:
			_fill())


func _process(delta: float) -> void:
	if not visible:
		return
	_fill()
	if Economy.online:
		_board_timer -= delta
		if _board_timer <= 0.0:
			_board_timer = BOARD_EVERY
			Economy.ask_season_board()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	_status.text = ""
	_signature = ""
	_board_timer = 0.0
	_fill()
	visible = true


func close_panel() -> void:
	visible = false


func _on_claim_track() -> void:
	var sr := Economy.season_rules
	var castle := Economy.player_castle
	var reward := sr.track_reward(int(castle.season.track), castle.keep_level()) if int(castle.season.track) < sr.track.size() else {}
	var why := Economy.claim_season_track()
	_said(why, "Received: %s" % Economy.reward_text(reward))


func _on_claim_prize() -> void:
	var why := Economy.claim_season_prize()
	_said(why, "Your prize is on its way to your castle.")


func _said(why: String, done: String) -> void:
	Audio.play("reward" if why == "" else "denied")
	_status.add_theme_color_override("font_color", DONE if why == "" else Color(1.0, 0.55, 0.4))
	_status.text = done if why == "" else why
	_signature = ""
	_fill()


func _fill() -> void:
	var sr := Economy.season_rules
	var castle := Economy.player_castle
	if sr == null or castle == null:
		return
	var now := Economy.now()
	sr.roll(castle, now)
	var key := int(castle.season.key)
	_season.text = "Season of %s    ends in %s" % [SeasonRules.name_of(key), _days(SeasonRules.end_of(key) - now)]
	var points := sr.renown(castle)
	var sig := str([castle.season, points, castle.keep_level(), Economy.season_board])
	if sig == _signature:
		return
	_signature = sig
	var help: Label = get_meta("window_help")
	help.text = "A season is a calendar month. You earn renown for what you do in it: %s. Renown milestones give rewards on the track (bigger keeps get bigger ones); claim them before the month ends, because a new season starts again from 0. The whole track gives the season's title, %s.%s" % [_weights(sr), sr.renowned,
		"\nWhen the month ends, the lords and alliances with the most renown win prizes and a title for that season (an alliance's renown is its members' added up). Claim them here during the next season." if Economy.online else "\nOnline, the best lords and alliances of each season also win prizes and titles."]
	help.visible = not has_meta("in_window")
	_renown.text = "Your renown: %d" % points
	var parts: PackedStringArray = []
	var b := sr.breakdown(castle)
	for k: String in b:
		if float(b[k]) >= 1.0:
			parts.append("%s %d" % [PARTS.get(k, k), int(floor(b[k]))])
	_parts.text = "From " + ",  ".join(parts) if not parts.is_empty() else "Build, train, beat robber barons and bring home loot to earn renown."
	var top_need := float(sr.track[-1].renown) if not sr.track.is_empty() else 1.0
	_bar.max_value = top_need
	_bar.value = minf(points, top_need)
	_fill_track(sr, castle, points)
	_ranking.visible = Economy.online
	if Economy.online:
		_fill_ranking(sr)


func _fill_track(sr: SeasonRules, castle: CastleState, points: int) -> void:
	for child in _track.get_children():
		_track.remove_child(child)
		child.queue_free()
	var claimed := int(castle.season.track)
	for i in sr.track.size():
		var need := int(sr.track[i].renown)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(124, 150)
		var next := i == claimed
		var reached := points >= need
		var style := GameTheme.card_box(Color(0.09, 0.075, 0.055, 0.95), GameTheme.RIM_BRIGHT if next and reached else GameTheme.RIM_DIM)
		style.set_content_margin_all(6)
		if next and reached:
			style.set_border_width_all(2)
			style.bg_color = Color(0.2, 0.14, 0.06, 0.95)
		card.add_theme_stylebox_override("panel", style)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)
		card.add_child(box)
		var head := MenuStyle.label("%d" % need, 16, READY if reached else LOCKED)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_theme_font_override("font", GameTheme.TITLE_FONT)
		box.add_child(head)
		var reward := sr.track_reward(i, castle.keep_level())
		for r: String in reward.get("resources", {}):
			box.add_child(_amount(r, "%d" % int(reward.resources[r])))
		for unit: String in reward.get("troops", {}):
			box.add_child(_amount(unit, "%d" % int(reward.troops[unit])))
		if i == sr.track.size() - 1:
			var t := MenuStyle.label("+ title", 13, MenuStyle.GOLD)
			t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(t)
		var gap := Control.new()
		gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(gap)
		if i < claimed:
			var tag := MenuStyle.label("Claimed", 13, DONE)
			tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(tag)
			card.modulate = Color(1, 1, 1, 0.7)
		elif next and reached:
			var b := Button.new()
			b.text = "Claim"
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 14)
			b.pressed.connect(_on_claim_track)
			box.add_child(GameTheme.primary(b))
		_track.add_child(card)


func _fill_ranking(sr: SeasonRules) -> void:
	var board: Dictionary = Economy.season_board
	for grid in [_players, _alliances]:
		for child in grid.get_children():
			grid.remove_child(child)
			child.queue_free()
	var players: Array = board.get("players", [])
	for i in mini(players.size(), 10):
		var p: Dictionary = players[i]
		_players.add_child(MenuStyle.label("%d." % (i + 1), 15, MenuStyle.GOLD if i < 3 else MenuStyle.MUTED))
		var name := String(p.name) + (" [%s]" % p.tag if String(p.get("tag", "")) != "" else "")
		var who := MenuStyle.label(name, 15, MenuStyle.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_players.add_child(who)
		_players.add_child(MenuStyle.label("%d" % int(p.points), 15, MenuStyle.TEXT))
		var prize := SeasonRules.prize_for(sr.player_prizes, i + 1)
		_players.add_child(MenuStyle.label(String(prize.get("title", "")), 14, MenuStyle.MUTED))
	if players.is_empty():
		_players.add_child(MenuStyle.label("Nobody has renown yet this season." if not board.is_empty() else "Asking the server...", 15, MenuStyle.MUTED))
	var alliances: Array = board.get("alliances", [])
	for i in alliances.size():
		var a: Dictionary = alliances[i]
		_alliances.add_child(MenuStyle.label("%d." % (i + 1), 15, MenuStyle.GOLD if i < 3 else MenuStyle.MUTED))
		var who := MenuStyle.label("[%s] %s" % [a.tag, a.name], 15, MenuStyle.TEXT)
		who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_alliances.add_child(who)
		_alliances.add_child(MenuStyle.label("%d" % int(a.points), 15, MenuStyle.TEXT))
	var me: Dictionary = board.get("me", {}) if board.get("me") is Dictionary else {}
	_me.text = "You: place %d with %d renown" % [int(me.place), int(me.points)] if int(me.get("place", 0)) > 0 else "Earn renown to join the ranking."
	var lines: PackedStringArray = []
	for p: Dictionary in sr.player_prizes:
		lines.append("%s %s" % [_places(sr.player_prizes, p), p.title])
	var al: PackedStringArray = []
	for p: Dictionary in sr.alliance_prizes:
		al.append("%s %s" % [_places(sr.alliance_prizes, p), p.title])
	_prizes.text = "Prizes when the month ends:\nLords: %s\nAlliances (every member): %s" % [",  ".join(lines), ",  ".join(al)]
	var last: Dictionary = board.get("last", {}) if board.get("last") is Dictionary else {}
	_last_claim.visible = false
	if last.is_empty() or int(last.get("points", 0)) <= 0:
		_last.text = "Last season: you earned no renown. Prizes for this season can be claimed here next month."
		return
	var won: PackedStringArray = []
	var mine := SeasonRules.prize_for(sr.player_prizes, int(last.place))
	var ours := SeasonRules.prize_for(sr.alliance_prizes, int(last.get("alliance_place", 0)))
	for p: Dictionary in [mine, ours]:
		if not p.is_empty():
			won.append("%s (%s)" % [p.title, Economy.reward_text(p.reward)])
	var text := "Last season, %s: you earned %d renown, place %d" % [SeasonRules.name_of(int(last.key)), int(last.points), int(last.place)]
	if int(last.get("alliance_place", 0)) > 0:
		text += ", your alliance place %d" % int(last.alliance_place)
	text += ".  "
	if bool(last.get("claimed", false)) or SeasonRules.check_prize(Economy.player_castle) != "":
		text += "Prize claimed." if not won.is_empty() else "No prize this time."
	elif won.is_empty():
		text += "No prize this time; aim for the top %d." % int(sr.player_prizes[-1].top)
	else:
		text += "You won: " + ";  ".join(won)
		_last_claim.visible = true
	_last.text = text


static func _places(list: Array, p: Dictionary) -> String:
	## "1st", "2nd-3rd", "4th-10th" for a prize in a list.
	var i := list.find(p)
	var from := 1 if i == 0 else int(list[i - 1].top) + 1
	var to := int(p.top)
	return _nth(from) if from == to else "%s-%s" % [_nth(from), _nth(to)]


static func _nth(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]


static func _weights(sr: SeasonRules) -> String:
	var parts: PackedStringArray = []
	for k: String in sr.weights:
		var w := float(sr.weights[k])
		if k in ["pvp_won", "pvp_held"] and not Economy.online:
			continue
		if w >= 1.0:
			parts.append("%d per %s" % [int(w), ONE.get(k, k)])
		else:
			parts.append("1 per %d %s" % [roundi(1.0 / w), PARTS.get(k, k)])
	return ", ".join(parts)


func _grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 4)
	return g


static func _amount(icon: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(Icons.rect(icon, 16))
	row.add_child(MenuStyle.label(text, 13, MenuStyle.TEXT))
	return row


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]
