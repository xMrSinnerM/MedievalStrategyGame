extends PanelContainer
## The forge screen (a tab of the Army window): your Marks and gem pouch,
## where three gems of a kind fuse into the next tier, and the forge, where
## three pieces of gear of one rarity and side become one random piece of
## the next rarity, in the slot of the first one picked (GearRules gems and
## forge). Gems go into gear from the Commanders tab.

var _marks: Label
var _pouch: GridContainer
var _groups: VBoxContainer
var _forge: Button
var _status: Label
var _picked: Array = []        ## bag item ids picked for the forge, in order
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
	var title := MenuStyle.title("Forge", 30)
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
	var help := MenuStyle.label("Robber barons drop gems as well as gear, and every win pays Marks, the trade coin. Gems go into "
			+ "your gear's sockets (Commanders tab) and add to its bonuses. Three gems of one kind and tier fuse into one of "
			+ "the next tier. The forge melds three pieces of gear of one rarity into one of the next rarity, for Marks. "
			+ "Marks are only earned by playing: barons, melting gear, chest jackpots and event prizes. They can't be bought.",
			14, MenuStyle.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(1000, 0)
	set_meta("window_help", help)
	box.add_child(help)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.custom_minimum_size = Vector2(430, 0)
	columns.add_child(left)
	_marks = MenuStyle.label("", 20, MenuStyle.GOLD)
	_marks.add_theme_font_override("font", GameTheme.TITLE_FONT)
	left.add_child(_marks)
	left.add_child(MenuStyle.label("Gem pouch", 18, MenuStyle.GOLD))
	var pouch_scroll := ScrollContainer.new()
	pouch_scroll.custom_minimum_size = Vector2(0, 330)
	pouch_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(pouch_scroll)
	_pouch = GridContainer.new()
	_pouch.columns = 3
	_pouch.add_theme_constant_override("h_separation", 10)
	_pouch.add_theme_constant_override("v_separation", 4)
	pouch_scroll.add_child(_pouch)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	right.add_child(MenuStyle.label("The forge: pick three pieces of one rarity and side", 18, MenuStyle.GOLD))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_groups = VBoxContainer.new()
	_groups.add_theme_constant_override("separation", 6)
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_groups)
	_forge = Button.new()
	_forge.focus_mode = Control.FOCUS_NONE
	_forge.add_theme_font_size_override("font_size", 16)
	_forge.custom_minimum_size = Vector2(0, 40)
	_forge.pressed.connect(_on_forge)
	right.add_child(_forge)
	_status = MenuStyle.label("", 15, MenuStyle.GOLD)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	Economy.changed.connect(func() -> void:
		if visible:
			_refresh())


func open_panel() -> void:
	_status.text = ""
	_picked = []
	_signature = ""
	visible = true
	_refresh()


func close_panel() -> void:
	visible = false


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func _refresh() -> void:
	var castle := Economy.player_castle
	var g := Economy.gear_rules
	if castle == null or g == null:
		return
	# Forget picks that left the bag.
	var ids: Array = castle.armoury.bag.map(func(x: Dictionary) -> int: return int(x.id))
	_picked = _picked.filter(func(id: int) -> bool: return ids.has(id))
	var signature := JSON.stringify(castle.armoury.bag) + JSON.stringify(castle.armoury.gems) + str(castle.armoury.get("marks", 0)) + str(_picked)
	if signature == _signature:
		return
	_signature = signature
	_marks.text = "%d Marks" % int(castle.armoury.get("marks", 0))
	_build_pouch(castle, g)
	_build_groups(castle, g)
	_update_forge(castle, g)


func _build_pouch(castle: CastleState, g: GearRules) -> void:
	for child in _pouch.get_children():
		_pouch.remove_child(child)
		child.queue_free()
	var keys: Array = []
	for kind: String in g.gems:
		for tier in range(g.gem_tiers.size(), 0, -1):
			var key := GearRules.gem_key(kind, tier)
			if GearRules.gem_count(castle, key) > 0:
				keys.append(key)
	if keys.is_empty():
		_pouch.columns = 1
		_pouch.add_child(MenuStyle.label("No gems yet. Beat robber barons to find them.", 14, MenuStyle.MUTED))
		return
	_pouch.columns = 3
	for key: String in keys:
		var n := GearRules.gem_count(castle, key)
		var name_label := MenuStyle.label("%d × %s" % [n, g.gem_name(key)], 14, g.gem_color(key))
		name_label.custom_minimum_size = Vector2(170, 0)
		_pouch.add_child(name_label)
		_pouch.add_child(MenuStyle.label(g.gem_text(key), 12, MenuStyle.MUTED))
		var fuse := Button.new()
		fuse.focus_mode = Control.FOCUS_NONE
		fuse.add_theme_font_size_override("font_size", 12)
		fuse.text = "Fuse %d" % g.fuse_count
		var why := g.check_fuse(castle, key)
		fuse.disabled = why != ""
		var p := g.gem_parts(key)
		fuse.tooltip_text = why if why != "" else "%d %s make one %s." % [g.fuse_count, g.gem_name(key),
				g.gem_name(GearRules.gem_key(p.kind, int(p.tier) + 1))]
		var k := key
		fuse.pressed.connect(func() -> void:
			var into := g.gem_name(GearRules.gem_key(p.kind, int(p.tier) + 1))
			_tell(Economy.fuse_gems(k), "Fused into a %s." % into))
		_pouch.add_child(fuse)


func _build_groups(castle: CastleState, g: GearRules) -> void:
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	var first := _first_picked(castle)
	var shown := 0
	for rarity: String in g.rarities:
		if g.next_rarity(rarity) == "":
			continue
		for side: String in ["attack", "defence"]:
			var items: Array = castle.armoury.bag.filter(func(x: Dictionary) -> bool: return x.rarity == rarity and x.side == side)
			if items.is_empty():
				continue
			shown += 1
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			row.add_theme_constant_override("v_separation", 6)
			_groups.add_child(row)
			var head := MenuStyle.label("%s %s (%d):" % [g.rarities[rarity].name, side, items.size()], 14, g.rarity_color(rarity))
			head.custom_minimum_size = Vector2(150, 0)
			row.add_child(head)
			for item: Dictionary in items:
				var id := int(item.id)
				var b := Button.new()
				b.focus_mode = Control.FOCUS_NONE
				b.toggle_mode = true
				b.button_pressed = _picked.has(id)
				b.add_theme_font_size_override("font_size", 12)
				b.text = "%s (%s)" % [item.name, String(g.slot_names.get(item.slot, item.slot)).to_lower()]
				b.tooltip_text = g.item_text(item)
				b.disabled = not first.is_empty() and not _picked.has(id) and (first.rarity != rarity or first.side != side)
				for state in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color"]:
					b.add_theme_color_override(state, g.rarity_color(rarity))
				b.pressed.connect(func() -> void: _pick(id))
				row.add_child(b)
	if shown == 0:
		_groups.add_child(MenuStyle.label("Nothing to forge: your bag holds no gear below legendary.", 14, MenuStyle.MUTED))


func _first_picked(castle: CastleState) -> Dictionary:
	if _picked.is_empty():
		return {}
	for x: Dictionary in castle.armoury.bag:
		if int(x.id) == int(_picked[0]):
			return x
	return {}


func _pick(id: int) -> void:
	if _picked.has(id):
		_picked.erase(id)
	elif _picked.size() < Economy.gear_rules.forge_count:
		_picked.append(id)
	_status.text = ""
	_signature = ""
	_refresh()


func _update_forge(castle: CastleState, g: GearRules) -> void:
	var first := _first_picked(castle)
	if first.is_empty():
		_forge.text = "Pick %d pieces to forge" % g.forge_count
		_forge.disabled = true
		_forge.tooltip_text = ""
		return
	var into := g.next_rarity(first.rarity)
	var into_name := String(g.rarities.get(into, {}).get("name", into)).to_lower()
	_forge.text = "Forge %d / %d into %s %s %s %s (%d Marks)" % [_picked.size(), g.forge_count,
			"an" if "aeiou".contains(into_name.left(1)) else "a", into_name, first.side,
			String(g.slot_names.get(first.slot, first.slot)).to_lower(), g.forge_cost(first.rarity)]
	var why := g.check_forge(castle, _picked)
	_forge.disabled = why != ""
	_forge.tooltip_text = why if _picked.size() == g.forge_count else "The new piece takes the slot of the first one you picked."
	if _picked.size() == g.forge_count and why != "":
		_status.text = why


func _on_forge() -> void:
	var castle := Economy.player_castle
	var before := int(castle.armoury.next_item)
	var why := Economy.forge_gear(_picked.duplicate())
	var made := {}
	if why == "":
		for x: Dictionary in castle.armoury.bag:
			if int(x.id) == before:
				made = x
		_picked = []
	var g := Economy.gear_rules
	_tell(why, "The forge made the %s: %s." % [made.get("name", "new gear"), g.item_text(made)] if not made.is_empty()
			else "The forge made new gear. Find it under Commanders.")


func _tell(why: String, done: String) -> void:
	_status.text = why if why != "" else done
	_signature = ""
	_refresh()
