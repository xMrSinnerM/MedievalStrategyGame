extends CanvasLayer
## The world map's HUD: a resource bar along the top with the main buttons,
## controls, what your party is doing, zoom level and frame rate, plus the
## castle and party panels, battle reports and news of battles between lords.
## F1 hides it.

const NEWS_TIME := 7.0
const ChatBox := preload("res://scripts/ui/chat_box.gd")
const TOP := 66.0                ## panels start below the resource bar

var _info: Label
var _resources: ResourceBar
var _alliance_button: Button
var _owner_panel: Control
var _zoom_t := 0.0
var _party_status := ""
var _news: Label
var _news_left := 0.0
var _alert: Label
var _event: Label                ## online: the timed event on now, or the next one
var _sieges := {}                ## castle id -> {"besieger", "until"} for sieges of your castles


func _ready() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", GameTheme.bar_box())
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	_resources = ResourceBar.new()
	_resources.show_builders = false
	row.add_child(_resources)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var diplomacy := preload("res://scripts/ui/diplomacy_panel.gd").new()
	var leaderboard := preload("res://scripts/ui/leaderboard_panel.gd").new()
	var alliance := preload("res://scripts/ui/alliance_panel.gd").new()
	var events := preload("res://scripts/ui/event_panel.gd").new()
	if Economy.online:
		_alliance_button = _bar_button("Alliance (G)", alliance.toggle)
		row.add_child(_alliance_button)
		row.add_child(_bar_button("Events (V)", events.toggle))
		var owner := preload("res://scripts/ui/admin_panel.gd").new()
		_owner_panel = owner
		var owner_button := _bar_button("Owner (O)", owner.toggle)
		owner_button.visible = Economy.is_admin
		Economy.admin_changed.connect(func(_e: String) -> void: owner_button.visible = Economy.is_admin)
		row.add_child(owner_button)
		row.add_child(_bar_button("Leaderboard (L)", leaderboard.toggle))
	else:
		row.add_child(_bar_button("Diplomacy (K)", diplomacy.toggle))
	row.add_child(_bar_button("Your castle (C)", func() -> void:
		EventBus.castle_requested.emit(Economy.player_castle.id)))
	var panel := PanelContainer.new()
	panel.position = Vector2(12, TOP + 2)
	panel.add_theme_stylebox_override("panel", MenuStyle.panel(0.6, 10))
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 14)
	panel.add_child(_info)
	add_child(panel)
	var info := preload("res://scripts/ui/castle_info_panel.gd").new()
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.offset_top = TOP
	info.offset_right = -12
	add_child(info)
	var baron_panel := preload("res://scripts/ui/baron_panel.gd").new()
	baron_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	baron_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	baron_panel.offset_top = TOP
	baron_panel.offset_right = -12
	add_child(baron_panel)
	if Economy.online:
		var player_panel := preload("res://scripts/ui/player_panel.gd").new()
		player_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		player_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		player_panel.offset_top = TOP
		player_panel.offset_right = -12
		add_child(player_panel)
	var party_panel := preload("res://scripts/ui/party_panel.gd").new()
	party_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	party_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	party_panel.offset_top = TOP
	party_panel.offset_right = -12
	add_child(party_panel)
	var report := preload("res://scripts/ui/battle_report.gd").new()
	report.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	report.grow_horizontal = Control.GROW_DIRECTION_BOTH
	report.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(report)
	diplomacy.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	diplomacy.grow_horizontal = Control.GROW_DIRECTION_BOTH
	diplomacy.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(diplomacy)
	leaderboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	leaderboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	leaderboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(leaderboard)
	alliance.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	alliance.grow_horizontal = Control.GROW_DIRECTION_BOTH
	alliance.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(alliance)
	events.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	events.grow_horizontal = Control.GROW_DIRECTION_BOTH
	events.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(events)
	if _owner_panel != null:
		_owner_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_owner_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_owner_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
		add_child(_owner_panel)
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
	_news.offset_bottom = -64 if Economy.online else -24
	_news.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_news)
	EventBus.battle_fought.connect(_on_battle)
	Online.order_failed.connect(func(message: String) -> void:
		if not is_inside_tree() or not visible or alliance.visible or (chat != null and chat.is_open()):
			return
		_news.text = "The server refused that: " + message if message != "" else "The server didn't answer."
		_news_left = NEWS_TIME)
	Economy.diplomacy_changed.connect(_on_diplomacy)
	if Economy.online:
		var banner := PanelContainer.new()
		banner.add_theme_stylebox_override("panel", MenuStyle.panel(0.8, 10))
		banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
		banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
		banner.offset_bottom = -12
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_event = Label.new()
		_event.add_theme_font_size_override("font_size", 15)
		_event.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.add_child(_event)
		add_child(banner)
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
	if Economy.online:
		var shield := ""
		if Economy.is_protected():
			shield = "    Beginner protection: %s left (ends if you attack a player)" % _hours(Economy.protected_until - Economy.now())
		_info.text = "Online as %s" % Online.email + shield + "\nClick: pick your castle, another player's or a robber baron camp    C: your castle    L: leaderboard    G: alliance    V: events    Enter: chat" + ("    O: owner tools" if Economy.is_admin else "") + "\nWASD / drag: pan    Q E / right-drag: rotate    wheel: zoom\nM: parchment map    Home: recentre    F1: hide    Esc: menu\nzoom %d%%    %d fps" % [int(_zoom_t * 100.0), Engine.get_frames_per_second()]
		return
	_info.text = "Click: travel there, or pick a castle or party    F: find your party    C: your castle    K: diplomacy\nWASD / drag: pan    Q E / right-drag: rotate    wheel: zoom\nM: parchment map    Home: recentre    F1: hide    Esc: menu\nYour party: %s\nzoom %d%%    %d fps" % [_party_status, int(_zoom_t * 100.0), Engine.get_frames_per_second()]


func _show_event() -> void:
	## The banner: the timed event on now and how long it lasts, else the next one.
	var on := Economy.events_on()
	var banner := _event.get_parent() as Control
	if not on.is_empty():
		var e: Dictionary = on[0]
		_event.text = "%s: %s  Ends in %s" % [e.name, e.description, _days(float(e.end) - Economy.now())]
		if e.has("invasion"):
			_event.text += "    Your points: %d" % Economy.invasion_points()
		_event.add_theme_color_override("font_color", MenuStyle.GOLD)
		banner.visible = true
		return
	var next := Economy.next_event()
	banner.visible = not next.is_empty()
	if not next.is_empty():
		_event.text = "Next event: %s in %s" % [next.name, _days(float(next.start) - Economy.now())]
		_event.add_theme_color_override("font_color", MenuStyle.MUTED)


func _update_alliance_button() -> void:
	## Invitations to you, or players asking to join your alliance, show as a count.
	var waiting: int = Economy.alliance.get("invites", []).size() + Economy.alliance.get("requests", []).size()
	_alliance_button.text = "Alliance (G)" if waiting == 0 else "Alliance (G)  %d new" % waiting


func _bar_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 15)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(action)
	return b


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
