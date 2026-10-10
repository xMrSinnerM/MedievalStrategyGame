extends PanelContainer
## The report shown after your warband fights or storms a castle: who won,
## each side's soldiers before the battle and how many fell, and the plunder.

const TEXT := Color(0.95, 0.9, 0.8)
const MUTED := Color(0.78, 0.72, 0.62)
const WIN := Color(0.6, 0.9, 0.45)
const LOSS := Color(0.95, 0.45, 0.35)

var _title: Label
var _place: Label
var _grid: GridContainer
var _footer: Label


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.09, 0.06, 0.94)
	style.border_color = Color(0.7, 0.55, 0.3)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)
	custom_minimum_size = Vector2(440, 0)
	visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = _label(26, WIN)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_place = _label(15, MUTED)
	_place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_place)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_grid)
	_footer = _label(15, TEXT)
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_footer)
	var ok := Button.new()
	ok.text = "Continue"
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.custom_minimum_size = Vector2(140, 0)
	ok.pressed.connect(func() -> void: visible = false)
	box.add_child(ok)
	EventBus.battle_fought.connect(_on_battle)


func _on_battle(report: Dictionary) -> void:
	if report.player == "":
		return
	show_report(report)


func show_report(report: Dictionary) -> void:
	var me: String = report.player
	var them := "b" if me == "a" else "a"
	var won: bool = report.winner == me
	var enemy: String = report.defender if me == "a" else report.attacker
	var siege: bool = report.get("siege", false)
	_title.text = "Victory!" if won else "Defeat"
	if siege:
		_title.text = {"captured": "Castle captured!", "sacked": "Castle sacked!"}.get(report.outcome, "The walls held")
	_title.add_theme_color_override("font_color", WIN if won else LOSS)
	if siege and me == "a":
		_place.text = "You stormed the walls of %s" % enemy
	elif me == "a":
		_place.text = "You attacked %s near %s" % [enemy, report.place]
	else:
		_place.text = "%s attacked you near %s" % [enemy, report.place]
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for text in ["", "Yours", "Fell", "Garrison" if siege else enemy, "Fell"]:
		_grid.add_child(_label(14, MUTED, text))
	var units: Array = []
	for side in [report[me], report[them]]:
		for unit: String in side:
			if not units.has(unit):
				units.append(unit)
	var totals := [0, 0, 0, 0]
	for unit: String in units:
		var row := [_count(report[me], unit, "start"), _count(report[me], unit, "lost"),
				_count(report[them], unit, "start"), _count(report[them], unit, "lost")]
		_grid.add_child(_label(15, TEXT, Economy.rules.unit_plural(unit)))
		for k in 4:
			totals[k] += row[k]
			_grid.add_child(_cell(row[k], k % 2 == 1))
	_grid.add_child(_label(15, Color(1.0, 0.9, 0.65), "Total"))
	for k in 4:
		_grid.add_child(_cell(totals[k], k % 2 == 1))
	if siege and me == "a":
		if report.outcome == "captured":
			_footer.text = "%s is yours, with its buildings and stores." % enemy
		elif report.outcome == "sacked":
			_footer.text = "You carried off %s." % _spoils(report.spoils)
		else:
			_footer.text = "Your surviving soldiers fell back from the walls."
		if won and report.loot > 0:
			_footer.text += " Plunder: %d gold." % report.loot
	elif won:
		var fate := "%s fled home." % enemy if totals[3] < totals[2] else "None of %s's soldiers survived." % enemy
		_footer.text = "Your warband plundered %d gold. %s" % [report.loot, fate] if report.loot > 0 else fate
	else:
		_footer.text = "Your surviving soldiers fell back. %s took %d gold in plunder." % [enemy, report.loot]
	visible = true


func _spoils(spoils: Dictionary) -> String:
	var parts: PackedStringArray = []
	for r: String in spoils:
		if spoils[r] > 0:
			parts.append("%d %s" % [spoils[r], r])
	return ", ".join(parts) if not parts.is_empty() else "nothing"


func _count(side: Dictionary, unit: String, key: String) -> int:
	return int(side[unit][key]) if side.has(unit) else 0


func _cell(n: int, is_loss: bool) -> Label:
	var l := _label(15, LOSS if is_loss and n > 0 else TEXT, ("-%d" if is_loss and n > 0 else "%d") % n)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _label(size: int, color: Color, text := "") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
