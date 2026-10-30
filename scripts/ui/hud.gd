extends CanvasLayer
## The world map's HUD: a bar along the top with your resources, the timed
## event and the way to your castle; map tools and your quests top left; the
## minimap and the card of what you clicked top right; and a dock bottom right
## that opens the windows (quests, commanders, your lands, alliance, market,
## events). Also battle reports and news of battles between lords. F1 hides it.

const NEWS_TIME := 7.0
const ChatBox := preload("res://scripts/ui/chat_box.gd")
const TOP := 66.0                ## panels start below the resource bar

var _controls: MapControls
var _resources: ResourceBar
var _alliance_button: Button
var _quests_button: Button
var _quest_book_check := 0.0
var _status: Label               ## your party, or beginner protection online
var _owner_panel: Control
var _zoom_t := 0.0
var _party_status := ""
var _news: Label
var _news_left := 0.0
var _alert: Label
var _event: Label                ## online: the timed event on now, or the next one
var _sieges := {}                ## castle id -> {"besieger", "until"} for sieges of your castles
var _windows: Array[GameWindow] = []
var _gift: Control               ## the Royal Gift page, opened by itself once when today's is waiting
var _gift_wait := 2.0            ## seconds after the map opens before it may show (-1: done)


func _ready() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", GameTheme.bar_box())
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(bar)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	bar.add_child(top)
	var crest := Icons.rect("crest", 40)
	crest.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(crest)
	_resources = ResourceBar.new()
	_resources.show_builders = false
	_resources.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(_resources)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(gap)
	if Economy.online:
		_event = MenuStyle.label("", 15, MenuStyle.MUTED)
		_event.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_event.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_event.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_event.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_event.mouse_filter = Control.MOUSE_FILTER_PASS
		top.add_child(_event)
	var castle_button := Button.new()
	castle_button.text = "Your castle"
	castle_button.tooltip_text = "Your castle (C)"
	castle_button.icon = Icons.get_icon("might", 22)
	castle_button.focus_mode = Control.FOCUS_NONE
	castle_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	GameTheme.primary(castle_button)
	castle_button.pressed.connect(func() -> void: EventBus.castle_requested.emit(Economy.player_castle.id))
	castle_button.add_to_group("tutorial_castle_button")
	top.add_child(castle_button)

	# Top left: the map tools, then your quests and what your party is doing.
	var left := HBoxContainer.new()
	left.position = Vector2(12, TOP + 4)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	_controls = MapControls.new()
	_controls.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left.add_child(_controls)
	var notes := VBoxContainer.new()
	notes.add_theme_constant_override("separation", 6)
	left.add_child(notes)
	var achievements := preload("res://scripts/ui/achievements_panel.gd").new()
	var quests := preload("res://scripts/ui/quest_panel.gd").new()
	quests.achievements = achievements
	_gift = preload("res://scripts/ui/login_panel.gd").new()
	var season := preload("res://scripts/ui/season_panel.gd").new()
	var treasure := preload("res://scripts/ui/chest_panel.gd").new()
	var tracker := preload("res://scripts/ui/quest_tracker.gd").new()
	tracker.panel = quests
	tracker.add_to_group("tutorial_quest_tracker")
	tracker.achievements = achievements
	tracker.gift = _gift
	tracker.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	notes.add_child(tracker)
	var status_card := PanelContainer.new()
	status_card.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 8))
	status_card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	status_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notes.add_child(status_card)
	_status = MenuStyle.label("", 14, MenuStyle.MUTED)
	status_card.add_child(_status)
	# Right: the minimap, with the card of whatever you clicked under it.
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.offset_top = TOP
	right.offset_right = -12
	right.add_theme_constant_override("separation", 8)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(right)
	var minimap := Minimap.new()
	minimap.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(minimap)
	_controls.minimap = minimap
	var cards: Array[Control] = [preload("res://scripts/ui/castle_info_panel.gd").new(),
			preload("res://scripts/ui/baron_panel.gd").new(), preload("res://scripts/ui/village_panel.gd").new()]
	if Economy.online:
		cards.append(preload("res://scripts/ui/player_panel.gd").new())
	cards.append(preload("res://scripts/ui/party_panel.gd").new())
	cards.append(preload("res://scripts/ui/encounter_panel.gd").new())
	for card in cards:
		card.size_flags_horizontal = Control.SIZE_SHRINK_END
		right.add_child(card)

	var report := preload("res://scripts/ui/battle_report.gd").new()
	report.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	report.grow_horizontal = Control.GROW_DIRECTION_BOTH
	report.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(report)

	# The windows. Each old panel is a page in one of them; related ones
	# share a window as tabs.
	var commanders := preload("res://scripts/ui/commanders_panel.gd").new()
	var skills := preload("res://scripts/ui/skills_panel.gd").new()
	var villages := preload("res://scripts/ui/villages_panel.gd").new()
	var outpost := preload("res://scripts/ui/outpost_panel.gd").new()
	var diplomacy := preload("res://scripts/ui/diplomacy_panel.gd").new()
	var alliance := preload("res://scripts/ui/alliance_panel.gd").new()
	var war := preload("res://scripts/ui/war_panel.gd").new()
	var tournament := preload("res://scripts/ui/tournament_panel.gd").new()
	var leaderboard := preload("res://scripts/ui/leaderboard_panel.gd").new()
	var events := preload("res://scripts/ui/event_panel.gd").new()
	var market := preload("res://scripts/ui/market_panel.gd").new()
	var quest_window := _window("Quests", "quests", [quests, "Quests", _gift, "Royal Gift", season, "Season", treasure, "Treasure", achievements, "Achievements"])
	var army_window := _window("Commanders", "commanders", [commanders, "Commanders", skills, "Skills"])
	var lands_window := _window("Your lands", "villages", [villages, "Villages", outpost, "Outpost"])
	var alliance_window := _window("Alliance", "alliance", [alliance, "Alliance", war, "War", tournament, "Tournament", leaderboard, "Leaderboard"])
	var diplomacy_window := _window("Diplomacy", "diplomacy", [diplomacy, ""])
	var events_window := _window("Events", "events", [events, ""])
	var market_window: GameWindow = null
	if Economy.online:
		market_window = _window("Market", "market", [market, ""])
	_window("Capital", "villages", [preload("res://scripts/ui/town_panel.gd").new(), ""])
	var owner_window: GameWindow = null
	if Economy.online:
		_owner_panel = preload("res://scripts/ui/admin_panel.gd").new()
		owner_window = _window("Owner tools", "owner", [_owner_panel, ""])

	# Bottom right: the dock that opens them.
	var dock := PanelContainer.new()
	dock.add_theme_stylebox_override("panel", GameTheme.panel_box(0.85, 8))
	dock.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	dock.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	dock.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dock.offset_right = -12
	dock.offset_bottom = -12
	add_child(dock)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	dock.add_child(row)
	_quests_button = _dock_button("Quests", "quests", "Quests, the Royal Gift, the season, treasure chests and achievements (J, Y)", quest_window.toggle)
	row.add_child(_quests_button)
	row.add_child(_dock_button("Army", "commanders", "Commanders, their gear and skills (H)", army_window.toggle))
	row.add_child(_dock_button("Lands", "villages", "Your villages, capitals and outpost (B, P)", lands_window.toggle))
	if Economy.online:
		_alliance_button = _dock_button("Alliance", "alliance", "Alliance, alliance war, tournament and leaderboard (G, K, L)", alliance_window.toggle)
		row.add_child(_alliance_button)
		row.add_child(_dock_button("Market", "market", "Market (T)", market_window.toggle))
		row.add_child(_dock_button("Events", "events", "Events (V)", events_window.toggle))
		var owner_button := _dock_button("Owner", "owner", "Owner tools (O)", owner_window.toggle)
		owner_button.visible = Economy.is_admin
		Economy.admin_changed.connect(func(_e: String) -> void: owner_button.visible = Economy.is_admin)
		row.add_child(owner_button)
	else:
		row.add_child(_dock_button("Diplomacy", "diplomacy", "Diplomacy (K)", diplomacy_window.toggle))
	if Economy.online:
		Economy.alliance_changed.connect(func(_error: String) -> void: _update_alliance_button())
	var chat: ChatBox = null
	if Economy.online:
		chat = ChatBox.new()
		chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
		chat.offset_left = 12
		chat.offset_bottom = -12
		add_child(chat)
	if Economy.online:
		var help := preload("res://scripts/ui/help_panel.gd").new()
		help.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		help.grow_horizontal = Control.GROW_DIRECTION_BOTH
		help.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(help)
		Economy.aid_news.connect(func(text: String) -> void:
			_news.text = text
			_news_left = NEWS_TIME * 1.5)
	var attack := preload("res://scripts/ui/attack_panel.gd").new()
	attack.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	attack.grow_horizontal = Control.GROW_DIRECTION_BOTH
	attack.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(attack)
	_news = Label.new()
	_news.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	_news.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.04))
	_news.add_theme_constant_override("outline_size", 6)
	_news.add_theme_font_size_override("font_size", 17)
	_news.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_news.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_news.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_news.offset_bottom = -24
	_news.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_news)
	EventBus.battle_fought.connect(_on_battle)
	Online.order_failed.connect(func(message: String) -> void:
		if not is_inside_tree() or not visible or alliance.visible or market.visible or (chat != null and chat.is_open()):
			return
		_news.text = "The server refused that: " + message if message != "" else "The server didn't answer."
		_news_left = NEWS_TIME)
	Economy.diplomacy_changed.connect(_on_diplomacy)
	Economy.achievement_news.connect(func(text: String) -> void:
		_news.text = text
		_news_left = NEWS_TIME * 1.5)
	_alert = Label.new()
	_alert.add_theme_color_override("font_color", Color(1.0, 0.5, 0.38))
	_alert.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.03))
	_alert.add_theme_constant_override("outline_size", 7)
	_alert.add_theme_font_size_override("font_size", 20)
	_alert.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_alert.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_alert.offset_top = 180
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_alert)
	EventBus.siege_started.connect(func(castle_id: String, besieger: String, until: float) -> void:
		var castle := Economy.get_castle(castle_id)
		if castle != null and castle.owner == "player":
			_sieges[castle_id] = {"besieger": besieger, "until": until})
	EventBus.siege_ended.connect(func(castle_id: String) -> void: _sieges.erase(castle_id))
	EventBus.camera_zoom_changed.connect(func(t: float) -> void: _zoom_t = t)
	EventBus.party_status_changed.connect(func(text: String) -> void: _party_status = text)
	# The windows go over everything else, so their shade dims the whole map.
	for w in _windows:
		move_child(w, -1)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		visible = not visible


func _on_battle(report: Dictionary) -> void:
	## Battles between lords make the news; your own get the full report.
	if report.player != "":
		return
	var winner: String = report.attacker if report.winner == "a" else report.defender
	var loser: String = report.defender if report.winner == "a" else report.attacker
	if report.get("siege", false):
		_news.text = {"captured": "%s captured %s", "sacked": "%s sacked %s"}.get(report.outcome,
				"%s failed to storm %s") % [report.attacker, report.defender]
	else:
		_news.text = "%s defeated %s near %s" % [winner, loser, report.place]
	_news_left = NEWS_TIME


func _on_diplomacy(news: Array) -> void:
	## Wars declared and peace made are news too.
	if news.is_empty():
		return
	_news.text = "  ".join(news)
	if _news.text.contains("offers you peace"):
		_news.text += "  Press K to answer."
	_news_left = NEWS_TIME * 1.5


func _process(delta: float) -> void:
	_news_left = maxf(_news_left - delta, 0.0)
	_news.modulate.a = clampf(_news_left, 0.0, 1.0)
	var alerts: PackedStringArray = []
	var now := Time.get_ticks_msec() * 0.001
	for castle_id: String in _sieges:
		alerts.append("%s is besieging %s! Assault in %d s" % [_sieges[castle_id].besieger,
				Economy.get_castle(castle_id).castle_name, maxi(ceili(_sieges[castle_id].until - now), 0)])
	if Economy.online:
		for r: Dictionary in Economy.raids:
			if not r.get("mine", false) and r.get("state", "") == "out":
				alerts.append("%s's army reaches your castle in %s" % [r.attacker_name,
						_clock(float(r.arrive) - Economy.now())])
	_alert.text = "\n".join(alerts)
	if _event != null:
		_show_event()
	if not visible:
		return
	_resources.show_castle(Economy.player_castle, Economy.troops_away() if not Economy.marches.is_empty() or not Economy.aid.is_empty() else 0)
	_quest_book_check -= delta
	if _quest_book_check <= 0.0:
		_quest_book_check = 0.5
		var book := Economy.quest_book
		var waiting: bool = (book != null and book.can_claim_anything(Economy.player_castle)) \
				or (Economy.achievements != null and Economy.achievements.can_claim_anything(Economy.player_castle)) \
				or Economy.login_waiting() or Economy.season_waiting() \
				or (Economy.chest_rules != null and Economy.chest_rules.total(Economy.player_castle) > 0)
		_set_badge(_quests_button, "!" if waiting else "")
	_show_gift(delta)
	var status := ""
	if Economy.online:
		if Economy.is_protected():
			status = "Beginner protection: %s left (ends if you attack a player)" % _hours(Economy.protected_until - Economy.now())
		_controls.keys = "Click: pick your castle, another player's, a robber baron camp, a village or a town\nC: your castle   L: leaderboard   G: alliance   V: events   T: market   K: alliance war   J: quests   Y: achievements   H: commanders   P: outpost   B: villages   Enter: chat" + ("   O: owner tools" if Economy.is_admin else "") + "\nWASD / drag: pan   Q E / right-drag: rotate   wheel: zoom\nM: parchment map   N: minimap   Home: recentre   F1: hide   Esc: menu\n\nOnline as " + Online.email
	else:
		if _party_status != "":
			status = "Your party: %s" % _party_status
		_controls.keys = "Click: travel there, or pick a castle, town, party or village\nF: find your party   C: your castle   K: diplomacy   J: quests   Y: achievements   H: commanders   P: outpost   B: villages\nWASD / drag: pan   Q E / right-drag: rotate   wheel: zoom\nM: parchment map   N: minimap   Home: recentre   F1: hide   Esc: menu"
	if _status.text != status:
		_status.text = status
	_status.get_parent().visible = status != ""
	_controls.show_status(_zoom_t)


func _show_gift(delta: float) -> void:
	## Once, shortly after the map opens: today's Royal Gift if it's waiting,
	## unless the tutorial is on or a window is already open.
	if _gift_wait < 0.0:
		return
	_gift_wait -= delta
	if _gift_wait > 0.0:
		return
	_gift_wait = -1.0
	var main := get_tree().current_scene
	var tutorial: Variant = main.get("tutorial") if main != null else null
	if tutorial != null and tutorial.running():
		return
	for w in _windows:
		if w.is_open():
			return
	if Economy.login_waiting():
		_gift.open_panel()


func _show_event() -> void:
	## In the top bar: the timed event on now and how long it lasts (what it
	## does is in the tooltip), else the next one.
	var on := Economy.events_on()
	if not on.is_empty():
		var e: Dictionary = on[0]
		var text := "%s  ·  ends in %s" % [e.name, _days(float(e.end) - Economy.now())]
		if e.has("invasion"):
			text += "  ·  your points: %d" % Economy.invasion_points()
		elif e.has("horde"):
			text += "  ·  horde points: %d  ·  trophies: %d" % [Economy.my_horde_points(), Economy.war_trophies()]
		_event.text = text
		_event.tooltip_text = "%s: %s" % [e.name, e.description]
		_event.add_theme_color_override("font_color", MenuStyle.GOLD)
		return
	var next := Economy.next_event()
	_event.text = "" if next.is_empty() else "Next event: %s in %s" % [next.name, _days(float(next.start) - Economy.now())]
	_event.tooltip_text = ""
	_event.add_theme_color_override("font_color", MenuStyle.MUTED)


func _update_alliance_button() -> void:
	## Invitations to you, or players asking to join your alliance, show as a count.
	var waiting: int = Economy.alliance.get("invites", []).size() + Economy.alliance.get("requests", []).size()
	_set_badge(_alliance_button, str(waiting) if waiting > 0 else "")


func _window(title: String, icon: String, pages: Array) -> GameWindow:
	## A window holding pages: [panel, tab name, panel, tab name, ...].
	var w := GameWindow.new(title, icon)
	for i in range(0, pages.size(), 2):
		w.add_page(pages[i], pages[i + 1])
	add_child(w)
	_windows.append(w)
	return w


func _dock_button(text: String, icon: String, tip: String, action: Callable) -> Button:
	## A square dock button: a big icon with its name under it, and a red
	## badge in the corner when something waits there.
	var b := Button.new()
	b.custom_minimum_size = Vector2(78, 70)
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", GameTheme.button_box(Color(0.075, 0.063, 0.05, 0.95), GameTheme.RIM_DIM))
	b.pressed.connect(action)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var picture := Icons.rect(icon, 34)
	picture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(picture)
	var caption := MenuStyle.label(text, 14, GameTheme.TEXT)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	var badge := Label.new()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var dot := StyleBoxFlat.new()
	dot.bg_color = Color(0.72, 0.16, 0.12)
	dot.border_color = GameTheme.GOLD
	dot.set_border_width_all(1)
	dot.set_corner_radius_all(10)
	dot.content_margin_left = 6
	dot.content_margin_right = 6
	badge.add_theme_stylebox_override("normal", dot)
	badge.add_theme_font_size_override("font_size", 13)
	badge.custom_minimum_size = Vector2(20, 20)
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.offset_top = -6
	badge.offset_right = 6
	badge.visible = false
	b.add_child(badge)
	b.set_meta("badge", badge)
	return b


func _set_badge(b: Button, text: String) -> void:
	if b == null:
		return
	var badge: Label = b.get_meta("badge")
	badge.text = text
	badge.visible = text != ""


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return _hours(seconds)


static func _hours(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	return "%dh %02dm" % [m / 60, m % 60]
