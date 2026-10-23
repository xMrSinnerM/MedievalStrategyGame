extends PanelContainer
## The villages screen (B): the resource villages you hold, what they send
## you each hour and who guards them, how many more your keep can hold, and
## the villages nearest your castle with who holds them. "Show" takes the map
## there and opens the village's panel.

const NEAREST := 8

var _body: VBoxContainer
var _signature := ""


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(820, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := MenuStyle.title("Villages", 30)
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
	_body.add_theme_constant_override("separation", 8)
	box.add_child(_body)
	Economy.villages_changed.connect(func() -> void:
		if visible:
			_refresh())
	Economy.changed.connect(func() -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_B and not get_tree().paused:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and visible:
		close_panel()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		_signature = ""
		visible = true
		_refresh()


func close_panel() -> void:
	visible = false


func _refresh() -> void:
	var vr := Economy.village_rules
	var mine := Economy.my_villages()
	var near := _nearest()
	# Rebuild only when something shown changes, not on every tick.
	var signature := JSON.stringify([Economy.village_states, Economy.player_castle.keep_level(), mine.size()])
	if signature == _signature:
		return
	_signature = signature
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var keep := Economy.player_castle.keep_level()
	var steps: PackedStringArray = []
	for s: Dictionary in vr.slots:
		steps.append("keep %d: %d" % [int(s.keep), int(s.count)])
	_body.add_child(MenuStyle.label("You hold %d of %d (keep level %d).   Villages a keep can hold: %s." % [
			mine.size(), Economy.village_slots(), keep, ", ".join(steps)], 15, MenuStyle.TEXT))
	var income := Economy.village_income()
	if not income.is_empty():
		var parts: PackedStringArray = []
		for r: String in income:
			parts.append("+%d %s" % [int(income[r]), r])
		_body.add_child(MenuStyle.label("They send you %s an hour." % ", ".join(parts), 15, Color(0.6, 0.9, 0.5)))
	_body.add_child(MenuStyle.label("Your villages", 20, MenuStyle.GOLD))
	if mine.is_empty():
		var hint := MenuStyle.label("None yet. Beat a village's militia to take it: it then sends you its resource every hour, "
				+ "and whoever takes it from you carries off what it holds." + (" Online, station soldiers there to keep it." if Economy.online else ""),
				14, MenuStyle.MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(780, 0)
		_body.add_child(hint)
	else:
		var grid := _grid()
		for text in ["Village", "Works", "Per hour", "Holds", "Guards", ""]:
			grid.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
		for v: Dictionary in mine:
			var state := Economy.village_state(String(v.id))
			var guards := 0
			for unit: String in state.get("guard", {}):
				guards += int(state.guard[unit])
			grid.add_child(MenuStyle.label(String(v.name), 15, MenuStyle.TEXT))
			grid.add_child(MenuStyle.label("%s, level %d" % [v.resource, int(v.level)], 15, MenuStyle.TEXT))
			grid.add_child(MenuStyle.label("+%d" % vr.yield_per_hour(v.resource, int(v.level)), 15, MenuStyle.TEXT))
			grid.add_child(MenuStyle.label("%d" % Economy.village_stock(String(v.id)), 15, MenuStyle.TEXT))
			grid.add_child(MenuStyle.label("%d" % guards if Economy.online else "-", 15, MenuStyle.TEXT))
			grid.add_child(_show_button(String(v.id)))
		_body.add_child(grid)
	_body.add_child(MenuStyle.label("Nearest villages", 20, MenuStyle.GOLD))
	var others := _grid()
	for text in ["Village", "Works", "Held by", "Defenders", "March", ""]:
		others.add_child(MenuStyle.label(text, 14, MenuStyle.MUTED))
	for v: Dictionary in near:
		var id := String(v.id)
		var state := Economy.village_state(id)
		var owner := String(state.get("owner", ""))
		var tag := String(state.get("tag", ""))
		var defenders := vr.defenders(v, state)
		var n := 0
		for unit: String in defenders:
			n += int(defenders[unit])
		others.add_child(MenuStyle.label(String(v.name), 15, MenuStyle.TEXT))
		others.add_child(MenuStyle.label("%s, level %d" % [v.resource, int(v.level)], 15, MenuStyle.TEXT))
		others.add_child(MenuStyle.label(("[%s] " % tag if tag != "" else "") + owner if owner != "" else "the militia", 15,
				Color(0.55, 0.95, 0.55) if state.get("ally", false) else MenuStyle.TEXT))
		others.add_child(MenuStyle.label("%d" % n, 15, MenuStyle.TEXT))
		others.add_child(MenuStyle.label(_clock(Economy.village_march_time(id)), 15, MenuStyle.TEXT))
		others.add_child(_show_button(id))
	_body.add_child(others)


func _nearest() -> Array:
	var home := Economy.home_position()
	var list := Economy.villages.filter(func(v: Dictionary) -> bool: return not Economy.is_my_village(String(v.id)))
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return home.distance_to(Vector2(float(a.position[0]), float(a.position[1]))) \
				< home.distance_to(Vector2(float(b.position[0]), float(b.position[1]))))
	return list.slice(0, NEAREST)


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 4)
	return grid


func _show_button(id: String) -> Button:
	var b := Button.new()
	b.text = "Show"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func() -> void:
		close_panel()
		EventBus.map_focus_requested.emit(Economy.village_position(id))
		EventBus.village_selected.emit(id))
	return b


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [s / 60, s % 60]
