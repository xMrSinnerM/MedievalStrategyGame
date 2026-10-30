extends PanelContainer
## The game owner's tools (O on the world map, online, only for the owner's
## account): start or stop timed events whenever you like, and give any
## player, or everyone, resources and soldiers. The server checks every order
## and keeps a log of them; other players never see this panel.

const ON := Color(0.55, 0.9, 0.45)
const GIVE_STEP := 100

var _events: GridContainer
var _target: OptionButton
var _amounts := {}     # resource or unit id -> SpinBox
var _log: Label
var _status: Label
var _states := {}     # event id -> its "On, ends in ..." label
var _timer := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(760, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var head := HBoxContainer.new()
	set_meta("window_head", head)
	box.add_child(head)
	var title := MenuStyle.title("Owner tools", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	box.add_child(MenuStyle.label("Only you can see this. Every action is written to the log below.", 14, MenuStyle.MUTED))

	box.add_child(MenuStyle.label("Events", 19, MenuStyle.GOLD))
	_events = GridContainer.new()
	_events.columns = 4
	_events.add_theme_constant_override("h_separation", 18)
	_events.add_theme_constant_override("v_separation", 6)
	box.add_child(_events)
	box.add_child(HSeparator.new())

	box.add_child(MenuStyle.label("Give resources and soldiers", 19, MenuStyle.GOLD))
	var to := HBoxContainer.new()
	to.add_theme_constant_override("separation", 10)
	to.add_child(MenuStyle.label("To:", 16, MenuStyle.TEXT))
	_target = OptionButton.new()
	_target.custom_minimum_size = Vector2(260, 30)
	_target.focus_mode = Control.FOCUS_NONE
	to.add_child(_target)
	box.add_child(to)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for r: String in Economy.rules.resources:
		_add_amount(grid, r, r.capitalize())
	for unit: String in Economy.rules.units:
		_add_amount(grid, unit, Economy.rules.unit_plural(unit))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	buttons.add_child(MenuStyle.button("Give", _give, 180.0))
	buttons.add_child(MenuStyle.button("Clear", _clear, 180.0))
	box.add_child(buttons)
	_status = MenuStyle.label("", 15, MenuStyle.MUTED)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	box.add_child(HSeparator.new())

	box.add_child(MenuStyle.label("Admin log", 19, MenuStyle.GOLD))
	_log = MenuStyle.label("", 14, MenuStyle.TEXT)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_log)
	Economy.admin_changed.connect(_on_admin_changed)


func _add_amount(grid: GridContainer, id: String, text: String) -> void:
	grid.add_child(MenuStyle.label(text, 16, MenuStyle.TEXT))
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 1000000
	spin.step = 1
	spin.custom_arrow_step = GIVE_STEP
	spin.custom_minimum_size = Vector2(140, 0)
	grid.add_child(spin)
	_amounts[id] = spin


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_O and not get_tree().paused and Economy.online and Economy.is_admin:
		toggle()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_ESCAPE and visible:
		close_panel()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.0
		_tick_events()


func toggle() -> void:
	if visible:
		close_panel()
	else:
		open_panel()


func open_panel() -> void:
	if not Economy.is_admin:
		return
	_fill()
	Economy.admin_order({"action": "admin"})
	visible = true


func close_panel() -> void:
	visible = false


func _on_admin_changed(error: String) -> void:
	if not Economy.is_admin:
		visible = false
		return
	if error != "":
		_status.text = error
		_status.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	elif _status.text.begins_with("Sending"):
		_status.text = "Sent."
	_fill()


func _fill() -> void:
	_fill_events()
	var chosen := _target.get_item_text(_target.selected) if _target.selected >= 0 else ""
	_target.clear()
	_target.add_item("Everyone")
	for name: String in Economy.admin_view.get("players", []):
		_target.add_item(name)
		if name == chosen:
			_target.select(_target.item_count - 1)
	var lines: PackedStringArray = []
	for e: Dictionary in Economy.admin_view.get("log", []).slice(0, 8):
		lines.append("%s  %s" % [Time.get_datetime_string_from_unix_time(int(e.at), true), _log_text(e)])
	_log.text = "\n".join(lines) if not lines.is_empty() else "Nothing yet."


func _tick_events() -> void:
	var t := Economy.now()
	for e: Dictionary in Economy.admin_view.get("events", []):
		var state: Label = _states.get(String(e.id))
		if state != null and e.get("on", false):
			state.text = "On, ends in %s" % _days(float(e.end) - t)


func _fill_events() -> void:
	_states.clear()
	var keep := {}   # remember typed hours while redrawing
	for child in _events.get_children():
		if child is SpinBox:
			keep[child.name] = child.value
		_events.remove_child(child)
		child.queue_free()
	var t := Economy.now()
	for e: Dictionary in Economy.admin_view.get("events", []):
		var on: bool = e.get("on", false)
		_events.add_child(MenuStyle.label(String(e.name), 16, MenuStyle.TEXT))
		var state := MenuStyle.label("On, ends in %s" % _days(float(e.end) - t) if on else "Off", 15, ON if on else MenuStyle.MUTED)
		state.custom_minimum_size = Vector2(190, 0)
		_events.add_child(state)
		_states[String(e.id)] = state
		var hours := SpinBox.new()
		hours.name = "hours_" + String(e.id)
		hours.min_value = 1
		hours.max_value = 336
		hours.suffix = "h"
		hours.value = keep.get(hours.name, float(e.get("hours", 24)))
		hours.editable = not on
		_events.add_child(hours)
		var button := Button.new()
		button.text = "Stop now" if on else "Start now"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(130, 30)
		var id := String(e.id)
		button.pressed.connect(func() -> void:
			button.disabled = true
			_status.text = ""
			if on:
				Economy.admin_order({"action": "admin_stop_event", "event": id})
			else:
				Economy.admin_order({"action": "admin_start_event", "event": id, "hours": int(hours.value)}))
		_events.add_child(button)


func _give() -> void:
	var resources := {}
	var troops := {}
	for id: String in _amounts:
		var n := int(_amounts[id].value)
		if n <= 0:
			continue
		if Economy.rules.units.has(id):
			troops[id] = n
		else:
			resources[id] = n
	if resources.is_empty() and troops.is_empty():
		_status.text = "Choose something to give."
		return
	var target := "*" if _target.selected <= 0 else _target.get_item_text(_target.selected)
	_status.remove_theme_color_override("font_color")
	_status.text = "Sending to %s..." % ("everyone" if target == "*" else target)
	Economy.admin_order({"action": "admin_give", "target": target, "resources": resources, "troops": troops})


func _clear() -> void:
	for id: String in _amounts:
		_amounts[id].value = 0


func _log_text(e: Dictionary) -> String:
	var d: Dictionary = e.get("details", {})
	match String(e.get("action", "")):
		"admin_start_event":
			return "Started %s for %dh" % [_event_name(d), roundi((float(d.end) - float(d.start)) / 3600.0)]
		"admin_stop_event":
			return "Stopped %s" % _event_name(d)
		"admin_give":
			var parts: PackedStringArray = []
			for r: String in d.get("resources", {}):
				parts.append("%d %s" % [int(d.resources[r]), r])
			for u: String in d.get("troops", {}):
				parts.append("%d %s" % [int(d.troops[u]), Economy.rules.unit_plural(u)])
			return "Gave %s to %s" % [", ".join(parts), String(d.get("target", "?"))]
	return String(e.get("action", ""))


func _event_name(d: Dictionary) -> String:
	for e: Dictionary in Economy.admin_view.get("events", []):
		if e.id == d.get("event", ""):
			return String(e.name)
	return String(d.get("event", "?"))


static func _days(seconds: float) -> String:
	var m := maxi(0, ceili(seconds / 60.0))
	if m >= 1440:
		return "%dd %02dh" % [m / 1440, (m % 1440) / 60]
	return "%dh %02dm" % [m / 60, m % 60]
