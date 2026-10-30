extends PanelContainer
## The commanders screen (H): your commanders and castellan with the gear
## they wear, and the bag of gear robber barons dropped. Click gear in the
## bag to put it on someone or sell it; click worn gear to take it off.
## Commanders wear attack gear and lead your attacks; the castellan wears
## defence gear and leads your castle's defence (GearRules).

const SLOT_WIDTH := 150

var _people: VBoxContainer
var _bag_title: Label
var _bag: GridContainer
var _detail: VBoxContainer
var _status: Label
var _selected := -1            ## the bag item shown in the detail box
var _signature := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(1060, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	box.add_child(head)
	var title := MenuStyle.title("Commanders", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	var about := MenuStyle.label("Commanders lead your attacks and wear attack gear; the castellan leads your castle's defence "
			+ "and wears defence gear. Robber barons drop gear when beaten, better from stronger camps. More commanders join "
			+ "at keep levels 3 and 5, and they rise in level by fighting, earning a skill point each level.", 14, MenuStyle.MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(1000, 0)
	box.add_child(about)
	set_meta("window_help", about)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)
	_people = VBoxContainer.new()
	_people.add_theme_constant_override("separation", 8)
	_people.custom_minimum_size = Vector2(640, 0)
	columns.add_child(_people)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	_bag_title = MenuStyle.label("", 18, MenuStyle.GOLD)
	right.add_child(_bag_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 250)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_bag = GridContainer.new()
	_bag.columns = 2
	_bag.add_theme_constant_override("h_separation", 6)
	_bag.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_bag)
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	right.add_child(detail)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.custom_minimum_size = Vector2(0, 150)
	detail.add_child(_detail)
	_status = MenuStyle.label("", 15, MenuStyle.GOLD)
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_H and not get_tree().paused:
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
	_selected = -1
	_signature = ""
	visible = true
	_refresh()


func close_panel() -> void:
	visible = false


func _refresh() -> void:
	var castle := Economy.player_castle
	var g := Economy.gear_rules
	if castle == null or g == null:
		return
	var away: PackedStringArray = []
	for c: Dictionary in castle.armoury.commanders:
		away.append(_clock(float(c.away_until) - Economy.now()))
	var signature := JSON.stringify(castle.armoury) + ",".join(away) + str(_selected)
	if signature == _signature:
		return
	_signature = signature
	_build_people(castle, g)
	_build_bag(castle, g)
	_build_detail(castle, g)


# --- Commanders and castellan ------------------------------------------------------

func _build_people(castle: CastleState, g: GearRules) -> void:
	for child in _people.get_children():
		_people.remove_child(child)
		child.queue_free()
	for c: Dictionary in castle.armoury.commanders:
		var left := float(c.away_until) - Economy.now()
		var level := int(c.level)
		var next := g.xp_to_next(c)
		var line := "Level %d   %s" % [level, ("%d xp to level %d" % [next, level + 1]) if next > 0 else "highest level"]
		line += "   " + ("Away with an army, home in %s" % _clock(left) if left > 0.0 else "At home")
		var spare := GearRules.skill_points(c)
		if spare > 0:
			line += "   %d skill point%s to spend (Skills tab)" % [spare, "" if spare == 1 else "s"]
		_people.add_child(_card(String(c.name), line, g.effects_text(g.commander_effects(c)), c.gear, int(c.id), left > 0.0, g))
	_people.add_child(_card("Castellan", "Leads your castle's defence", g.effects_text(g.castellan_effects(castle)),
			castle.armoury.castellan, "castellan", false, g))


func _card(title: String, line: String, fx: String, gear: Dictionary, who: Variant, away: bool, g: GearRules) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	head.add_child(MenuStyle.label(title, 18, MenuStyle.GOLD))
	head.add_child(MenuStyle.label(line, 14, MenuStyle.MUTED))
	box.add_child(MenuStyle.label(fx, 14, MenuStyle.TEXT))
	var slots := HBoxContainer.new()
	slots.add_theme_constant_override("separation", 6)
	box.add_child(slots)
	for slot: String in g.slots:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(SLOT_WIDTH, 44)
		b.add_theme_font_size_override("font_size", 12)
		b.clip_text = true
		var slot_name := String(g.slot_names.get(slot, slot))
		if gear.has(slot):
			var item: Dictionary = gear[slot]
			b.text = "%s\n%s" % [slot_name, item.name]
			_color(b, g.rarity_color(item.rarity))
			b.tooltip_text = "%s (%s)\n%s\nClick to take it off." % [item.name, g.rarities[item.rarity].name, g.item_text(item)]
			b.disabled = away
			var s := slot
			b.pressed.connect(func() -> void: _tell(Economy.unequip_gear(who, s), "%s goes back in your bag." % item.name))
		else:
			b.text = "%s\nempty" % slot_name
			_color(b, MenuStyle.MUTED)
			b.disabled = true
		slots.add_child(b)
	return card


# --- The bag ---------------------------------------------------------------------------

func _build_bag(castle: CastleState, g: GearRules) -> void:
	for child in _bag.get_children():
		_bag.remove_child(child)
		child.queue_free()
	var bag: Array = castle.armoury.bag
	_bag_title.text = "Your bag (%d / %d)" % [bag.size(), g.bag_size]
	if bag.is_empty():
		_bag.columns = 1
		var none := MenuStyle.label("Empty. Beat robber barons to find gear.", 14, MenuStyle.MUTED)
		_bag.add_child(none)
		return
	_bag.columns = 2
	for item: Dictionary in bag:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = int(item.id) == _selected
		b.custom_minimum_size = Vector2(178, 40)
		b.add_theme_font_size_override("font_size", 12)
		b.clip_text = true
		b.text = "%s\n%s %s" % [item.name, "Attack" if item.side == "attack" else "Defence", String(g.slot_names.get(item.slot, item.slot)).to_lower()]
		_color(b, g.rarity_color(item.rarity))
		b.tooltip_text = g.item_text(item)
		var id := int(item.id)
		b.pressed.connect(func() -> void:
			_selected = id
			_refresh())
		_bag.add_child(b)


func _build_detail(castle: CastleState, g: GearRules) -> void:
	for child in _detail.get_children():
		_detail.remove_child(child)
		child.queue_free()
	var item := {}
	for x: Dictionary in castle.armoury.bag:
		if int(x.id) == _selected:
			item = x
	if item.is_empty():
		_detail.add_child(MenuStyle.label("Pick gear in your bag to wear or sell it.", 14, MenuStyle.MUTED))
		return
	var name_label := MenuStyle.label(String(item.name), 18, g.rarity_color(item.rarity))
	_detail.add_child(name_label)
	_detail.add_child(MenuStyle.label("%s %s %s" % [g.rarities[item.rarity].name, "attack" if item.side == "attack" else "defence",
			String(g.slot_names.get(item.slot, item.slot)).to_lower()], 14, MenuStyle.MUTED))
	_detail.add_child(MenuStyle.label(g.item_text(item), 15, MenuStyle.TEXT))
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 6)
	buttons.add_theme_constant_override("v_separation", 6)
	_detail.add_child(buttons)
	var id := int(item.id)
	if item.side == "attack":
		for c: Dictionary in castle.armoury.commanders:
			var who := int(c.id)
			var first := String(c.name).split(" ")[1] if String(c.name).split(" ").size() > 1 else String(c.name)
			var b := _small("Give to %s" % first, func() -> void:
				_selected = -1
				_tell(Economy.equip_gear(who, id), "%s now wears the %s." % [c.name, item.name]))
			if c.gear.has(item.slot):
				b.tooltip_text = "Swaps out %s (%s)" % [c.gear[item.slot].name, g.item_text(c.gear[item.slot])]
			b.disabled = float(c.away_until) > Economy.now()
			buttons.add_child(b)
	else:
		var b := _small("Give to the castellan", func() -> void:
			_selected = -1
			_tell(Economy.equip_gear("castellan", id), "Your castellan now wears the %s." % item.name))
		if castle.armoury.castellan.has(item.slot):
			var old: Dictionary = castle.armoury.castellan[item.slot]
			b.tooltip_text = "Swaps out %s (%s)" % [old.name, g.item_text(old)]
		buttons.add_child(b)
	buttons.add_child(_small("Sell for %d gold" % g.sell_price(item), func() -> void:
		_selected = -1
		_tell(Economy.sell_gear(id), "Sold the %s for %d gold." % [item.name, g.sell_price(item)])))


func _tell(why: String, done: String) -> void:
	_status.text = why if why != "" else done
	_signature = ""
	_refresh()


func _small(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 32)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(action)
	return b


static func _color(b: Button, color: Color) -> void:
	for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_disabled_color"]:
		b.add_theme_color_override(state, color if state != "font_disabled_color" else color.darkened(0.3))


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
