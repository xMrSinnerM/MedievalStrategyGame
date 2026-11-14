extends PanelContainer
## The Kingdoms page (R): the lands across the sea (data/kingdoms.json).
## Each has its own painted map. Before you have a castle there it shows
## what the kingdom holds and what founding one costs; after, your castle
## and the good waiting in it, the ships carrying it home, and the robber
## barons' camps: click one on the map to see it and send an army.

var _tabs := {}                ## kingdom id -> its Button
var _map: KingdomMap
var _side: VBoxContainer
var _status: Label
var _kingdom := ""
var _camp := ""
var _signature := ""
var _stock: Label              ## the good waiting, refreshed every tick
var _ship: Button
var _camp_text: Label
var _attack: Button


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
	var title := MenuStyle.title("Kingdoms", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	var about := MenuStyle.label("Across the sea lie other kingdoms, each with its own map, its own robber barons and a good "
			+ "found nowhere else. Found a castle there and its keep gathers the good; ships carry it home, where it pays for elite "
			+ "soldiers and master studies. Your armies sail from home to fight the kingdom's barons, who hold the good too. "
			+ "Goods need no storage and can't be looted or bought.", 14, MenuStyle.MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(960, 0)
	box.add_child(about)
	set_meta("window_help", about)
	var picks := HBoxContainer.new()
	picks.add_theme_constant_override("separation", 8)
	box.add_child(picks)
	var rules := Economy.kingdom_rules
	for id: String in rules.ids():
		var b := Button.new()
		b.text = String(rules.kingdoms[id].name)
		b.icon = Icons.get_icon(String(rules.kingdoms[id].good), 22)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 38)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(func() -> void: _show(id))
		picks.add_child(b)
		_tabs[id] = b
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	box.add_child(columns)
	_map = KingdomMap.new()
	_map.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_map.camp_picked.connect(func(id: String) -> void:
		_camp = id
		_signature = ""
		_refresh())
	_map.castle_picked.connect(_enter)
	columns.add_child(_map)
	_side = VBoxContainer.new()
	_side.add_theme_constant_override("separation", 8)
	_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_side)
	_status = MenuStyle.label("", 15, MenuStyle.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_refresh())
	Economy.kingdoms_changed.connect(func() -> void:
		if visible:
			_signature = ""
			_refresh())
	if not rules.ids().is_empty():
		_kingdom = String(rules.ids()[0])


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_R and not get_tree().paused:
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
	_status.text = ""
	visible = true
	_show(_kingdom)


func close_panel() -> void:
	visible = false


func _show(id: String) -> void:
	_kingdom = id
	_camp = ""
	_signature = ""
	for k: String in _tabs:
		_tabs[k].button_pressed = k == id
	_map.show_kingdom(id)
	_refresh()


func _enter() -> void:
	if Economy.kingdom_castle(_kingdom) == null:
		return
	close_panel()
	EventBus.castle_requested.emit(KingdomRules.castle_id(_kingdom))


func _refresh() -> void:
	var rules := Economy.kingdom_rules
	if Economy.player_castle == null or rules == null or not rules.has(_kingdom):
		return
	var def: Dictionary = rules.kingdoms[_kingdom]
	var castle := Economy.kingdom_castle(_kingdom)
	var signature := "%s|%s|%s|%s" % [_kingdom, _camp, castle != null, Economy.check_found_kingdom(_kingdom) if castle == null else ""]
	if signature != _signature:
		_signature = signature
		for child in _side.get_children():
			_side.remove_child(child)
			child.queue_free()
		_stock = null
		_ship = null
		_camp_text = null
		_attack = null
		if castle == null:
			_build_found(def)
		else:
			_build_castle(def, castle)
	if castle == null or _stock == null:
		return
	var good := String(def.good)
	var keep := castle.keep_level()
	var waiting := rules.waiting(castle, _kingdom)
	_stock.text = "%s waiting here: %d of %d  (+%d an hour)\nAt home: %d %s" % [rules.good_name(good), waiting,
			int(float(def.yield.store) * keep), int(float(def.yield.rate) * keep),
			floori(float(Economy.player_castle.goods.get(good, 0.0)) + 0.0001), good]
	_ship.text = "Ship %d %s home  (%s)" % [waiting, good, _clock(rules.voyage(_kingdom))]
	_ship.disabled = waiting < 1
	if _camp_text != null:
		_show_camp()


# --- Before you have a castle there ---------------------------------------------------

func _build_found(def: Dictionary) -> void:
	var rules := Economy.kingdom_rules
	_side.add_child(MenuStyle.label(String(def.name), 26, MenuStyle.GOLD))
	var text := MenuStyle.label(String(def.get("description", "")), 15, MenuStyle.TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(text)
	var good := String(def.good)
	var gives := IconLabel.make("Its keep gathers %d %s an hour for each keep level, and its %d baron camps hold more." % [
			int(def.yield.rate), good, def.get("camps", []).size()], 15)
	gives.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(gives)
	var uses := MenuStyle.label(_uses(good), 14, MenuStyle.MUTED)
	uses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(uses)
	var keep := Economy.player_castle.keep_level()
	_side.add_child(MenuStyle.label("Needs keep level %d (yours: %d)." % [int(def.keep_needed), keep], 15,
			MenuStyle.TEXT if keep >= int(def.keep_needed) else Color(0.95, 0.55, 0.45)))
	var cost: PackedStringArray = []
	for r: String in def.cost:
		cost.append("%d %s" % [int(def.cost[r]), r])
	_side.add_child(IconLabel.make("Costs " + ", ".join(cost), 15))
	var limits := MenuStyle.label("The castle there builds farms, woodcutters, quarries, houses, storehouses and decorations, a wall and "
			+ "a keep up to level %d. It can't be attacked." % rules.keep_cap, 14, MenuStyle.MUTED)
	limits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_side.add_child(limits)
	var why := Economy.check_found_kingdom(_kingdom)
	var found := GameTheme.primary(_button("Found a castle in %s" % def.name, func() -> void:
		var result := Economy.found_kingdom(_kingdom)
		_status.text = result if result != "" else ("Your ships are sailing for %s." % def.name if Economy.online
				else "%s is yours. Click it on the map to enter it." % def.castle_name)
		_signature = ""
		_refresh()))
	found.disabled = why != ""
	found.tooltip_text = why
	_side.add_child(found)


func _uses(good: String) -> String:
	## What a good pays for, read from the soldiers and studies that cost it.
	var rules := Economy.rules
	var names: PackedStringArray = []
	for unit: String in rules.units:
		if rules.unit_cost(unit).has(good):
			names.append(rules.unit_plural(unit))
	for study: String in rules.studies:
		if rules.study_cost(study, 1).has(good):
			names.append(rules.study_name(study))
	return "%s pays for: %s." % [Economy.kingdom_rules.good_name(good), ", ".join(names)] if not names.is_empty() else ""


# --- Your castle there ----------------------------------------------------------------

func _build_castle(def: Dictionary, castle: CastleState) -> void:
	var rules := Economy.kingdom_rules
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_side.add_child(head)
	var title := MenuStyle.label(String(def.castle_name), 24, MenuStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(MenuStyle.label("Keep %d / %d" % [castle.keep_level(), rules.keep_cap], 15, MenuStyle.MUTED))
	head.add_child(_button("Enter castle", _enter))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	_side.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.add_child(Medallion.make(String(def.good), 44))
	_stock = MenuStyle.label("", 15, MenuStyle.TEXT)
	_stock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stock)
	_ship = _button("", func() -> void:
		var why := Economy.ship_goods(_kingdom)
		_status.text = why if why != "" else "The ship has sailed. It lands in %s." % _clock(rules.voyage(_kingdom))
		_refresh())
	box.add_child(_ship)
	var uses := MenuStyle.label(_uses(String(def.good)), 13, MenuStyle.MUTED)
	uses.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(uses)
	var camp_card := PanelContainer.new()
	camp_card.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	_side.add_child(camp_card)
	var camp_box := VBoxContainer.new()
	camp_box.add_theme_constant_override("separation", 6)
	camp_card.add_child(camp_box)
	_camp_text = MenuStyle.label("", 14, MenuStyle.TEXT)
	_camp_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	camp_box.add_child(_camp_text)
	_attack = GameTheme.primary(_button("Prepare attack", func() -> void:
		close_panel()
		EventBus.attack_screen_requested.emit(_camp)))
	camp_box.add_child(_attack)
	_show_camp()


func _show_camp() -> void:
	var camp := Economy.get_baron(_camp)
	_attack.visible = camp != null
	if camp == null:
		_camp_text.text = "Click a camp on the map to see its garrison and loot, and to send an army against it."
		return
	var br := Economy.baron_rules.for_camp(camp)
	var now := Economy.now()
	var lines: PackedStringArray = ["%s, level %d" % [camp.camp_name, camp.level]]
	if camp.level < br.max_level:
		lines.append("Wins %d of %d to reach level %d" % [camp.defeats, br.defeats_needed(camp.level), camp.level + 1])
	var garrison := camp.garrison(Economy.baron_rules)
	var parts: PackedStringArray = []
	var total := 0
	for unit: String in garrison:
		total += int(garrison[unit])
		parts.append("%d %s" % [garrison[unit], Economy.rules.unit_plural(unit).to_lower()])
	lines.append("Garrison of %d: %s" % [total, ", ".join(parts)])
	lines.append("Palisade: defenders +%d%% defence" % roundi((Battle.wall_from_defense(br.palisade(camp.level)
			* camp.walls_factor(now)) - 1.0) * 100.0))
	var loot := Economy.baron_loot(camp.level, camp)
	parts = []
	for r: String in loot:
		parts.append("%d %s" % [loot[r], r])
	lines.append("Loot: " + ", ".join(parts))
	lines.append("Voyage and march: %s each way" % _clock(Economy.march_time_to(camp)))
	if not camp.is_ready(now):
		lines.append("Rebuilding for %s" % _clock(camp.rebuilt_at - now))
	_camp_text.text = "\n".join(lines)
	_attack.text = "Prepare attack" if camp.is_ready(now) else "Rebuilding"
	_attack.disabled = not camp.is_ready(now) or Economy.player_castle.troop_count() <= 0
	_attack.tooltip_text = "Your garrison at home is empty." if Economy.player_castle.troop_count() <= 0 else ""


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]
