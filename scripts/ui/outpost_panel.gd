extends PanelContainer
## The outpost screen (P): before you have one, the regions you could found
## it in and what it costs; after, carts between your castle and your outpost
## and the carts on the road. The rules are OutpostRules (data/outposts.json).

const CARD_WIDTH := 235

var _body: VBoxContainer
var _status: Label
var _amounts := {}             ## "home" / "outpost" -> {resource: SpinBox}
var _road: Label
var _signature := ""


func _ready() -> void:
	add_to_group("outpost_panel")
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(1000, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := MenuStyle.title("Outpost", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	box.add_child(_body)
	_status = MenuStyle.label("", 15, MenuStyle.GOLD)
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_refresh())
	Economy.outpost_changed.connect(func() -> void:
		if visible:
			_signature = ""
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_P and not get_tree().paused:
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
	_signature = ""
	visible = true
	_refresh()


func close_panel() -> void:
	visible = false


func _refresh() -> void:
	if Economy.player_castle == null or Economy.outpost_rules == null:
		return
	var o := Economy.outpost_rules
	var signature := "none" if Economy.outpost.is_empty() else "have"
	if Economy.outpost.is_empty():
		for r: String in o.regions:
			signature += Economy.check_found_outpost(r)
	if signature != _signature:
		_signature = signature
		for child in _body.get_children():
			_body.remove_child(child)
			child.queue_free()
		_amounts.clear()
		_road = null
		if Economy.outpost.is_empty():
			_build_found(o)
		else:
			_build_carts(o)
	if _road != null:
		_road.text = _road_text()
		for side: String in _amounts:
			for r: String in _amounts[side]:
				var from := Economy.outpost_castle() if side == "outpost" else Economy.player_castle
				_amounts[side][r].max_value = floorf(float(from.resources.get(r, 0.0)))


# --- Founding ----------------------------------------------------------------------

func _build_found(o: OutpostRules) -> void:
	var about := MenuStyle.label("An outpost is a second castle near yours, with its own buildings, storage and production. "
			+ "Pick the land it works: that resource flows half as fast again there. It can build farms, woodcutters, quarries, "
			+ "houses, storehouses, banners, gardens and wells, a wall and a keep up to level %d, and carts carry what it makes home." % o.keep_cap,
			14, MenuStyle.MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(960, 0)
	_body.add_child(about)
	var cost: PackedStringArray = []
	for r: String in o.cost:
		cost.append("%d %s" % [int(o.cost[r]), r])
	var keep := Economy.player_castle.keep_level()
	_body.add_child(MenuStyle.label("Needs keep level %d (yours: %d).  Costs %s." % [o.keep_needed, keep, ", ".join(cost)],
			15, MenuStyle.TEXT if keep >= o.keep_needed else Color(0.95, 0.55, 0.45)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_body.add_child(row)
	for r: String in o.regions:
		var region: Dictionary = o.regions[r]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
		card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
		row.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		card.add_child(box)
		box.add_child(MenuStyle.label(String(region.name), 20, MenuStyle.GOLD))
		box.add_child(MenuStyle.label("+%d%% %s" % [roundi(float(region.bonus) * 100.0), r], 15, Color(0.6, 0.9, 0.5)))
		var text := MenuStyle.label(String(region.get("description", "")), 13, MenuStyle.MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size = Vector2(CARD_WIDTH - 24, 70)
		box.add_child(text)
		var why := Economy.check_found_outpost(r)
		var found := _button("Found here", func() -> void:
			var result := Economy.found_outpost(r)
			_status.text = result if result != "" else ("Your outpost is being raised in the %s." % region.name if Economy.online
					else "%s is yours. Open it from the map, or with Enter outpost below." % region.name)
			_signature = ""
			_refresh())
		found.disabled = why != ""
		found.tooltip_text = why
		box.add_child(found)


# --- Carts -------------------------------------------------------------------------

func _build_carts(o: OutpostRules) -> void:
	var castle := Economy.outpost_castle()
	if castle == null:
		return
	var region: Dictionary = o.regions.get(Economy.outpost.region, {})
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	_body.add_child(head)
	head.add_child(MenuStyle.label(String(Economy.outpost.name), 22, MenuStyle.GOLD))
	head.add_child(MenuStyle.label("+%d%% %s   Keep %d / %d   Carts take %s each way" % [
			roundi(float(region.get("bonus", 0.0)) * 100.0), Economy.outpost.region, castle.keep_level(), o.keep_cap,
			_clock(Economy.cart_time())], 15, MenuStyle.MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_button("Enter outpost", func() -> void:
		close_panel()
		EventBus.castle_requested.emit(OutpostRules.OUTPOST_ID)))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	_body.add_child(columns)
	columns.add_child(_side("home", "From your castle to the outpost", Economy.player_castle, o))
	columns.add_child(_side("outpost", "From the outpost to your castle", castle, o))
	_body.add_child(MenuStyle.label("On the road", 18, MenuStyle.GOLD))
	_road = MenuStyle.label("", 14, MenuStyle.TEXT)
	_body.add_child(_road)


func _side(side: String, title: String, from: CastleState, o: OutpostRules) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(MenuStyle.label(title, 17, MenuStyle.GOLD))
	box.add_child(MenuStyle.label("Up to %d per trip" % o.cart_capacity(from), 14, MenuStyle.MUTED))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	box.add_child(grid)
	_amounts[side] = {}
	for r: String in from.rules.resources:
		grid.add_child(MenuStyle.label(r.capitalize(), 14, MenuStyle.TEXT))
		var spin := SpinBox.new()
		spin.step = 50
		spin.max_value = floorf(float(from.resources.get(r, 0.0)))
		spin.custom_minimum_size = Vector2(120, 0)
		grid.add_child(spin)
		_amounts[side][r] = spin
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	buttons.add_child(_button("Fill the carts", func() -> void: _fill(side, from, o)))
	buttons.add_child(_button("Send", func() -> void:
		var load := {}
		for r: String in _amounts[side]:
			var n := int(_amounts[side][r].value)
			if n > 0:
				load[r] = n
		var why := Economy.send_carts(side == "outpost", load)
		_status.text = why if why != "" else "The carts are on their way, %s." % _clock(Economy.cart_time())
		if why == "":
			for r: String in _amounts[side]:
				_amounts[side][r].value = 0
		_refresh()))
	return card


func _fill(side: String, from: CastleState, o: OutpostRules) -> void:
	## Loads as much as fits, evenly from every resource the castle has.
	var room := o.cart_capacity(from)
	var have: Array = from.rules.resources.filter(func(r: String) -> bool: return floori(float(from.resources[r])) > 0)
	for r: String in _amounts[side]:
		_amounts[side][r].value = 0
	while room > 0 and not have.is_empty():
		var share := maxi(1, room / have.size())
		var still: Array = []
		for r: String in have:
			var spin: SpinBox = _amounts[side][r]
			var n := mini(share, floori(float(from.resources[r])) - int(spin.value))
			n = mini(n, room)
			spin.value += n
			room -= n
			if int(spin.value) < floori(float(from.resources[r])):
				still.append(r)
		have = still


func _road_text() -> String:
	var lines: PackedStringArray = []
	var now := Economy.now()
	for c: Dictionary in Economy.outpost.get("carts", []):
		var load: PackedStringArray = []
		for r: String in c.resources:
			load.append("%d %s" % [int(c.resources[r]), r])
		lines.append("%s to %s, arriving in %s" % [", ".join(load), "the outpost" if c.to == "outpost" else "your castle",
				_clock(float(c.arrive) - now)])
	return "\n".join(lines) if not lines.is_empty() else "No carts on the road."


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]
