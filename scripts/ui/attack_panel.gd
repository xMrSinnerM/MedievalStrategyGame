extends PanelContainer
## The attack screen, opened from a robber baron camp's panel: choose how many
## of each soldier to send, and see your chances, the losses to expect, how
## much of the loot they can carry and how long the march takes.

const WIN := Color(0.55, 0.9, 0.45)
const LOSS := Color(0.95, 0.4, 0.3)
const SAMPLES := 12

var camp_id := ""

var _title: Label
var _rows: GridContainer
var _spins := {}               ## unit -> SpinBox
var _enemy: Label
var _summary: Label
var _send: Button
var _note: Label
var _quiet := false            ## true while setting spin boxes from code


func _ready() -> void:
	add_theme_stylebox_override("panel", MenuStyle.panel(0.95))
	custom_minimum_size = Vector2(720, 0)
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
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 36)
	box.add_child(columns)
	var mine := VBoxContainer.new()
	mine.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mine.add_child(MenuStyle.label("Your army", 18, MenuStyle.GOLD))
	_rows = GridContainer.new()
	_rows.columns = 3
	_rows.add_theme_constant_override("h_separation", 12)
	_rows.add_theme_constant_override("v_separation", 6)
	mine.add_child(_rows)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	quick.add_child(_small_button("All", func() -> void: _fill(1.0)))
	quick.add_child(_small_button("Half", func() -> void: _fill(0.5)))
	quick.add_child(_small_button("None", func() -> void: _fill(0.0)))
	mine.add_child(quick)
	columns.add_child(mine)
	var theirs := VBoxContainer.new()
	theirs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	theirs.add_child(MenuStyle.label("The camp", 18, MenuStyle.GOLD))
	_enemy = MenuStyle.label("", 15, MenuStyle.TEXT)
	theirs.add_child(_enemy)
	columns.add_child(theirs)
	box.add_child(HSeparator.new())
	_summary = MenuStyle.label("", 16, MenuStyle.TEXT)
	box.add_child(_summary)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	_send = MenuStyle.button("Send army", _send_army, 220.0)
	buttons.add_child(_send)
	buttons.add_child(MenuStyle.button("Cancel", close_panel, 220.0))
	box.add_child(buttons)
	_note = MenuStyle.label("", 15, MenuStyle.GOLD)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note)
	EventBus.attack_screen_requested.connect(open_for)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()


func open_for(id: String) -> void:
	var camp := Economy.get_baron(id)
	if camp == null:
		return
	camp_id = id
	_title.text = "Attack %s (level %d)" % [camp.camp_name, camp.level]
	_note.text = ""
	_note.visible = false
	_build_rows()
	_describe_camp(camp)
	_fill(1.0)
	visible = true


func close_panel() -> void:
	visible = false


func _build_rows() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_spins.clear()
	var troops: Dictionary = Economy.player_castle.troops
	for unit: String in Economy.rules.units:
		var have := int(troops.get(unit, 0))
		if have <= 0:
			continue
		_rows.add_child(MenuStyle.label(Economy.rules.unit_plural(unit), 16, MenuStyle.TEXT))
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = have
		spin.step = 1
		spin.custom_minimum_size = Vector2(110, 0)
		spin.value_changed.connect(func(_v: float) -> void:
			if not _quiet:
				_update())
		_rows.add_child(spin)
		_rows.add_child(MenuStyle.label("of %d" % have, 15, MenuStyle.MUTED))
		_spins[unit] = spin
	if _spins.is_empty():
		_rows.add_child(MenuStyle.label("Your garrison is empty.", 15, MenuStyle.MUTED))


func _describe_camp(camp: BaronCamp) -> void:
	var br := Economy.baron_rules
	var lines: PackedStringArray = []
	var garrison := camp.garrison(br)
	for unit: String in garrison:
		lines.append("%d %s" % [garrison[unit], Economy.rules.unit_plural(unit)])
	var wall := Battle.wall_from_defense(br.palisade(camp.level))
	lines.append("Palisade: +%d%% defence" % roundi((wall - 1.0) * 100.0))
	var loot := br.loot(camp.level)
	var parts: PackedStringArray = []
	for r: String in loot:
		parts.append("%d %s" % [loot[r], r])
	lines.append("Loot: " + ", ".join(parts))
	_enemy.text = "\n".join(lines)


func _army() -> Dictionary:
	var army := {}
	for unit: String in _spins:
		var n := int(_spins[unit].value)
		if n > 0:
			army[unit] = n
	return army


func _fill(share: float) -> void:
	_quiet = true
	for unit: String in _spins:
		var spin: SpinBox = _spins[unit]
		spin.value = floorf(spin.max_value * share)
	_quiet = false
	_update()


func _update() -> void:
	var camp := Economy.get_baron(camp_id)
	if camp == null:
		return
	var br := Economy.baron_rules
	var army := _army()
	var total := 0
	for unit: String in army:
		total += int(army[unit])
	var garrison := camp.garrison(br)
	var wall := Battle.wall_from_defense(br.palisade(camp.level))
	var lines: PackedStringArray = []
	if total == 0:
		lines.append("Choose some soldiers to send.")
		_summary.add_theme_color_override("font_color", MenuStyle.TEXT)
	else:
		# A handful of simulated battles give the odds and the losses to expect.
		var wins := 0
		var lost := 0
		for k in SAMPLES:
			var result := Battle.fight(Economy.rules, army, garrison, 1000 + k, wall)
			if result.winner == "a":
				wins += 1
			lost += Battle.lost_count(result.a)
		var chance := float(wins) / SAMPLES
		lines.append("Sending %d soldiers: %s (%d%%), losing about %d" % [total, Battle.odds_text(chance),
				roundi(chance * 100.0), roundi(float(lost) / SAMPLES)])
		var loot_total := 0
		var loot := br.loot(camp.level)
		for r: String in loot:
			loot_total += int(loot[r])
		var carry := br.carry(army)
		lines.append("They can carry %d of the camp's %d loot" % [mini(int(carry), loot_total), loot_total]
				+ ("" if carry >= loot_total else " (send more to carry it all)"))
		_summary.add_theme_color_override("font_color", LOSS.lerp(WIN, chance))
	var march := Economy.march_time_to(camp)
	lines.append("March: %s there, %s back" % [_clock(march), _clock(march)])
	if not camp.is_ready(Economy.now()):
		lines.append("The camp is rebuilding for %s." % _clock(camp.rebuilt_at - Economy.now()))
	_summary.text = "\n".join(lines)
	_send.disabled = Economy.check_attack(camp_id, army) != ""


func _send_army() -> void:
	var why := Economy.send_attack(camp_id, _army())
	if why != "":
		_note.text = why
		_note.visible = true
		return
	close_panel()
	EventBus.baron_selected.emit("")


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
	return "%d:%02d" % [s / 60, s % 60]
