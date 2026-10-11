extends PanelContainer
## Online: helping a member of your alliance, opened from their castle's
## panel. Either load a cart with resources (at most carry_limit() per
## shipment, see data/aid.json) or choose soldiers to stand in their castle
## and help defend it for a few hours.

var _player := ""
var _kind := ""                ## "resources" or "troops"

var _title: Label
var _what: Label
var _rows: GridContainer
var _spins := {}               ## resource or unit -> SpinBox
var _summary: Label
var _send: Button
var _note: Label
var _quiet := false            ## true while setting spin boxes from code


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(560, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = MenuStyle.title("", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "×"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 20)
	close.pressed.connect(close_panel)
	head.add_child(close)
	_what = MenuStyle.label("", 15, MenuStyle.MUTED)
	_what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_what)
	_rows = GridContainer.new()
	_rows.columns = 3
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 6)
	box.add_child(_rows)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	quick.add_child(_small_button("All", func() -> void: _fill(1.0)))
	quick.add_child(_small_button("Half", func() -> void: _fill(0.5)))
	quick.add_child(_small_button("None", func() -> void: _fill(0.0)))
	box.add_child(quick)
	box.add_child(HSeparator.new())
	_summary = MenuStyle.label("", 16, MenuStyle.TEXT)
	box.add_child(_summary)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	_send = MenuStyle.button("Send", _send_help, 220.0)
	buttons.add_child(_send)
	buttons.add_child(MenuStyle.button("Cancel", close_panel, 220.0))
	box.add_child(buttons)
	_note = MenuStyle.label("", 15, MenuStyle.GOLD)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	EventBus.help_screen_requested.connect(open_for)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func open_for(player_name: String, kind: String) -> void:
	if Economy.get_other(player_name).is_empty():
		return
	_player = player_name
	_kind = kind
	var hours := int(Economy.aid_rules.get("station_hours", 8))
	if kind == "resources":
		_title.text = "Send resources to %s" % player_name
		_what.text = "A cart carries up to %d resources (%d per keep level). What their storage can't hold is lost." \
				% [Economy.carry_limit(), int(Economy.aid_rules.get("carry_per_keep_level", 500))]
		_send.text = "Send cart"
	else:
		_title.text = "Send defenders to %s" % player_name
		_what.text = "Your soldiers stand in %s's castle for %d hours and fight beside their garrison if it is attacked, then march home. You can call them back sooner." \
				% [player_name, hours]
		_send.text = "Send defenders"
	_note.text = ""
	_build_rows()
	_fill(0.0)
	visible = true


func close_panel() -> void:
	visible = false


func _build_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_spins.clear()
	var castle := Economy.player_castle
	var keys: Array = castle.rules.resources if _kind == "resources" else Economy.rules.units.keys()
	for k: String in keys:
		var have := floori(float(castle.resources.get(k, 0.0))) if _kind == "resources" else int(castle.troops.get(k, 0))
		if have <= 0:
			continue
		var title := k.capitalize() if _kind == "resources" else Economy.rules.unit_plural(k)
		_rows.add_child(MenuStyle.label(title, 16, MenuStyle.TEXT))
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = mini(have, Economy.carry_limit()) if _kind == "resources" else have
		spin.step = 1
		spin.custom_minimum_size = Vector2(120, 0)
		spin.value_changed.connect(func(_v: float) -> void:
			if not _quiet:
				_update())
		_rows.add_child(spin)
		_rows.add_child(MenuStyle.label("of %d" % have, 15, MenuStyle.MUTED))
		_spins[k] = spin
	if _spins.is_empty():
		_rows.add_child(MenuStyle.label("Your storage is empty." if _kind == "resources" else "Your garrison is empty.",
				15, MenuStyle.MUTED))


func _chosen() -> Dictionary:
	var out := {}
	for k: String in _spins:
		var n := int(_spins[k].value)
		if n > 0:
			out[k] = n
	return out


func _fill(share: float) -> void:
	_quiet = true
	if _kind == "resources":
		# Share the cart out evenly between the resources you have.
		var room := float(Economy.carry_limit()) * share
		var keys := _spins.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return _spins[a].max_value < _spins[b].max_value)
		for i in keys.size():
			var spin: SpinBox = _spins[keys[i]]
			spin.value = minf(spin.max_value, floorf(room / (keys.size() - i)))
			room -= spin.value
	else:
		for unit: String in _spins:
			var spin: SpinBox = _spins[unit]
			spin.value = floorf(spin.max_value * share)
	_quiet = false
	_update()


func _update() -> void:
	var chosen := _chosen()
	var total := 0
	for k: String in chosen:
		total += int(chosen[k])
	var lines: PackedStringArray = []
	var march := Economy.march_time_to_player(_player)
	if _kind == "resources":
		lines.append("Loaded: %d of %d" % [total, Economy.carry_limit()])
		lines.append("The cart arrives in %s" % _clock(march))
	else:
		lines.append("Sending %d soldiers" % total)
		lines.append("March: %s there, %s back" % [_clock(march), _clock(march)])
	var why := Economy.check_shipment(_player, chosen) if _kind == "resources" else Economy.check_defenders(_player, chosen)
	if why != "" and total > 0:
		lines.append(why)
	_summary.text = "\n".join(lines)
	_send.disabled = why != ""


func _send_help() -> void:
	var chosen := _chosen()
	var why := Economy.send_resources(_player, chosen) if _kind == "resources" else Economy.send_defenders(_player, chosen)
	if why != "":
		_note.text = why
		return
	close_panel()


func _small_button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(80, 32)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(action)
	return b


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
	return "%d:%02d" % [s / 60, s % 60]
