extends PanelContainer
## Shown on the world map when you click a resource village: what it works
## and sends its holder each hour, who holds it, who defends it behind its
## palisade, what it holds now (whoever takes it carries that off), any peace
## after it changed hands, the march time and your chances. A button opens
## the attack screen. For your own village: online, send soldiers to guard
## it or bring them home; and give the village up.
## Capitals (the towns) use the same panel: they send gold, and whoever holds
## one makes every castle of their alliance produce more. Offline you can
## also send your party there. A capital also shows its town buildings, and
## whoever holds it can raise them here, one at a time.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const GOOD := Color(0.55, 0.9, 0.45)
const BAD := Color(0.95, 0.4, 0.3)

var village_id := ""

var _title: Label
var _kind: Label
var _details: Label
var _odds: Label
var _note: Label
var _attack: Button
var _travel: Button
var _guard_box: VBoxContainer
var _guard_spins := {}         ## unit -> SpinBox
var _station: Button
var _recall: Button
var _abandon: Button
var _abandon_armed := false
var _timer := 0.0
var _town_box: VBoxContainer
var _town_toggle: Button
var _town_now: Label

var _picture: InfoPicture

func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.85, 12))
	custom_minimum_size = Vector2(460, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_picture = InfoPicture.wrap(self, box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = _label(20, Color(1.0, 0.86, 0.55))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(func() -> void: show_village(""))
	head.add_child(close)
	_kind = _label(15, MUTED)
	box.add_child(_kind)
	_details = _label(14, TEXT)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_details)
	_town_box = VBoxContainer.new()
	_town_box.add_theme_constant_override("separation", 2)
	box.add_child(_town_box)
	_town_toggle = _button("", func() -> void: EventBus.town_buildings_requested.emit(village_id))
	_town_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_town_box.add_child(_town_toggle)
	_town_now = _label(14, GOOD)
	_town_box.add_child(_town_now)
	_odds = _label(15, TEXT)
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_odds)
	_attack = GameTheme.primary(_button("Prepare attack", func() -> void: EventBus.attack_screen_requested.emit("village:" + village_id)))
	box.add_child(_attack)
	_travel = _button("Travel here", func() -> void:
		EventBus.travel_requested.emit(village_id)
		show_village(""))
	box.add_child(_travel)
	_guard_box = VBoxContainer.new()
	_guard_box.add_theme_constant_override("separation", 4)
	box.add_child(_guard_box)
	_recall = _button("Bring the guards home", func() -> void:
		Economy.recall_guard(village_id)
		_note.text = "Your guards are leaving %s." % Economy.village_info(village_id).get("name", ""))
	box.add_child(_recall)
	_abandon = _button("Give up this village", _give_up)
	box.add_child(_abandon)
	_note = _label(14, Color(1.0, 0.75, 0.5))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	EventBus.village_selected.connect(show_village)
	for clears in [EventBus.party_selected, EventBus.settlement_selected, EventBus.baron_selected, EventBus.player_selected]:
		clears.connect(func(id: String) -> void:
			if id != "":
				show_village(""))
	Economy.villages_changed.connect(func() -> void:
		_guard_spins.clear()
		_refresh())
	Economy.changed.connect(_refresh)


func show_village(id: String) -> void:
	village_id = id
	_note.text = ""
	_abandon_armed = false
	_guard_spins.clear()
	visible = id != "" and not Economy.village_info(id).is_empty()
	_refresh()


func _process(delta: float) -> void:
	_timer -= delta
	if visible and _timer <= 0.0:
		_timer = 1.0
		_refresh()


func _refresh() -> void:
	if not visible:
		return
	var info := Economy.village_info(village_id)
	if info.is_empty():
		visible = false
		return
	var vr := Economy.village_rules_for(village_id)
	var capital: bool = info.get("capital", false)
	var what := "capital" if capital else "village"
	var state := Economy.village_state(village_id)
	var mine := Economy.is_my_village(village_id)
	var owner := String(state.get("owner", ""))
	var level := int(info.level)
	var per_hour := vr.rate(info, state, Economy.now())
	var bonus := "+%d%%" % roundi(Economy.capital_rules.bonus(level) * 100.0)
	var now := Economy.now()
	_title.text = String(info.name)
	_picture.show_place(InfoPicture.faction_place("capital", String(info.get("faction", ""))) if capital else "village")
	if capital:
		var faction := String(GameData.get_faction(String(info.get("faction", ""))).get("name", ""))
		_kind.text = ("Royal capital, level %d" if level >= 2 else "Town, level %d") % level + (", %s" % faction if faction != "" else "")
	else:
		_kind.text = "%s, level %d" % [vr.resource_names.get(info.resource, "Village"), level]
	var lines: PackedStringArray = []
	if mine:
		lines.append("Yours: it sends you %d %s an hour" % [per_hour, info.resource])
		if capital:
			lines.append(("Your alliance's castles produce %s more" if Economy.online else "Your castle produces %s more") % bonus)
	elif owner != "":
		var tag := String(state.get("tag", ""))
		lines.append("Held by %s%s%s" % ["[%s] " % tag if tag != "" else "", owner, " (your alliance)" if state.get("ally", false) else ""])
		lines.append("Sends its holder %d %s an hour" % [per_hour, info.resource])
		if capital:
			lines.append(("Your castle produces %s more for it" if state.get("ally", false) else "Their alliance's castles produce %s more") % bonus)
	elif capital:
		lines.append("Held by the town guard")
		lines.append("Take it and it sends you %d %s an hour" % [per_hour, info.resource])
		lines.append(("and every castle of your alliance produces %s more" if Economy.online else "and your castle produces %s more") % bonus)
	else:
		lines.append("Held by the local militia")
		lines.append("Take it and it sends you %d %s an hour" % [per_hour, info.resource])
	lines.append("Holds %d of %d %s%s" % [Economy.village_stock(village_id), vr.cap(info, state, now), info.resource,
			"" if mine else " (yours if you take it)"])
	var defenders := vr.defenders(info, state, now)
	var total := 0
	for unit: String in defenders:
		total += int(defenders[unit])
	lines.append(("Guards: %d soldiers" if owner != "" else "Town guard: %d soldiers" if capital else "Militia: %d soldiers") % total
			+ (" (%d of them the guardhouse's watch)" % _count(Economy.capital_rules.watch(info, state, now))
				if capital and not Economy.capital_rules.watch(info, state, now).is_empty() else ""))
	for unit: String in defenders:
		lines.append("    %d %s" % [int(defenders[unit]), Economy.rules.unit_plural(unit)])
	var wall := Battle.wall_from_defense(vr.wall_defense(info, state, now))
	lines.append("%s: defenders +%d%% defence" % ["Walls" if capital else "Palisade", roundi((wall - 1.0) * 100.0)])
	var peace := Economy.village_peace_until(village_id)
	if peace > now:
		lines.append("At peace for %s after changing hands" % _long_clock(peace - now))
	lines.append("March: %s each way" % _clock(Economy.village_march_time(village_id)))
	if not capital:
		lines.append("Your villages: %d of %d (keep level %d)" % [Economy.my_villages().size(), Economy.village_slots(),
				Economy.player_castle.keep_level()])
	else:
		var cr := Economy.capital_rules
		lines.append("You hold %d of %d capital%s (from keep level %d)" % [Economy.my_capitals().size(), cr.per_player,
				"" if cr.per_player == 1 else "s", cr.min_keep])
		if Economy.online:
			lines.append("Your alliance holds %d of %d" % [Economy.alliance_capitals(), cr.per_alliance])
			lines.append("Alliance war: +%d war points an hour for its holder's alliance (K)" % (int(Economy.war_rules.get("hold_per_hour", 0)) * level))
		if Economy.capital_bonus() > 0.0:
			lines.append("Capitals give you +%d%% production now" % roundi(Economy.capital_bonus() * 100.0))
	_details.text = "\n".join(lines)
	_refresh_town(capital, mine)
	_attack.visible = not mine
	_travel.visible = capital and not Economy.online
	_recall.visible = mine and Economy.online and total > 0
	_abandon.visible = mine
	_abandon.text = "Click again to give it up" if _abandon_armed else "Give up this %s" % what
	_guard_box.visible = mine and Economy.online
	if mine and Economy.online and _guard_spins.is_empty():
		_build_guard_rows()
	var army: Dictionary = Economy.player_castle.troops
	var have := Economy.player_castle.troop_count()
	if mine:
		_odds.text = "" if Economy.online else "Nobody comes to take %ss from you here; online, other players will." % what
		_odds.add_theme_color_override("font_color", MUTED)
		return
	var why := Economy.check_village_attack(village_id, army)
	if have <= 0:
		_odds.text = "Your garrison is empty. Train soldiers first."
		_odds.add_theme_color_override("font_color", TEXT)
	elif why != "" and why != "Choose some soldiers to send.":
		_odds.text = why
		_odds.add_theme_color_override("font_color", BAD)
	else:
		var chance := Battle.siege_odds(Economy.rules, Battle.auto_waves(army), defenders, Battle.DEFAULT_LAYOUT, 1, wall) \
				if total > 0 else 1.0
		_odds.text = "Your garrison of %d: %s (%d%%)" % [have, Battle.odds_text(chance), roundi(chance * 100.0)]
		_odds.add_theme_color_override("font_color", BAD.lerp(GOOD, chance))
	_attack.disabled = have <= 0 or (why != "" and why != "Choose some soldiers to send.")


func _refresh_town(capital: bool, mine: bool) -> void:
	## A line with the capital's town buildings, and the one going up; it
	## opens their window (town_panel.gd), where its holder builds them.
	_town_box.visible = capital
	if not capital:
		return
	var cr := Economy.capital_rules
	var state := Economy.village_state(village_id)
	var now := Economy.now()
	var built: PackedStringArray = []
	for id: String in cr.buildings:
		var level := cr.building_level(state, id, now)
		if level > 0:
			built.append("%s %d" % [cr.buildings[id].get("name", id), level])
	_town_toggle.text = "Town buildings: %s  ▸" % (", ".join(built) if not built.is_empty() else "none yet")
	_town_toggle.tooltip_text = "Build them in your capital" if mine else "See what this town has built"
	var going := cr.under_way(state, now)
	_town_now.visible = not going.is_empty()
	if not going.is_empty():
		_town_now.text = "Building %s level %d: %s left" % [String(cr.buildings.get(going.id, {}).get("name", going.id)), int(going.level),
				_long_clock(float(going.finish) - now)]


static func _count(army: Dictionary) -> int:
	var n := 0
	for unit: String in army:
		n += int(army[unit])
	return n


func _build_guard_rows() -> void:
	for child in _guard_box.get_children():
		_guard_box.remove_child(child)
		child.queue_free()
	_guard_box.add_child(_label(15, Color(1.0, 0.86, 0.55), "Send soldiers to guard it"))
	var grid := GridContainer.new()
	grid.columns = 2
	_guard_box.add_child(grid)
	for unit: String in Economy.player_castle.troops:
		if int(Economy.player_castle.troops[unit]) <= 0:
			continue
		grid.add_child(_label(14, TEXT, Economy.rules.unit_plural(unit)))
		var spin := SpinBox.new()
		spin.max_value = int(Economy.player_castle.troops[unit])
		spin.custom_minimum_size = Vector2(110, 0)
		grid.add_child(spin)
		_guard_spins[unit] = spin
	if _guard_spins.is_empty():
		_guard_box.add_child(_label(14, MUTED, "Your garrison is empty."))
		return
	_station = _button("Send guards", _send_guards)
	_guard_box.add_child(_station)


func _send_guards() -> void:
	var army := {}
	for unit: String in _guard_spins:
		var n := int(_guard_spins[unit].value)
		if n > 0:
			army[unit] = n
	var why := Economy.station(village_id, army)
	_note.text = why if why != "" else "Your guards are on their way, %s." % _clock(Economy.village_march_time(village_id))
	if why == "":
		_guard_spins.clear()
		_refresh()


func _give_up() -> void:
	if not _abandon_armed:
		_abandon_armed = true
		_refresh()
		return
	var why := Economy.abandon_village(village_id)
	_abandon_armed = false
	var info := Economy.village_info(village_id)
	_note.text = why if why != "" else "You gave up %s; %s take it back." % [info.get("name", ""),
			"the town guard" if info.get("capital", false) else "the militia"]
	_refresh()


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]


static func _long_clock(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	return "%dh %02dm" % [m / 60, m % 60]


func _label(size: int, color: Color, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
