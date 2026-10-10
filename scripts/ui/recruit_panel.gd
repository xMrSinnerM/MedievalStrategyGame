extends VBoxContainer
## The barracks part of the castle's building panel: train soldiers, see the
## training queue and the garrison. Read-only when visiting someone else's
## castle.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const HEAD := Color(1.0, 0.9, 0.65)
const AMOUNTS := [1, 5, 10]

var hud: CanvasLayer     ## the castle HUD, for its view and button style

var _unit_rows := {}      ## unit -> {info: Label, cost: Label, buttons: Array[Button], max: Button}
var _units_box: VBoxContainer
var _queue_box: VBoxContainer
var _queue_signature := "?"
var _queue_bar: ProgressBar
var _queue_first: Label
var _garrison: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(HSeparator.new())
	add_child(_label("Train soldiers", 16, HEAD))
	_units_box = VBoxContainer.new()
	_units_box.add_theme_constant_override("separation", 6)
	add_child(_units_box)
	_queue_box = VBoxContainer.new()
	_queue_box.add_theme_constant_override("separation", 3)
	add_child(_queue_box)
	_garrison = _label("", 14, TEXT)
	_garrison.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_garrison.custom_minimum_size = Vector2(306, 0)
	add_child(_garrison)


func refresh() -> void:
	var view: Node3D = hud.view
	var castle: CastleState = view.castle
	var rules := castle.rules
	if _unit_rows.is_empty():
		_build_rows(rules)
	for unit: String in _unit_rows:
		var row: Dictionary = _unit_rows[unit]
		var locked := castle.barracks_level() < rules.unit_barracks_level(unit)
		if locked:
			row.info.text = "%s: unlocks at barracks level %d" % [rules.unit_name(unit), rules.unit_barracks_level(unit)]
		else:
			row.info.text = "%s   attack %d, defence %d, eats %s food/h" % [rules.unit_name(unit),
				int(rules.unit_stat(unit, "attack")), int(rules.unit_stat(unit, "defense")), String.num(rules.unit_upkeep(unit))]
			row.cost.text = "%s, %s each" % [hud._cost_text(rules.unit_cost(unit)), view.format_time(rules.unit_time(unit, castle.barracks_level()))]
		row.info.modulate.a = 0.5 if locked else 1.0
		row.line.visible = not locked
		var can := castle.affordable(unit)
		for b: Button in row.buttons:
			var n: int = b.get_meta("amount")
			var reason := castle.check_recruit(unit, n)
			b.visible = view.editable and not locked
			b.disabled = reason != ""
			b.tooltip_text = reason if reason != "" else "Train %d for %s" % [n, hud._cost_text(rules.unit_cost(unit, n))]
		row.max.visible = view.editable and not locked
		row.max.set_meta("amount", can)
		row.max.text = "Max %d" % can
		row.max.disabled = can < 1 or castle.check_recruit(unit, can) != ""
	_refresh_queue(castle)
	var parts: PackedStringArray = []
	for unit: String in castle.troops:
		if castle.troops[unit] > 0:
			var noun := rules.unit_name(unit) if castle.troops[unit] == 1 else rules.unit_plural(unit)
			parts.append("%d %s" % [castle.troops[unit], noun.to_lower()])
	_garrison.text = "Garrison: %s" % (", ".join(parts) if not parts.is_empty() else "nobody yet")
	if castle.troop_count() + castle.field_count() > 0:
		_garrison.text += ". With the warband, soldiers eat %d food/h" % int(castle.upkeep_per_hour())
	if castle.hunger > 0.0 or (castle.resources.get("food", 0.0) <= 0.0 and castle.net_per_hour().food < 0.0):
		_garrison.text += "\nNo food left: soldiers are deserting!"


func update_progress(now: float) -> void:
	## Called every frame for a smooth progress bar.
	var castle: CastleState = hud.view.castle
	if _queue_bar == null or castle.training.is_empty():
		return
	var batch: Dictionary = castle.training[0]
	_queue_bar.value = 100.0 * (1.0 - maxf(batch.next - now, 0.0) / maxf(batch.unit_time, 1.0))
	_queue_first.text = "%s x%d   next in %s, all in %s" % [castle.rules.unit_name(batch.unit), batch.remaining,
		hud.view.format_time(maxf(batch.next - now, 0.0)), hud.view.format_time(castle.training_left(now))]


func _build_rows(rules: BuildingRules) -> void:
	for unit: String in rules.units:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		var info := _label("", 14, TEXT)
		box.add_child(info)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 4)
		var cost := _label("", 13, MUTED)
		cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(cost)
		var buttons: Array[Button] = []
		for n: int in AMOUNTS:
			var b := _small_button("+%d" % n, unit, n)
			line.add_child(b)
			buttons.append(b)
		var max_button := _small_button("Max", unit, 0)
		line.add_child(max_button)
		box.add_child(line)
		_units_box.add_child(box)
		_unit_rows[unit] = {"info": info, "cost": cost, "line": line, "buttons": buttons, "max": max_button}


func _refresh_queue(castle: CastleState) -> void:
	var parts: PackedStringArray = []
	for t in castle.training:
		parts.append("%s:%d" % [t.unit, t.remaining])
	var signature := "|".join(parts) + ("e" if hud.view.editable else "")
	if signature == _queue_signature:
		return
	_queue_signature = signature
	for child in _queue_box.get_children():
		_queue_box.remove_child(child)
		child.queue_free()
	_queue_bar = null
	if castle.training.is_empty():
		return
	_queue_box.add_child(_label("Training (%d/%d)" % [castle.training.size(), castle.rules.queue_size], 15, HEAD))
	for i in castle.training.size():
		var t: Dictionary = castle.training[i]
		var row := HBoxContainer.new()
		var l := _label("%s x%d" % [castle.rules.unit_name(t.unit), t.remaining], 13, TEXT)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if hud.view.editable:
			var cancel: Button = hud._button("Cancel")
			cancel.add_theme_font_size_override("font_size", 12)
			cancel.tooltip_text = "Refunds %d%% of what the untrained soldiers cost" % int(CastleState.CANCEL_REFUND * 100.0)
			var index := i
			cancel.pressed.connect(func() -> void: hud.view.cancel_training(index))
			row.add_child(cancel)
		_queue_box.add_child(row)
		if i == 0:
			_queue_first = l
			_queue_bar = ProgressBar.new()
			_queue_bar.show_percentage = false
			_queue_bar.custom_minimum_size = Vector2(0, 8)
			_queue_box.add_child(_queue_bar)


func _small_button(text: String, unit: String, amount: int) -> Button:
	var b: Button = hud._button(text)
	b.add_theme_font_size_override("font_size", 12)
	b.custom_minimum_size = Vector2(34, 0)
	b.set_meta("amount", amount)
	b.pressed.connect(func() -> void: hud.view.recruit(unit, int(b.get_meta("amount"))))
	return b


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
