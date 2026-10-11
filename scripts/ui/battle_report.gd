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
	add_theme_stylebox_override("panel", MenuStyle.panel(0.94, 18))
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
	Economy.attack_resolved.connect(show_baron_report)


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
		if me == "a":
			_title.text = {"captured": "Castle captured!", "sacked": "Castle sacked!"}.get(report.outcome, "The walls held")
		else:
			_title.text = {"captured": "Castle lost!", "sacked": "Castle sacked!"}.get(report.outcome, "The walls held!")
	_title.add_theme_color_override("font_color", WIN if won else LOSS)
	if siege and me == "a":
		_place.text = "You stormed the walls of %s" % enemy
	elif siege:
		_place.text = "%s stormed %s" % [enemy, report.defender]
	elif me == "a":
		_place.text = "You attacked %s near %s" % [enemy, report.place]
	else:
		_place.text = "%s attacked you near %s" % [enemy, report.place]
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var their_side := "Garrison" if siege and me == "a" else enemy
	for text in ["", "Garrison" if siege and me == "b" else "Yours", "Fell", their_side, "Fell"]:
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
	elif siege:
		if report.outcome == "captured":
			_footer.text = "%s now belongs to %s." % [report.defender, enemy]
		elif report.outcome == "sacked":
			_footer.text = "%s carried off %s. Train more soldiers to hold the walls." % [enemy, _spoils(report.spoils)]
		else:
			_footer.text = "Your garrison held. %s fell back." % enemy
	elif won:
		var fate := "%s fled home." % enemy if totals[3] < totals[2] else "None of %s's soldiers survived." % enemy
		_footer.text = "Your warband plundered %d gold. %s" % [report.loot, fate] if report.loot > 0 else fate
	else:
		_footer.text = "Your surviving soldiers fell back. %s took %d gold in plunder." % [enemy, report.loot]
	if report.get("lifted", "") != "":
		_footer.text += "\nThe siege of %s is lifted." % report.lifted
	visible = true


func show_baron_report(report: Dictionary) -> void:
	## The report for an army you sent against a robber baron camp (or, online,
	## a battle between your castle and another player's).
	if report.get("raid", false):
		show_raid_report(report)
		return
	if report.get("empty", false):
		_title.text = "Nothing to fight"
		_title.add_theme_color_override("font_color", MUTED)
		_place.text = "%s was still in ashes when your army arrived." % report.defender
		_clear_grid()
		_footer.text = "Your army is marching home."
		visible = true
		return
	report = report.duplicate()
	report.attacker = "Your army"
	show_report(report)
	var won: bool = report.winner == "a"
	_place.text = "Your army attacked %s (level %d)" % [report.defender, report.level]
	var lines: PackedStringArray = []
	if won:
		lines.append("Your army is bringing home %s." % _spoils(report.spoils))
		if report.leveled:
			lines.append("%s rises to level %d: more soldiers, more loot." % [report.defender, report.new_level])
		else:
			lines.append("Wins %d of %d before %s reaches level %d." % [report.defeats, report.needed, report.defender, report.new_level + 1])
	else:
		lines.append("The camp held. Your surviving soldiers are marching home.")
	_footer.text = "\n".join(lines)


func show_raid_report(report: Dictionary) -> void:
	## A battle between players: your army against their castle, or theirs against yours.
	show_report(report)
	var attacking: bool = report.player == "a"
	var won: bool = report.winner == report.player
	var walls := "+%d%% from the walls" % roundi((float(report.get("wall", 1.0)) - 1.0) * 100.0)
	if attacking:
		_title.text = "Victory!" if won else "Defeat"
		_place.text = "Your army attacked %s's castle (%s)" % [report.name, walls]
		_footer.text = "Your army is bringing home %s." % _spoils(report.spoils) if won \
				else "%s's garrison held. Your surviving soldiers are marching home." % report.name
		if report.b.is_empty():
			_footer.text = "No soldiers were home to defend it.\n" + _footer.text
	else:
		_title.text = "Your walls held!" if won else "Your castle was raided!"
		_place.text = "%s attacked your castle (%s)" % [report.name, walls]
		_footer.text = "%s's army fell back with nothing." % report.name if won \
				else "%s carried off %s. Train more soldiers to hold the walls." % [report.name, _spoils(report.spoils)]
	_title.add_theme_color_override("font_color", WIN if won else LOSS)


func _clear_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


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
