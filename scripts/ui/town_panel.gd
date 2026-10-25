extends PanelContainer
## A capital's town buildings: town walls, market, guardhouse and guild hall
## (data/capitals.json "buildings"), each a card with its level, what it does
## now and at its next level, and for the capital's holder what that costs
## and a button to build it. Above them, the building going up. Opened from
## the capital's card on the map; anyone can look, only the holder builds.
## One building at a time, paid from your castle, and nothing bought can
## hurry it: only time and resources.

const ICONS := {"walls": "defence", "market": "gold", "guardhouse": "shield", "guildhall": "alliance"}
const DONE := Color(0.55, 0.9, 0.45)
const LOCKED := Color(1.0, 0.6, 0.45)

var village_id := ""

var _title: Label
var _holder: Label
var _now_box: PanelContainer
var _now_title: Label
var _now_bar: ProgressBar
var _now_time: Label
var _note: Label
var _cards := {}          ## building -> {"level", "effect", "next", "cost", "button"}
var _timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.96, 20))
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	head.add_child(Icons.rect("villages", 38))
	_title = MenuStyle.title("", 30)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_child(_title)
	_holder = MenuStyle.label("", 15, MenuStyle.MUTED)
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_holder)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)

	# The building going up.
	_now_box = PanelContainer.new()
	_now_box.add_theme_stylebox_override("panel", MenuStyle.panel(0.5, 10))
	box.add_child(_now_box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_now_box.add_child(row)
	_now_title = MenuStyle.label("", 17, MenuStyle.TEXT)
	_now_title.custom_minimum_size = Vector2(300, 0)
	_now_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_now_title)
	_now_bar = ProgressBar.new()
	_now_bar.show_percentage = false
	_now_bar.custom_minimum_size = Vector2(220, 14)
	_now_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_now_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_now_bar)
	_now_time = MenuStyle.label("", 15, MenuStyle.GOLD)
	_now_time.custom_minimum_size = Vector2(90, 0)
	_now_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_now_time.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_now_time)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)
	var cr := Economy.capital_rules
	for id: String in cr.buildings:
		grid.add_child(_card(id, cr.buildings[id]))
	_note = MenuStyle.label("", 15, Color(1.0, 0.75, 0.5))
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_note)
	var hint := MenuStyle.label("Town buildings belong to the town: they stay when it changes hands or is given up, "
			+ "but one still going up is lost. One at a time, paid from your castle.", 14, MenuStyle.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	EventBus.town_buildings_requested.connect(open_panel)
	Economy.villages_changed.connect(_refresh)
	Economy.changed.connect(_refresh)


func _card(id: String, def: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", MenuStyle.panel(0.55, 12))
	card.custom_minimum_size = Vector2(380, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	head.add_child(Icons.rect(ICONS.get(id, "villages"), 28))
	var name := MenuStyle.label(String(def.get("name", id)), 19, MenuStyle.GOLD)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name)
	var level := MenuStyle.label("", 15, MenuStyle.MUTED)
	head.add_child(level)
	var about := MenuStyle.label(String(def.get("description", "")), 13, MenuStyle.MUTED)
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(350, 0)
	box.add_child(about)
	var effect := MenuStyle.label("", 15, MenuStyle.TEXT)
	box.add_child(effect)
	var next := MenuStyle.label("", 14, MenuStyle.TEXT)
	box.add_child(next)
	var cost := MenuStyle.label("", 14, MenuStyle.MUTED)
	cost.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(cost)
	var button := GameTheme.primary(Button.new())
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_build.bind(id))
	box.add_child(button)
	_cards[id] = {"level": level, "effect": effect, "next": next, "cost": cost, "button": button}
	return card


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func open_panel(id: String) -> void:
	if not Economy.is_capital(id):
		return
	village_id = id
	_note.text = ""
	visible = true
	_refresh()


func close_panel() -> void:
	visible = false


func _process(delta: float) -> void:
	_timer -= delta
	if visible and _timer <= 0.0:
		_timer = 1.0
		_refresh()


func _refresh() -> void:
	if not visible:
		return
	var cr := Economy.capital_rules
	var info := Economy.village_info(village_id)
	var state := Economy.village_state(village_id)
	var mine := Economy.is_my_village(village_id)
	var now := Economy.now()
	var owner := String(state.get("owner", ""))
	_title.text = "%s: town buildings" % info.get("name", "")
	_holder.text = "Yours" if mine else ("Held by %s" % owner if owner != "" else "Held by the town guard")
	var going := cr.under_way(state, now)
	_now_box.visible = not going.is_empty()
	if not going.is_empty():
		var total := cr.building_time(String(going.id), int(going.level))
		var left := float(going.finish) - now
		_now_title.text = "Building %s, level %d" % [cr.buildings.get(going.id, {}).get("name", going.id), int(going.level)]
		_now_bar.value = 100.0 * clampf(1.0 - left / maxf(total, 1.0), 0.0, 1.0)
		_now_time.text = long_clock(left)
	for id: String in _cards:
		var card: Dictionary = _cards[id]
		var level := cr.building_level(state, id, now)
		var top := int(cr.buildings[id].get("max_level", 1))
		card.level.text = "Level %d of %d" % [level, top]
		card.effect.text = "Now: %s" % effect_text(id, level)
		card.effect.add_theme_color_override("font_color", DONE if level > 0 else MenuStyle.MUTED)
		if level >= top:
			card.next.text = "Fully built"
			card.cost.text = ""
			card.button.visible = false
			continue
		card.next.text = "Level %d: %s" % [level + 1, effect_text(id, level + 1)]
		var cost := cr.building_cost(id, level + 1)
		var parts: PackedStringArray = []
		for r: String in cost:
			parts.append("%d %s" % [int(cost[r]), r])
		card.cost.text = "%s, %s" % [", ".join(parts), long_clock(cr.building_time(id, level + 1))]
		card.button.visible = mine
		card.button.text = "Build" if level == 0 else "Upgrade to level %d" % (level + 1)
		var why := Economy.check_capital_build(village_id, id) if mine else ""
		card.button.disabled = why != ""
		card.button.tooltip_text = why
		card.cost.add_theme_color_override("font_color", LOCKED if why == "Not enough resources" else MenuStyle.MUTED)


func _build(id: String) -> void:
	var why := Economy.build_in_capital(village_id, id)
	_note.text = why if why != "" else "Work on the %s has begun." % Economy.capital_rules.buildings.get(id, {}).get("name", id)
	_refresh()


static func effect_text(id: String, level: int) -> String:
	## What a town building does at this level, in a few words.
	if level <= 0:
		return "not built"
	var n := Economy.capital_rules.building_effect(id, level)
	match id:
		"walls":
			return "+%d to the town's walls" % roundi(n)
		"market":
			return "+%d%% gold an hour" % roundi(n * 100.0)
		"guardhouse":
			return "%d townsfolk fight beside your guards" % roundi(n)
		"guildhall":
			return "+%d%% production for %s" % [roundi(n * 100.0), "your alliance" if Economy.online else "your castle"]
	return ""


static func long_clock(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	return "%dh %02dm" % [m / 60, m % 60]
