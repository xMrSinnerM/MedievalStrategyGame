extends VBoxContainer
## The hospital part of the castle's building panel: the wounded in its beds,
## healing them for food, and the healing queue. Read-only when visiting
## someone else's castle.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const HEAD := Color(1.0, 0.9, 0.65)
const AMOUNTS := [1, 10]

var hud: CanvasLayer     ## the castle HUD, for its view and button style

var _beds: Label
var _rows_box: VBoxContainer
var _rows_signature := "?"
var _queue_box: VBoxContainer
var _queue_signature := "?"
var _queue_bar: ProgressBar
var _queue_first: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(HSeparator.new())
	add_child(_label("The wounded", 16, HEAD))
	_beds = _label("", 14, TEXT)
	_beds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_beds.custom_minimum_size = Vector2(306, 0)
	add_child(_beds)
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 6)
	add_child(_rows_box)
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 3)
	add_child(_queue_box)


func refresh() -> void:
	var view: Node3D = hud.view
	var castle: CastleState = view.castle
	var rules := castle.rules
	_beds.text = "Beds: %d of %d taken. Of the soldiers you lose, %d%% of those defending your walls and %d%% of those in your attacks are carried here while there is room." % [
			castle.wounded_count(), castle.beds(), roundi(100.0 * rules.wounded_share(false)), roundi(100.0 * rules.wounded_share(true))]
	if castle.wounded_count() >= castle.beds() and castle.beds() > 0:
		_beds.text += "\nEvery bed is taken: heal some, or the next to fall are lost."
	var parts: PackedStringArray = []
	for unit: String in castle.wounded:
		parts.append("%s:%d:%d" % [unit, int(castle.wounded[unit]), castle.healable(unit)])
	var signature := "|".join(parts) + ("e" if view.editable else "") + str(castle.healing.size()) + str(castle.hospital_level())
	if signature != _rows_signature:
		_rows_signature = signature
		_fill_rows(castle)
	_refresh_queue(castle)


func update_progress(now: float) -> void:
	## Called every frame for a smooth progress bar.
	var castle: CastleState = hud.view.castle
	if _queue_bar == null or castle.healing.is_empty():
		return
	var batch: Dictionary = castle.healing[0]
	_queue_bar.value = 100.0 * (1.0 - maxf(batch.next - now, 0.0) / maxf(batch.unit_time, 1.0))
	_queue_first.text = "%s x%d   next in %s, all in %s" % [castle.rules.unit_name(batch.unit), batch.remaining,
		hud.view.format_time(maxf(batch.next - now, 0.0)), hud.view.format_time(castle.healing_left(now))]


func _fill_rows(castle: CastleState) -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	var rules := castle.rules
	if castle.wounded.is_empty():
		_rows_box.add_child(_label("Nobody is waiting for the healers.", 13, MUTED))
		return
	for unit: String in castle.wounded:
		var n := int(castle.wounded[unit])
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.add_child(_label("%d wounded %s" % [n, (rules.unit_name(unit) if n == 1 else rules.unit_plural(unit)).to_lower()], 14, TEXT))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		var cost := _label("%s, %s each" % [hud._cost_text(rules.heal_cost(unit)), hud.view.format_time(castle.heal_time(unit))], 13, MUTED)
		cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(cost)
		if hud.view.editable:
			for amount: int in AMOUNTS:
				if amount > 1 and n < amount:
					continue
				line.add_child(_heal_button("+%d" % amount, castle, unit, amount))
			var can := castle.healable(unit)
			line.add_child(_heal_button("All %d" % can if can >= n else "Max %d" % can, castle, unit, can))
		box.add_child(line)
		_rows_box.add_child(box)


func _heal_button(text: String, castle: CastleState, unit: String, amount: int) -> Button:
	var b: Button = hud._button(text)
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(34, 0)
	var reason := castle.check_heal(unit, amount) if amount > 0 else "Not enough food"
	b.disabled = reason != ""
	b.tooltip_text = reason if reason != "" else "Heal %d for %s" % [amount, hud._cost_text(castle.rules.heal_cost(unit, amount))]
	b.pressed.connect(func() -> void: hud.view.heal_wounded(unit, amount))
	return b


func _refresh_queue(castle: CastleState) -> void:
	var parts: PackedStringArray = []
	for h in castle.healing:
		parts.append("%s:%d" % [h.unit, h.remaining])
	var signature := "|".join(parts) + ("e" if hud.view.editable else "")
	if signature == _queue_signature:
		return
	_queue_signature = signature
	for child in _queue_box.get_children():
		_queue_box.remove_child(child)
		child.queue_free()
	_queue_bar = null
	if castle.healing.is_empty():
		return
	_queue_box.add_child(_label("Healing (%d/%d)" % [castle.healing.size(), castle.rules.queue_size], 15, HEAD))
	for i in castle.healing.size():
		var h: Dictionary = castle.healing[i]
		var row := HBoxContainer.new()
		var l := _label("%s x%d" % [castle.rules.unit_name(h.unit), h.remaining], 13, TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if hud.view.editable:
			var cancel: Button = hud._button("Cancel")
			cancel.add_theme_font_size_override("font_size", 12)
			cancel.tooltip_text = "They stay wounded; %d%% of the food comes back" % int(CastleState.CANCEL_REFUND * 100.0)
			var index := i
			cancel.pressed.connect(func() -> void: hud.view.cancel_healing(index))
			row.add_child(cancel)
		_queue_box.add_child(row)
		if i == 0:
			_queue_first = l
			_queue_bar = ProgressBar.new()
			_queue_bar.show_percentage = false
			_queue_bar.custom_minimum_size = Vector2(0, 8)
			_queue_box.add_child(_queue_bar)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
