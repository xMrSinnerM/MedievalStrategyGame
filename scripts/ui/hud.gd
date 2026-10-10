extends CanvasLayer
## Minimal HUD: controls, what your party is doing, zoom level and frame rate,
## plus the castle and party panels, battle reports and news of battles
## between lords. F1 hides it.

const NEWS_TIME := 7.0

var _info: Label
var _zoom_t := 0.0
var _party_status := ""
var _news: Label
var _news_left := 0.0
var _alert: Label
var _sieges := {}                ## castle id -> {"besieger", "until"} for sieges of your castles


func _ready() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, 0.65)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	_info = Label.new()
	_info.add_theme_color_override("font_color", Color(0.95, 0.9, 0.8))
	_info.add_theme_font_size_override("font_size", 14)
	panel.add_child(_info)
	add_child(panel)
	var castle_button := Button.new()
	castle_button.text = "Your castle (C)"
	castle_button.focus_mode = Control.FOCUS_NONE
	castle_button.add_theme_font_size_override("font_size", 15)
	castle_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	castle_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	castle_button.offset_top = 12
	castle_button.offset_right = -12
	castle_button.pressed.connect(func() -> void: EventBus.castle_requested.emit(Economy.player_castle.id))
	add_child(castle_button)
	var diplomacy := preload("res://scripts/ui/diplomacy_panel.gd").new()
	var diplomacy_button := Button.new()
	diplomacy_button.text = "Diplomacy (K)"
	diplomacy_button.focus_mode = Control.FOCUS_NONE
	diplomacy_button.add_theme_font_size_override("font_size", 15)
	diplomacy_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	diplomacy_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	diplomacy_button.offset_top = 12
	diplomacy_button.offset_right = -150
	diplomacy_button.pressed.connect(diplomacy.toggle)
	add_child(diplomacy_button)
	var info := preload("res://scripts/ui/castle_info_panel.gd").new()
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info.offset_top = 56
	info.offset_right = -12
	add_child(info)
	var party_panel := preload("res://scripts/ui/party_panel.gd").new()
	party_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	party_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	party_panel.offset_top = 56
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
	Economy.diplomacy_changed.connect(_on_diplomacy)
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
	_alert.text = "\n".join(alerts)
	if not visible:
		return
	var castle: CastleState = Economy.player_castle
	var stock := ""
	if castle:
		var cap := castle.storage_capacity()
		var rates := castle.net_per_hour()
		for r in Economy.rules.resources:
			stock += "%s %d/%d (%+d/h)   " % [r.capitalize(), int(castle.resources[r]), int(cap), int(rates[r])]
		stock += "Garrison %d   " % castle.troop_count()
	_info.text = stock + "\n" + "Click: travel there, or pick a castle or party    F: find your party    C: your castle    K: diplomacy\nWASD / drag: pan    Q E / right-drag: rotate    wheel: zoom\nM: parchment map    Home: recentre    F1: hide    Esc: menu\nYour party: %s\nzoom %d%%    %d fps" % [_party_status, int(_zoom_t * 100.0), Engine.get_frames_per_second()]
